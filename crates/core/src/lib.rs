mod assignments;
mod attendance;
mod auth;
mod client;
mod courses;
mod error;
mod extensions;
mod protocol;
mod resources;
mod session;
mod transport;

pub use assignments::{BLOCKED_UPLOAD_EXTENSIONS, MAX_ASSIGNMENT_UPLOAD_BYTES};
pub use attendance::parse_attendance_qr_payload;
pub use auth::{get_token_expiration_ms, LoginFlow, LoginResult, UserInfoPayload};
pub use client::{OpenUcloudClient, OpenUcloudEndpoints};
pub use courses::resolve_course_detail;
pub use error::AuthError;
pub use extensions::client_capabilities;
pub use resources::{
    next_download_path, next_download_path_in_dir, next_download_path_reserved, sanitize_file_name,
};
pub use session::{now_ms, refresh_session_if_needed, SessionManager};
pub use transport::{
    DownloadCancelFlag, DownloadProgress, HttpBody, HttpClient, HttpMethod, HttpRequest,
    HttpResponse, HttpResponseHead, ReqwestHttpClient,
};
