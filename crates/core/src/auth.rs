use crate::{AuthError, HttpBody, HttpClient, HttpMethod, HttpRequest, OpenCloudClient};
use base64::Engine;
use open_cloud_api::{AuthErrorCode, RoleInfo, RoleName, SessionUser};
use serde::Deserialize;
use std::collections::HashMap;

const PORTAL_BASIC_AUTH: &str = "Basic cG9ydGFsOnBvcnRhbF9zZWNyZXQ=";

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LoginFlow {
    pub captcha_id: Option<String>,
    pub captcha_image: Option<String>,
    pub cookie: String,
    pub created_at_ms: u64,
    pub execution: String,
    pub username: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LoginResult {
    pub access_token: String,
    pub access_token_expires_at_ms: u64,
    pub refresh_token: String,
    pub refresh_token_expires_at_ms: u64,
    pub roles: Vec<RoleInfo>,
    pub selected_role: RoleName,
    pub user: SessionUser,
}

impl<C> OpenCloudClient<C>
where
    C: HttpClient,
{
    pub async fn start_login(&self, username: &str) -> Result<LoginFlow, AuthError> {
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Get,
                url: self.endpoints.login_url.clone(),
                headers: Vec::new(),
                body: None,
            })
            .await?;
        let cookie = response
            .header("set-cookie")
            .and_then(|value| value.split(';').next())
            .filter(|value| !value.is_empty())
            .ok_or_else(|| AuthError::upstream("无法初始化统一认证登录会话。"))?
            .to_string();
        let html = response.text()?;
        let execution = extract_between(&html, r#"<input name="execution" value=""#, r#"""#)
            .ok_or_else(|| AuthError::upstream("无法获取统一认证 execution。"))?;
        let captcha_id = extract_between(&html, "config.captcha", "}")
            .and_then(|chunk| extract_between(&chunk, "id: '", "'"));

        let captcha_image = if let Some(captcha_id) = &captcha_id {
            let captcha_url = format!(
                "https://auth.bupt.edu.cn/authserver/captcha?captchaId={captcha_id}&r=00000"
            );
            let captcha_response = self
                .http
                .send(HttpRequest {
                    method: HttpMethod::Get,
                    url: captcha_url,
                    headers: vec![("cookie".to_string(), cookie.clone())],
                    body: None,
                })
                .await?;
            if !(200..300).contains(&captcha_response.status) {
                return Err(AuthError::upstream("验证码加载失败。"));
            }
            let content_type = captcha_response
                .header("content-type")
                .unwrap_or("image/png")
                .to_string();
            Some(format!(
                "data:{content_type};base64,{}",
                base64::engine::general_purpose::STANDARD.encode(captcha_response.body)
            ))
        } else {
            None
        };

        Ok(LoginFlow {
            captcha_id,
            captcha_image,
            cookie,
            created_at_ms: now_ms(),
            execution,
            username: username.to_string(),
        })
    }

    pub async fn finish_login(
        &self,
        flow: LoginFlow,
        password: &str,
        role: Option<RoleName>,
        captcha: Option<&str>,
    ) -> Result<LoginResult, AuthError> {
        let form_body = format!(
            "username={}&password={}{}&submit=%E7%99%BB%E5%BD%95&type=username_password&execution={}&_eventId=submit",
            form_url(&flow.username),
            form_url(password),
            captcha
                .map(|captcha| format!("&captcha={}", form_url(captcha)))
                .unwrap_or_default(),
            form_url(&flow.execution),
        );
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Post,
                url: self.endpoints.login_url.clone(),
                headers: vec![
                    ("authority".to_string(), "auth.bupt.edu.cn".to_string()),
                    (
                        "content-type".to_string(),
                        "application/x-www-form-urlencoded".to_string(),
                    ),
                    ("cookie".to_string(), flow.cookie.clone()),
                    ("referer".to_string(), self.endpoints.login_url.clone()),
                    (
                        "user-agent".to_string(),
                        "Mozilla/5.0 AppleWebKit/537.36 Chrome/118 Safari/537.36".to_string(),
                    ),
                ],
                body: Some(HttpBody::text(form_body)),
            })
            .await?;

        if response.status != 302 {
            let html = response.text().unwrap_or_default();
            let error = parse_error_message(&html);
            if response.status == 401 {
                if error.as_deref() == Some("Invalid credentials.") {
                    return Err(AuthError::new(
                        AuthErrorCode::InvalidCredentials,
                        "用户名或密码错误。",
                    ));
                }
                return Err(AuthError::new(
                    if flow.captcha_id.is_some() {
                        AuthErrorCode::CaptchaInvalid
                    } else {
                        AuthErrorCode::InvalidCredentials
                    },
                    error
                        .map(|value| format!("登录失败：{value}"))
                        .unwrap_or_else(|| "登录失败。".to_string()),
                ));
            }
            return Err(AuthError::upstream(
                error.unwrap_or_else(|| "统一认证登录失败。".to_string()),
            ));
        }

        let location = response
            .header("location")
            .ok_or_else(|| AuthError::upstream("登录成功但未收到 ticket。"))?;
        let ticket = url::Url::parse(location)
            .ok()
            .and_then(|url| {
                url.query_pairs()
                    .find(|(key, _)| key == "ticket")
                    .map(|(_, value)| value.to_string())
            })
            .ok_or_else(|| AuthError::upstream("无法从回调中提取 ticket。"))?;

        let token_payload = self.exchange_ticket(&ticket).await?;
        let roles = self.get_user_roles(&token_payload.refresh_token).await?;
        if roles.is_empty() {
            return Err(AuthError::new(
                AuthErrorCode::RoleNotFound,
                "用户没有可用角色。",
            ));
        }
        let selected_role = role.unwrap_or_else(|| roles[0].role_name.clone());
        let refreshed = self
            .refresh_user_info(
                &token_payload.refresh_token,
                Some(selected_role.clone()),
                &roles,
            )
            .await?;
        let access_token_expires_at_ms = get_token_expiration_ms(&refreshed.access_token)
            .ok_or_else(|| {
                AuthError::new(AuthErrorCode::SessionExpired, "登录会话缺少过期时间。")
            })?;
        let refresh_token_expires_at_ms = get_token_expiration_ms(&refreshed.refresh_token)
            .ok_or_else(|| {
                AuthError::new(AuthErrorCode::SessionExpired, "登录会话缺少过期时间。")
            })?;

        Ok(LoginResult {
            access_token: refreshed.access_token,
            access_token_expires_at_ms,
            refresh_token: refreshed.refresh_token,
            refresh_token_expires_at_ms,
            roles,
            selected_role,
            user: SessionUser {
                account: refreshed.account,
                real_name: refreshed.real_name,
                user_id: refreshed.user_id,
                user_name: refreshed.user_name,
            },
        })
    }

    async fn exchange_ticket(&self, ticket: &str) -> Result<UserInfoPayload, AuthError> {
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Post,
                url: self.endpoints.token_url.clone(),
                headers: token_headers(&self.endpoints.ucloud_referer),
                body: Some(HttpBody::text(format!(
                    "ticket={}&grant_type=third",
                    form_url(ticket)
                ))),
            })
            .await?;
        parse_json_response(response, "UCloud token 兑换失败。")
    }

    pub async fn get_user_roles(&self, token: &str) -> Result<Vec<RoleInfo>, AuthError> {
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Get,
                url: self.endpoints.roles_url.clone(),
                headers: vec![
                    ("authorization".to_string(), PORTAL_BASIC_AUTH.to_string()),
                    ("Blade-Auth".to_string(), token.to_string()),
                ],
                body: None,
            })
            .await?;
        let payload: RoleListPayload = parse_json_response(response, "获取用户角色失败。")?;
        Ok(payload.data)
    }

    pub async fn refresh_user_info(
        &self,
        refresh_token: &str,
        role: Option<RoleName>,
        known_roles: &[RoleInfo],
    ) -> Result<UserInfoPayload, AuthError> {
        let mut fields = vec![
            ("grant_type".to_string(), "refresh_token".to_string()),
            ("refresh_token".to_string(), refresh_token.to_string()),
        ];
        if let Some(role) = role {
            let role_info = known_roles
                .iter()
                .find(|info| info.role_name == role)
                .ok_or_else(|| {
                    AuthError::new(AuthErrorCode::RoleNotFound, "用户不存在指定角色。")
                })?;
            fields.push(("identity".to_string(), role_info.id.clone()));
        }
        let (content_type, body) = multipart_form(fields);
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Post,
                url: self.endpoints.token_url.clone(),
                headers: vec![
                    ("authorization".to_string(), PORTAL_BASIC_AUTH.to_string()),
                    ("content-type".to_string(), content_type),
                ],
                body: Some(HttpBody::text(body)),
            })
            .await?;
        parse_json_response(response, "刷新 token 失败。")
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
pub struct UserInfoPayload {
    pub access_token: String,
    pub account: String,
    pub refresh_token: String,
    pub expires_in: u64,
    pub real_name: String,
    pub user_id: String,
    pub user_name: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
struct RoleListPayload {
    data: Vec<RoleInfo>,
}

pub fn get_token_expiration_ms(token: &str) -> Option<u64> {
    let payload = token.split('.').nth(1)?;
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload)
        .ok()?;
    let json: HashMap<String, serde_json::Value> = serde_json::from_slice(&bytes).ok()?;
    json.get("exp")?.as_u64().map(|seconds| seconds * 1000)
}

