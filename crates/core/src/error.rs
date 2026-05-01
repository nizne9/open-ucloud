use open_cloud_api::AuthErrorCode;
use thiserror::Error;

#[derive(Clone, Debug, Error, Eq, PartialEq)]
#[error("{message}")]
pub struct AuthError {
    pub code: AuthErrorCode,
    pub message: String,
}

impl AuthError {
    pub fn new(code: AuthErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    pub fn upstream(message: impl Into<String>) -> Self {
        Self::new(AuthErrorCode::UpstreamUnavailable, message)
    }
}
