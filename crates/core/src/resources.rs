use crate::protocol::{parse_ucloud_envelope, value_to_string, UcloudJsonHeaders};
use crate::{AuthError, HttpClient, HttpMethod, HttpRequest, OpenCloudClient};
use open_cloud_api::{CourseResourceDetail, CourseResourceSummary, CourseResourcesResponse};
use serde::Deserialize;
use std::collections::HashSet;

const PORTAL_BASIC_AUTH: &str = "Basic cG9ydGFsOnBvcnRhbF9zZWNyZXQ=";
const MAX_DOWNLOAD_REDIRECTS: usize = 10;

impl<C> OpenCloudClient<C>
where
    C: HttpClient,
{
    pub async fn get_course_resources(
        &self,
        site_id: &str,
        site_name: &str,
        user_id: &str,
        access_token: &str,
    ) -> Result<CourseResourcesResponse, AuthError> {
        let mut url = url::Url::parse(&self.endpoints.resource_tree_url)
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        url.query_pairs_mut()
            .append_pair("siteId", site_id)
            .append_pair("userId", user_id);
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Post,
                url: url.to_string(),
                headers: portal_json_headers(access_token),
                body: None,
            })
            .await?;
        let data: RawResourceTree =
            parse_ucloud_envelope(response, "课程资料加载失败，请稍后重试。")?;
        let mut resources = Vec::new();
        for node in data.nodes() {
            collect_tree_resources(node, &mut resources);
        }
        Ok(CourseResourcesResponse {
            records: dedupe_resources(resources)
                .into_iter()
                .filter_map(|resource| to_resource_summary(resource, site_id, site_name))
                .collect(),
        })
    }

    pub async fn get_resource_detail(
        &self,
        resource_id: &str,
        site_id: &str,
        site_name: &str,
        access_token: &str,
    ) -> Result<CourseResourceDetail, AuthError> {
        let details = self
            .get_resource_details_by_ids(&[resource_id.to_string()], access_token)
            .await?;
        let resource = details
            .into_iter()
            .find(|detail| raw_resource_id(detail).as_deref() == Some(resource_id))
            .ok_or_else(|| AuthError::upstream("资料详情加载失败，请稍后重试。"))?;
        self.to_resource_detail(resource, site_id, site_name, access_token)
            .await
    }

    pub async fn get_resource_download_url(
        &self,
        resource_id: &str,
        access_token: &str,
    ) -> Result<Option<String>, AuthError> {
        let mut url = url::Url::parse(&self.endpoints.resource_preview_url)
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        url.query_pairs_mut().append_pair("resourceId", resource_id);
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Get,
                url: url.to_string(),
                headers: portal_json_headers(access_token),
                body: None,
            })
            .await?;
        if !(200..300).contains(&response.status) {
            return Ok(None);
        }
        let payload: UcloudPreviewEnvelope = serde_json::from_slice(&response.body)
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        if payload.success == Some(false) {
            return Ok(None);
        }
        Ok(payload.data.and_then(|data| data.preview_url))
    }

    pub async fn download_url_bytes(&self, url: &str) -> Result<Vec<u8>, AuthError> {
        let mut next_url = url.to_string();
        for _ in 0..=MAX_DOWNLOAD_REDIRECTS {
            let response = self
                .http
                .send(HttpRequest {
                    method: HttpMethod::Get,
                    url: next_url.clone(),
                    headers: Vec::new(),
                    body: None,
                })
                .await?;
            if (200..300).contains(&response.status) {
                return Ok(response.body);
            }
            if is_download_redirect(response.status) {
                let location = response
                    .header("Location")
                    .ok_or_else(|| AuthError::upstream("资料下载重定向缺少 Location。"))?
                    .to_string();
                next_url = resolve_download_redirect(&next_url, &location)?;
                continue;
            }
            return Err(AuthError::upstream(format!(
                "资料下载失败。 HTTP status {}.",
                response.status
            )));
        }
        Err(AuthError::upstream("资料下载重定向次数过多。"))
    }

    pub(crate) async fn get_resource_details_by_ids(
        &self,
        resource_ids: &[String],
        access_token: &str,
    ) -> Result<Vec<RawResourceDetail>, AuthError> {
        let normalized = resource_ids
            .iter()
            .map(|id| id.trim())
            .filter(|id| !id.is_empty())
            .collect::<Vec<_>>();
        if normalized.is_empty() {
            return Ok(Vec::new());
        }
        let mut url = url::Url::parse(&self.endpoints.resource_by_id_url)
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        url.query_pairs_mut()
            .append_pair("resourceIds", &normalized.join(","));
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Get,
                url: url.to_string(),
                headers: portal_json_headers(access_token),
                body: None,
            })
            .await?;
        parse_ucloud_envelope(response, "课程资料加载失败，请稍后重试。")
    }

    pub(crate) async fn to_resource_detail(
        &self,
        resource: RawResourceDetail,
        site_id: &str,
        site_name: &str,
        access_token: &str,
    ) -> Result<CourseResourceDetail, AuthError> {
        let resource_id = raw_resource_id(&resource).unwrap_or_default();
        let download_url = if resource_id.is_empty() {
            None
        } else {
            self.get_resource_download_url(&resource_id, access_token)
                .await?
        };
        Ok(CourseResourceDetail {
            description: pick_string([
                resource.description,
                resource.introduction,
                resource.remark,
            ]),
            download_url,
            ext: pick_string([resource.ext]),
            name: pick_string([resource.name, resource.file_name, Some(resource_id.clone())])
                .unwrap_or_default(),
            resource_id,
            site_id: site_id.to_string(),
            site_name: site_name.to_string(),
            size_bytes: pick_u64([resource.file_size, resource.size]),
            updated_at: pick_string([resource.update_time, resource.create_time])
                .unwrap_or_default(),
        })
    }
}