fn parse_json_response<T>(response: crate::HttpResponse, message: &str) -> Result<T, AuthError>
where
    T: for<'de> Deserialize<'de>,
{
    if !(200..300).contains(&response.status) {
        return Err(AuthError::upstream(format!(
            "{message} HTTP status {}.",
            response.status
        )));
    }
    serde_json::from_slice(&response.body).map_err(|error| AuthError::upstream(error.to_string()))
}

fn token_headers(referer: &str) -> Vec<(String, String)> {
    vec![
        (
            "accept".to_string(),
            "application/json, text/plain, */*".to_string(),
        ),
        ("authorization".to_string(), PORTAL_BASIC_AUTH.to_string()),
        (
            "content-type".to_string(),
            "application/x-www-form-urlencoded".to_string(),
        ),
        ("Referer".to_string(), referer.to_string()),
        (
            "Referrer-Policy".to_string(),
            "strict-origin-when-cross-origin".to_string(),
        ),
        ("tenant-id".to_string(), "000000".to_string()),
    ]
}

fn extract_between(input: &str, prefix: &str, suffix: &str) -> Option<String> {
    let start = input.find(prefix)? + prefix.len();
    let rest = &input[start..];
    let end = rest.find(suffix)?;
    Some(rest[..end].to_string())
}

fn parse_error_message(html: &str) -> Option<String> {
    let marker = r#"<div class="alert alert-danger" id="errorDiv">"#;
    let section = extract_between(html, marker, "</div>")?;
    extract_between(&section, "<p>", "</p>")
}

fn form_url(value: &str) -> String {
    url::form_urlencoded::byte_serialize(value.as_bytes()).collect()
}

fn multipart_form(fields: Vec<(String, String)>) -> (String, String) {
    let boundary = "----open-cloud-bupt-auth-boundary";
    let mut body = String::new();
    for (name, value) in fields {
        body.push_str("--");
        body.push_str(boundary);
        body.push_str("\r\n");
        body.push_str("Content-Disposition: form-data; name=\"");
        body.push_str(&name);
        body.push_str("\"\r\n\r\n");
        body.push_str(&value);
        body.push_str("\r\n");
    }
    body.push_str("--");
    body.push_str(boundary);
    body.push_str("--\r\n");
    (format!("multipart/form-data; boundary={boundary}"), body)
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}
