use crate::{AuthError, HttpResponse};
use serde::Deserialize;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
struct UcloudEnvelope<T> {
    data: Option<T>,
    message: Option<String>,
    msg: Option<String>,
    success: Option<bool>,
}

impl<T> UcloudEnvelope<T> {
    fn upstream_message(self, fallback: &str) -> String {
        self.message
            .or(self.msg)
            .filter(|message| !message.trim().is_empty())
            .unwrap_or_else(|| fallback.to_string())
    }
}

pub(crate) fn parse_ucloud_envelope<T>(
    response: HttpResponse,
    fallback: &str,
) -> Result<T, AuthError>
where
    T: for<'de> Deserialize<'de>,
{
    if !(200..300).contains(&response.status) {
        return Err(AuthError::upstream(format!(
            "{fallback} HTTP status {}.",
            response.status
        )));
    }
    let payload: UcloudEnvelope<T> = serde_json::from_slice(&response.body)
        .map_err(|error| AuthError::upstream(error.to_string()))?;
    if payload.success == Some(false) {
        return Err(AuthError::upstream(payload.upstream_message(fallback)));
    }
    payload
        .data
        .ok_or_else(|| AuthError::upstream(fallback.to_string()))
}

pub(crate) struct UcloudJsonHeaders<'a> {
    basic_auth: &'a str,
    access_token: &'a str,
}

impl<'a> UcloudJsonHeaders<'a> {
    pub(crate) fn new(basic_auth: &'a str, access_token: &'a str) -> Self {
        Self {
            basic_auth,
            access_token,
        }
    }

    pub(crate) fn into_vec(self) -> Vec<(String, String)> {
        vec![
            ("authorization".to_string(), self.basic_auth.to_string()),
            ("Blade-Auth".to_string(), self.access_token.to_string()),
        ]
    }
}

pub(crate) fn value_to_string(value: serde_json::Value) -> Option<String> {
    match value {
        serde_json::Value::String(value) => Some(value.trim().to_string()),
        serde_json::Value::Number(value) => Some(value.to_string()),
        _ => None,
    }
}
