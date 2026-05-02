use async_trait::async_trait;
use open_cloud_api::{AssignmentDetailResponse, AssignmentStatus, AuthErrorCode};
use open_cloud_core::{
    AuthError, HttpBody, HttpClient, HttpMethod, HttpRequest, HttpResponse, OpenCloudClient,
    OpenCloudEndpoints,
};
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

fn response(status: u16, body: &str) -> HttpResponse {
    HttpResponse {
        status,
        headers: Vec::new(),
        body: body.as_bytes().to_vec(),
    }
}

fn body_text(request: &HttpRequest) -> String {
    match request.body.as_ref().expect("request body") {
        HttpBody::Text(value) => value.clone(),
        HttpBody::Bytes(bytes) => String::from_utf8(bytes.clone()).expect("body utf8"),
    }
}

fn assignment_detail(status: AssignmentStatus) -> AssignmentDetailResponse {
    AssignmentDetailResponse {
        class_name: "1 班".to_string(),
        comment: String::new(),
        content: "完成报告".to_string(),
        end_time: "2099-05-03".to_string(),
        id: "work-1".to_string(),
        is_overtime_commit: false,
        score: None,
        site_id: "site-1".to_string(),
        site_name: "软件测试".to_string(),
        start_time: "2026-05-01".to_string(),
        status,
        submitted_at: String::new(),
        submitted_attachments: Vec::new(),
        submitted_content: String::new(),
        teacher_resources: Vec::new(),
        title: "实验报告".to_string(),
    }
}

#[tokio::test]
async fn get_course_assignments_normalizes_records_and_request_shape() {
    let http = MockHttp::with(vec![response(
        200,
        r#"{"success":true,"data":{"records":[
          {"id":"work-1","assignmentTitle":"实验报告","siteId":1001,"siteName":"软件测试","assignmentBeginTime":"2026-05-01","assignmentEndTime":"2099-05-03","isCommit":0},
          {"id":"work-2","title":"已提交作业","siteId":"site-1","statusName":"已提交","startTime":"2026-05-01","endTime":"2099-05-03"},
          {"id":"","assignmentTitle":"空 ID","siteId":"site-1"}
        ]}}"#,
    )]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let result = client
        .get_course_assignments("site-1", "软件测试", "access-token", "实验")
        .await
        .expect("assignments load");

    assert_eq!(result.records.len(), 2);
    assert_eq!(result.records[0].id, "work-1");
    assert_eq!(result.records[0].site_id, "1001");
    assert_eq!(result.records[0].site_name, "软件测试");
    assert_eq!(result.records[0].status, AssignmentStatus::Pending);
    assert_eq!(result.records[1].status, AssignmentStatus::Submitted);

    let request = http.requests().pop().expect("assignment request");
    assert_eq!(request.method, HttpMethod::Post);
    assert_eq!(
        request.url,
        "https://apiucloud.bupt.edu.cn/ykt-site/work/student/list"
    );
    let body = body_text(&request);
    assert!(body.contains(r#""siteId":"site-1""#));
    assert!(body.contains(r#""keyword":"实验""#));
    assert!(request.headers.iter().any(|(name, value)| {
        name.eq_ignore_ascii_case("authorization") && value == "Basic cG9ydGFsOnBvcnRhbF9zZWNyZXQ="
    }));
    assert!(request
        .headers
        .iter()
        .any(|(name, value)| name == "Blade-Auth" && value == "access-token"));
}

#[tokio::test]
async fn get_undone_assignments_keeps_only_assignment_items() {
    let http = MockHttp::with(vec![response(
        200,
        r#"{"success":true,"data":{"undoneList":[
          {"activityId":"work-1","activityName":"待提交","endTime":"2099-05-03","siteId":1001,"siteName":"软件测试","type":3},
          {"activityId":"quiz-1","activityName":"测验","endTime":"2099-05-03","siteId":1001,"siteName":"软件测试","type":2}
        ]}}"#,
    )]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let result = client
        .get_undone_assignments("u-1", "access-token")
        .await
        .expect("undone assignments load");

    assert_eq!(result.records.len(), 1);
    assert_eq!(result.records[0].id, "work-1");
    assert_eq!(result.records[0].source, "undone");
    assert_eq!(result.records[0].status, AssignmentStatus::Pending);

    let request = http.requests().pop().expect("undone request");
    assert_eq!(request.method, HttpMethod::Get);
    assert!(request.url.contains("/ykt-site/site/student/undone?"));
    assert!(request.url.contains("userId=u-1"));
}

#[tokio::test]
async fn get_assignment_detail_loads_teacher_and_submitted_resources() {
    let http = MockHttp::with(vec![
        response(
            200,
            r#"{"success":true,"data":{
              "id":"work-1","assignmentTitle":"实验报告","assignmentContent":"完成报告","assignmentBeginTime":"2026-05-01","assignmentEndTime":"2099-05-03",
              "siteId":"site-1","siteName":"软件测试","className":"1 班","assignmentComment":"不错","assignmentScore":95,
              "commitTime":"2026-05-02","studentCommitContent":"已完成","isOvertimeCommit":0,
              "assignmentResource":[{"resourceId":"teacher-1"}],
              "submitAttachmentList":[{"id":"student-1","name":"report.pdf","ext":"pdf","storageId":"storage-1"}]
            }}"#,
        ),
        response(
            200,
            r#"{"success":true,"data":[{"id":"teacher-1","name":"template.docx","ext":"docx"}]}"#,
        ),
        response(
            200,
            r#"{"success":true,"data":{"previewUrl":"https://files.example/teacher"}}"#,
        ),
        response(
            200,
            r#"{"success":true,"data":{"previewUrl":"https://files.example/student"}}"#,
        ),
    ]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

    let detail = client
        .get_assignment_detail("work-1", "access-token")
        .await
        .expect("detail loads");

    assert_eq!(detail.id, "work-1");
    assert_eq!(detail.status, AssignmentStatus::Submitted);
    assert_eq!(detail.score, Some(95));
    assert_eq!(detail.teacher_resources[0].resource_id, "teacher-1");
    assert_eq!(
        detail.teacher_resources[0].preview_url.as_deref(),
        Some("https://files.example/teacher")
    );
    assert_eq!(detail.submitted_attachments[0].resource_id, "student-1");
}

