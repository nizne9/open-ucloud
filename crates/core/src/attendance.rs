use crate::{AuthClient, AuthError, HttpClient, HttpMethod, HttpRequest};
use open_cloud_api::GoingSite;
use serde::Deserialize;

const SWORD_BASIC_AUTH: &str = "Basic c3dvcmQ6c3dvcmRfc2VjcmV0";

impl<C> AuthClient<C>
where
    C: HttpClient,
{
    pub async fn get_going_sites(
        &self,
        site_ids: &[String],
        access_token: &str,
    ) -> Result<Vec<GoingSite>, AuthError> {
        if site_ids.is_empty() {
            return Ok(Vec::new());
        }
        let mut url = url::Url::parse(&self.endpoints.going_sites_url)
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        url.query_pairs_mut()
            .append_pair("siteIds", &site_ids.join(","));
        let mut headers = ucloud_json_headers(SWORD_BASIC_AUTH, access_token);
        headers.push(("content-type".to_string(), "application/json".to_string()));
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Post,
                url: url.to_string(),
                headers,
                body: Some("{}".to_string()),
            })
            .await?;
        let data: RawGoingSiteList = parse_ucloud_envelope(response, "签到状态加载失败。")?;
        Ok(normalize_going_sites(data))
    }
}

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

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(untagged)]
enum RawGoingSiteList {
    Records { records: Option<Vec<RawGoingSite>> },
    Array(Vec<RawGoingSite>),
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawGoingSite {
    group_id: Option<serde_json::Value>,
    site_id: Option<serde_json::Value>,
}

fn normalize_going_sites(payload: RawGoingSiteList) -> Vec<GoingSite> {
    let records = match payload {
        RawGoingSiteList::Records { records } => records.unwrap_or_default(),
        RawGoingSiteList::Array(records) => records,
    };
    records
        .into_iter()
        .filter_map(|record| {
            let group_id = value_to_string(record.group_id?)?;
            let site_id = value_to_string(record.site_id?)?;
            if group_id.is_empty() || site_id.is_empty() {
                return None;
            }
            Some(GoingSite { group_id, site_id })
        })
        .collect()
}

fn parse_ucloud_envelope<T>(response: crate::HttpResponse, fallback: &str) -> Result<T, AuthError>
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

fn ucloud_json_headers(basic_auth: &str, access_token: &str) -> Vec<(String, String)> {
    vec![
        ("authorization".to_string(), basic_auth.to_string()),
        ("Blade-Auth".to_string(), access_token.to_string()),
    ]
}

fn value_to_string(value: serde_json::Value) -> Option<String> {
    match value {
        serde_json::Value::String(value) => Some(value.trim().to_string()),
        serde_json::Value::Number(value) => Some(value.to_string()),
        _ => None,
    }
}