fn is_download_redirect(status: u16) -> bool {
    matches!(status, 301 | 302 | 303 | 307 | 308)
}

fn resolve_download_redirect(current_url: &str, location: &str) -> Result<String, AuthError> {
    url::Url::parse(current_url)
        .and_then(|base| base.join(location))
        .map(|url| url.to_string())
        .map_err(|error| AuthError::upstream(error.to_string()))
}

pub(crate) fn portal_json_headers(access_token: &str) -> Vec<(String, String)> {
    let mut headers = UcloudJsonHeaders::new(PORTAL_BASIC_AUTH, access_token).into_vec();
    headers.push((
        "Referer".to_string(),
        "https://ucloud.bupt.edu.cn/".to_string(),
    ));
    headers.push(("tenant-id".to_string(), "000000".to_string()));
    headers
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(untagged)]
enum RawResourceTree {
    Array(Vec<RawResourceTreeNode>),
    One(Box<RawResourceTreeNode>),
}

impl RawResourceTree {
    fn nodes(&self) -> Vec<&RawResourceTreeNode> {
        match self {
            Self::Array(nodes) => nodes.iter().collect(),
            Self::One(node) => vec![node.as_ref()],
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawResourceTreeNode {
    attachment_v_os: Option<Vec<RawResourceAttachment>>,
    children: Option<Vec<RawResourceTreeNode>>,
    resource: Option<RawResourceDetail>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
struct RawResourceAttachment {
    resource: Option<RawResourceDetail>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RawResourceDetail {
    pub(crate) create_time: Option<String>,
    pub(crate) description: Option<String>,
    pub(crate) ext: Option<String>,
    pub(crate) file_name: Option<String>,
    pub(crate) file_size: Option<serde_json::Value>,
    pub(crate) id: Option<serde_json::Value>,
    pub(crate) introduction: Option<String>,
    pub(crate) name: Option<String>,
    pub(crate) remark: Option<String>,
    pub(crate) resource_id: Option<serde_json::Value>,
    pub(crate) size: Option<serde_json::Value>,
    pub(crate) storage_id: Option<String>,
    pub(crate) update_time: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawPreviewUrl {
    preview_url: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
struct UcloudPreviewEnvelope {
    data: Option<RawPreviewUrl>,
    success: Option<bool>,
}

fn collect_tree_resources(node: &RawResourceTreeNode, bucket: &mut Vec<RawResourceDetail>) {
    if let Some(resource) = &node.resource {
        bucket.push(resource.clone());
    }
    for attachment in node.attachment_v_os.as_deref().unwrap_or_default() {
        if let Some(resource) = &attachment.resource {
            bucket.push(resource.clone());
        }
    }
    for child in node.children.as_deref().unwrap_or_default() {
        collect_tree_resources(child, bucket);
    }
}

fn dedupe_resources(resources: Vec<RawResourceDetail>) -> Vec<RawResourceDetail> {
    let mut seen = HashSet::new();
    resources
        .into_iter()
        .filter(|resource| {
            let Some(resource_id) = raw_resource_id(resource) else {
                return false;
            };
            seen.insert(resource_id)
        })
        .collect()
}

fn to_resource_summary(
    resource: RawResourceDetail,
    site_id: &str,
    site_name: &str,
) -> Option<CourseResourceSummary> {
    let resource_id = raw_resource_id(&resource)?;
    Some(CourseResourceSummary {
        ext: pick_string([resource.ext]),
        name: pick_string([resource.name, resource.file_name, Some(resource_id.clone())])
            .unwrap_or_default(),
        resource_id,
        site_id: site_id.to_string(),
        site_name: site_name.to_string(),
        size_bytes: pick_u64([resource.file_size, resource.size]),
        updated_at: pick_string([resource.update_time, resource.create_time]).unwrap_or_default(),
    })
}

pub(crate) fn raw_resource_id(resource: &RawResourceDetail) -> Option<String> {
    resource
        .resource_id
        .clone()
        .and_then(value_to_string)
        .or_else(|| resource.id.clone().and_then(value_to_string))
        .filter(|value| !value.is_empty())
}

fn pick_string<const N: usize>(values: [Option<String>; N]) -> Option<String> {
    values
        .into_iter()
        .flatten()
        .map(|value| value.trim().to_string())
        .find(|value| !value.is_empty())
}

fn pick_u64<const N: usize>(values: [Option<serde_json::Value>; N]) -> Option<u64> {
    values.into_iter().flatten().find_map(|value| match value {
        serde_json::Value::Number(number) => number.as_u64(),
        serde_json::Value::String(value) => value.trim().parse::<u64>().ok(),
        _ => None,
    })
}
