use crate::{AuthError, HttpResponse};
use open_ucloud_api::AuthErrorCode;
use serde::Deserialize;

pub(crate) const PORTAL_BASIC_AUTH: &str = "Basic cG9ydGFsOnBvcnRhbF9zZWNyZXQ=";
pub(crate) const SWORD_BASIC_AUTH: &str = "Basic c3dvcmQ6c3dvcmRfc2VjcmV0";

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
            .filter(|message| !message.trim().is_empty())
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
    parse_ucloud_optional_envelope(response, fallback)?
        .ok_or_else(|| AuthError::upstream(fallback.to_string()))
}

pub(crate) fn parse_ucloud_optional_envelope<T>(
    response: HttpResponse,
    fallback: &str,
) -> Result<Option<T>, AuthError>
where
    T: for<'de> Deserialize<'de>,
{
    let payload: UcloudEnvelope<T> = parse_ucloud_response(response, fallback)?;
    if payload.success == Some(false) {
        return Err(AuthError::upstream(payload.upstream_message(fallback)));
    }
    Ok(payload.data)
}

pub(crate) fn parse_ucloud_empty_success(
    response: HttpResponse,
    fallback: &str,
) -> Result<(), AuthError> {
    let payload: UcloudEnvelope<serde_json::Value> = parse_ucloud_response(response, fallback)?;
    if payload.success == Some(true) {
        return Ok(());
    }
    Err(AuthError::upstream(payload.upstream_message(fallback)))
}

fn parse_ucloud_response<T>(
    response: HttpResponse,
    fallback: &str,
) -> Result<UcloudEnvelope<T>, AuthError>
where
    T: for<'de> Deserialize<'de>,
{
    if !(200..300).contains(&response.status) {
        return Err(http_status_error(
            response.status,
            response.header("retry-after"),
            fallback,
        ));
    }
    serde_json::from_slice(&response.body).map_err(|error| AuthError::upstream(error.to_string()))
}

pub(crate) fn http_status_error(
    status: u16,
    retry_after: Option<&str>,
    fallback: &str,
) -> AuthError {
    let message = format!("{fallback} HTTP status {status}.");
    match status {
        401 | 403 => AuthError::new(AuthErrorCode::SessionExpired, message),
        404 => AuthError::new(AuthErrorCode::NotFound, message),
        429 => AuthError::new(AuthErrorCode::RateLimited, message)
            .with_retry_after(retry_after.and_then(|value| value.trim().parse().ok())),
        _ => AuthError::upstream(message),
    }
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

    pub(crate) fn into_json_post_vec(self) -> Vec<(String, String)> {
        let mut headers = self.into_vec();
        headers.push(("content-type".to_string(), "application/json".to_string()));
        headers
    }
}

pub(crate) fn portal_json_headers(access_token: &str, referer: &str) -> Vec<(String, String)> {
    let mut headers = UcloudJsonHeaders::new(PORTAL_BASIC_AUTH, access_token).into_vec();
    headers.push(("Referer".to_string(), referer.to_string()));
    headers.push(("tenant-id".to_string(), "000000".to_string()));
    headers
}

pub(crate) fn portal_json_utf8_headers(access_token: &str, referer: &str) -> Vec<(String, String)> {
    let mut headers = portal_json_headers(access_token, referer);
    headers.push((
        "Content-Type".to_string(),
        "application/json;charset=UTF-8".to_string(),
    ));
    headers
}

fn normalize_non_empty(value: String) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else if trimmed.len() == value.len() {
        Some(value)
    } else {
        Some(trimmed.to_string())
    }
}

pub(crate) fn value_to_string(value: serde_json::Value) -> Option<String> {
    match value {
        serde_json::Value::String(value) => normalize_non_empty(value),
        serde_json::Value::Number(value) => Some(value.to_string()),
        _ => None,
    }
}

pub(crate) fn pick_string<const N: usize>(values: [Option<String>; N]) -> Option<String> {
    values.into_iter().flatten().find_map(normalize_non_empty)
}

