use crate::protocol::{parse_ucloud_envelope, value_to_string, UcloudJsonHeaders};
use crate::{AuthClient, AuthError, HttpClient, HttpMethod, HttpRequest};
use open_cloud_api::{AuthErrorCode, CourseDetailResponse, CourseSite, GoingSite};
use serde::Deserialize;

const SWORD_BASIC_AUTH: &str = "Basic c3dvcmQ6c3dvcmRfc2VjcmV0";

impl<C> AuthClient<C>
where
    C: HttpClient,
{
    pub async fn get_student_courses(
        &self,
        user_id: &str,
        access_token: &str,
    ) -> Result<Vec<CourseSite>, AuthError> {
        let mut url = url::Url::parse(&self.endpoints.course_sites_url)
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        url.query_pairs_mut()
            .append_pair("current", "1")
            .append_pair("siteRoleCode", "2")
            .append_pair("size", "9999")
            .append_pair("userId", user_id);
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Get,
                url: url.to_string(),
                headers: UcloudJsonHeaders::new(SWORD_BASIC_AUTH, access_token).into_vec(),
                body: None,
            })
            .await?;
        let data: RawCourseSiteList = parse_ucloud_envelope(response, "课程加载失败。")?;
        Ok(normalize_course_sites(data))
    }
}

pub fn resolve_course_detail(
    courses: &[CourseSite],
    going_sites: &[GoingSite],
    site_id: &str,
) -> Result<CourseDetailResponse, AuthError> {
    let course = courses
        .iter()
        .find(|course| course.id == site_id)
        .cloned()
        .ok_or_else(|| {
            AuthError::new(
                AuthErrorCode::UnknownAuthError,
                format!("未找到课程：{site_id}。"),
            )
        })?;
    let going_site = going_sites
        .iter()
        .find(|site| site.site_id == site_id)
        .cloned();
    Ok(CourseDetailResponse { course, going_site })
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(untagged)]
enum RawCourseSiteList {
    Records { records: Option<Vec<RawCourseSite>> },
    Array(Vec<RawCourseSite>),
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawCourseSite {
    id: Option<serde_json::Value>,
    site_name: Option<String>,
}

fn normalize_course_sites(payload: RawCourseSiteList) -> Vec<CourseSite> {
    let records = match payload {
        RawCourseSiteList::Records { records } => records.unwrap_or_default(),
        RawCourseSiteList::Array(records) => records,
    };
    records
        .into_iter()
        .filter_map(|record| {
            let id = value_to_string(record.id?)?;
            let site_name = record.site_name.unwrap_or_default().trim().to_string();
            if id.is_empty() || site_name.is_empty() {
                return None;
            }
            Some(CourseSite { id, site_name })
        })
        .collect()
}
