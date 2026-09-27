use open_ucloud_api::AuthErrorCode;
use open_ucloud_core::{HttpBody, HttpRequest, OpenUcloudClient, OpenUcloudEndpoints};

mod common;
use common::{response, MockHttp};

fn body_json(request: &HttpRequest) -> serde_json::Value {
    let body = match request.body.as_ref().expect("request body") {
        HttpBody::Text(value) => value.as_str(),
        HttpBody::Bytes(_) => panic!("expected text body"),
    };
    serde_json::from_str(body).expect("request body is json")
}

fn test_endpoints() -> OpenUcloudEndpoints {
    OpenUcloudEndpoints {
        attendance_basic_url: "https://api.example/attendance/basic".to_string(),
        attendance_sign_url: "https://api.example/attendance/sign".to_string(),
        clock_url: "https://api.example/clock".to_string(),
        ..OpenUcloudEndpoints::default()
    }
}

#[tokio::test]
async fn basic_id_request_posts_identifiers_and_returns_id() {
    let http = MockHttp::with(vec![response(
        200,
        r#"{"success":true,"data":{"attendanceBasicInfo":{"id":"att-1"}}}"#,
    )]);
    let client = OpenUcloudClient::new(http.clone(), test_endpoints());

    let attendance_id = client
        .get_attendance_basic_id("site-1", "group-1", "access-1")
        .await
        .expect("basic id resolves");

    assert_eq!(attendance_id, "att-1");
    let requests = http.requests();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].url, "https://api.example/attendance/basic");
    let body = body_json(&requests[0]);
    assert_eq!(body["siteId"], "site-1");
    assert_eq!(body["groupId"], "group-1");
    assert!(requests[0]
        .headers
        .iter()
        .any(|(name, value)| name.eq_ignore_ascii_case("Blade-Auth") && value == "access-1"));
}

#[tokio::test]
async fn basic_id_rejects_empty_identifiers_without_a_request() {
    let http = MockHttp::with(Vec::new());
    let client = OpenUcloudClient::new(http.clone(), test_endpoints());

    let err = client
        .get_attendance_basic_id("", "group-1", "access-1")
        .await
        .expect_err("empty site fails");
    assert_eq!(err.code, AuthErrorCode::InvalidInput);

    let err = client
        .get_attendance_basic_id("site-1", "", "access-1")
        .await
        .expect_err("empty group fails");
    assert_eq!(err.code, AuthErrorCode::InvalidInput);

    let err = client
        .get_attendance_basic_id("   ", "group-1", "access-1")
        .await
        .expect_err("whitespace site fails");
    assert_eq!(err.code, AuthErrorCode::InvalidInput);
    assert!(http.requests().is_empty());
}

#[tokio::test]
async fn sign_rejects_empty_identifiers_without_a_request() {
    let http = MockHttp::with(Vec::new());
    let client = OpenUcloudClient::new(http.clone(), test_endpoints());

    let err = client
        .sign_attendance("", "group-1", "user-1", "access-1")
        .await
        .expect_err("empty site fails");
    assert_eq!(err.code, AuthErrorCode::InvalidInput);

    let err = client
        .sign_attendance("site-1", "", "user-1", "access-1")
        .await
        .expect_err("empty group fails");
    assert_eq!(err.code, AuthErrorCode::InvalidInput);

    let err = client
        .sign_attendance("site-1", "group-1", "", "access-1")
        .await
        .expect_err("empty user fails");
    assert_eq!(err.code, AuthErrorCode::InvalidInput);

    let err = client
        .sign_attendance("   ", "group-1", "user-1", "access-1")
        .await
        .expect_err("whitespace site fails");
    assert_eq!(err.code, AuthErrorCode::InvalidInput);
    assert!(http.requests().is_empty());
}

#[tokio::test]
async fn prepare_qr_rejects_empty_identifiers_without_a_request() {
    let http = MockHttp::with(Vec::new());
    let client = OpenUcloudClient::new(http.clone(), test_endpoints());

    let err = client
        .prepare_attendance_qr("", "group-1", "access-1")
        .await
        .expect_err("empty site fails");
    assert_eq!(err.code, AuthErrorCode::InvalidInput);

    let err = client
        .prepare_attendance_qr("site-1", "", "access-1")
        .await
        .expect_err("empty group fails");
    assert_eq!(err.code, AuthErrorCode::InvalidInput);

    let err = client
        .prepare_attendance_qr("site-1", "   ", "access-1")
        .await
        .expect_err("whitespace group fails");
    assert_eq!(err.code, AuthErrorCode::InvalidInput);
    assert!(http.requests().is_empty());
}

