mod attendance;
mod auth;
mod client;
mod courses;
mod error;
mod session;
mod transport;

pub use auth::{get_token_expiration_ms, LoginFlow, LoginResult, UserInfoPayload};
pub use client::{AuthClient, AuthEndpoints};
pub use courses::resolve_course_detail;
pub use error::AuthError;
pub use session::{refresh_session_if_needed, SessionManager};
pub use transport::{HttpClient, HttpMethod, HttpRequest, HttpResponse, ReqwestHttpClient};
