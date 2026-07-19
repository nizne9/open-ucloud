use async_trait::async_trait;
use open_cloud_api::{AuthErrorCode, RoleName};
use open_cloud_core::{
    get_token_expiration_ms, resolve_course_detail, AuthError, HttpBody, HttpClient, HttpRequest,
    HttpResponse, OpenCloudClient, OpenCloudEndpoints, SessionManager,
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

fn body_text(request: &HttpRequest) -> &str {
    match request.body.as_ref().expect("request body") {
        HttpBody::Text(value) => value.as_str(),
        HttpBody::Bytes(_) => panic!("expected text body"),
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
            &[
                ("set-cookie", "route=node-1; Path=/; HttpOnly"),
                ("set-cookie", "JSESSIONID=abc; Path=/; Secure"),
            ],
            r#"<input type="hidden" value="e1" data-extra="ok" name="execution">
               <script>config.captcha = { "identity": "not-the-id", "id" : "cap-1" };</script>"#,
        ),
        response(200, &[("content-type", "image/png")], "png"),
    ]);
    let endpoints = OpenCloudEndpoints {
        login_url: "https://login.example.edu/cas/login?service=https://cloud.example.edu"
            .to_string(),
        ..OpenCloudEndpoints::default()
    };
    let client = OpenCloudClient::new(http.clone(), endpoints);

    let flow = client.start_login("2024000000").await.expect("flow starts");

    assert_eq!(flow.execution, "e1");
    assert_eq!(flow.captcha_id.as_deref(), Some("cap-1"));
    assert_eq!(
        flow.captcha_image.as_deref(),
        Some("data:image/png;base64,cG5n")
    );
    assert_eq!(flow.cookie, "route=node-1; JSESSIONID=abc");
    let requests = http.requests();
    assert!(requests[1].headers.iter().any(|(name, value)| {
        name.eq_ignore_ascii_case("cookie") && value == "route=node-1; JSESSIONID=abc"
    }));
    assert!(requests[1]
        .url
        .starts_with("https://login.example.edu/authserver/captcha?"));
}

