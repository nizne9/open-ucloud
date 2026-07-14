use async_trait::async_trait;
use open_cloud_api::{AssignmentDetailResponse, AssignmentStatus, AuthErrorCode};
use open_cloud_core::{
    AuthError, DownloadCancelFlag, DownloadProgress, HttpBody, HttpClient, HttpMethod, HttpRequest,
    HttpResponse, OpenCloudClient, OpenCloudEndpoints,
};
use std::collections::VecDeque;
use std::path::PathBuf;
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

#[derive(Clone, Default)]
struct PathUploadHttp {
    responses: Arc<Mutex<VecDeque<HttpResponse>>>,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    uploaded_paths: Arc<Mutex<Vec<PathBuf>>>,
    uploaded_fields: Arc<Mutex<MultipartFieldsLog>>,
}

type MultipartFieldsLog = Vec<Vec<(String, String)>>;

impl PathUploadHttp {
    fn with(responses: Vec<HttpResponse>) -> Self {
        Self {
            responses: Arc::new(Mutex::new(VecDeque::from(responses))),
            requests: Arc::new(Mutex::new(Vec::new())),
            uploaded_paths: Arc::new(Mutex::new(Vec::new())),
            uploaded_fields: Arc::new(Mutex::new(Vec::new())),
        }
    }

    fn uploaded_paths(&self) -> Vec<PathBuf> {
        self.uploaded_paths
            .lock()
            .expect("uploaded paths lock")
            .clone()
    }

    fn uploaded_fields(&self) -> Vec<Vec<(String, String)>> {
        self.uploaded_fields
            .lock()
            .expect("uploaded fields lock")
            .clone()
    }
}

#[async_trait]
impl HttpClient for PathUploadHttp {
    async fn send(&self, request: HttpRequest) -> Result<HttpResponse, AuthError> {
        self.requests.lock().expect("requests lock").push(request);
        self.responses
            .lock()
            .expect("responses lock")
            .pop_front()
            .ok_or_else(|| AuthError::upstream("missing mock response"))
    }

    async fn send_multipart_file(
        &self,
        request: HttpRequest,
        fields: Vec<(String, String)>,
        _file_field_name: String,
        _file_name: String,
        path: PathBuf,
    ) -> Result<HttpResponse, AuthError> {
        self.requests.lock().expect("requests lock").push(request);
        self.uploaded_paths
            .lock()
            .expect("uploaded paths lock")
            .push(path);
        self.uploaded_fields
            .lock()
            .expect("uploaded fields lock")
            .push(fields);
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

fn response_with_headers(status: u16, headers: &[(&str, &str)], body: &str) -> HttpResponse {
    HttpResponse {
        status,
        headers: headers
            .iter()
            .map(|(name, value)| (name.to_string(), value.to_string()))
            .collect(),
        body: body.as_bytes().to_vec(),
    }
}

fn body_text(request: &HttpRequest) -> String {
    match request.body.as_ref().expect("request body") {
        HttpBody::Text(value) => value.clone(),
        HttpBody::Bytes(bytes) => String::from_utf8(bytes.clone()).expect("body utf8"),
    }
}

fn header_value<'a>(request: &'a HttpRequest, header: &str) -> &'a str {
    request
        .headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case(header))
        .map(|(_, value)| value.as_str())
        .expect("header exists")
}

