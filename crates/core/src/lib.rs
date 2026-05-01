use async_trait::async_trait;
use base64::Engine;
use open_cloud_api::{
    AuthErrorCode, CourseDetailResponse, CourseSite, GoingSite, RoleInfo, RoleName, SessionUser,
};
use open_cloud_store::{AuthSession, SessionStore};
use serde::Deserialize;
use std::collections::HashMap;
use thiserror::Error;

const PORTAL_BASIC_AUTH: &str = "Basic cG9ydGFsOnBvcnRhbF9zZWNyZXQ=";
const SWORD_BASIC_AUTH: &str = "Basic c3dvcmQ6c3dvcmRfc2VjcmV0";

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AuthEndpoints {
    pub login_url: String,
    pub course_sites_url: String,
    pub going_sites_url: String,
    pub token_url: String,
    pub roles_url: String,
    pub ucloud_referer: String,
}

impl Default for AuthEndpoints {
    fn default() -> Self {
        Self {
            login_url:
                "https://auth.bupt.edu.cn/authserver/login?service=https://ucloud.bupt.edu.cn"
                    .to_string(),
            course_sites_url: "https://apiucloud.bupt.edu.cn/ykt-site/site/list/student/current"
                .to_string(),
            going_sites_url: "https://apiucloud.bupt.edu.cn/blade-chat/web/chat/myCourse"
                .to_string(),
            token_url: "https://apiucloud.bupt.edu.cn/ykt-basics/oauth/token".to_string(),
            roles_url: "https://apiucloud.bupt.edu.cn/ykt-basics/userroledomaindept/listByUserId"
                .to_string(),
            ucloud_referer: "https://ucloud.bupt.edu.cn/".to_string(),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum HttpMethod {
    Get,
    Post,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HttpRequest {
    pub method: HttpMethod,
    pub url: String,
    pub headers: Vec<(String, String)>,
    pub body: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HttpResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl HttpResponse {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(key, _)| key.eq_ignore_ascii_case(name))
            .map(|(_, value)| value.as_str())
    }

    pub fn text(&self) -> Result<String, AuthError> {
        String::from_utf8(self.body.clone())
            .map_err(|_| AuthError::upstream("invalid upstream text"))
    }
}

#[async_trait]
pub trait HttpClient: Clone + Send + Sync + 'static {
    async fn send(&self, request: HttpRequest) -> Result<HttpResponse, AuthError>;
}

#[derive(Clone, Default)]
pub struct ReqwestHttpClient {
    client: reqwest::Client,
}

impl ReqwestHttpClient {
    pub fn new() -> Result<Self, AuthError> {
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        Ok(Self { client })
    }
}

#[async_trait]
impl HttpClient for ReqwestHttpClient {
    async fn send(&self, request: HttpRequest) -> Result<HttpResponse, AuthError> {
        let method = match request.method {
            HttpMethod::Get => reqwest::Method::GET,
            HttpMethod::Post => reqwest::Method::POST,
        };
        let mut builder = self.client.request(method, &request.url);
        for (name, value) in &request.headers {
            builder = builder.header(name, value);
        }
        if let Some(body) = request.body {
            builder = builder.body(body);
        }
        let response = builder
            .send()
            .await
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        let status = response.status().as_u16();
        let headers = response
            .headers()
            .iter()
            .filter_map(|(name, value)| {
                value
                    .to_str()
                    .ok()
                    .map(|value| (name.as_str().to_string(), value.to_string()))
            })
            .collect();
        let body = response
            .bytes()
            .await
            .map_err(|error| AuthError::upstream(error.to_string()))?
            .to_vec();
        Ok(HttpResponse {
            status,
            headers,
            body,
        })
    }
}

#[derive(Clone, Debug, Error, Eq, PartialEq)]
#[error("{message}")]
pub struct AuthError {
    pub code: AuthErrorCode,
    pub message: String,
}

impl AuthError {
    pub fn new(code: AuthErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    pub fn upstream(message: impl Into<String>) -> Self {
        Self::new(AuthErrorCode::UpstreamUnavailable, message)
    }
}

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

#[derive(Clone)]
pub struct AuthClient<C> {
    endpoints: AuthEndpoints,
    http: C,
}

impl<C> AuthClient<C>
where
    C: HttpClient,
{
    pub fn new(http: C, endpoints: AuthEndpoints) -> Self {
        Self { endpoints, http }
    }

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
                body: Some(form_body),
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
                body: Some(format!("ticket={}&grant_type=third", form_url(ticket))),
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
                body: Some(body),
            })
            .await?;
        parse_json_response(response, "刷新 token 失败。")
    }

