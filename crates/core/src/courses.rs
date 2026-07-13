use crate::protocol::{parse_ucloud_envelope, value_to_string, UcloudJsonHeaders};
use crate::{AuthError, HttpClient, HttpMethod, HttpRequest, OpenCloudClient};
use open_cloud_api::{AuthErrorCode, CourseDetailResponse, CourseSite, GoingSite};
use serde::Deserialize;
use std::collections::HashSet;

const SWORD_BASIC_AUTH: &str = "Basic c3dvcmQ6c3dvcmRfc2VjcmV0";
const COURSE_PAGE_SIZE: u32 = 100;
const MAX_COURSE_PAGES: u32 = 100;

impl<C> OpenCloudClient<C>
where
    C: HttpClient,
{
    pub async fn get_student_courses(
        &self,
        user_id: &str,
        access_token: &str,
    ) -> Result<Vec<CourseSite>, AuthError> {
        let mut courses = Vec::new();
        let mut seen_ids = HashSet::new();

        for current in 1..=MAX_COURSE_PAGES {
            let mut url = url::Url::parse(&self.endpoints.course_sites_url)
                .map_err(|error| AuthError::upstream(error.to_string()))?;
            url.query_pairs_mut()
                .append_pair("current", &current.to_string())
                .append_pair("siteRoleCode", "2")
                .append_pair("size", &COURSE_PAGE_SIZE.to_string())
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
            let records = data.into_records();
            let record_count = records.len();
            let previous_count = courses.len();
            courses.extend(
                normalize_course_sites(records)
                    .into_iter()
                    .filter(|course| seen_ids.insert(course.id.clone())),
            );

            if record_count < COURSE_PAGE_SIZE as usize || courses.len() == previous_count {
                break;
            }
            if current == MAX_COURSE_PAGES {
                return Err(AuthError::upstream(
                    "课程数量超过客户端分页安全上限，请缩小查询范围。",
                ));
            }
        }

        Ok(courses)
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

impl RawCourseSiteList {
    fn into_records(self) -> Vec<RawCourseSite> {
        match self {
            Self::Records { records } => records.unwrap_or_default(),
            Self::Array(records) => records,
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawCourseSite {
    id: Option<serde_json::Value>,
    site_name: Option<String>,
}

fn normalize_course_sites(records: Vec<RawCourseSite>) -> Vec<CourseSite> {
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
