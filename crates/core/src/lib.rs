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

pub use attendance::parse_attendance_qr_payload;
pub use auth::{get_token_expiration_ms, LoginFlow, LoginResult, UserInfoPayload};
pub use client::{OpenCloudClient, OpenCloudEndpoints};
pub use courses::resolve_course_detail;
pub use error::AuthError;
pub use extensions::client_capabilities;
pub use session::{refresh_session_if_needed, SessionManager};
pub use transport::{
    HttpBody, HttpClient, HttpMethod, HttpRequest, HttpResponse, ReqwestHttpClient,
};