#[tokio::test]
async fn finish_login_flow_maps_invalid_captcha() {
    let http = MockHttp::with(vec![response(
        401,
        &[],
        r#"<div id="errorDiv" class="alert alert-danger"><p><strong>Bad captcha.</strong></p></div>"#,
    )]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
    let flow = open_cloud_core::LoginFlow {
        captcha_id: Some("cap-1".to_string()),
        captcha_image: None,
        cookie: "JSESSIONID=abc".to_string(),
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
        response(303, &[("location", "/callback?ticket=ticket-1")], ""),
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
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());
    let flow = open_cloud_core::LoginFlow {
        captcha_id: None,
        captcha_image: None,
        cookie: "JSESSIONID=abc".to_string(),
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
    let requests = http.requests();
    assert!(body_text(&requests[0]).contains("username=2024000000"));
    assert!(
        requests[3].headers.iter().any(|(name, value)| {
            name.eq_ignore_ascii_case("content-type")
                && value.starts_with("multipart/form-data; boundary=")
        }),
        "refresh token request must use multipart form data like byrdocs/bupt-auth"
    );
    let refresh_body = body_text(&requests[3]);
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
    let auth = OpenCloudClient::new(http, OpenCloudEndpoints::default());
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

#[tokio::test]
async fn get_student_courses_requests_documented_endpoint_and_filters_records() {
    let http = MockHttp::with(vec![response(
        200,
        &[],
        r#"{"success":true,"data":{"records":[
          {"id":1001,"siteName":"软件测试"},
          {"id":"site-2","siteName":"  操作系统  "},
          {"id":"","siteName":"空课程"},
          {"id":"site-3","siteName":""}
        ]}}"#,
    )]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let courses = client
        .get_student_courses("u-1", "access-token")
        .await
        .expect("courses load");

    assert_eq!(courses.len(), 2);
    assert_eq!(courses[0].id, "1001");
    assert_eq!(courses[0].site_name, "软件测试");
    assert_eq!(courses[1].id, "site-2");
    assert_eq!(courses[1].site_name, "操作系统");

    let request = http.requests().pop().expect("course request");
    assert_eq!(request.method, open_cloud_core::HttpMethod::Get);
    assert!(request
        .url
        .starts_with("https://apiucloud.bupt.edu.cn/ykt-site/site/list/student/current?"));
    let url = url::Url::parse(&request.url).expect("course request url parses");
    assert_eq!(
        url.query_pairs()
            .find(|(key, _)| key == "current")
            .unwrap()
            .1,
        "1"
    );
    assert_eq!(
        url.query_pairs()
            .find(|(key, _)| key == "siteRoleCode")
            .unwrap()
            .1,
        "2"
    );
    assert_eq!(
        url.query_pairs().find(|(key, _)| key == "size").unwrap().1,
        "100"
    );
    assert_eq!(
        url.query_pairs()
            .find(|(key, _)| key == "userId")
            .unwrap()
            .1,
        "u-1"
    );
    assert!(request.headers.iter().any(|(name, value)| {
        name.eq_ignore_ascii_case("authorization") && value == "Basic c3dvcmQ6c3dvcmRfc2VjcmV0"
    }));
    assert!(request
        .headers
        .iter()
        .any(|(name, value)| name == "Blade-Auth" && value == "access-token"));
}

#[tokio::test]
async fn get_student_courses_paginates_and_deduplicates_ids() {
    let first_page = (0..100)
        .map(|index| serde_json::json!({"id": format!("site-{index}"), "siteName": format!("课程 {index}")}))
        .collect::<Vec<_>>();
    let http = MockHttp::with(vec![
        response(
            200,
            &[],
            &serde_json::json!({"success": true, "data": {"records": first_page}}).to_string(),
        ),
        response(
            200,
            &[],
            r#"{"success":true,"data":{"records":[
              {"id":"site-99","siteName":"重复课程"},
              {"id":"site-100","siteName":"新课程"}
            ]}}"#,
        ),
    ]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let courses = client
        .get_student_courses("u-1", "access-token")
        .await
        .expect("courses load");

    assert_eq!(courses.len(), 101);
    assert_eq!(courses.last().expect("last course").id, "site-100");
    let requests = http.requests();
    assert_eq!(requests.len(), 2);
    let second_url = url::Url::parse(&requests[1].url).expect("second request url parses");
    assert_eq!(
        second_url
            .query_pairs()
            .find(|(key, _)| key == "current")
            .expect("current query")
            .1,
        "2"
    );
}