#[tokio::test]
async fn submit_assignment_rejects_empty_submission_before_network() {
    let http = MockHttp::default();
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let err = client
        .submit_assignment("work-1", "u-1", "   ", &[], "access-token")
        .await
        .expect_err("empty submission fails");

    assert_eq!(err.code, AuthErrorCode::UnknownAuthError);
    assert_eq!(err.message, "请先填写作业内容或上传附件。");
    assert!(http.requests().is_empty());
}

#[tokio::test]
async fn submit_assignment_sends_documented_payload() {
    let http = MockHttp::with(vec![response(200, r#"{"success":true}"#)]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let result = client
        .submit_assignment(
            "work-1",
            "u-1",
            "答案",
            &["resource-1".to_string()],
            "access-token",
        )
        .await
        .expect("submit succeeds");

    assert!(result.ok);
    let request = http.requests().pop().expect("submit request");
    assert_eq!(request.method, HttpMethod::Post);
    assert_eq!(
        request.url,
        "https://apiucloud.bupt.edu.cn/ykt-site/work/submit"
    );
    let body = body_text(&request);
    assert!(body.contains(r#""assignmentId":"work-1""#));
    assert!(body.contains(r#""assignmentContent":"答案""#));
    assert!(body.contains(r#""attachmentIds":["resource-1"]"#));
}

#[tokio::test]
async fn upload_assignment_file_sends_multipart_and_preview_url() {
    let http = MockHttp::with(vec![
        response(200, r#"{"success":true,"data":"resource-1"}"#),
        response(
            200,
            r#"{"success":true,"data":{"previewUrl":"https://files.example/report"}}"#,
        ),
    ]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let result = client
        .upload_assignment_file(
            &assignment_detail(AssignmentStatus::Pending),
            "report.pdf",
            b"pdf-bytes",
            "u-1",
            "access-token",
        )
        .await
        .expect("upload succeeds");

    assert_eq!(result.assignment_id, "work-1");
    assert_eq!(result.file_name, "report.pdf");
    assert_eq!(result.resource_id, "resource-1");
    assert_eq!(result.site_id, "site-1");
    assert_eq!(
        result.preview_url.as_deref(),
        Some("https://files.example/report")
    );
    let request = http.requests().first().expect("upload request").clone();
    assert_eq!(request.method, HttpMethod::Post);
    assert_eq!(
        request.url,
        "https://apiucloud.bupt.edu.cn/blade-source/resource/upload/biz"
    );
    assert!(request.headers.iter().any(|(name, value)| {
        name.eq_ignore_ascii_case("content-type")
            && value.starts_with("multipart/form-data; boundary=")
    }));
    let body = body_text(&request);
    assert!(body.contains(r#"name="bizType""#));
    assert!(body.contains(r#"name="file"; filename="report.pdf""#));
}

#[tokio::test]
async fn upload_assignment_file_escapes_multipart_filename() {
    let http = MockHttp::with(vec![
        response(200, r#"{"success":true,"data":"resource-1"}"#),
        response(
            200,
            r#"{"success":true,"data":{"previewUrl":"https://files.example/report"}}"#,
        ),
    ]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let result = client
        .upload_assignment_file(
            &assignment_detail(AssignmentStatus::Pending),
            "报告\"\\.pdf",
            b"pdf-bytes",
            "u-1",
            "access-token",
        )
        .await
        .expect("upload succeeds");

    assert_eq!(result.resource_id, "resource-1");
    let request = http.requests().first().expect("upload request").clone();
    let body = body_text(&request);
    assert!(body.contains(r#"filename="报告\"\\.pdf""#));
    assert!(!body.contains("filename*="));
}

#[tokio::test]
async fn upload_assignment_file_rejects_header_breaking_filename() {
    let http = MockHttp::with(Vec::new());
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let error = client
        .upload_assignment_file(
            &assignment_detail(AssignmentStatus::Pending),
            "报告\r\nX-Test: injected.pdf",
            b"pdf-bytes",
            "u-1",
            "access-token",
        )
        .await
        .expect_err("header-breaking filename is rejected");

    assert_eq!(error.code, AuthErrorCode::InvalidFileName);
    assert!(http.requests().is_empty());
}

#[tokio::test]
async fn get_course_resources_flattens_tree_and_dedupes() {
    let http = MockHttp::with(vec![response(
        200,
        r#"{"success":true,"data":[
          {"resource":{"id":1001,"name":"课件.pdf","ext":"pdf","fileSize":"1024","updateTime":"2026-05-02"}},
          {"attachmentVOs":[{"resource":{"resourceId":"resource-2","fileName":"附件.zip","size":2048}}],
           "children":[{"resource":{"id":1001,"name":"重复.pdf"}}]}
        ]}"#,
    )]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let resources = client
        .get_course_resources("site-1", "软件测试", "u-1", "access-token")
        .await
        .expect("resources load");

    assert_eq!(resources.records.len(), 2);
    assert_eq!(resources.records[0].resource_id, "1001");
    assert_eq!(resources.records[0].name, "课件.pdf");
    assert_eq!(resources.records[0].size_bytes, Some(1024));
    assert_eq!(resources.records[1].resource_id, "resource-2");

    let request = http.requests().pop().expect("resources request");
    assert_eq!(request.method, HttpMethod::Post);
    assert!(request
        .url
        .contains("/ykt-site/site-resource/tree/student?"));
    assert!(request.url.contains("siteId=site-1"));
    assert!(request.url.contains("userId=u-1"));
}

#[tokio::test]
async fn get_resource_detail_adds_download_url() {
    let http = MockHttp::with(vec![
        response(
            200,
            r#"{"success":true,"data":[{"id":"resource-1","name":"课件.pdf","description":"说明","fileSize":1024,"updateTime":"2026-05-02"}]}"#,
        ),
        response(
            200,
            r#"{"success":true,"data":{"previewUrl":"https://files.example/resource"}}"#,
        ),
    ]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

    let detail = client
        .get_resource_detail("resource-1", "site-1", "软件测试", "access-token")
        .await
        .expect("resource detail loads");

    assert_eq!(detail.resource_id, "resource-1");
    assert_eq!(detail.description.as_deref(), Some("说明"));
    assert_eq!(
        detail.download_url.as_deref(),
        Some("https://files.example/resource")
    );
}
