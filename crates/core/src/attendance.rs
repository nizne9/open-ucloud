use crate::protocol::{parse_ucloud_envelope, value_to_string, UcloudJsonHeaders};
use crate::{AuthError, HttpBody, HttpClient, HttpMethod, HttpRequest, OpenCloudClient};
use open_cloud_api::{AttendanceQrPayload, AuthErrorCode, GoingSite};
use serde::Deserialize;

const SWORD_BASIC_AUTH: &str = "Basic c3dvcmQ6c3dvcmRfc2VjcmV0";
const CHECKWORK_PREFIX: &str = "checkwork|";

impl<C> OpenCloudClient<C>
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
        let mut headers = UcloudJsonHeaders::new(SWORD_BASIC_AUTH, access_token).into_vec();
        headers.push(("content-type".to_string(), "application/json".to_string()));
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Post,
                url: url.to_string(),
                headers,
                body: Some(HttpBody::text("{}")),
            })
            .await?;
        let data: RawGoingSiteList = parse_ucloud_envelope(response, "签到状态加载失败。")?;
        Ok(normalize_going_sites(data))
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

pub fn parse_attendance_qr_payload(value: &str) -> Result<AttendanceQrPayload, AuthError> {
    let payload = value
        .trim()
        .strip_prefix(CHECKWORK_PREFIX)
        .ok_or_else(invalid_attendance_qr_payload)?;
    let mut attendance_id = None;
    let mut site_id = None;
    let mut create_time = None;
    let mut class_lesson_id = None;

    for segment in payload.split('&') {
        let (key, raw_value) = segment
            .split_once('=')
            .ok_or_else(invalid_attendance_qr_payload)?;
        if raw_value.is_empty() {
            return Err(invalid_attendance_qr_payload());
        }
        let slot = match key {
            "id" => &mut attendance_id,
            "siteId" => &mut site_id,
            "createTime" => &mut create_time,
            "classLessonId" => &mut class_lesson_id,
            _ => return Err(invalid_attendance_qr_payload()),
        };
        if slot.replace(raw_value.to_string()).is_some() {
            return Err(invalid_attendance_qr_payload());
        }
    }

    Ok(AttendanceQrPayload {
        attendance_id: attendance_id.ok_or_else(invalid_attendance_qr_payload)?,
        site_id: site_id.ok_or_else(invalid_attendance_qr_payload)?,
        create_time: create_time.ok_or_else(invalid_attendance_qr_payload)?,
        class_lesson_id: class_lesson_id.ok_or_else(invalid_attendance_qr_payload)?,
    })
}

fn invalid_attendance_qr_payload() -> AuthError {
    AuthError::new(AuthErrorCode::InvalidInput, "签到二维码内容无效或不完整。")
}