fn has_header(request: &HttpRequest, header: &str, expected: &str) -> bool {
    request
        .headers
        .iter()
        .any(|(name, value)| name.eq_ignore_ascii_case(header) && value == expected)
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
          {"id":"work-3","assignmentTitle":"省略课程 ID","assignmentEndTime":"2099-05-03"},
          {"id":"","assignmentTitle":"空 ID","siteId":"site-1"}
        ]}}"#,
    )]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let result = client
        .get_course_assignments("site-1", "软件测试", "access-token", "实验")
        .await
        .expect("assignments load");

    assert_eq!(result.records.len(), 3);
    assert_eq!(result.records[0].id, "work-1");
    assert_eq!(result.records[0].site_id, "1001");
    assert_eq!(result.records[0].site_name, "软件测试");
    assert_eq!(result.records[0].status, AssignmentStatus::Pending);
    assert_eq!(result.records[1].status, AssignmentStatus::Submitted);
    assert_eq!(result.records[2].id, "work-3");
    assert_eq!(result.records[2].site_id, "site-1");
    assert_eq!(result.records[2].site_name, "软件测试");

    let request = http.requests().pop().expect("assignment request");
    assert_eq!(request.method, HttpMethod::Post);
    assert_eq!(
        request.url,
        "https://apiucloud.bupt.edu.cn/ykt-site/work/student/list"
    );
    let body = body_text(&request);
    assert!(body.contains(r#""siteId":"site-1""#));
    assert!(body.contains(r#""keyword":"实验""#));
    assert!(body.contains(r#""current":1"#));
    assert!(body.contains(r#""size":100"#));
    assert!(request.headers.iter().any(|(name, value)| {
        name.eq_ignore_ascii_case("authorization") && value == "Basic cG9ydGFsOnBvcnRhbF9zZWNyZXQ="
    }));
    assert!(request
        .headers
        .iter()
        .any(|(name, value)| name == "Blade-Auth" && value == "access-token"));
}

#[tokio::test]
async fn get_course_assignments_paginates_and_deduplicates_ids() {
    let first_page = (0..100)
        .map(|index| {
            serde_json::json!({
                "id": format!("work-{index}"),
                "assignmentTitle": format!("作业 {index}"),
                "assignmentEndTime": "2099-05-03"
            })
        })
        .collect::<Vec<_>>();
    let http = MockHttp::with(vec![
        response(
            200,
            &serde_json::json!({"success": true, "data": {"records": first_page}}).to_string(),
        ),
        response(
            200,
            r#"{"success":true,"data":{"records":[
              {"id":"work-99","assignmentTitle":"重复作业"},
              {"id":"work-100","assignmentTitle":"新作业"}
            ]}}"#,
        ),
    ]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let result = client
        .get_course_assignments("site-1", "软件测试", "access-token", "")
        .await
        .expect("assignments load");

    assert_eq!(result.records.len(), 101);
    assert_eq!(
        result.records.last().expect("last assignment").id,
        "work-100"
    );
    let requests = http.requests();
    assert_eq!(requests.len(), 2);
    assert!(body_text(&requests[1]).contains(r#""current":2"#));
}

#[tokio::test]
async fn submitted_assignment_with_past_deadline_is_expired() {
    let http = MockHttp::with(vec![response(
        200,
        r#"{"success":true,"data":{"records":[
          {"id":"work-1","title":"已提交但已截止","siteId":"site-1","statusName":"已提交","commitTime":"2026-05-01","endTime":"2000-01-01"}
        ]}}"#,
    )]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

    let result = client
        .get_course_assignments("site-1", "软件测试", "access-token", "")
        .await
        .expect("assignments load");

    assert_eq!(result.records[0].status, AssignmentStatus::Expired);
}

#[tokio::test]
async fn get_undone_assignments_keeps_only_assignment_items() {
    let http = MockHttp::with(vec![response(
        200,
        r#"{"success":true,"data":{"undoneList":[
          {"activityId":2043171894306238465,"activityName":"待提交","endTime":"2099-05-03","siteId":1001,"siteName":"软件测试","type":3},
          {"activityId":"quiz-1","activityName":"测验","endTime":"2099-05-03","siteId":1001,"siteName":"软件测试","type":2}
        ]}}"#,
    )]);
    let endpoints = OpenCloudEndpoints {
        assignment_undone_url: "https://example.test/ykt-site/site/student/undone".to_string(),
        ..OpenCloudEndpoints::default()
    };
    let client = OpenCloudClient::new(http.clone(), endpoints);

    let result = client
        .get_undone_assignments("u-1", "access-token")
        .await
        .expect("undone assignments load");

    assert_eq!(result.records.len(), 1);
    assert_eq!(result.records[0].id, "2043171894306238465");
    assert_eq!(result.records[0].source, "undone");
    assert_eq!(result.records[0].status, AssignmentStatus::Pending);

    let request = http.requests().pop().expect("undone request");
    assert_eq!(request.method, HttpMethod::Get);
    assert!(request
        .url
        .starts_with("https://example.test/ykt-site/site/student/undone?"));
    assert!(request.url.contains("userId=u-1"));
}

#[tokio::test]
async fn get_assignment_detail_loads_teacher_and_submitted_resources() {
    let http = MockHttp::with(vec![
        response(
            200,
            r#"{"success":true,"data":{
              "id":"work-1","title":"实验报告","assignmentContent":"完成报告","assignmentBeginTime":"2026-05-01","assignmentEndTime":"2099-05-03",
              "siteId":"site-1","siteName":"软件测试","className":"1 班","assignmentComment":"不错","assignmentScore":95,
              "commitTime":"2026-05-02","studentCommitContent":"已完成","isOvertimeCommit":0,
              "assignmentResource":[{"resourceId":2050487502087970817}],
              "submitAttachmentList":[],
              "studentAttachmentList":[{"id":"student-1","name":"report.pdf","ext":"pdf","storageId":"storage-1"}]
            }}"#,
        ),
        response(
            200,
            r#"{"success":true,"data":[{"id":2050487502087970817,"name":"template.docx","ext":"docx"}]}"#,
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
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let detail = client
        .get_assignment_detail("work-1", "access-token")
        .await
        .expect("detail loads");

    assert_eq!(detail.id, "work-1");
    assert_eq!(detail.title, "实验报告");
    assert_eq!(detail.status, AssignmentStatus::Submitted);
    assert_eq!(detail.score, Some(95.0));
    assert_eq!(
        detail.teacher_resources[0].resource_id,
        "2050487502087970817"
    );
    assert_eq!(
        detail.teacher_resources[0].preview_url.as_deref(),
        Some("https://files.example/teacher")
    );
    assert_eq!(detail.submitted_attachments[0].resource_id, "student-1");
    let requests = http.requests();
    assert!(has_header(&requests[2], "Blade-Auth", "access-token"));
    assert!(has_header(&requests[3], "Blade-Auth", "access-token"));
}

#[tokio::test]
async fn get_assignment_detail_accepts_fractional_score() {
    let http = MockHttp::with(vec![response(
        200,
        r#"{"success":true,"data":{
          "id":"work-1","title":"实验报告","assignmentContent":"完成报告","assignmentBeginTime":"2026-05-01","assignmentEndTime":"2099-05-03",
          "siteId":"site-1","siteName":"软件测试","assignmentScore":95.5
        }}"#,
    )]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

    let detail = client
        .get_assignment_detail("work-1", "access-token")
        .await
        .expect("detail loads with fractional score");

    assert_eq!(detail.score, Some(95.5));
}

#[tokio::test]
async fn submit_assignment_rejects_empty_submission_before_network() {
    let http = MockHttp::default();
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let err = client
        .submit_assignment("work-1", "u-1", "   ", &[], "access-token")
        .await
        .expect_err("empty submission fails");

    assert_eq!(err.code, AuthErrorCode::InvalidInput);
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
async fn submit_assignment_preserves_content_whitespace() {
    let http = MockHttp::with(vec![response(200, r#"{"success":true}"#)]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());
    let content = "  line one\n    code();\n  ";

    client
        .submit_assignment("work-1", "u-1", content, &[], "access-token")
        .await
        .expect("submit succeeds");

    let request = http.requests().pop().expect("submit request");
    let body: serde_json::Value =
        serde_json::from_str(&body_text(&request)).expect("submit body is json");
    assert_eq!(body["assignmentContent"], content);
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
    let preview_request = http.requests().get(1).expect("preview request").clone();
    assert!(has_header(&preview_request, "Blade-Auth", "access-token"));
}

#[tokio::test]
async fn upload_assignment_file_path_uses_transport_file_upload() {
    let path = std::env::temp_dir().join(format!("open-cloud-upload-{}.pdf", std::process::id()));
    std::fs::write(&path, b"pdf-bytes").expect("upload fixture");
    let http = PathUploadHttp::with(vec![
        response(200, r#"{"success":true,"data":"resource-1"}"#),
        response(
            200,
            r#"{"success":true,"data":{"previewUrl":"https://files.example/report"}}"#,
        ),
    ]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let result = client
        .upload_assignment_file_path(
            &assignment_detail(AssignmentStatus::Pending),
            "report.pdf",
            &path,
            "u-1",
            "access-token",
        )
        .await
        .expect("upload succeeds");

    assert_eq!(result.resource_id, "resource-1");
    assert_eq!(http.uploaded_paths(), vec![path]);
    assert_eq!(
        http.uploaded_fields(),
        vec![vec![
            ("userId".to_string(), "u-1".to_string()),
            ("bizType".to_string(), "3".to_string()),
        ]]
    );
}

#[tokio::test]
async fn upload_assignment_file_uses_boundary_that_does_not_collide_with_file_bytes() {
    let http = MockHttp::with(vec![
        response(200, r#"{"success":true,"data":"resource-1"}"#),
        response(
            200,
            r#"{"success":true,"data":{"previewUrl":"https://files.example/report"}}"#,
        ),
    ]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());
    let bytes = b"before\r\n------open-cloud-assignment-upload-boundary\r\nafter";

    client
        .upload_assignment_file(
            &assignment_detail(AssignmentStatus::Pending),
            "report.pdf",
            bytes,
            "u-1",
            "access-token",
        )
        .await
        .expect("upload succeeds");

    let request = http.requests().first().expect("upload request").clone();
    let boundary = header_value(&request, "content-type")
        .strip_prefix("multipart/form-data; boundary=")
        .expect("multipart boundary");
    let delimiter = format!("--{boundary}");

    assert!(!bytes
        .windows(delimiter.len())
        .any(|window| window == delimiter.as_bytes()));
}

#[tokio::test]
async fn upload_assignment_file_derives_boundary_from_upload_values() {
    let http = MockHttp::with(vec![
        response(200, r#"{"success":true,"data":"resource-1"}"#),
        response(200, r#"{"success":true,"data":{"previewUrl":"one"}}"#),
        response(200, r#"{"success":true,"data":"resource-2"}"#),
        response(200, r#"{"success":true,"data":{"previewUrl":"two"}}"#),
    ]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    client
        .upload_assignment_file(
            &assignment_detail(AssignmentStatus::Pending),
            "one.pdf",
            b"one",
            "u-1",
            "access-token",
        )
        .await
        .expect("first upload succeeds");
    client
        .upload_assignment_file(
            &assignment_detail(AssignmentStatus::Pending),
            "two.pdf",
            b"two",
            "u-1",
            "access-token",
        )
        .await
        .expect("second upload succeeds");

    let requests = http.requests();
    let first_boundary = header_value(&requests[0], "content-type")
        .strip_prefix("multipart/form-data; boundary=")
        .expect("first multipart boundary");
    let second_boundary = header_value(&requests[2], "content-type")
        .strip_prefix("multipart/form-data; boundary=")
        .expect("second multipart boundary");

    assert_ne!(first_boundary, second_boundary);
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
async fn upload_assignment_file_rejects_blocked_extension_with_trailing_space() {
    let http = MockHttp::with(Vec::new());
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let error = client
        .upload_assignment_file(
            &assignment_detail(AssignmentStatus::Pending),
            "script.sh ",
            b"script bytes",
            "u-1",
            "access-token",
        )
        .await
        .expect_err("blocked extension with trailing space is rejected");

    assert_eq!(error.code, AuthErrorCode::FileTypeNotAllowed);
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
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

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
    let requests = http.requests();
    assert!(has_header(&requests[1], "Blade-Auth", "access-token"));
}

#[tokio::test]
async fn download_url_to_path_streams_redirected_body_to_partial_then_renames() {
    let http = MockHttp::with(vec![
        response_with_headers(302, &[("Location", "/object/resource-1")], ""),
        response(200, "file bytes"),
    ]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());
    let path = temp_download_path("streamed-resource.txt");
    let _ = std::fs::remove_file(&path);
    let bytes_seen = Arc::new(Mutex::new(0_u64));
    let progress = {
        let bytes_seen = bytes_seen.clone();
        DownloadProgress::new(move |bytes| {
            *bytes_seen.lock().expect("progress lock") += bytes;
        })
    };

    let written = client
        .download_url_to_path(
            "https://files.example/download/resource-1",
            &path,
            progress,
            DownloadCancelFlag::new(),
        )
        .await
        .expect("download writes target");

    assert_eq!(written, path);
    assert_eq!(
        std::fs::read(&path).expect("downloaded file"),
        b"file bytes"
    );
    assert_eq!(*bytes_seen.lock().expect("progress lock"), 10);
    assert!(!partial_files_for(&path)
        .into_iter()
        .any(|path| path.exists()));
    let _ = std::fs::remove_file(&path);
}

#[tokio::test]
async fn download_url_to_path_removes_partial_when_cancelled_before_request() {
    let http = MockHttp::with(vec![response(200, "file bytes")]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());
    let path = temp_download_path("cancelled-resource.txt");
    let _ = std::fs::remove_file(&path);
    let cancel = DownloadCancelFlag::new();
    cancel.cancel();

    let error = client
        .download_url_to_path(
            "https://files.example/download/resource-1",
            &path,
            DownloadProgress::default(),
            cancel,
        )
        .await
        .expect_err("download is cancelled");

    assert_eq!(error.code, AuthErrorCode::Cancelled);
    assert!(!path.exists());
    assert!(partial_files_for(&path).is_empty());
    assert!(http.requests().is_empty());
}

#[tokio::test]
async fn download_url_to_path_removes_partial_when_cancelled_before_rename() {
    let http = MockHttp::with(vec![response(200, "file bytes")]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());
    let path = temp_download_path("cancelled-before-rename.txt");
    let _ = std::fs::remove_file(&path);
    let cancel = DownloadCancelFlag::new();
    let progress = {
        let cancel = cancel.clone();
        DownloadProgress::new(move |_| {
            cancel.cancel();
        })
    };

    let error = client
        .download_url_to_path(
            "https://files.example/download/resource-1",
            &path,
            progress,
            cancel,
        )
        .await
        .expect_err("download is cancelled before rename");

    assert_eq!(error.code, AuthErrorCode::Cancelled);
    assert!(!path.exists());
    assert!(partial_files_for(&path).is_empty());
    assert_eq!(http.requests().len(), 1);
}

#[tokio::test]
async fn download_url_to_path_never_overwrites_a_racing_target() {
    let http = MockHttp::with(vec![response(200, "new bytes")]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
    let path = temp_download_path("existing-resource.txt");
    std::fs::write(&path, b"existing bytes").expect("existing target fixture");

    let error = client
        .download_url_to_path(
            "https://files.example/download/resource-1",
            &path,
            DownloadProgress::default(),
            DownloadCancelFlag::new(),
        )
        .await
        .expect_err("existing target is preserved");

    assert_eq!(error.code, AuthErrorCode::FileSystem);
    assert_eq!(
        std::fs::read(&path).expect("existing target remains"),
        b"existing bytes"
    );
    assert!(partial_files_for(&path).is_empty());
    let _ = std::fs::remove_file(&path);
}

fn temp_download_path(name: &str) -> PathBuf {
    std::env::temp_dir().join(format!("open-ucloud-{}-{name}", std::process::id()))
}

fn partial_files_for(target: &std::path::Path) -> Vec<PathBuf> {
    let parent = target.parent().expect("target parent");
    let file_name = target
        .file_name()
        .and_then(|value| value.to_str())
        .expect("target file name");
    std::fs::read_dir(parent)
        .expect("temp dir")
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|value| value.to_str())
                .is_some_and(|name| {
                    name.starts_with(&format!(".{file_name}.")) && name.ends_with(".part")
                })
        })
        .collect()
}
