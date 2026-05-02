use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum AuthErrorCode {
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
pub enum RoleName {
    #[serde(rename = "学生")]
    Student,
    #[serde(rename = "教师")]
    Teacher,
    #[serde(rename = "助教")]
    Assistant,
}

impl RoleName {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Student => "学生",
            Self::Teacher => "教师",
            Self::Assistant => "助教",
        }
    }
}

impl std::str::FromStr for RoleName {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "学生" => Ok(Self::Student),
            "教师" => Ok(Self::Teacher),
            "助教" => Ok(Self::Assistant),
            _ => Err(format!("unsupported role: {value}")),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RoleInfo {
    pub domain_id: String,
    pub domain_name: String,
    pub id: String,
    pub role_aliase: String,
    pub role_id: String,
    pub role_name: RoleName,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionUser {
    pub account: String,
    pub real_name: String,
    pub user_id: String,
    pub user_name: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthStartRequest {
    pub username: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthStartResponse {
    pub captcha_image: Option<String>,
    pub flow_id: String,
    pub requires_captcha: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthFinishRequest {
    pub captcha: Option<String>,
    pub flow_id: String,
    pub password: String,
    pub role: Option<RoleName>,
    pub username: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthFinishResponse {
    pub roles: Vec<RoleInfo>,
    pub selected_role: RoleName,
    pub user: SessionUser,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthSessionResponse {
    pub selected_role: RoleName,
    pub user: SessionUser,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseSite {
    pub id: String,
    pub site_name: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseListResponse {
    pub records: Vec<CourseSite>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GoingSite {
    pub group_id: String,
    pub site_id: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseActivityResponse {
    pub records: Vec<CourseSite>,
    pub going_sites: Vec<GoingSite>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseDetailResponse {
    pub course: CourseSite,
    pub going_site: Option<GoingSite>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AttendanceStatusResponse {
    pub site_id: String,
    pub site_name: String,
    pub going: bool,
    pub group_id: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AssignmentUploadResponse {
    pub assignment_id: String,
    pub file_name: String,
    pub preview_url: Option<String>,
    pub resource_id: String,
    pub site_id: String,
    pub site_name: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AssignmentSubmitResponse {
    pub ok: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum AssignmentStatus {
    Pending,
    Submitted,
    Expired,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AssignmentSummary {
    pub end_time: String,
    pub id: String,
    pub site_id: String,
    pub site_name: String,
    pub source: String,
    pub start_time: String,
    pub status: AssignmentStatus,
    pub title: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AssignmentListResponse {
    pub records: Vec<AssignmentSummary>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AssignmentResource {
    pub ext: Option<String>,
    pub name: String,
    pub preview_url: Option<String>,
    pub resource_id: String,
    pub storage_id: Option<String>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AssignmentDetailResponse {
    pub class_name: String,
    pub comment: String,
    pub content: String,
    pub end_time: String,
    pub id: String,
    pub is_overtime_commit: bool,
    pub score: Option<f64>,
    pub site_id: String,
    pub site_name: String,
    pub start_time: String,
    pub status: AssignmentStatus,
    pub submitted_at: String,
    pub submitted_attachments: Vec<AssignmentResource>,
    pub submitted_content: String,
    pub teacher_resources: Vec<AssignmentResource>,
    pub title: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseResourceSummary {
    pub ext: Option<String>,
    pub name: String,
    pub resource_id: String,
    pub site_id: String,
    pub site_name: String,
    pub size_bytes: Option<u64>,
    pub updated_at: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseResourcesResponse {
    pub records: Vec<CourseResourceSummary>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseResourceDetail {
    pub description: Option<String>,
    pub download_url: Option<String>,
    pub ext: Option<String>,
    pub name: String,
    pub resource_id: String,
    pub site_id: String,
    pub site_name: String,
    pub size_bytes: Option<u64>,
    pub updated_at: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseResourceDetailResponse {
    pub detail: CourseResourceDetail,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseResourceDownloadResponse {
    pub records: Vec<CourseResourceDetail>,
    pub written_paths: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthErrorResponse {
    pub code: AuthErrorCode,
    pub message: String,
    pub retry_after_seconds: Option<u64>,
}
