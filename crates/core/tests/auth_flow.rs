use async_trait::async_trait;
use open_cloud_api::{AuthErrorCode, RoleName};
use open_cloud_core::{
    get_token_expiration_ms, AuthClient, AuthEndpoints, AuthError, HttpClient, HttpRequest,
    HttpResponse, SessionManager,
};
use open_cloud_store::{AuthSession, MemorySessionStore, SessionStore};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

#[derive(Clone, Default)]
struct MockHttp {
    responses: Arc<Mutex<VecDeque<HttpResponse>>>,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

impl MockHttp {
    fn with(responses: Vec<HttpResponse>) -> Self {
        Self {
            responses: Arc::new(Mutex::new(VecDeque::from(responses))),
            requests: Arc::new(Mutex::new(Vec::new())),
        }
    }

    fn requests(&self) -> Vec<HttpRequest> {
        self.requests.lock().expect("requests lock").clone()
    }
}

#[async_trait]
impl HttpClient for MockHttp {
    async fn send(&self, request: HttpRequest) -> Result<HttpResponse, AuthError> {
        self.requests.lock().expect("requests lock").push(request);
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

fn base64_url(input: &str) -> String {
    use base64::Engine;
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(input)
}

#[tokio::test]
async fn start_login_flow_extracts_execution_and_captcha() {
    let http = MockHttp::with(vec![
        response(
            200,
            &[("set-cookie", "JSESSIONID=abc; Path=/")],
            r#"<input name="execution" value="e1"><script>config.captcha = { id: 'cap-1' }</script>"#,
        ),
        response(200, &[("content-type", "image/png")], "png"),
    ]);
    let client = AuthClient::new(http.clone(), AuthEndpoints::default());

    let flow = client.start_login("2024000000").await.expect("flow starts");

    assert_eq!(flow.execution, "e1");
    assert_eq!(flow.captcha_id.as_deref(), Some("cap-1"));
    assert_eq!(
        flow.captcha_image.as_deref(),
        Some("data:image/png;base64,cG5n")
    );
    assert_eq!(flow.cookie, "JSESSIONID=abc");
}

#[tokio::test]
async fn finish_login_flow_maps_invalid_captcha() {
    let http = MockHttp::with(vec![response(
        401,
        &[],
        r#"<div class="alert alert-danger" id="errorDiv"><p>Bad captcha.</p></div>"#,
    )]);
    let client = AuthClient::new(http, AuthEndpoints::default());
    let flow = open_cloud_core::LoginFlow {
        captcha_id: Some("cap-1".to_string()),
        captcha_image: None,
        cookie: "JSESSIONID=abc".to_string(),
        created_at_ms: 1,
        execution: "e1".to_string(),
        username: "2024000000".to_string(),
    };

    let err = client
        .finish_login(flow, "password", None, Some("0000"))
        .await
        .expect_err("captcha should fail");

    assert_eq!(err.code, AuthErrorCode::CaptchaInvalid);
}

#[tokio::test]
async fn finish_login_flow_exchanges_ticket_and_selects_role() {
    let access = jwt_with_exp(4_200);
    let refresh = jwt_with_exp(9_200);
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
    let client = AuthClient::new(http.clone(), AuthEndpoints::default());
    let flow = open_cloud_core::LoginFlow {
        captcha_id: None,
        captcha_image: None,
        cookie: "JSESSIONID=abc".to_string(),
        created_at_ms: 1,
        execution: "e1".to_string(),
        username: "2024000000".to_string(),
    };

    let result = client
        .finish_login(flow, "password", Some(RoleName::Student), None)
        .await
        .expect("login succeeds");

    assert_eq!(result.selected_role, RoleName::Student);
    assert_eq!(result.user.real_name, "Alice");
    assert_eq!(result.roles[0].id, "identity-1");
    assert_eq!(result.access_token_expires_at_ms, 4_200_000);
    assert_eq!(result.refresh_token_expires_at_ms, 9_200_000);
    assert!(http.requests()[0]
        .body
        .as_deref()
        .unwrap()
        .contains("username=2024000000"));
    let requests = http.requests();
    assert!(
        requests[3].headers.iter().any(|(name, value)| {
            name.eq_ignore_ascii_case("content-type")
                && value.starts_with("multipart/form-data; boundary=")
        }),
        "refresh token request must use multipart form data like byrdocs/bupt-auth"
    );
    let refresh_body = requests[3].body.as_deref().expect("refresh body");
    assert!(refresh_body.contains(r#"name="grant_type""#));
    assert!(refresh_body.contains("refresh_token"));
    assert!(refresh_body.contains(r#"name="identity""#));
}

#[test]
fn parses_jwt_expiration_milliseconds() {
    assert_eq!(get_token_expiration_ms(&jwt_with_exp(42)), Some(42_000));
    assert_eq!(get_token_expiration_ms("not-a-jwt"), None);
}

#[tokio::test]
async fn session_manager_refreshes_expiring_access_token() {
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
    ]);
    let auth = AuthClient::new(http, AuthEndpoints::default());
    let store = MemorySessionStore::default();
    store.create(
        "s-1".to_string(),
        AuthSession {
            access_token: jwt_with_exp(101),
            access_token_expires_at_ms: 101_000,
            refresh_token: jwt_with_exp(1_000),
            refresh_token_expires_at_ms: 1_000_000,
            role: RoleName::Student,
            user: open_cloud_api::SessionUser {
                account: "2024000000".to_string(),
                real_name: "Alice".to_string(),
                user_id: "u-1".to_string(),
                user_name: "2024000000".to_string(),
            },
        },
        1_000_000,
    );
    let manager = SessionManager::new(auth, store.clone());

    let token = manager
        .resolve_access_token("s-1", 100_500)
        .await
        .expect("session refreshes");

    assert_eq!(token, refreshed_access);
    assert_eq!(
        store
            .get("s-1", 100_500)
            .expect("updated session")
            .access_token_expires_at_ms,
        8_000_000
    );
}