#[tokio::test]
async fn basic_id_reports_not_found_when_upstream_id_is_missing() {
    let http = MockHttp::with(vec![response(
        200,
        r#"{"success":true,"data":{"attendanceBasicInfo":{"id":""}}}"#,
    )]);
    let client = OpenUcloudClient::new(http, test_endpoints());

    let err = client
        .get_attendance_basic_id("site-1", "group-1", "access-1")
        .await
        .expect_err("missing id fails");

    assert_eq!(err.code, AuthErrorCode::NotFound);
}

#[tokio::test]
async fn clock_param_gets_endpoint_and_returns_nested_data() {
    let http = MockHttp::with(vec![response(
        200,
        r#"{"success":true,"data":{"data":"1700000000000"}}"#,
    )]);
    let client = OpenUcloudClient::new(http.clone(), test_endpoints());

    let clock = client
        .get_attendance_clock_param("access-1")
        .await
        .expect("clock resolves");

    assert_eq!(clock, "1700000000000");
    let requests = http.requests();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].url, "https://api.example/clock");
}

#[tokio::test]
async fn sign_submits_full_payload_and_reports_ok() {
    let http = MockHttp::with(vec![
        response(
            200,
            r#"{"success":true,"data":{"attendanceBasicInfo":{"id":"att-1"}}}"#,
        ),
        response(200, r#"{"success":true,"data":{"data":"clock-1"}}"#),
        response(200, r#"{"success":true}"#),
    ]);
    let client = OpenUcloudClient::new(http.clone(), test_endpoints());

    let result = client
        .sign_attendance("site-1", "group-1", "user-1", "access-1")
        .await
        .expect("sign succeeds");

    assert!(result.ok);
    assert_eq!(result.site_id, "site-1");
    assert_eq!(result.group_id, "group-1");

    let requests = http.requests();
    assert_eq!(requests.len(), 3);
    assert_eq!(requests[2].url, "https://api.example/attendance/sign");
    let sign_body = body_json(&requests[2]);
    let detail = &sign_body["attendanceDetailInfo"];
    assert_eq!(detail["attendanceId"], "att-1");
    assert_eq!(detail["classLessonId"], "group-1");
    assert_eq!(detail["siteId"], "site-1");
    assert_eq!(detail["userId"], "user-1");
    assert_eq!(sign_body["qrCodeCreateTime"], "clock-1");
}

#[tokio::test]
async fn sign_fails_when_upstream_reports_unsuccessful() {
    let http = MockHttp::with(vec![
        response(
            200,
            r#"{"success":true,"data":{"attendanceBasicInfo":{"id":"att-1"}}}"#,
        ),
        response(200, r#"{"success":true,"data":{"data":"clock-1"}}"#),
        response(200, r#"{"success":false,"message":"签到已结束。"}"#),
    ]);
    let client = OpenUcloudClient::new(http, test_endpoints());

    let err = client
        .sign_attendance("site-1", "group-1", "user-1", "access-1")
        .await
        .expect_err("unsuccessful sign fails");

    assert_eq!(err.code, AuthErrorCode::UpstreamUnavailable);
    assert_eq!(err.message, "签到已结束。");
}

#[tokio::test]
async fn prepare_qr_returns_attendance_id_and_create_time() {
    let http = MockHttp::with(vec![
        response(
            200,
            r#"{"success":true,"data":{"attendanceBasicInfo":{"id":"att-1"}}}"#,
        ),
        response(200, r#"{"success":true,"data":{"data":"clock-1"}}"#),
    ]);
    let client = OpenUcloudClient::new(http, test_endpoints());

    let qr = client
        .prepare_attendance_qr("site-1", "group-1", "access-1")
        .await
        .expect("qr prepares");

    assert_eq!(qr.attendance_id, "att-1");
    assert_eq!(qr.site_id, "site-1");
    assert_eq!(qr.group_id, "group-1");
    assert_eq!(qr.create_time, "clock-1");
}
