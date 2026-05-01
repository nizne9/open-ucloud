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

#[cfg(test)]
mod tests {
    use super::*;
    use open_cloud_api::AuthErrorCode;
    use serde::Deserialize;

    #[derive(Debug, Deserialize, Eq, PartialEq)]
    struct Payload {
        value: String,
    }

    fn response(status: u16, body: &str) -> HttpResponse {
        HttpResponse {
            status,
            headers: Vec::new(),
            body: body.as_bytes().to_vec(),
        }
    }

    #[test]
    fn parses_successful_ucloud_envelope_data() {
        let payload: Payload = parse_ucloud_envelope(
            response(200, r#"{"success":true,"data":{"value":"ok"}}"#),
            "fallback",
        )
        .expect("envelope parses");

        assert_eq!(
            payload,
            Payload {
                value: "ok".to_string()
            }
        );
    }

    #[test]
    fn maps_ucloud_failure_message_before_msg() {
        let err = parse_ucloud_envelope::<Payload>(
            response(
                200,
                r#"{"success":false,"message":"message wins","msg":"msg loses"}"#,
            ),
            "fallback",
        )
        .expect_err("failure maps");

        assert_eq!(err.code, AuthErrorCode::UpstreamUnavailable);
        assert_eq!(err.message, "message wins");
    }

    #[test]
    fn maps_ucloud_failure_msg_when_message_is_missing() {
        let err = parse_ucloud_envelope::<Payload>(
            response(200, r#"{"success":false,"msg":"msg wins"}"#),
            "fallback",
        )
        .expect_err("failure maps");

        assert_eq!(err.code, AuthErrorCode::UpstreamUnavailable);
        assert_eq!(err.message, "msg wins");
    }

    #[test]
    fn reports_fallback_when_success_data_is_missing() {
        let err =
            parse_ucloud_envelope::<Payload>(response(200, r#"{"success":true}"#), "fallback")
                .expect_err("missing data maps");

        assert_eq!(err.code, AuthErrorCode::UpstreamUnavailable);
        assert_eq!(err.message, "fallback");
    }

    #[test]
    fn reports_http_status_before_parsing_body() {
        let err = parse_ucloud_envelope::<Payload>(response(503, "not json"), "fallback")
            .expect_err("http status maps");

        assert_eq!(err.code, AuthErrorCode::UpstreamUnavailable);
        assert_eq!(err.message, "fallback HTTP status 503.");
    }

    #[test]
    fn converts_string_and_number_values() {
        assert_eq!(
            value_to_string(serde_json::Value::String("  site-1  ".to_string())).as_deref(),
            Some("site-1")
        );
        assert_eq!(
            value_to_string(serde_json::Value::Number(1001.into())).as_deref(),
            Some("1001")
        );
        assert_eq!(value_to_string(serde_json::Value::Bool(true)), None);
    }

    #[test]
    fn builds_ucloud_json_headers() {
        let headers = UcloudJsonHeaders::new("Basic token", "access-token").into_vec();

        assert_eq!(
            headers,
            vec![
                ("authorization".to_string(), "Basic token".to_string()),
                ("Blade-Auth".to_string(), "access-token".to_string()),
            ]
        );
    }
}
