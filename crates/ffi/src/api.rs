use open_cloud_api::{AuthErrorCode, AuthErrorResponse};
use open_cloud_core::{
    refresh_session_if_needed, LoginFlow, OpenCloudClient, OpenCloudEndpoints, ReqwestHttpClient,
};
use open_cloud_store::AuthSession;
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiLoginFlow {
    pub captcha_id: Option<String>,
    pub captcha_image: Option<String>,
    pub cookie: String,
    pub created_at_ms: u64,
    pub execution: String,
    pub username: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum FfiAuthErrorCode {
    CaptchaRequired,
    CaptchaInvalid,
    EmptyUpload,
    FileTooLarge,
    InvalidFileName,
    FileTypeNotAllowed,
    FlowExpired,
    InvalidCredentials,
    RoleNotFound,
    SecureStorageUnavailable,
    SessionExpired,
    UpstreamUnavailable,
    UnknownAuthError,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum FfiRoleName {
    #[serde(rename = "学生")]
    Student,
    #[serde(rename = "教师")]
    Teacher,
    #[serde(rename = "助教")]
    Assistant,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiRoleInfo {
    pub domain_id: String,
    pub domain_name: String,
    pub id: String,
    pub role_aliase: String,
    pub role_id: String,
    pub role_name: FfiRoleName,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiSessionUser {
    pub account: String,
    pub real_name: String,
    pub user_id: String,
    pub user_name: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiAuthStartResult {
    pub captcha_image: Option<String>,
    pub flow_id: String,
    pub requires_captcha: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiAuthFinishRequest {
    pub captcha: Option<String>,
    pub flow_id: String,
    pub password: String,
    pub role: Option<FfiRoleName>,
    pub username: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiAuthFinishResult {
    pub roles: Vec<FfiRoleInfo>,
    pub selected_role: FfiRoleName,
    pub user: FfiSessionUser,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiAuthSessionResponse {
    pub selected_role: FfiRoleName,
    pub user: FfiSessionUser,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiCourseSite {
    pub id: String,
    pub site_name: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiGoingSite {
    pub group_id: String,
    pub site_id: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiAuthStartResponse {
    pub auth: FfiAuthStartResult,
    pub flow: FfiLoginFlow,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiAuthFinishResponse {
    pub auth: FfiAuthFinishResult,
    pub session_payload: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiCourseResponse {
    pub records: Vec<FfiCourseSite>,
    pub going_sites: Vec<FfiGoingSite>,
    pub updated_session_payload: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiLogoutResponse {
    pub clear_session: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FfiAuthError {
    pub code: FfiAuthErrorCode,
    pub message: String,
    pub retry_after_seconds: Option<u64>,
}

impl From<AuthErrorResponse> for FfiAuthError {
    fn from(value: AuthErrorResponse) -> Self {
        Self {
            code: value.code.into(),
            message: value.message,
            retry_after_seconds: value.retry_after_seconds,
        }
    }
}

pub async fn auth_start(username: String) -> Result<FfiAuthStartResponse, FfiAuthError> {
    let client = default_client()?;
    auth_start_with_client(&client, username).await
}

pub async fn auth_finish(
    request: FfiAuthFinishRequest,
    flow: FfiLoginFlow,
) -> Result<FfiAuthFinishResponse, FfiAuthError> {
    let client = default_client()?;
    auth_finish_with_client(&client, request, flow).await
}

pub fn session_summary(session_payload: String) -> Result<FfiAuthSessionResponse, FfiAuthError> {
    let session = decode_session_payload(&session_payload, now_ms())?;
    Ok(FfiAuthSessionResponse {
        selected_role: session.role.into(),
        user: session.user.into(),
    })
}

pub async fn courses(
    session_payload: String,
    with_going: bool,
) -> Result<FfiCourseResponse, FfiAuthError> {
    let client = default_client()?;
    courses_with_client(&client, session_payload, with_going, now_ms()).await
}

pub fn logout() -> FfiLogoutResponse {
    FfiLogoutResponse {
        clear_session: true,
    }
}

async fn auth_start_with_client<C>(
    client: &OpenCloudClient<C>,
    username: String,
) -> Result<FfiAuthStartResponse, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    let flow = client.start_login(&username).await.map_err(to_ffi_error)?;
    let response = FfiAuthStartResult {
        captcha_image: flow.captcha_image.clone(),
        flow_id: flow.execution.clone(),
        requires_captcha: flow.captcha_id.is_some(),
    };
    Ok(FfiAuthStartResponse {
        auth: response,
        flow: flow.into(),
    })
}

async fn auth_finish_with_client<C>(
    client: &OpenCloudClient<C>,
    request: FfiAuthFinishRequest,
    flow: FfiLoginFlow,
) -> Result<FfiAuthFinishResponse, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    if request.username != flow.username || request.flow_id != flow.execution {
        return Err(error(
            AuthErrorCode::FlowExpired,
            "登录流程已失效，请重新开始登录。",
        ));
    }

    let result = client
        .finish_login(
            flow.into(),
            &request.password,
            request.role.map(Into::into),
            request.captcha.as_deref(),
        )
        .await
        .map_err(to_ffi_error)?;
    let session = AuthSession {
        access_token: result.access_token,
        access_token_expires_at_ms: result.access_token_expires_at_ms,
        refresh_token: result.refresh_token,
        refresh_token_expires_at_ms: result.refresh_token_expires_at_ms,
        role: result.selected_role.clone(),
        user: result.user.clone(),
    };
    Ok(FfiAuthFinishResponse {
        auth: FfiAuthFinishResult {
            roles: result.roles.into_iter().map(Into::into).collect(),
            selected_role: result.selected_role.into(),
            user: result.user.into(),
        },
        session_payload: encode_session_payload(&session)?,
    })
}

async fn courses_with_client<C>(
    client: &OpenCloudClient<C>,
    session_payload: String,
    with_going: bool,
    now_ms: u64,
) -> Result<FfiCourseResponse, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    let session = decode_session_payload(&session_payload, now_ms)?;
    let original = session.clone();
    let refreshed = refresh_session_if_needed(client, session, now_ms)
        .await
        .map_err(to_ffi_error)?;
    let updated_session_payload = if refreshed != original {
        Some(encode_session_payload(&refreshed)?)
    } else {
        None
    };
    let records = client
        .get_student_courses(&refreshed.user.user_id, &refreshed.access_token)
        .await
        .map_err(to_ffi_error)?;
    let going_sites = if with_going {
        let site_ids = records
            .iter()
            .map(|course| course.id.clone())
            .collect::<Vec<_>>();
        client
            .get_going_sites(&site_ids, &refreshed.access_token)
            .await
            .map_err(to_ffi_error)?
    } else {
        Vec::new()
    };
    Ok(FfiCourseResponse {
        records: records.into_iter().map(Into::into).collect(),
        going_sites: going_sites.into_iter().map(Into::into).collect(),
        updated_session_payload,
    })
}

fn default_client() -> Result<OpenCloudClient<ReqwestHttpClient>, FfiAuthError> {
    let http = ReqwestHttpClient::new().map_err(to_ffi_error)?;
    Ok(OpenCloudClient::new(http, OpenCloudEndpoints::default()))
}

fn encode_session_payload(session: &AuthSession) -> Result<String, FfiAuthError> {
    serde_json::to_string(session).map_err(|source| {
        error(
            AuthErrorCode::UnknownAuthError,
            format!("登录会话编码失败：{source}"),
        )
    })
}

fn decode_session_payload(session_payload: &str, now_ms: u64) -> Result<AuthSession, FfiAuthError> {
    let session = serde_json::from_str::<AuthSession>(session_payload).map_err(|_| {
        error(
            AuthErrorCode::SessionExpired,
            "登录会话已损坏，请重新登录。",
        )
    })?;
    if session.refresh_token_expires_at_ms <= now_ms {
        return Err(error(
            AuthErrorCode::SessionExpired,
            "登录会话已失效，请重新登录。",
        ));
    }
    Ok(session)
}

fn to_ffi_error(error_value: open_cloud_core::AuthError) -> FfiAuthError {
    error(error_value.code, error_value.message)
}

fn error(code: AuthErrorCode, message: impl Into<String>) -> FfiAuthError {
    FfiAuthError {
        code: code.into(),
        message: message.into(),
        retry_after_seconds: None,
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock before unix epoch")
        .as_millis() as u64
}

impl From<LoginFlow> for FfiLoginFlow {
    fn from(value: LoginFlow) -> Self {
        Self {
            captcha_id: value.captcha_id,
            captcha_image: value.captcha_image,
            cookie: value.cookie,
            created_at_ms: value.created_at_ms,
            execution: value.execution,
            username: value.username,
        }
    }
}

impl From<FfiLoginFlow> for LoginFlow {
    fn from(value: FfiLoginFlow) -> Self {
        Self {
            captcha_id: value.captcha_id,
            captcha_image: value.captcha_image,
            cookie: value.cookie,
            created_at_ms: value.created_at_ms,
            execution: value.execution,
            username: value.username,
        }
    }
}

impl From<AuthErrorCode> for FfiAuthErrorCode {
    fn from(value: AuthErrorCode) -> Self {
        match value {
            AuthErrorCode::CaptchaRequired => Self::CaptchaRequired,
            AuthErrorCode::CaptchaInvalid => Self::CaptchaInvalid,
            AuthErrorCode::EmptyUpload => Self::EmptyUpload,
            AuthErrorCode::FileTooLarge => Self::FileTooLarge,
            AuthErrorCode::InvalidFileName => Self::InvalidFileName,
            AuthErrorCode::FileTypeNotAllowed => Self::FileTypeNotAllowed,
            AuthErrorCode::FlowExpired => Self::FlowExpired,
            AuthErrorCode::InvalidCredentials => Self::InvalidCredentials,
            AuthErrorCode::RoleNotFound => Self::RoleNotFound,
            AuthErrorCode::SecureStorageUnavailable => Self::SecureStorageUnavailable,
            AuthErrorCode::SessionExpired => Self::SessionExpired,
            AuthErrorCode::UpstreamUnavailable => Self::UpstreamUnavailable,
            AuthErrorCode::UnknownAuthError => Self::UnknownAuthError,
        }
    }
}

impl From<FfiRoleName> for open_cloud_api::RoleName {
    fn from(value: FfiRoleName) -> Self {
        match value {
            FfiRoleName::Student => Self::Student,
            FfiRoleName::Teacher => Self::Teacher,
            FfiRoleName::Assistant => Self::Assistant,
        }
    }
}

impl From<open_cloud_api::RoleName> for FfiRoleName {
    fn from(value: open_cloud_api::RoleName) -> Self {
        match value {
            open_cloud_api::RoleName::Student => Self::Student,
            open_cloud_api::RoleName::Teacher => Self::Teacher,
            open_cloud_api::RoleName::Assistant => Self::Assistant,
        }
    }
}

impl From<open_cloud_api::RoleInfo> for FfiRoleInfo {
    fn from(value: open_cloud_api::RoleInfo) -> Self {
        Self {
            domain_id: value.domain_id,
            domain_name: value.domain_name,
            id: value.id,
            role_aliase: value.role_aliase,
            role_id: value.role_id,
            role_name: value.role_name.into(),
        }
    }
}

impl From<open_cloud_api::SessionUser> for FfiSessionUser {
    fn from(value: open_cloud_api::SessionUser) -> Self {
        Self {
            account: value.account,
            real_name: value.real_name,
            user_id: value.user_id,
            user_name: value.user_name,
        }
    }
}

impl From<open_cloud_api::CourseSite> for FfiCourseSite {
    fn from(value: open_cloud_api::CourseSite) -> Self {
        Self {
            id: value.id,
            site_name: value.site_name,
        }
    }
}

impl From<open_cloud_api::GoingSite> for FfiGoingSite {
    fn from(value: open_cloud_api::GoingSite) -> Self {
        Self {
            group_id: value.group_id,
            site_id: value.site_id,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;
    use open_cloud_api::{RoleName, SessionUser};
    use open_cloud_core::{AuthError, HttpRequest, HttpResponse};
    use std::collections::VecDeque;
    use std::sync::{Arc, Mutex};

    #[derive(Clone, Default)]
    struct MockHttp {
        responses: Arc<Mutex<VecDeque<HttpResponse>>>,
    }

    impl MockHttp {
        fn with(responses: Vec<HttpResponse>) -> Self {
            Self {
                responses: Arc::new(Mutex::new(VecDeque::from(responses))),
            }
        }
    }

    #[async_trait]
    impl open_cloud_core::HttpClient for MockHttp {
        async fn send(&self, _request: HttpRequest) -> Result<HttpResponse, AuthError> {
            self.responses
                .lock()
                .expect("responses lock")
                .pop_front()
                .ok_or_else(|| AuthError::upstream("missing mock response"))
        }
    }

    fn response(status: u16, headers: &[(&str, &str)], body: &str) -> HttpResponse {
        HttpResponse {
            status,
            headers: headers
                .iter()
                .map(|(name, value)| (name.to_string(), value.to_string()))
                .collect(),
            body: body.as_bytes().to_vec(),
        }
    }

    fn jwt_with_exp(exp: u64) -> String {
        let header = base64_url(r#"{"alg":"none"}"#);
        let payload = base64_url(&format!(r#"{{"exp":{exp}}}"#));
        format!("{header}.{payload}.sig")
    }

    fn future_exp(seconds_from_now: u64) -> u64 {
        now_ms() / 1000 + seconds_from_now
    }

    fn base64_url(input: &str) -> String {
        use base64::Engine;
        base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(input)
    }

    fn user() -> SessionUser {
        SessionUser {
            account: "2024000000".to_string(),
            real_name: "Alice".to_string(),
            user_id: "u-1".to_string(),
            user_name: "2024000000".to_string(),
        }
    }

    fn session(access_exp: u64, refresh_exp: u64) -> AuthSession {
        AuthSession {
            access_token: jwt_with_exp(access_exp),
            access_token_expires_at_ms: access_exp * 1000,
            refresh_token: jwt_with_exp(refresh_exp),
            refresh_token_expires_at_ms: refresh_exp * 1000,
            role: RoleName::Student,
            user: user(),
        }
    }

    #[test]
    fn session_summary_does_not_expose_tokens() {
        let payload = encode_session_payload(&session(future_exp(10_000), future_exp(20_000)))
            .expect("session encodes");

        let summary = session_summary(payload).expect("summary loads");

        assert_eq!(summary.user.real_name, "Alice");
        assert_eq!(summary.selected_role, FfiRoleName::Student);
    }

    #[test]
    fn broken_session_payload_returns_stable_error() {
        let err = session_summary("not json".to_string()).expect_err("payload fails");

        assert_eq!(err.code, FfiAuthErrorCode::SessionExpired);
    }

    #[test]
    fn expired_refresh_token_returns_session_expired() {
        let payload = encode_session_payload(&session(1, 1)).expect("session encodes");

        let err = decode_session_payload(&payload, 2_000).expect_err("session expires");

        assert_eq!(err.code, FfiAuthErrorCode::SessionExpired);
    }

    #[tokio::test]
    async fn auth_finish_returns_session_payload_and_public_summary() {
        let access = jwt_with_exp(future_exp(4_200));
        let refresh = jwt_with_exp(future_exp(9_200));
        let http = MockHttp::with(vec![
            response(
                302,
                &[("location", "https://ucloud.bupt.edu.cn?ticket=ticket-1")],
                "",
            ),
            response(
                200,
                &[],
                &format!(
                    r#"{{
                      "access_token":"first-access",
                      "refresh_token":"{refresh}",
                      "expires_in":3600,
                      "account":"2024000000",
                      "real_name":"Alice",
                      "user_id":"u-1",
                      "user_name":"2024000000"
                    }}"#
                ),
            ),
            response(
                200,
                &[],
                r#"{"data":[{"domainId":"d","domainName":"教学空间","id":"identity-1","roleAliase":"学生","roleId":"role-1","roleName":"学生"}]}"#,
            ),
            response(
                200,
                &[],
                &format!(
                    r#"{{
                      "access_token":"{access}",
                      "refresh_token":"{refresh}",
                      "expires_in":3600,
                      "account":"2024000000",
                      "real_name":"Alice",
                      "user_id":"u-1",
                      "user_name":"2024000000"
                    }}"#
                ),
            ),
        ]);
        let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

        let result = auth_finish_with_client(
            &client,
            FfiAuthFinishRequest {
                captcha: None,
                flow_id: "e1".to_string(),
                password: "password".to_string(),
                role: Some(FfiRoleName::Student),
                username: "2024000000".to_string(),
            },
            FfiLoginFlow {
                captcha_id: None,
                captcha_image: None,
                cookie: "JSESSIONID=abc".to_string(),
                created_at_ms: 1,
                execution: "e1".to_string(),
                username: "2024000000".to_string(),
            },
        )
        .await
        .expect("login succeeds");

        assert_eq!(result.auth.user.real_name, "Alice");
        assert_eq!(result.auth.roles.len(), 1);
        let summary = session_summary(result.session_payload).expect("summary loads");
        assert_eq!(summary.user, user().into());
    }

    #[tokio::test]
    async fn courses_refreshes_expiring_session_and_returns_updated_payload() {
        let refreshed_access = jwt_with_exp(8_000);
        let refreshed_refresh = jwt_with_exp(16_000);
        let http = MockHttp::with(vec![
            response(
                200,
                &[],
                r#"{"data":[{"domainId":"d","domainName":"教学空间","id":"identity-1","roleAliase":"学生","roleId":"role-1","roleName":"学生"}]}"#,
            ),
            response(
                200,
                &[],
                &format!(
                    r#"{{
                      "access_token":"{refreshed_access}",
                      "refresh_token":"{refreshed_refresh}",
                      "expires_in":3600,
                      "account":"2024000000",
                      "real_name":"Alice",
                      "user_id":"u-1",
                      "user_name":"2024000000"
                    }}"#
                ),
            ),
            response(
                200,
                &[],
                r#"{"success":true,"data":{"records":[{"id":"site-1","siteName":"软件测试"}]}}"#,
            ),
            response(
                200,
                &[],
                r#"{"success":true,"data":{"records":[{"groupId":"group-1","siteId":"site-1"}]}}"#,
            ),
        ]);
        let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
        let payload = encode_session_payload(&session(101, 1_000)).expect("session encodes");

        let result = courses_with_client(&client, payload, true, 100_500)
            .await
            .expect("courses load");

        assert_eq!(
            result.records,
            vec![FfiCourseSite {
                id: "site-1".to_string(),
                site_name: "软件测试".to_string()
            }]
        );
        assert_eq!(result.going_sites[0].group_id, "group-1");
        let updated = result
            .updated_session_payload
            .expect("refreshed session payload");
        assert!(updated.contains(&refreshed_access));
    }

    #[tokio::test]
    async fn courses_without_going_keeps_session_payload_when_access_token_is_valid() {
        let http = MockHttp::with(vec![response(
            200,
            &[],
            r#"{"success":true,"data":{"records":[{"id":"site-1","siteName":"软件测试"}]}}"#,
        )]);
        let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
        let payload = encode_session_payload(&session(future_exp(10_000), future_exp(20_000)))
            .expect("session encodes");

        let result = courses_with_client(&client, payload, false, 100_500)
            .await
            .expect("courses load");

        assert_eq!(result.records.len(), 1);
        assert!(result.going_sites.is_empty());
        assert_eq!(result.updated_session_payload, None);
    }
}