    pub async fn get_student_courses(
        &self,
        user_id: &str,
        access_token: &str,
    ) -> Result<Vec<CourseSite>, AuthError> {
        let mut url = url::Url::parse(&self.endpoints.course_sites_url)
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        url.query_pairs_mut()
            .append_pair("current", "1")
            .append_pair("siteRoleCode", "2")
            .append_pair("size", "9999")
            .append_pair("userId", user_id);
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Get,
                url: url.to_string(),
                headers: ucloud_json_headers(SWORD_BASIC_AUTH, access_token),
                body: None,
            })
            .await?;
        let data: RawCourseSiteList = parse_ucloud_envelope(response, "课程加载失败。")?;
        Ok(normalize_course_sites(data))
    }

    pub async fn get_going_sites(
        &self,
        site_ids: &[String],
        access_token: &str,
    ) -> Result<Vec<GoingSite>, AuthError> {
        if site_ids.is_empty() {
            return Ok(Vec::new());
        }
        let mut url = url::Url::parse(&self.endpoints.going_sites_url)
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        url.query_pairs_mut()
            .append_pair("siteIds", &site_ids.join(","));
        let mut headers = ucloud_json_headers(SWORD_BASIC_AUTH, access_token);
        headers.push(("content-type".to_string(), "application/json".to_string()));
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Post,
                url: url.to_string(),
                headers,
                body: Some("{}".to_string()),
            })
            .await?;
        let data: RawGoingSiteList = parse_ucloud_envelope(response, "签到状态加载失败。")?;
        Ok(normalize_going_sites(data))
    }
}

#[derive(Clone)]
pub struct SessionManager<C, S> {
    auth: AuthClient<C>,
    store: S,
}

impl<C, S> SessionManager<C, S>
where
    C: HttpClient,
    S: SessionStore,
{
    pub fn new(auth: AuthClient<C>, store: S) -> Self {
        Self { auth, store }
    }

    pub async fn resolve_access_token(
        &self,
        session_id: &str,
        now_ms: u64,
    ) -> Result<String, AuthError> {
        let session = self.store.get(session_id, now_ms).ok_or_else(|| {
            AuthError::new(
                AuthErrorCode::SessionExpired,
                "登录会话已失效，请重新登录。",
            )
        })?;
        if session.access_token_expires_at_ms.saturating_sub(now_ms) > 60_000 {
            return Ok(session.access_token);
        }

        let next = refresh_session_if_needed(&self.auth, session, now_ms).await?;
        let access_token = next.access_token.clone();
        let refresh_token_expires_at_ms = next.refresh_token_expires_at_ms;
        self.store
            .update(session_id.to_string(), next, refresh_token_expires_at_ms);
        Ok(access_token)
    }
}

pub async fn refresh_session_if_needed<C>(
    auth: &AuthClient<C>,
    session: AuthSession,
    now_ms: u64,
) -> Result<AuthSession, AuthError>
where
    C: HttpClient,
{
    if session.access_token_expires_at_ms.saturating_sub(now_ms) > 60_000 {
        return Ok(session);
    }

    let roles = auth.get_user_roles(&session.refresh_token).await?;
    let refreshed = auth
        .refresh_user_info(&session.refresh_token, Some(session.role.clone()), &roles)
        .await?;
    let access_token_expires_at_ms = get_token_expiration_ms(&refreshed.access_token)
        .ok_or_else(|| AuthError::new(AuthErrorCode::SessionExpired, "登录会话缺少过期时间。"))?;
    let refresh_token_expires_at_ms = get_token_expiration_ms(&refreshed.refresh_token)
        .ok_or_else(|| AuthError::new(AuthErrorCode::SessionExpired, "登录会话缺少过期时间。"))?;
    Ok(AuthSession {
        access_token: refreshed.access_token,
        access_token_expires_at_ms,
        refresh_token: refreshed.refresh_token,
        refresh_token_expires_at_ms,
        role: session.role,
        user: SessionUser {
            account: refreshed.account,
            real_name: refreshed.real_name,
            user_id: refreshed.user_id,
            user_name: refreshed.user_name,
        },
    })
}

