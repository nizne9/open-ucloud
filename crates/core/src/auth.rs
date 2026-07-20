use crate::protocol::{http_status_error, PORTAL_BASIC_AUTH};
use crate::transport::multipart_boundary;
use crate::{AuthError, HttpBody, HttpClient, HttpMethod, HttpRequest, OpenCloudClient};
use base64::Engine;
use cookie::Cookie;
use open_cloud_api::{AuthErrorCode, RoleInfo, RoleName, SessionUser};
use scraper::{Html, Selector};
use serde::Deserialize;
use std::collections::HashMap;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LoginFlow {
    pub captcha_id: Option<String>,
    pub captcha_image: Option<String>,
    pub cookie: String,
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
        let cookie = login_cookie_header(&response)
            .ok_or_else(|| AuthError::upstream("无法初始化统一认证登录会话。"))?;
        let html = response.text()?;
        let (execution, captcha_id) = {
            let document = Html::parse_document(&html);
            let execution = input_value(&document, "execution")
                .ok_or_else(|| AuthError::upstream("无法获取统一认证 execution。"))?;
            (execution, captcha_id(&document))
        };

        let captcha_image = if let Some(captcha_id) = &captcha_id {
            let captcha_url = captcha_url(&self.endpoints.login_url, captcha_id)?;
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
                    (
                        "content-type".to_string(),
                        "application/x-www-form-urlencoded".to_string(),
                    ),
                    ("cookie".to_string(), flow.cookie.clone()),
                    ("referer".to_string(), self.endpoints.login_url.clone()),
                ],
                body: Some(HttpBody::text(form_body)),
            })
            .await?;

        if !matches!(response.status, 302 | 303) {
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
        let ticket = resolve_location(&self.endpoints.login_url, location)
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
        return Err(http_status_error(
            response.status,
            response.header("retry-after"),
            message,
        ));
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

fn login_cookie_header(response: &crate::HttpResponse) -> Option<String> {
    let values = response
        .header_values("set-cookie")
        .filter_map(|value| Cookie::parse(value.to_string()).ok())
        .map(|cookie| format!("{}={}", cookie.name(), cookie.value()))
        .collect::<Vec<_>>();
    (!values.is_empty()).then(|| values.join("; "))
}

fn input_value(document: &Html, name: &str) -> Option<String> {
    let selector = Selector::parse(&format!(r#"input[name="{name}"]"#)).ok()?;
    document
        .select(&selector)
        .filter_map(|element| element.value().attr("value"))
        .map(str::trim)
        .find(|value| !value.is_empty())
        .map(str::to_string)
}

fn captcha_id(document: &Html) -> Option<String> {
    let selector = Selector::parse("script").ok()?;
    document.select(&selector).find_map(|script| {
        quoted_property(&script.text().collect::<String>(), "config.captcha", "id")
    })
}

fn quoted_property(source: &str, object_marker: &str, property: &str) -> Option<String> {
    let object = source.split_once(object_marker)?.1;
    let object = object.split_once('{')?.1.split_once('}')?.0;
    let property_start = object.match_indices(property).find_map(|(index, _)| {
        let before = object[..index].chars().next_back();
        let after = object[index + property.len()..].chars().next();
        let is_boundary = |value: Option<char>| match value {
            Some(value) => !(value.is_ascii_alphanumeric() || value == '_'),
            None => true,
        };
        (is_boundary(before) && is_boundary(after)).then_some(index + property.len())
    })?;
    let value = object[property_start..].split_once(':')?.1.trim_start();
    let quote = value.chars().next()?;
    if !matches!(quote, '\'' | '"') {
        return None;
    }
    let value = &value[quote.len_utf8()..];
    let end = value.find(quote)?;
    (!value[..end].is_empty()).then(|| value[..end].to_string())
}

fn captcha_url(login_url: &str, captcha_id: &str) -> Result<String, AuthError> {
    let mut url =
        url::Url::parse(login_url).map_err(|error| AuthError::upstream(error.to_string()))?;
    url.set_path("/authserver/captcha");
    url.set_query(None);
    url.query_pairs_mut()
        .append_pair("captchaId", captcha_id)
        .append_pair("r", "00000");
    Ok(url.to_string())
}

fn resolve_location(base: &str, location: &str) -> Option<url::Url> {
    url::Url::parse(location).ok().or_else(|| {
        url::Url::parse(base)
            .ok()
            .and_then(|base| base.join(location).ok())
    })
}

fn parse_error_message(html: &str) -> Option<String> {
    let document = Html::parse_document(html);
    let selector = Selector::parse("#errorDiv p").ok()?;
    let message = document
        .select(&selector)
        .next()?
        .text()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    (!message.is_empty()).then_some(message)
}

fn form_url(value: &str) -> String {
    url::form_urlencoded::byte_serialize(value.as_bytes()).collect()
}

fn multipart_form(fields: Vec<(String, String)>) -> (String, String) {
    let values = fields
        .iter()
        .map(|(_, value)| value.as_bytes())
        .collect::<Vec<_>>();
    let boundary = multipart_boundary(&values);
    let mut body = String::new();
    for (name, value) in fields {
        body.push_str("--");
        body.push_str(&boundary);
        body.push_str("\r\n");
        body.push_str("Content-Disposition: form-data; name=\"");
        body.push_str(&name);
        body.push_str("\"\r\n\r\n");
        body.push_str(&value);
        body.push_str("\r\n");
    }
    body.push_str("--");
    body.push_str(&boundary);
    body.push_str("--\r\n");
    (format!("multipart/form-data; boundary={boundary}"), body)
}