#[tokio::test]
async fn get_student_courses_accepts_array_payload() {
    let http = MockHttp::with(vec![response(
        200,
        &[],
        r#"{"data":[{"id":"site-1","siteName":"软件测试"}]}"#,
    )]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

    let courses = client
        .get_student_courses("u-1", "access-token")
        .await
        .expect("courses load");

    assert_eq!(courses[0].id, "site-1");
    assert_eq!(courses[0].site_name, "软件测试");
}

#[tokio::test]
async fn get_student_courses_maps_upstream_failure() {
    let http = MockHttp::with(vec![response(
        200,
        &[],
        r#"{"success":false,"message":"课程加载失败","data":[]}"#,
    )]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

    let err = client
        .get_student_courses("u-1", "access-token")
        .await
        .expect_err("upstream failure maps");

    assert_eq!(err.code, AuthErrorCode::UpstreamUnavailable);
    assert_eq!(err.message, "课程加载失败");
}

#[tokio::test]
async fn get_student_courses_preserves_failure_message_without_data() {
    let http = MockHttp::with(vec![response(
        200,
        &[],
        r#"{"success":false,"msg":"登录已过期"}"#,
    )]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

    let err = client
        .get_student_courses("u-1", "access-token")
        .await
        .expect_err("upstream failure maps");

    assert_eq!(err.code, AuthErrorCode::UpstreamUnavailable);
    assert_eq!(err.message, "登录已过期");
}

#[tokio::test]
async fn get_student_courses_preserves_failure_msg_over_fallback() {
    let http = MockHttp::with(vec![response(
        200,
        &[],
        r#"{"success":false,"msg":"角色无权访问"}"#,
    )]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

    let err = client
        .get_student_courses("u-1", "access-token")
        .await
        .expect_err("upstream failure maps");

    assert_eq!(err.code, AuthErrorCode::UpstreamUnavailable);
    assert_eq!(err.message, "角色无权访问");
}

#[tokio::test]
async fn get_student_courses_reports_fallback_when_success_data_is_missing() {
    let http = MockHttp::with(vec![response(200, &[], r#"{"success":true}"#)]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

    let err = client
        .get_student_courses("u-1", "access-token")
        .await
        .expect_err("missing data fails");

    assert_eq!(err.code, AuthErrorCode::UpstreamUnavailable);
    assert_eq!(err.message, "课程加载失败。");
}

#[tokio::test]
async fn get_student_courses_reports_http_status_failures() {
    let http = MockHttp::with(vec![response(502, &[], r#"bad gateway"#)]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

    let err = client
        .get_student_courses("u-1", "access-token")
        .await
        .expect_err("http failure maps");

    assert_eq!(err.code, AuthErrorCode::UpstreamUnavailable);
    assert_eq!(err.message, "课程加载失败。 HTTP status 502.");
}

#[tokio::test]
async fn get_going_sites_requests_my_course_endpoint_and_filters_records() {
    let http = MockHttp::with(vec![response(
        200,
        &[],
        r#"{"success":true,"data":{"records":[
          {"groupId":2001,"siteId":1001},
          {"groupId":"group-2","siteId":"site-2"},
          {"groupId":"","siteId":"site-3"},
          {"groupId":"group-4","siteId":""}
        ]}}"#,
    )]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let going_sites = client
        .get_going_sites(&["1001".to_string(), "site-2".to_string()], "access-token")
        .await
        .expect("going sites load");

    assert_eq!(going_sites.len(), 2);
    assert_eq!(going_sites[0].group_id, "2001");
    assert_eq!(going_sites[0].site_id, "1001");
    assert_eq!(going_sites[1].group_id, "group-2");
    assert_eq!(going_sites[1].site_id, "site-2");

    let request = http.requests().pop().expect("going sites request");
    assert_eq!(request.method, open_cloud_core::HttpMethod::Post);
    assert!(request
        .url
        .starts_with("https://apiucloud.bupt.edu.cn/blade-chat/web/chat/myCourse?"));
    let url = url::Url::parse(&request.url).expect("going sites request url parses");
    assert_eq!(
        url.query_pairs()
            .find(|(key, _)| key == "siteIds")
            .unwrap()
            .1,
        "1001,site-2"
    );
    assert_eq!(body_text(&request), "{}");
    assert!(request.headers.iter().any(|(name, value)| {
        name.eq_ignore_ascii_case("content-type") && value == "application/json"
    }));
    assert!(request
        .headers
        .iter()
        .any(|(name, value)| name == "Blade-Auth" && value == "access-token"));
}

#[tokio::test]
async fn get_going_sites_skips_request_when_no_course_ids_exist() {
    let http = MockHttp::default();
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let going_sites = client
        .get_going_sites(&[], "access-token")
        .await
        .expect("empty course ids succeed");

    assert!(going_sites.is_empty());
    assert!(http.requests().is_empty());
}

#[tokio::test]
async fn get_going_sites_maps_upstream_failure() {
    let http = MockHttp::with(vec![response(
        200,
        &[],
        r#"{"success":false,"msg":"签到状态加载失败"}"#,
    )]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

    let err = client
        .get_going_sites(&["1001".to_string()], "access-token")
        .await
        .expect_err("upstream failure maps");

    assert_eq!(err.code, AuthErrorCode::UpstreamUnavailable);
    assert_eq!(err.message, "签到状态加载失败");
}

#[test]
fn parse_attendance_qr_payload_accepts_official_checkwork_value() {
    let payload = open_cloud_core::parse_attendance_qr_payload(
        "checkwork|id=attendance-1&siteId=site-1&createTime=2026-05-08+09:30:00&classLessonId=group-1",
    )
    .expect("payload parses");

    assert_eq!(payload.attendance_id, "attendance-1");
    assert_eq!(payload.site_id, "site-1");
    assert_eq!(payload.create_time, "2026-05-08+09:30:00");
    assert_eq!(payload.class_lesson_id, "group-1");
}

#[test]
fn parse_attendance_qr_payload_rejects_incomplete_or_unsupported_values() {
    let missing = open_cloud_core::parse_attendance_qr_payload(
        "checkwork|id=attendance-1&siteId=site-1&createTime=clock-1",
    )
    .expect_err("missing class lesson is rejected");
    assert_eq!(missing.message, "签到二维码内容无效或不完整。");

    assert!(open_cloud_core::parse_attendance_qr_payload(
        "checkwork|id=attendance-1&siteId=site-1&createTime=clock-1&classLessonId=group-1&extra=1",
    )
    .is_err());
    assert!(open_cloud_core::parse_attendance_qr_payload(
        "checkwork|id=attendance-1&siteId=site-1&createTime=clock-1&classLessonId=group-1&id=other",
    )
    .is_err());
    assert!(open_cloud_core::parse_attendance_qr_payload("site-1:group-1").is_err());
}

#[test]
fn resolve_course_detail_matches_course_and_going_site() {
    let courses = vec![
        open_cloud_api::CourseSite {
            id: "site-1".to_string(),
            site_name: "软件测试".to_string(),
        },
        open_cloud_api::CourseSite {
            id: "site-2".to_string(),
            site_name: "操作系统".to_string(),
        },
    ];
    let going_sites = vec![open_cloud_api::GoingSite {
        group_id: "group-1".to_string(),
        site_id: "site-2".to_string(),
    }];

    let detail = resolve_course_detail(&courses, &going_sites, "site-2").expect("course exists");

    assert_eq!(detail.course.site_name, "操作系统");
    assert_eq!(
        detail
            .going_site
            .as_ref()
            .map(|site| site.group_id.as_str()),
        Some("group-1")
    );
}

#[test]
fn resolve_course_detail_reports_missing_course() {
    let courses = vec![open_cloud_api::CourseSite {
        id: "site-1".to_string(),
        site_name: "软件测试".to_string(),
    }];

    let err = resolve_course_detail(&courses, &[], "missing").expect_err("course is missing");

    assert_eq!(err.code, AuthErrorCode::NotFound);
    assert_eq!(err.message, "未找到课程：missing。");
}

#[tokio::test]
async fn refresh_user_info_maps_401_to_session_expired() {
    let http = MockHttp::with(vec![response(401, &[], "unauthorized")]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

    let err = client
        .refresh_user_info("refresh-token", None, &[])
        .await
        .expect_err("401 fails the refresh");

    assert_eq!(err.code, AuthErrorCode::SessionExpired);
}

#[tokio::test]
async fn role_lookup_rate_limit_preserves_retry_after() {
    let http = MockHttp::with(vec![response(
        429,
        &[("Retry-After", "30")],
        "too many requests",
    )]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

    let err = client
        .get_user_roles("token")
        .await
        .expect_err("429 fails the request");

    assert_eq!(err.code, AuthErrorCode::RateLimited);
    assert_eq!(err.retry_after_seconds, Some(30));
}