pub fn resolve_course_detail(
    courses: &[CourseSite],
    going_sites: &[GoingSite],
    site_id: &str,
) -> Result<CourseDetailResponse, AuthError> {
    let course = courses
        .iter()
        .find(|course| course.id == site_id)
        .cloned()
        .ok_or_else(|| {
            AuthError::new(
                AuthErrorCode::UnknownAuthError,
                format!("未找到课程：{site_id}。"),
            )
        })?;
    let going_site = going_sites
        .iter()
        .find(|site| site.site_id == site_id)
        .cloned();
    Ok(CourseDetailResponse { course, going_site })
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

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
struct UcloudEnvelope<T> {
    data: Option<T>,
    message: Option<String>,
    msg: Option<String>,
    success: Option<bool>,
}

impl<T> UcloudEnvelope<T> {
    fn upstream_message(self, fallback: &str) -> String {
        self.message
            .or(self.msg)
            .filter(|message| !message.trim().is_empty())
            .unwrap_or_else(|| fallback.to_string())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(untagged)]
enum RawCourseSiteList {
    Records { records: Option<Vec<RawCourseSite>> },
    Array(Vec<RawCourseSite>),
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawCourseSite {
    id: Option<serde_json::Value>,
    site_name: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(untagged)]
enum RawGoingSiteList {
    Records { records: Option<Vec<RawGoingSite>> },
    Array(Vec<RawGoingSite>),
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawGoingSite {
    group_id: Option<serde_json::Value>,
    site_id: Option<serde_json::Value>,
}

fn normalize_course_sites(payload: RawCourseSiteList) -> Vec<CourseSite> {
    let records = match payload {
        RawCourseSiteList::Records { records } => records.unwrap_or_default(),
        RawCourseSiteList::Array(records) => records,
    };
    records
        .into_iter()
        .filter_map(|record| {
            let id = value_to_string(record.id?)?;
            let site_name = record.site_name.unwrap_or_default().trim().to_string();
            if id.is_empty() || site_name.is_empty() {
                return None;
            }
            Some(CourseSite { id, site_name })
        })
        .collect()
}

fn value_to_string(value: serde_json::Value) -> Option<String> {
    match value {
        serde_json::Value::String(value) => Some(value.trim().to_string()),
        serde_json::Value::Number(value) => Some(value.to_string()),
        _ => None,
    }
}

fn normalize_going_sites(payload: RawGoingSiteList) -> Vec<GoingSite> {
    let records = match payload {
        RawGoingSiteList::Records { records } => records.unwrap_or_default(),
        RawGoingSiteList::Array(records) => records,
    };
    records
        .into_iter()
        .filter_map(|record| {
            let group_id = value_to_string(record.group_id?)?;
            let site_id = value_to_string(record.site_id?)?;
            if group_id.is_empty() || site_id.is_empty() {
                return None;
            }
            Some(GoingSite { group_id, site_id })
        })
        .collect()
}

pub fn get_token_expiration_ms(token: &str) -> Option<u64> {
    let payload = token.split('.').nth(1)?;
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload)
        .ok()?;
    let json: HashMap<String, serde_json::Value> = serde_json::from_slice(&bytes).ok()?;
    json.get("exp")?.as_u64().map(|seconds| seconds * 1000)
}

fn parse_json_response<T>(response: HttpResponse, message: &str) -> Result<T, AuthError>
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

fn parse_ucloud_envelope<T>(response: HttpResponse, fallback: &str) -> Result<T, AuthError>
where
    T: for<'de> Deserialize<'de>,
{
    if !(200..300).contains(&response.status) {
        return Err(AuthError::upstream(format!(
            "{fallback} HTTP status {}.",
            response.status
        )));
    }
    let payload: UcloudEnvelope<T> = serde_json::from_slice(&response.body)
        .map_err(|error| AuthError::upstream(error.to_string()))?;
    if payload.success == Some(false) {
        return Err(AuthError::upstream(payload.upstream_message(fallback)));
    }
    payload
        .data
        .ok_or_else(|| AuthError::upstream(fallback.to_string()))
}

fn ucloud_json_headers(basic_auth: &str, access_token: &str) -> Vec<(String, String)> {
    vec![
        ("authorization".to_string(), basic_auth.to_string()),
        ("Blade-Auth".to_string(), access_token.to_string()),
    ]
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
