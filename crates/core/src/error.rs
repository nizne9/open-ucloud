use open_cloud_api::AuthErrorCode;
use thiserror::Error;

#[derive(Clone, Debug, Error, Eq, PartialEq)]
#[error("{message}")]
pub struct AuthError {
    pub code: AuthErrorCode,
    pub message: String,
    pub retry_after_seconds: Option<u64>,
}

impl AuthError {
    pub fn new(code: AuthErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            retry_after_seconds: None,
        }
    }

    pub fn upstream(message: impl Into<String>) -> Self {
        Self::new(AuthErrorCode::UpstreamUnavailable, message)
    }

    pub fn file_system(message: impl Into<String>) -> Self {
        Self::new(AuthErrorCode::FileSystem, message)
    }

    pub fn with_retry_after(mut self, retry_after_seconds: Option<u64>) -> Self {
        self.retry_after_seconds = retry_after_seconds;
        self
    }
}
