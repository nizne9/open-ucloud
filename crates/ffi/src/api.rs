use crate::session::{shared_session_coordinator, SessionCoordinator};
use futures_util::stream::{self, StreamExt};
use open_cloud_api::{
    AuthErrorCode, AuthErrorResponse, CourseResourceDetail, CourseResourceSummary,
};
use open_cloud_core::{
    client_capabilities, now_ms, parse_attendance_qr_payload, DownloadCancelFlag, DownloadProgress,
    LoginFlow, OpenCloudClient, OpenCloudEndpoints, ReqwestHttpClient,
};
use open_cloud_store::AuthSession;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};
use tokio::task::JoinHandle;

const MAX_ASSIGNMENT_UPLOAD_BYTES: u64 = 25 * 1024 * 1024;
const BLOCKED_UPLOAD_EXTENSIONS: &[&str] = &[
    "ade", "adp", "apk", "app", "bat", "bin", "cmd", "com", "cpl", "dll", "dmg", "exe", "hta",
    "ins", "iso", "jar", "js", "jse", "lnk", "msc", "msi", "msp", "mst", "pif", "scr", "sh", "vb",
    "vbe", "vbs", "ws", "wsc", "wsf", "wsh",
];
const COURSE_DOWNLOAD_CONCURRENCY: usize = 4;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiLoginFlow {
    pub captcha_id: Option<String>,
    pub captcha_image: Option<String>,
    pub cookie: String,
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
    Cancelled,
    InvalidInput,
    NotFound,
    FileSystem,
    RateLimited,
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
    pub role_alias: String,
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
pub struct FfiAttendanceQrPayload {
    pub attendance_id: String,
    pub site_id: String,
    pub create_time: String,
    pub class_lesson_id: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiClientCapabilities {
    pub self_attendance: bool,
    pub attendance_qr_payload_parsing: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum FfiAssignmentStatus {
    Pending,
    Submitted,
    Expired,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiAssignmentSummary {
    pub end_time: String,
    pub id: String,
    pub site_id: String,
    pub site_name: String,
    pub source: String,
    pub start_time: String,
    pub status: FfiAssignmentStatus,
    pub title: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiAssignmentResource {
    pub ext: Option<String>,
    pub name: String,
    pub preview_url: Option<String>,
    pub resource_id: String,
    pub storage_id: Option<String>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiAssignmentDetailResponse {
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
    pub status: FfiAssignmentStatus,
    pub submitted_at: String,
    pub submitted_attachments: Vec<FfiAssignmentResource>,
    pub submitted_content: String,
    pub teacher_resources: Vec<FfiAssignmentResource>,
    pub title: String,
    pub updated_session_payload: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiAssignmentListResponse {
    pub records: Vec<FfiAssignmentSummary>,
    pub updated_session_payload: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiAssignmentUploadResponse {
    pub assignment_id: String,
    pub file_name: String,
    pub preview_url: Option<String>,
    pub resource_id: String,
    pub site_id: String,
    pub site_name: String,
    pub updated_session_payload: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiAssignmentSubmitResponse {
    pub ok: bool,
    pub updated_session_payload: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiCourseResourceSummary {
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
pub struct FfiCourseResourcesResponse {
    pub records: Vec<FfiCourseResourceSummary>,
    pub updated_session_payload: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiCourseResourceDetail {
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
pub struct FfiCourseResourceDetailResponse {
    pub detail: FfiCourseResourceDetail,
    pub updated_session_payload: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum FfiDownloadTaskState {
    Queued,
    Running,
    Succeeded,
    Failed,
    Cancelled,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiDownloadTaskStatus {
    pub task_id: String,
    pub state: FfiDownloadTaskState,
    pub current: u32,
    pub total: u32,
    pub bytes_downloaded: u64,
    pub current_file_name: Option<String>,
    pub written_paths: Vec<String>,
    pub records: Vec<FfiCourseResourceDetail>,
    pub error_message: Option<String>,
    pub updated_session_payload: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiDownloadTaskStartResponse {
    pub task_id: String,
    pub status: FfiDownloadTaskStatus,
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

struct DownloadTask {
    status: Mutex<FfiDownloadTaskStatus>,
    cancel: DownloadCancelFlag,
    handle: Mutex<Option<JoinHandle<()>>>,
}

struct ResourceDownloadTaskRequest {
    session: AuthSession,
    resource_id: String,
    site_id: String,
    site_name: String,
    output_path: String,
}

#[cfg(test)]
struct TestResourceDownloadRequest {
    session_payload: String,
    resource_id: String,
    site_id: String,
    site_name: String,
    output_path: String,
    now_ms: u64,
}

static DOWNLOAD_TASKS: OnceLock<Mutex<HashMap<String, Arc<DownloadTask>>>> = OnceLock::new();
static SHARED_CLIENT: OnceLock<OpenCloudClient<ReqwestHttpClient>> = OnceLock::new();

fn download_tasks() -> &'static Mutex<HashMap<String, Arc<DownloadTask>>> {
    DOWNLOAD_TASKS.get_or_init(|| Mutex::new(HashMap::new()))
}

// A poisoned lock only means a worker panicked mid-update; the payloads are
// still usable, so recover instead of panicking across the FFI boundary.
fn download_tasks_map() -> MutexGuard<'static, HashMap<String, Arc<DownloadTask>>> {
    download_tasks()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn lock_recover<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn shared_default_client() -> Result<&'static OpenCloudClient<ReqwestHttpClient>, FfiAuthError> {
    if let Some(client) = SHARED_CLIENT.get() {
        return Ok(client);
    }
    let http = ReqwestHttpClient::new().map_err(to_ffi_error)?;
    let _ = SHARED_CLIENT.set(OpenCloudClient::new(http, OpenCloudEndpoints::default()));
    SHARED_CLIENT.get().ok_or_else(|| {
        error(
            AuthErrorCode::UnknownAuthError,
            "HTTP 客户端初始化失败，请重试。",
        )
    })
}

fn create_download_task(total: u32) -> (String, Arc<DownloadTask>, FfiDownloadTaskStatus) {
    let task_id = uuid::Uuid::new_v4().to_string();
    let status = FfiDownloadTaskStatus {
        task_id: task_id.clone(),
        state: FfiDownloadTaskState::Queued,
        current: 0,
        total,
        bytes_downloaded: 0,
        current_file_name: None,
        written_paths: Vec::new(),
        records: Vec::new(),
        error_message: None,
        updated_session_payload: None,
    };
    let task = Arc::new(DownloadTask {
        status: Mutex::new(status.clone()),
        cancel: DownloadCancelFlag::new(),
        handle: Mutex::new(None),
    });
    download_tasks_map().insert(task_id.clone(), task.clone());
    (task_id, task, status)
}

fn read_download_status(task_id: &str) -> Result<FfiDownloadTaskStatus, FfiAuthError> {
    let task = download_tasks_map()
        .get(task_id)
        .cloned()
        .ok_or_else(|| error(AuthErrorCode::NotFound, "下载任务不存在。"))?;
    let status = lock_recover(&task.status);
    let terminal = is_terminal_download_state(&status.state);
    Ok(FfiDownloadTaskStatus {
        task_id: status.task_id.clone(),
        state: status.state.clone(),
        current: status.current,
        total: status.total,
        bytes_downloaded: status.bytes_downloaded,
        current_file_name: status.current_file_name.clone(),
        written_paths: if terminal {
            status.written_paths.clone()
        } else {
            Vec::new()
        },
        records: if terminal {
            status.records.clone()
        } else {
            Vec::new()
        },
        error_message: status.error_message.clone(),
        updated_session_payload: status.updated_session_payload.clone(),
    })
}

fn is_terminal_download_state(state: &FfiDownloadTaskState) -> bool {
    matches!(
        state,
        FfiDownloadTaskState::Succeeded
            | FfiDownloadTaskState::Failed
            | FfiDownloadTaskState::Cancelled
    )
}

fn update_download_status(task: &DownloadTask, f: impl FnOnce(&mut FfiDownloadTaskStatus)) {
    let mut status = lock_recover(&task.status);
    f(&mut status);
}

pub async fn auth_start(username: String) -> Result<FfiAuthStartResponse, FfiAuthError> {
    let client = shared_default_client()?;
    auth_start_with_client(client, username).await
}

pub async fn auth_finish(
    request: FfiAuthFinishRequest,
    flow: FfiLoginFlow,
) -> Result<FfiAuthFinishResponse, FfiAuthError> {
    let client = shared_default_client()?;
    let response = auth_finish_with_client(client, request, flow).await?;
    let session = decode_session_payload(&response.session_payload, now_ms())?;
    shared_session_coordinator().replace(session).await;
    Ok(response)
}

pub fn session_summary(session_payload: String) -> Result<FfiAuthSessionResponse, FfiAuthError> {
    let session = decode_session_payload(&session_payload, now_ms())?;
    Ok(FfiAuthSessionResponse {
        selected_role: session.role.into(),
        user: session.user.into(),
    })
}

pub fn capabilities() -> FfiClientCapabilities {
    client_capabilities().into()
}

pub fn parse_attendance_qr_payload_text(
    payload: String,
) -> Result<FfiAttendanceQrPayload, FfiAuthError> {
    parse_attendance_qr_payload(&payload)
        .map(Into::into)
        .map_err(to_ffi_error)
}

pub async fn courses(
    session_payload: String,
    with_going: bool,
) -> Result<FfiCourseResponse, FfiAuthError> {
    let client = shared_default_client()?;
    courses_with_client(
        client,
        shared_session_coordinator(),
        session_payload,
        with_going,
        now_ms(),
    )
    .await
}

pub async fn assignments_undone(
    session_payload: String,
) -> Result<FfiAssignmentListResponse, FfiAuthError> {
    let client = shared_default_client()?;
    assignments_undone_with_client(
        client,
        shared_session_coordinator(),
        session_payload,
        now_ms(),
    )
    .await
}

pub async fn assignments_for_course(
    session_payload: String,
    site_id: String,
    site_name: String,
    keyword: String,
) -> Result<FfiAssignmentListResponse, FfiAuthError> {
    let client = shared_default_client()?;
    assignments_for_course_with_client(
        client,
        shared_session_coordinator(),
        session_payload,
        site_id,
        site_name,
        keyword,
        now_ms(),
    )
    .await
}

pub async fn assignment_detail(
    session_payload: String,
    assignment_id: String,
) -> Result<FfiAssignmentDetailResponse, FfiAuthError> {
    let client = shared_default_client()?;
    assignment_detail_with_client(
        client,
        shared_session_coordinator(),
        session_payload,
        assignment_id,
        now_ms(),
    )
    .await
}

pub async fn assignment_upload(
    session_payload: String,
    assignment_id: String,
    file_path: String,
) -> Result<FfiAssignmentUploadResponse, FfiAuthError> {
    let client = shared_default_client()?;
    assignment_upload_with_client(
        client,
        shared_session_coordinator(),
        session_payload,
        assignment_id,
        file_path,
        now_ms(),
    )
    .await
}

pub async fn assignment_submit(
    session_payload: String,
    assignment_id: String,
    content: String,
    attachment_ids: Vec<String>,
) -> Result<FfiAssignmentSubmitResponse, FfiAuthError> {
    let client = shared_default_client()?;
    assignment_submit_with_client(
        client,
        shared_session_coordinator(),
        session_payload,
        assignment_id,
        content,
        attachment_ids,
        now_ms(),
    )
    .await
}

pub async fn resources_for_course(
    session_payload: String,
    site_id: String,
    site_name: String,
) -> Result<FfiCourseResourcesResponse, FfiAuthError> {
    let client = shared_default_client()?;
    resources_for_course_with_client(
        client,
        shared_session_coordinator(),
        session_payload,
        site_id,
        site_name,
        now_ms(),
    )
    .await
}

pub async fn resource_detail(
    session_payload: String,
    resource_id: String,
    site_id: String,
    site_name: String,
) -> Result<FfiCourseResourceDetailResponse, FfiAuthError> {
    let client = shared_default_client()?;
    resource_detail_with_client(
        client,
        shared_session_coordinator(),
        session_payload,
        resource_id,
        site_id,
        site_name,
        now_ms(),
    )
    .await
}

pub async fn resource_download_start(
    session_payload: String,
    resource_id: String,
    site_id: String,
    site_name: String,
    output_path: String,
) -> Result<FfiDownloadTaskStartResponse, FfiAuthError> {
    let client = shared_default_client()?;
    let (session, updated_session_payload) = refreshed_session(
        client,
        shared_session_coordinator(),
        session_payload,
        now_ms(),
    )
    .await?;
    let client = client.clone();
    let (task_id, task, mut status) = create_download_task(1);
    status.updated_session_payload = updated_session_payload;
    let worker_task = task.clone();
    let worker_task_id = task_id.clone();
    let handle = tokio::spawn(async move {
        let result = resource_download_task(
            client,
            worker_task.clone(),
            ResourceDownloadTaskRequest {
                session,
                resource_id,
                site_id,
                site_name,
                output_path,
            },
        )
        .await;
        finish_download_task(worker_task, result);
    });
    *lock_recover(&task.handle) = Some(handle);
    Ok(FfiDownloadTaskStartResponse {
        task_id: worker_task_id,
        status,
    })
}

pub async fn resource_download_course_start(
    session_payload: String,
    site_id: String,
    site_name: String,
    output_dir: String,
) -> Result<FfiDownloadTaskStartResponse, FfiAuthError> {
    let client = shared_default_client()?;
    let (session, updated_session_payload) = refreshed_session(
        client,
        shared_session_coordinator(),
        session_payload,
        now_ms(),
    )
    .await?;
    let client = client.clone();
    let (task_id, task, mut status) = create_download_task(0);
    status.updated_session_payload = updated_session_payload;
    let worker_task = task.clone();
    let worker_task_id = task_id.clone();
    let handle = tokio::spawn(async move {
        let result = resource_download_course_task(
            client,
            worker_task.clone(),
            session,
            site_id,
            site_name,
            output_dir,
        )
        .await;
        finish_download_task(worker_task, result);
    });
    *lock_recover(&task.handle) = Some(handle);
    Ok(FfiDownloadTaskStartResponse {
        task_id: worker_task_id,
        status,
    })
}

pub fn download_task_status(task_id: String) -> Result<FfiDownloadTaskStatus, FfiAuthError> {
    read_download_status(&task_id)
}

pub fn download_task_cancel(task_id: String) -> Result<FfiDownloadTaskStatus, FfiAuthError> {
    let task = download_tasks_map()
        .get(&task_id)
        .cloned()
        .ok_or_else(|| error(AuthErrorCode::NotFound, "下载任务不存在。"))?;
    task.cancel.cancel();
    update_download_status(&task, |status| {
        if matches!(
            status.state,
            FfiDownloadTaskState::Queued | FfiDownloadTaskState::Running
        ) {
            status.state = FfiDownloadTaskState::Cancelled;
            status.error_message = Some("下载已取消。".to_string());
        }
    });
    read_download_status(&task_id)
}

pub fn download_task_dispose(task_id: String) -> Result<(), FfiAuthError> {
    let task = download_tasks_map()
        .remove(&task_id)
        .ok_or_else(|| error(AuthErrorCode::NotFound, "下载任务不存在。"))?;
    task.cancel.cancel();
    if let Some(handle) = lock_recover(&task.handle).take() {
        handle.abort();
    }
    Ok(())
}

pub async fn logout() -> FfiLogoutResponse {
    shared_session_coordinator().clear().await;
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
    coordinator: &SessionCoordinator,
    session_payload: String,
    with_going: bool,
    now_ms: u64,
) -> Result<FfiCourseResponse, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    let (refreshed, updated_session_payload) =
        refreshed_session(client, coordinator, session_payload, now_ms).await?;
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

async fn assignments_undone_with_client<C>(
    client: &OpenCloudClient<C>,
    coordinator: &SessionCoordinator,
    session_payload: String,
    now_ms: u64,
) -> Result<FfiAssignmentListResponse, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    let (session, updated_session_payload) =
        refreshed_session(client, coordinator, session_payload, now_ms).await?;
    let response = client
        .get_undone_assignments(&session.user.user_id, &session.access_token)
        .await
        .map_err(to_ffi_error)?;
    Ok(FfiAssignmentListResponse {
        records: response.records.into_iter().map(Into::into).collect(),
        updated_session_payload,
    })
}

async fn assignments_for_course_with_client<C>(
    client: &OpenCloudClient<C>,
    coordinator: &SessionCoordinator,
    session_payload: String,
    site_id: String,
    site_name: String,
    keyword: String,
    now_ms: u64,
) -> Result<FfiAssignmentListResponse, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    let (session, updated_session_payload) =
        refreshed_session(client, coordinator, session_payload, now_ms).await?;
    let response = client
        .get_course_assignments(&site_id, &site_name, &session.access_token, &keyword)
        .await
        .map_err(to_ffi_error)?;
    Ok(FfiAssignmentListResponse {
        records: response.records.into_iter().map(Into::into).collect(),
        updated_session_payload,
    })
}

async fn assignment_detail_with_client<C>(
    client: &OpenCloudClient<C>,
    coordinator: &SessionCoordinator,
    session_payload: String,
    assignment_id: String,
    now_ms: u64,
) -> Result<FfiAssignmentDetailResponse, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    let (session, updated_session_payload) =
        refreshed_session(client, coordinator, session_payload, now_ms).await?;
    let detail = client
        .get_assignment_detail(&assignment_id, &session.access_token)
        .await
        .map_err(to_ffi_error)?;
    let mut response = FfiAssignmentDetailResponse::from(detail);
    response.updated_session_payload = updated_session_payload;
    Ok(response)
}

async fn assignment_upload_with_client<C>(
    client: &OpenCloudClient<C>,
    coordinator: &SessionCoordinator,
    session_payload: String,
    assignment_id: String,
    file_path: String,
    now_ms: u64,
) -> Result<FfiAssignmentUploadResponse, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    let (session, updated_session_payload) =
        refreshed_session(client, coordinator, session_payload, now_ms).await?;
    let detail = client
        .get_assignment_detail(&assignment_id, &session.access_token)
        .await
        .map_err(to_ffi_error)?;
    if detail.status == open_cloud_api::AssignmentStatus::Expired {
        return Err(error(
            AuthErrorCode::InvalidInput,
            "当前作业已截止，不能继续上传附件。",
        ));
    }
    let path = PathBuf::from(file_path);
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| error(AuthErrorCode::InvalidFileName, "invalid upload file name"))?;
    validate_upload_file_metadata(&path, file_name)?;
    let upload = client
        .upload_assignment_file_path(
            &detail,
            file_name,
            &path,
            &session.user.user_id,
            &session.access_token,
        )
        .await
        .map_err(to_ffi_error)?;
    let mut response = FfiAssignmentUploadResponse::from(upload);
    response.updated_session_payload = updated_session_payload;
    Ok(response)
}

async fn assignment_submit_with_client<C>(
    client: &OpenCloudClient<C>,
    coordinator: &SessionCoordinator,
    session_payload: String,
    assignment_id: String,
    content: String,
    attachment_ids: Vec<String>,
    now_ms: u64,
) -> Result<FfiAssignmentSubmitResponse, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    let (session, updated_session_payload) =
        refreshed_session(client, coordinator, session_payload, now_ms).await?;
    let response = client
        .submit_assignment(
            &assignment_id,
            &session.user.user_id,
            &content,
            &attachment_ids,
            &session.access_token,
        )
        .await
        .map_err(to_ffi_error)?;
    Ok(FfiAssignmentSubmitResponse {
        ok: response.ok,
        updated_session_payload,
    })
}

async fn resources_for_course_with_client<C>(
    client: &OpenCloudClient<C>,
    coordinator: &SessionCoordinator,
    session_payload: String,
    site_id: String,
    site_name: String,
    now_ms: u64,
) -> Result<FfiCourseResourcesResponse, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    let (session, updated_session_payload) =
        refreshed_session(client, coordinator, session_payload, now_ms).await?;
    let response = client
        .get_course_resources(
            &site_id,
            &site_name,
            &session.user.user_id,
            &session.access_token,
        )
        .await
        .map_err(to_ffi_error)?;
    Ok(FfiCourseResourcesResponse {
        records: response.records.into_iter().map(Into::into).collect(),
        updated_session_payload,
    })
}

async fn resource_detail_with_client<C>(
    client: &OpenCloudClient<C>,
    coordinator: &SessionCoordinator,
    session_payload: String,
    resource_id: String,
    site_id: String,
    site_name: String,
    now_ms: u64,
) -> Result<FfiCourseResourceDetailResponse, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    let (session, updated_session_payload) =
        refreshed_session(client, coordinator, session_payload, now_ms).await?;
    let detail = client
        .get_resource_detail(&resource_id, &site_id, &site_name, &session.access_token)
        .await
        .map_err(to_ffi_error)?;
    Ok(FfiCourseResourceDetailResponse {
        detail: detail.into(),
        updated_session_payload,
    })
}

#[cfg(test)]
async fn resource_download_with_client<C>(
    client: &OpenCloudClient<C>,
    coordinator: &SessionCoordinator,
    request: TestResourceDownloadRequest,
) -> Result<Vec<String>, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    let (session, _) =
        refreshed_session(client, coordinator, request.session_payload, request.now_ms).await?;
    let detail = client
        .get_resource_detail(
            &request.resource_id,
            &request.site_id,
            &request.site_name,
            &session.access_token,
        )
        .await
        .map_err(to_ffi_error)?;
    let written_path = download_resource_to_path(
        client,
        &detail,
        Path::new(&request.output_path),
        DownloadProgress::default(),
        DownloadCancelFlag::default(),
    )
    .await?;
    Ok(vec![written_path.display().to_string()])
}

#[cfg(test)]
async fn resource_download_course_with_client<C>(
    client: &OpenCloudClient<C>,
    coordinator: &SessionCoordinator,
    session_payload: String,
    site_id: String,
    site_name: String,
    output_dir: String,
    now_ms: u64,
) -> Result<Vec<String>, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    let (session, _) = refreshed_session(client, coordinator, session_payload, now_ms).await?;
    let list = client
        .get_course_resources(
            &site_id,
            &site_name,
            &session.user.user_id,
            &session.access_token,
        )
        .await
        .map_err(to_ffi_error)?;
    fs::create_dir_all(&output_dir).map_err(fs_error)?;
    let details = fetch_course_resource_details(
        client,
        list.records,
        &site_id,
        &site_name,
        &session.access_token,
        DownloadCancelFlag::default(),
    )
    .await?;
    let targets = course_download_targets(Path::new(&output_dir), details)?;
    let downloads =
        download_course_targets(client, targets, DownloadCancelFlag::default(), None).await?;
    Ok(downloads
        .into_iter()
        .map(|(_, path)| path.display().to_string())
        .collect())
}

async fn resource_download_task(
    client: OpenCloudClient<ReqwestHttpClient>,
    task: Arc<DownloadTask>,
    request: ResourceDownloadTaskRequest,
) -> Result<(), FfiAuthError> {
    update_download_status(&task, |status| {
        status.state = FfiDownloadTaskState::Running;
        status.total = 1;
    });
    let detail = client
        .get_resource_detail(
            &request.resource_id,
            &request.site_id,
            &request.site_name,
            &request.session.access_token,
        )
        .await
        .map_err(to_ffi_error)?;
    update_download_status(&task, |status| {
        status.current_file_name = Some(detail.name.clone());
        status.records = vec![detail.clone().into()];
    });
    let progress_task = task.clone();
    let progress = DownloadProgress::new(move |bytes| {
        update_download_status(&progress_task, |status| {
            status.bytes_downloaded = status.bytes_downloaded.saturating_add(bytes);
        });
    });
    let written_path = download_resource_to_path(
        &client,
        &detail,
        Path::new(&request.output_path),
        progress,
        task.cancel.clone(),
    )
    .await?;
    update_download_status(&task, |status| {
        status.current = 1;
        status.written_paths = vec![written_path.display().to_string()];
        status.current_file_name = None;
    });
    Ok(())
}

async fn resource_download_course_task(
    client: OpenCloudClient<ReqwestHttpClient>,
    task: Arc<DownloadTask>,
    session: AuthSession,
    site_id: String,
    site_name: String,
    output_dir: String,
) -> Result<(), FfiAuthError> {
    update_download_status(&task, |status| {
        status.state = FfiDownloadTaskState::Running;
    });
    let list = client
        .get_course_resources(
            &site_id,
            &site_name,
            &session.user.user_id,
            &session.access_token,
        )
        .await
        .map_err(to_ffi_error)?;
    fs::create_dir_all(&output_dir).map_err(fs_error)?;
    update_download_status(&task, |status| {
        status.total = list.records.len() as u32;
    });
    let details = fetch_course_resource_details(
        &client,
        list.records,
        &site_id,
        &site_name,
        &session.access_token,
        task.cancel.clone(),
    )
    .await?;

    let targets = course_download_targets(Path::new(&output_dir), details)?;
    download_course_targets(&client, targets, task.cancel.clone(), Some(task.clone())).await?;
    update_download_status(&task, |status| {
        status.current_file_name = None;
    });
    Ok(())
}

async fn fetch_course_resource_details<C>(
    client: &OpenCloudClient<C>,
    records: Vec<CourseResourceSummary>,
    site_id: &str,
    site_name: &str,
    access_token: &str,
    cancel: DownloadCancelFlag,
) -> Result<Vec<CourseResourceDetail>, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    stream::iter(records)
        .take_while({
            let cancel = cancel.clone();
            move |_| std::future::ready(!cancel.is_cancelled())
        })
        .map(|resource| {
            let client = client.clone();
            let site_id = site_id.to_string();
            let site_name = site_name.to_string();
            let access_token = access_token.to_string();
            let cancel = cancel.clone();
            async move {
                if cancel.is_cancelled() {
                    return Err(error(AuthErrorCode::Cancelled, "下载已取消。"));
                }
                let detail = client
                    .get_resource_detail(&resource.resource_id, &site_id, &site_name, &access_token)
                    .await
                    .map_err(to_ffi_error)?;
                if cancel.is_cancelled() {
                    return Err(error(AuthErrorCode::Cancelled, "下载已取消。"));
                }
                Ok(detail)
            }
        })
        .buffered(COURSE_DOWNLOAD_CONCURRENCY)
        .collect::<Vec<_>>()
        .await
        .into_iter()
        .collect()
}

fn course_download_targets(
    output_dir: &Path,
    details: Vec<CourseResourceDetail>,
) -> Result<Vec<(CourseResourceDetail, PathBuf)>, FfiAuthError> {
    let mut reserved = HashSet::new();
    details
        .into_iter()
        .map(|detail| {
            let requested = output_dir.join(sanitize_file_name(&detail.name));
            let target = next_download_path_reserved(&requested, &mut reserved)?;
            Ok((detail, target))
        })
        .collect()
}

fn next_download_path_reserved(
    requested_path: &Path,
    reserved: &mut HashSet<PathBuf>,
) -> Result<PathBuf, FfiAuthError> {
    if !requested_path.exists() && reserved.insert(requested_path.to_path_buf()) {
        return Ok(requested_path.to_path_buf());
    }
    let parent = requested_path.parent().unwrap_or_else(|| Path::new("."));
    let stem = requested_path
        .file_stem()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .unwrap_or("download");
    let extension = requested_path.extension().and_then(|value| value.to_str());
    for index in 1..10_000 {
        let file_name = match extension {
            Some(extension) if !extension.is_empty() => format!("{stem} ({index}).{extension}"),
            _ => format!("{stem} ({index})"),
        };
        let candidate = parent.join(file_name);
        if !candidate.exists() && reserved.insert(candidate.clone()) {
            return Ok(candidate);
        }
    }
    Err(error(
        AuthErrorCode::FileSystem,
        "could not allocate a non-overwriting download path.",
    ))
}

async fn download_course_targets<C>(
    client: &OpenCloudClient<C>,
    targets: Vec<(CourseResourceDetail, PathBuf)>,
    cancel: DownloadCancelFlag,
    task: Option<Arc<DownloadTask>>,
) -> Result<Vec<(CourseResourceDetail, PathBuf)>, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    stream::iter(targets)
        .map(|(detail, target)| {
            let client = client.clone();
            let cancel = cancel.clone();
            let task = task.clone();
            async move {
                if cancel.is_cancelled() {
                    return Err(error(AuthErrorCode::Cancelled, "下载已取消。"));
                }
                if let Some(task) = &task {
                    update_download_status(task, |status| {
                        status.current_file_name = Some(detail.name.clone());
                        status.records.push(detail.clone().into());
                    });
                }
                let progress = if let Some(task) = &task {
                    let progress_task = task.clone();
                    DownloadProgress::new(move |bytes| {
                        update_download_status(&progress_task, |status| {
                            status.bytes_downloaded = status.bytes_downloaded.saturating_add(bytes);
                        });
                    })
                } else {
                    DownloadProgress::default()
                };
                let written_path =
                    download_resource_to_path(&client, &detail, &target, progress, cancel.clone())
                        .await?;
                if let Some(task) = &task {
                    update_download_status(task, |status| {
                        status.current = status.current.saturating_add(1);
                        status
                            .written_paths
                            .push(written_path.display().to_string());
                    });
                }
                Ok((detail, written_path))
            }
        })
        .buffered(COURSE_DOWNLOAD_CONCURRENCY)
        .collect::<Vec<_>>()
        .await
        .into_iter()
        .collect()
}

fn finish_download_task(task: Arc<DownloadTask>, result: Result<(), FfiAuthError>) {
    update_download_status(&task, |status| match result {
        Ok(()) => {
            if !matches!(status.state, FfiDownloadTaskState::Cancelled) {
                status.state = FfiDownloadTaskState::Succeeded;
                status.current_file_name = None;
                status.error_message = None;
            }
        }
        Err(error) => {
            if matches!(status.state, FfiDownloadTaskState::Cancelled) {
                status.current_file_name = None;
                status.error_message = Some("下载已取消。".to_string());
            } else {
                status.state = FfiDownloadTaskState::Failed;
                status.current_file_name = None;
                status.error_message = Some(error.message);
            }
        }
    });
}

async fn refreshed_session<C>(
    client: &OpenCloudClient<C>,
    coordinator: &SessionCoordinator,
    session_payload: String,
    now_ms: u64,
) -> Result<(AuthSession, Option<String>), FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    let incoming = decode_session_payload(&session_payload, now_ms)?;
    let refreshed = coordinator
        .resolve(client, incoming.clone(), now_ms)
        .await
        .map_err(to_ffi_error)?;
    let updated_session_payload = if refreshed != incoming {
        Some(encode_session_payload(&refreshed)?)
    } else {
        None
    };
    Ok((refreshed, updated_session_payload))
}

async fn download_resource_to_path<C>(
    client: &OpenCloudClient<C>,
    detail: &open_cloud_api::CourseResourceDetail,
    requested_path: &Path,
    progress: DownloadProgress,
    cancel: DownloadCancelFlag,
) -> Result<PathBuf, FfiAuthError>
where
    C: open_cloud_core::HttpClient,
{
    let url = detail
        .download_url
        .as_deref()
        .ok_or_else(|| error(AuthErrorCode::NotFound, "当前资料暂时没有可用下载链接。"))?;
    let parent = requested_path.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent).map_err(fs_error)?;
    let path = next_download_path(requested_path)?;
    client
        .download_url_to_path(url, &path, progress, cancel)
        .await
        .map_err(to_ffi_error)?;
    Ok(path)
}

fn next_download_path(requested_path: &Path) -> Result<PathBuf, FfiAuthError> {
    if !requested_path.exists() {
        return Ok(requested_path.to_path_buf());
    }
    let parent = requested_path.parent().unwrap_or_else(|| Path::new("."));
    let stem = requested_path
        .file_stem()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .unwrap_or("download");
    let extension = requested_path.extension().and_then(|value| value.to_str());
    for index in 1..10_000 {
        let file_name = match extension {
            Some(extension) if !extension.is_empty() => format!("{stem} ({index}).{extension}"),
            _ => format!("{stem} ({index})"),
        };
        let candidate = parent.join(file_name);
        if !candidate.exists() {
            return Ok(candidate);
        }
    }
    Err(error(
        AuthErrorCode::FileSystem,
        "could not allocate a non-overwriting download path.",
    ))
}

fn sanitize_file_name(file_name: &str) -> String {
    let cleaned = file_name
        .chars()
        .map(|ch| match ch {
            '/' | '\\' | '\0' => '_',
            other => other,
        })
        .collect::<String>()
        .trim()
        .to_string();
    if cleaned.is_empty() {
        "download".to_string()
    } else {
        cleaned
    }
}

fn fs_error(source: std::io::Error) -> FfiAuthError {
    error(AuthErrorCode::FileSystem, source.to_string())
}

fn validate_upload_file_metadata(path: &Path, file_name: &str) -> Result<(), FfiAuthError> {
    if file_name.contains(['\r', '\n']) {
        return Err(error(
            AuthErrorCode::InvalidFileName,
            "上传文件名不能包含换行符。",
        ));
    }
    let metadata = fs::metadata(path).map_err(fs_error)?;
    if metadata.len() == 0 {
        return Err(error(AuthErrorCode::EmptyUpload, "上传文件不能为空。"));
    }
    if metadata.len() > MAX_ASSIGNMENT_UPLOAD_BYTES {
        return Err(error(
            AuthErrorCode::FileTooLarge,
            "单个附件不能超过 25 MB。",
        ));
    }
    let extension = file_name
        .rsplit_once('.')
        .map(|(_, extension)| extension.trim().to_ascii_lowercase());
    if extension
        .as_deref()
        .is_some_and(|extension| BLOCKED_UPLOAD_EXTENSIONS.contains(&extension))
    {
        return Err(error(
            AuthErrorCode::FileTypeNotAllowed,
            "当前不支持上传可执行文件，请改用文档、图片、压缩包或代码文本。",
        ));
    }
    Ok(())
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
    FfiAuthError {
        code: error_value.code.into(),
        message: error_value.message,
        retry_after_seconds: error_value.retry_after_seconds,
    }
}

fn error(code: AuthErrorCode, message: impl Into<String>) -> FfiAuthError {
    FfiAuthError {
        code: code.into(),
        message: message.into(),
        retry_after_seconds: None,
    }
}

impl From<LoginFlow> for FfiLoginFlow {
    fn from(value: LoginFlow) -> Self {
        Self {
            captcha_id: value.captcha_id,
            captcha_image: value.captcha_image,
            cookie: value.cookie,
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
            AuthErrorCode::Cancelled => Self::Cancelled,
            AuthErrorCode::InvalidInput => Self::InvalidInput,
            AuthErrorCode::NotFound => Self::NotFound,
            AuthErrorCode::FileSystem => Self::FileSystem,
            AuthErrorCode::RateLimited => Self::RateLimited,
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
            role_alias: value.role_alias,
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

impl From<open_cloud_api::AttendanceQrPayload> for FfiAttendanceQrPayload {
    fn from(value: open_cloud_api::AttendanceQrPayload) -> Self {
        Self {
            attendance_id: value.attendance_id,
            site_id: value.site_id,
            create_time: value.create_time,
            class_lesson_id: value.class_lesson_id,
        }
    }
}

impl From<open_cloud_api::ClientCapabilities> for FfiClientCapabilities {
    fn from(value: open_cloud_api::ClientCapabilities) -> Self {
        Self {
            self_attendance: value.self_attendance,
            attendance_qr_payload_parsing: value.attendance_qr_payload_parsing,
        }
    }
}

impl From<open_cloud_api::AssignmentStatus> for FfiAssignmentStatus {
    fn from(value: open_cloud_api::AssignmentStatus) -> Self {
        match value {
            open_cloud_api::AssignmentStatus::Pending => Self::Pending,
            open_cloud_api::AssignmentStatus::Submitted => Self::Submitted,
            open_cloud_api::AssignmentStatus::Expired => Self::Expired,
        }
    }
}

impl From<open_cloud_api::AssignmentSummary> for FfiAssignmentSummary {
    fn from(value: open_cloud_api::AssignmentSummary) -> Self {
        Self {
            end_time: value.end_time,
            id: value.id,
            site_id: value.site_id,
            site_name: value.site_name,
            source: value.source.as_str().to_string(),
            start_time: value.start_time,
            status: value.status.into(),
            title: value.title,
        }
    }
}

impl From<open_cloud_api::AssignmentResource> for FfiAssignmentResource {
    fn from(value: open_cloud_api::AssignmentResource) -> Self {
        Self {
            ext: value.ext,
            name: value.name,
            preview_url: value.preview_url,
            resource_id: value.resource_id,
            storage_id: value.storage_id,
        }
    }
}

impl From<open_cloud_api::AssignmentDetailResponse> for FfiAssignmentDetailResponse {
    fn from(value: open_cloud_api::AssignmentDetailResponse) -> Self {
        Self {
            class_name: value.class_name,
            comment: value.comment,
            content: value.content,
            end_time: value.end_time,
            id: value.id,
            is_overtime_commit: value.is_overtime_commit,
            score: value.score,
            site_id: value.site_id,
            site_name: value.site_name,
            start_time: value.start_time,
            status: value.status.into(),
            submitted_at: value.submitted_at,
            submitted_attachments: value
                .submitted_attachments
                .into_iter()
                .map(Into::into)
                .collect(),
            submitted_content: value.submitted_content,
            teacher_resources: value
                .teacher_resources
                .into_iter()
                .map(Into::into)
                .collect(),
            title: value.title,
            updated_session_payload: None,
        }
    }
}

impl From<open_cloud_api::AssignmentUploadResponse> for FfiAssignmentUploadResponse {
    fn from(value: open_cloud_api::AssignmentUploadResponse) -> Self {
        Self {
            assignment_id: value.assignment_id,
            file_name: value.file_name,
            preview_url: value.preview_url,
            resource_id: value.resource_id,
            site_id: value.site_id,
            site_name: value.site_name,
            updated_session_payload: None,
        }
    }
}

impl From<open_cloud_api::CourseResourceSummary> for FfiCourseResourceSummary {
    fn from(value: open_cloud_api::CourseResourceSummary) -> Self {
        Self {
            ext: value.ext,
            name: value.name,
            resource_id: value.resource_id,
            site_id: value.site_id,
            site_name: value.site_name,
            size_bytes: value.size_bytes,
            updated_at: value.updated_at,
        }
    }
}

impl From<open_cloud_api::CourseResourceDetail> for FfiCourseResourceDetail {
    fn from(value: open_cloud_api::CourseResourceDetail) -> Self {
        Self {
            description: value.description,
            download_url: value.download_url,
            ext: value.ext,
            name: value.name,
            resource_id: value.resource_id,
            site_id: value.site_id,
            site_name: value.site_name,
            size_bytes: value.size_bytes,
            updated_at: value.updated_at,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;
    use open_cloud_api::{RoleName, SessionUser};
    use open_cloud_core::{AuthError, HttpRequest, HttpResponse, HttpResponseHead};
    use std::collections::VecDeque;
    use std::path::Path;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Arc, Mutex};
    use std::time::Duration;

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
    impl open_cloud_core::HttpClient for MockHttp {
        async fn send(&self, request: HttpRequest) -> Result<HttpResponse, AuthError> {
            self.requests.lock().expect("requests lock").push(request);
            self.responses
                .lock()
                .expect("responses lock")
                .pop_front()
                .ok_or_else(|| AuthError::upstream("missing mock response"))
        }
    }

    #[derive(Clone)]
    struct SlowDownloadHttp {
        responses: Arc<Mutex<VecDeque<HttpResponse>>>,
        requests: Arc<Mutex<Vec<HttpRequest>>>,
        active_downloads: Arc<AtomicUsize>,
        max_active_downloads: Arc<AtomicUsize>,
    }

    impl SlowDownloadHttp {
        fn with(responses: Vec<HttpResponse>) -> Self {
            Self {
                responses: Arc::new(Mutex::new(VecDeque::from(responses))),
                requests: Arc::new(Mutex::new(Vec::new())),
                active_downloads: Arc::new(AtomicUsize::new(0)),
                max_active_downloads: Arc::new(AtomicUsize::new(0)),
            }
        }

        fn max_active_downloads(&self) -> usize {
            self.max_active_downloads.load(Ordering::SeqCst)
        }
    }

    #[async_trait]
    impl open_cloud_core::HttpClient for SlowDownloadHttp {
        async fn send(&self, request: HttpRequest) -> Result<HttpResponse, AuthError> {
            self.requests.lock().expect("requests lock").push(request);
            self.responses
                .lock()
                .expect("responses lock")
                .pop_front()
                .ok_or_else(|| AuthError::upstream("missing mock response"))
        }

        async fn download_to_path(
            &self,
            request: HttpRequest,
            path: &Path,
            progress: DownloadProgress,
            cancel: DownloadCancelFlag,
        ) -> Result<HttpResponseHead, AuthError> {
            self.requests.lock().expect("requests lock").push(request);
            if cancel.is_cancelled() {
                return Err(AuthError::upstream("cancelled"));
            }
            let active = self.active_downloads.fetch_add(1, Ordering::SeqCst) + 1;
            let mut observed = self.max_active_downloads.load(Ordering::SeqCst);
            while active > observed {
                match self.max_active_downloads.compare_exchange(
                    observed,
                    active,
                    Ordering::SeqCst,
                    Ordering::SeqCst,
                ) {
                    Ok(_) => break,
                    Err(next) => observed = next,
                }
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
            if let Some(parent) = path.parent() {
                tokio::fs::create_dir_all(parent)
                    .await
                    .map_err(|error| AuthError::upstream(error.to_string()))?;
            }
            tokio::fs::write(path, b"downloaded")
                .await
                .map_err(|error| AuthError::upstream(error.to_string()))?;
            progress.add(10);
            self.active_downloads.fetch_sub(1, Ordering::SeqCst);
            Ok(HttpResponseHead {
                status: 200,
                headers: Vec::new(),
            })
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
    fn parse_attendance_qr_payload_text_returns_scanned_fields() {
        let payload = parse_attendance_qr_payload_text(
            "checkwork|id=attendance-1&siteId=site-1&createTime=2026-05-08+09:30:00&classLessonId=group-1"
                .to_string(),
        )
        .expect("payload parses");

        assert_eq!(
            payload,
            FfiAttendanceQrPayload {
                attendance_id: "attendance-1".to_string(),
                site_id: "site-1".to_string(),
                create_time: "2026-05-08+09:30:00".to_string(),
                class_lesson_id: "group-1".to_string(),
            }
        );
    }

    #[test]
    fn parse_attendance_qr_payload_text_rejects_non_checkwork_values() {
        let err = parse_attendance_qr_payload_text("site-1:group-1".to_string())
            .expect_err("invalid payload fails");

        assert_eq!(err.code, FfiAuthErrorCode::InvalidInput);
    }

    #[test]
    fn capabilities_declares_qr_parsing_without_self_attendance() {
        assert_eq!(
            capabilities(),
            FfiClientCapabilities {
                self_attendance: false,
                attendance_qr_payload_parsing: true,
            }
        );
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
        let coordinator = SessionCoordinator::default();
        let payload = encode_session_payload(&session(101, 1_000)).expect("session encodes");

        let result = courses_with_client(&client, &coordinator, payload, true, 100_500)
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
    async fn concurrent_session_resolution_refreshes_only_once() {
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
        let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());
        let coordinator = SessionCoordinator::default();
        let incoming = session(101, 1_000);

        let (first, second) = tokio::join!(
            coordinator.resolve(&client, incoming.clone(), 100_500),
            coordinator.resolve(&client, incoming, 100_500),
        );

        assert_eq!(first.expect("first session").access_token, refreshed_access);
        assert_eq!(
            second.expect("second session").access_token,
            refreshed_access
        );
        assert_eq!(
            http.requests().len(),
            2,
            "refresh chain must be single-flight"
        );
    }

    #[tokio::test]
    async fn session_resolution_reconciles_a_stale_payload_with_cached_session() {
        let http = MockHttp::default();
        let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());
        let coordinator = SessionCoordinator::default();
        let stale = session(future_exp(5_000), future_exp(10_000));
        let current = session(future_exp(15_000), future_exp(20_000));
        coordinator.replace(current.clone()).await;

        let resolved = coordinator
            .resolve(&client, stale, now_ms())
            .await
            .expect("cached session resolves");

        assert_eq!(resolved, current);
        assert!(http.requests().is_empty());
    }

    #[tokio::test]
    async fn courses_without_going_keeps_session_payload_when_access_token_is_valid() {
        let http = MockHttp::with(vec![response(
            200,
            &[],
            r#"{"success":true,"data":{"records":[{"id":"site-1","siteName":"软件测试"}]}}"#,
        )]);
        let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
        let coordinator = SessionCoordinator::default();
        let payload = encode_session_payload(&session(future_exp(10_000), future_exp(20_000)))
            .expect("session encodes");

        let result = courses_with_client(&client, &coordinator, payload, false, 100_500)
            .await
            .expect("courses load");

        assert_eq!(result.records.len(), 1);
        assert!(result.going_sites.is_empty());
        assert_eq!(result.updated_session_payload, None);
    }

    #[tokio::test]
    async fn undone_assignments_refreshes_expiring_session_and_returns_updated_payload() {
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
                r#"{"success":true,"data":{"undoneList":[{"activityId":"work-1","activityName":"实验报告","endTime":"2026-05-03 23:59:59","type":3,"siteId":"site-1","siteName":"软件测试"}]}}"#,
            ),
        ]);
        let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
        let coordinator = SessionCoordinator::default();
        let payload = encode_session_payload(&session(101, 1_000)).expect("session encodes");

        let result = assignments_undone_with_client(&client, &coordinator, payload, 100_500)
            .await
            .expect("assignments load");

        assert_eq!(result.records[0].id, "work-1");
        let updated = result
            .updated_session_payload
            .expect("refreshed session payload");
        assert!(updated.contains(&refreshed_access));
    }

    #[tokio::test]
    async fn assignment_upload_rejects_expired_assignment_before_reading_file() {
        let http = MockHttp::with(vec![response(
            200,
            &[],
            r#"{"success":true,"data":{"assignmentEndTime":"2000-01-01 00:00:00","assignmentTitle":"实验报告","id":"work-1","siteId":"site-1","siteName":"软件测试"}}"#,
        )]);
        let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
        let coordinator = SessionCoordinator::default();
        let payload = encode_session_payload(&session(future_exp(10_000), future_exp(20_000)))
            .expect("session encodes");

        let err = assignment_upload_with_client(
            &client,
            &coordinator,
            payload,
            "work-1".to_string(),
            "/definitely/missing/report.pdf".to_string(),
            100_500,
        )
        .await
        .expect_err("expired assignment is rejected");

        assert_eq!(err.message, "当前作业已截止，不能继续上传附件。");
        assert_eq!(err.code, FfiAuthErrorCode::InvalidInput);
    }

    #[tokio::test]
    async fn resource_download_writes_to_next_non_overwriting_path() {
        let base = std::env::temp_dir().join(format!("open-cloud-ffi-{}", now_ms()));
        std::fs::create_dir_all(&base).expect("temp dir");
        let existing = base.join("课件.pdf");
        std::fs::write(&existing, b"old").expect("existing file");
        let output = base.join("课件.pdf");
        let http = MockHttp::with(vec![
            response(
                200,
                &[],
                r#"{"success":true,"data":[{"id":"resource-1","name":"课件.pdf","ext":"pdf","updateTime":"2026-05-02 10:00:00"}]}"#,
            ),
            response(
                200,
                &[],
                r#"{"success":true,"data":{"previewUrl":"https://files.example/resource-1"}}"#,
            ),
            response(200, &[], "new bytes"),
        ]);
        let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
        let coordinator = SessionCoordinator::default();
        let payload = encode_session_payload(&session(future_exp(10_000), future_exp(20_000)))
            .expect("session encodes");

        let result = resource_download_with_client(
            &client,
            &coordinator,
            TestResourceDownloadRequest {
                session_payload: payload,
                resource_id: "resource-1".to_string(),
                site_id: "site-1".to_string(),
                site_name: "软件测试".to_string(),
                output_path: output.display().to_string(),
                now_ms: 100_500,
            },
        )
        .await
        .expect("resource downloads");

        assert_eq!(std::fs::read(&existing).expect("existing"), b"old");
        assert_eq!(std::fs::read(&result[0]).expect("new"), b"new bytes");
        assert!(result[0].ends_with("课件 (1).pdf"));
    }

    #[tokio::test]
    async fn resource_download_course_sanitizes_upstream_file_names() {
        let base = std::env::temp_dir().join(format!("open-cloud-ffi-batch-{}", now_ms()));
        std::fs::create_dir_all(&base).expect("temp dir");
        let outside = base
            .parent()
            .expect("parent")
            .join("outside-from-ffi-test.pdf");
        let _ = std::fs::remove_file(&outside);
        let http = MockHttp::with(vec![
            response(
                200,
                &[],
                r#"{"success":true,"data":[{"resource":{"id":"resource-1","name":"safe.pdf"}}]}"#,
            ),
            response(
                200,
                &[],
                r#"{"success":true,"data":[{"id":"resource-1","name":"../outside-from-ffi-test.pdf","ext":"pdf","updateTime":"2026-05-02 10:00:00"}]}"#,
            ),
            response(
                200,
                &[],
                r#"{"success":true,"data":{"previewUrl":"https://files.example/resource-1"}}"#,
            ),
            response(200, &[], "new bytes"),
        ]);
        let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
        let coordinator = SessionCoordinator::default();
        let payload = encode_session_payload(&session(future_exp(10_000), future_exp(20_000)))
            .expect("session encodes");

        let result = resource_download_course_with_client(
            &client,
            &coordinator,
            payload,
            "site-1".to_string(),
            "软件测试".to_string(),
            base.display().to_string(),
            100_500,
        )
        .await
        .expect("course resources download");

        assert!(!outside.exists());
        assert_eq!(
            result,
            vec![base
                .join(".._outside-from-ffi-test.pdf")
                .display()
                .to_string()]
        );
        assert_eq!(
            std::fs::read(&result[0]).expect("sanitized file"),
            b"new bytes"
        );
    }

    #[tokio::test]
    async fn resource_download_course_downloads_files_concurrently() {
        let base = std::env::temp_dir().join(format!("open-cloud-ffi-parallel-{}", now_ms()));
        let http = SlowDownloadHttp::with(vec![
            response(
                200,
                &[],
                r#"{"success":true,"data":[{"resource":{"id":"resource-1","name":"one.pdf"}},{"resource":{"id":"resource-2","name":"two.pdf"}}]}"#,
            ),
            response(
                200,
                &[],
                r#"{"success":true,"data":[{"id":"resource-1","name":"one.pdf","ext":"pdf","updateTime":"2026-05-02 10:00:00"}]}"#,
            ),
            response(
                200,
                &[],
                r#"{"success":true,"data":{"previewUrl":"https://files.example/resource-1"}}"#,
            ),
            response(
                200,
                &[],
                r#"{"success":true,"data":[{"id":"resource-2","name":"two.pdf","ext":"pdf","updateTime":"2026-05-02 10:00:00"}]}"#,
            ),
            response(
                200,
                &[],
                r#"{"success":true,"data":{"previewUrl":"https://files.example/resource-2"}}"#,
            ),
        ]);
        let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());
        let coordinator = SessionCoordinator::default();
        let payload = encode_session_payload(&session(future_exp(10_000), future_exp(20_000)))
            .expect("session encodes");

        let result = resource_download_course_with_client(
            &client,
            &coordinator,
            payload,
            "site-1".to_string(),
            "软件测试".to_string(),
            base.display().to_string(),
            100_500,
        )
        .await
        .expect("course resources download");

        assert_eq!(result.len(), 2);
        assert!(
            http.max_active_downloads() >= 2,
            "expected overlapping downloads, max active was {}",
            http.max_active_downloads()
        );
    }

    #[test]
    fn running_download_status_omits_accumulated_result_payloads() {
        let (task_id, task, _) = create_download_task(2);
        update_download_status(&task, |status| {
            status.state = FfiDownloadTaskState::Running;
            status.current = 1;
            status.written_paths.push("/tmp/课件.pdf".to_string());
            status.records.push(FfiCourseResourceDetail {
                description: None,
                download_url: None,
                ext: Some("pdf".to_string()),
                name: "课件.pdf".to_string(),
                resource_id: "resource-1".to_string(),
                site_id: "site-1".to_string(),
                site_name: "软件测试".to_string(),
                size_bytes: None,
                updated_at: String::new(),
            });
        });

        let status = read_download_status(&task_id).expect("status exists");

        assert_eq!(status.state, FfiDownloadTaskState::Running);
        assert_eq!(status.current, 1);
        assert!(status.written_paths.is_empty());
        assert!(status.records.is_empty());
        download_tasks()
            .lock()
            .expect("download task map")
            .remove(&task_id);
    }

    #[tokio::test]
    async fn course_detail_fetch_stops_before_network_when_cancelled() {
        let http = MockHttp::with(vec![response(
            200,
            &[],
            r#"{"success":true,"data":[{"id":"resource-1","name":"课件.pdf"}]}"#,
        )]);
        let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());
        let cancel = DownloadCancelFlag::new();
        cancel.cancel();

        let details = fetch_course_resource_details(
            &client,
            vec![CourseResourceSummary {
                ext: None,
                name: "课件.pdf".to_string(),
                resource_id: "resource-1".to_string(),
                site_id: "site-1".to_string(),
                site_name: "软件测试".to_string(),
                size_bytes: None,
                updated_at: String::new(),
            }],
            "site-1",
            "软件测试",
            "access-token",
            cancel,
        )
        .await
        .expect("cancelled stream stops cleanly");

        assert!(details.is_empty());
        assert!(http.requests().is_empty());
    }
}