#[cfg(test)]
mod tests {
    use super::*;
    use open_ucloud_api::AuthErrorCode;
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
    fn maps_ucloud_failure_msg_when_message_is_blank() {
        let err = parse_ucloud_envelope::<Payload>(
            response(200, r#"{"success":false,"message":"  ","msg":"msg wins"}"#),
            "fallback",
        )
        .expect_err("blank message falls back to msg");

        assert_eq!(err.message, "msg wins");
    }

    #[test]
    fn optional_envelope_allows_missing_data() {
        let payload: Option<Payload> =
            parse_ucloud_optional_envelope(response(200, r#"{"success":true}"#), "fallback")
                .expect("missing data is allowed");

        assert_eq!(payload, None);
    }

    #[test]
    fn empty_success_requires_an_explicit_true_flag() {
        parse_ucloud_empty_success(response(200, r#"{"success":true}"#), "fallback")
            .expect("explicit success passes");

        let missing = parse_ucloud_empty_success(response(200, r#"{"data":{}}"#), "fallback")
            .expect_err("missing success flag fails");
        assert_eq!(missing.code, AuthErrorCode::UpstreamUnavailable);
        assert_eq!(missing.message, "fallback");

        let failed = parse_ucloud_empty_success(
            response(200, r#"{"success":false,"msg":"upstream says no"}"#),
            "fallback",
        )
        .expect_err("false success flag fails");
        assert_eq!(failed.message, "upstream says no");
    }

    #[test]
    fn empty_success_maps_http_status_semantics() {
        let err = parse_ucloud_empty_success(response(401, "not json"), "fallback")
            .expect_err("401 maps to session expired");

        assert_eq!(err.code, AuthErrorCode::SessionExpired);
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
    fn maps_rate_limit_status_and_retry_after() {
        let err = parse_ucloud_envelope::<Payload>(
            response_with_headers(429, &[("Retry-After", "30")], "not json"),
            "fallback",
        )
        .expect_err("rate limit maps");

        assert_eq!(err.code, AuthErrorCode::RateLimited);
        assert_eq!(err.retry_after_seconds, Some(30));
    }

    #[test]
    fn maps_session_and_not_found_statuses() {
        let session = parse_ucloud_envelope::<Payload>(response(401, ""), "fallback")
            .expect_err("session status maps");
        let missing = parse_ucloud_envelope::<Payload>(response(404, ""), "fallback")
            .expect_err("not found maps");

        assert_eq!(session.code, AuthErrorCode::SessionExpired);
        assert_eq!(missing.code, AuthErrorCode::NotFound);
    }

    #[test]
    fn converts_string_and_number_values() {
        assert_eq!(
            value_to_string(serde_json::Value::String("  site-1  ".to_string())).as_deref(),
            Some("site-1")
        );
        assert_eq!(
            value_to_string(serde_json::Value::String("   ".to_string())),
            None
        );
        assert_eq!(
            value_to_string(serde_json::Value::Number(1001.into())).as_deref(),
            Some("1001")
        );
        assert_eq!(value_to_string(serde_json::Value::Bool(true)), None);
    }

    #[test]
    fn picks_first_non_empty_string() {
        assert_eq!(
            pick_string([
                None,
                Some("".to_string()),
                Some("   ".to_string()),
                Some("  found  ".to_string())
            ]),
            Some("found".to_string())
        );
        assert_eq!(pick_string([None, Some("   ".to_string())]), None);
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

    #[test]
    fn builds_portal_json_headers() {
        let headers = portal_json_headers("tok123", "https://ucloud.example/");
        assert!(headers.contains(&("authorization".to_string(), PORTAL_BASIC_AUTH.to_string())));
        assert!(headers.contains(&("Blade-Auth".to_string(), "tok123".to_string())));
        assert!(headers.contains(&("Referer".to_string(), "https://ucloud.example/".to_string())));
        assert!(headers.contains(&("tenant-id".to_string(), "000000".to_string())));

        let utf8_headers = portal_json_utf8_headers("tok123", "https://ucloud.example/");
        assert!(utf8_headers.contains(&(
            "Content-Type".to_string(),
            "application/json;charset=UTF-8".to_string()
        )));
    }
}
