use crate::protocol::{
    parse_ucloud_empty_success, parse_ucloud_envelope, value_to_string, UcloudJsonHeaders,
};
use crate::{AuthError, HttpBody, HttpClient, HttpMethod, HttpRequest, OpenUcloudClient};
use open_ucloud_api::{
    AttendanceQrPayload, AttendanceQrResponse, AttendanceSignResponse, AuthErrorCode, GoingSite,
};
use serde::Deserialize;

const SWORD_BASIC_AUTH: &str = "Basic c3dvcmQ6c3dvcmRfc2VjcmV0";
const CHECKWORK_PREFIX: &str = "checkwork|";

impl<C> OpenUcloudClient<C>
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
        let headers = UcloudJsonHeaders::new(SWORD_BASIC_AUTH, access_token).into_json_post_vec();
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

    /// Look up the attendance id for an in-progress course session.
    pub async fn get_attendance_basic_id(
        &self,
        site_id: &str,
        group_id: &str,
        access_token: &str,
    ) -> Result<String, AuthError> {
        if site_id.is_empty() || group_id.is_empty() {
            return Err(invalid_attendance_input("签到课程信息不完整。"));
        }
        let headers = UcloudJsonHeaders::new(SWORD_BASIC_AUTH, access_token).into_json_post_vec();
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Post,
                url: self.endpoints.attendance_basic_url.clone(),
                headers,
                body: Some(HttpBody::text(
                    serde_json::json!({ "groupId": group_id, "siteId": site_id }).to_string(),
                )),
            })
            .await?;
        let basic: RawCheckoutBasic = parse_ucloud_envelope(response, "签到信息加载失败。")?;
        let attendance_id = value_to_string(basic.attendance_basic_info.id)
            .filter(|value| !value.is_empty())
            .ok_or_else(attendance_not_found)?;
        Ok(attendance_id)
    }

    /// Fetch the clock/encryption parameter required by the sign payload.
    pub async fn get_attendance_clock_param(
        &self,
        access_token: &str,
    ) -> Result<String, AuthError> {
        let headers = UcloudJsonHeaders::new(SWORD_BASIC_AUTH, access_token).into_vec();
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Get,
                url: self.endpoints.clock_url.clone(),
                headers,
                body: None,
            })
            .await?;
        let clock: RawClockResponse = parse_ucloud_envelope(response, "签到时间参数加载失败。")?;
        value_to_string(clock.data)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| AuthError::upstream("签到时间参数为空。"))
    }

    /// Submit attendance for a user-selected course with an active session.
    ///
    /// The platform reuses the group id as the sign payload's `classLessonId`
    /// (per the 2026-05-06 attendance design); verify against a live session.
    pub async fn sign_attendance(
        &self,
        site_id: &str,
        group_id: &str,
        user_id: &str,
        access_token: &str,
    ) -> Result<AttendanceSignResponse, AuthError> {
        if site_id.is_empty() || group_id.is_empty() || user_id.is_empty() {
            return Err(invalid_attendance_input("签到课程信息不完整。"));
        }
        // basic and clock are independent; fetch them concurrently to save a round trip.
        let (attendance_id, qr_code_create_time) = tokio::join!(
            self.get_attendance_basic_id(site_id, group_id, access_token),
            self.get_attendance_clock_param(access_token),
        );
        let body = sign_request_body(
            &attendance_id?,
            group_id,
            site_id,
            user_id,
            &qr_code_create_time?,
        );
        let headers = UcloudJsonHeaders::new(SWORD_BASIC_AUTH, access_token).into_json_post_vec();
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Post,
                url: self.endpoints.attendance_sign_url.clone(),
                headers,
                body: Some(HttpBody::text(body)),
            })
            .await?;
        parse_ucloud_empty_success(response, "签到提交失败。")?;
        Ok(AttendanceSignResponse {
            ok: true,
            site_id: site_id.to_string(),
            group_id: group_id.to_string(),
        })
    }

    /// Resolve the fields needed to render an in-progress attendance QR code.
    pub async fn prepare_attendance_qr(
        &self,
        site_id: &str,
        group_id: &str,
        access_token: &str,
    ) -> Result<AttendanceQrResponse, AuthError> {
        if site_id.is_empty() || group_id.is_empty() {
            return Err(invalid_attendance_input("签到课程信息不完整。"));
        }
        let (attendance_id, create_time) = tokio::join!(
            self.get_attendance_basic_id(site_id, group_id, access_token),
            self.get_attendance_clock_param(access_token),
        );
        Ok(AttendanceQrResponse {
            attendance_id: attendance_id?,
            site_id: site_id.to_string(),
            group_id: group_id.to_string(),
            create_time: create_time?,
        })
    }
}

fn sign_request_body(
    attendance_id: &str,
    class_lesson_id: &str,
    site_id: &str,
    user_id: &str,
    qr_code_create_time: &str,
) -> String {
    serde_json::json!({
        "attendanceDetailInfo": {
            "attendanceId": attendance_id,
            "classLessonId": class_lesson_id,
            "siteId": site_id,
            "userId": user_id,
        },
        "qrCodeCreateTime": qr_code_create_time,
    })
    .to_string()
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

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawCheckoutBasic {
    attendance_basic_info: RawAttendanceBasicInfo,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawAttendanceBasicInfo {
    id: serde_json::Value,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
struct RawClockResponse {
    data: serde_json::Value,
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

fn invalid_attendance_input(message: &str) -> AuthError {
    AuthError::new(AuthErrorCode::InvalidInput, message)
}

fn attendance_not_found() -> AuthError {
    AuthError::new(AuthErrorCode::NotFound, "当前没有进行中的签到。")
}

fn invalid_attendance_qr_payload() -> AuthError {
    AuthError::new(AuthErrorCode::InvalidInput, "签到二维码内容无效或不完整。")
}
