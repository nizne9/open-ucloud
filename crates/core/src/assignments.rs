use crate::protocol::{parse_ucloud_envelope, value_to_string};
use crate::resources::{portal_json_headers, raw_resource_id, RawResourceDetail};
use crate::{AuthError, HttpBody, HttpClient, HttpMethod, HttpRequest, OpenCloudClient};
use futures_util::stream::{self, StreamExt};
use open_cloud_api::{
    AssignmentDetailResponse, AssignmentListResponse, AssignmentResource, AssignmentStatus,
    AssignmentSubmitResponse, AssignmentSummary, AssignmentUploadResponse, AuthErrorCode,
};
use serde::Deserialize;
use std::collections::HashSet;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::Path;

const PORTAL_BASIC_AUTH: &str = "Basic cG9ydGFsOnBvcnRhbF9zZWNyZXQ=";
const MAX_ASSIGNMENT_UPLOAD_BYTES: usize = 25 * 1024 * 1024;
const ASSIGNMENT_PAGE_SIZE: u32 = 100;
const MAX_ASSIGNMENT_PAGES: u32 = 100;
const PREVIEW_URL_CONCURRENCY: usize = 4;
const BLOCKED_UPLOAD_EXTENSIONS: &[&str] = &[
    "ade", "adp", "apk", "app", "bat", "bin", "cmd", "com", "cpl", "dll", "dmg", "exe", "hta",
    "ins", "iso", "jar", "js", "jse", "lnk", "msc", "msi", "msp", "mst", "pif", "scr", "sh", "vb",
    "vbe", "vbs", "ws", "wsc", "wsf", "wsh",
];

impl<C> OpenCloudClient<C>
where
    C: HttpClient,
{
    pub async fn get_course_assignments(
        &self,
        site_id: &str,
        site_name: &str,
        access_token: &str,
        keyword: &str,
    ) -> Result<AssignmentListResponse, AuthError> {
        let mut assignments = Vec::new();
        let mut seen_ids = HashSet::new();

        for current in 1..=MAX_ASSIGNMENT_PAGES {
            let body = serde_json::json!({
                "current": current,
                "keyword": keyword,
                "siteId": site_id,
                "size": ASSIGNMENT_PAGE_SIZE
            });
            let response = self
                .http
                .send(HttpRequest {
                    method: HttpMethod::Post,
                    url: self.endpoints.assignment_list_url.clone(),
                    headers: json_headers(access_token),
                    body: Some(HttpBody::text(body.to_string())),
                })
                .await?;
            let data: RawAssignmentRecords =
                parse_ucloud_envelope(response, "课程作业加载失败，请稍后重试。")?;
            let records = data.records.unwrap_or_default();
            let record_count = records.len();
            let previous_count = assignments.len();
            assignments.extend(
                records
                    .into_iter()
                    .filter_map(|record| {
                        to_assignment_summary(record, "course", site_id, site_name)
                    })
                    .filter(|assignment| seen_ids.insert(assignment.id.clone())),
            );

            if record_count < ASSIGNMENT_PAGE_SIZE as usize || assignments.len() == previous_count {
                break;
            }
            if current == MAX_ASSIGNMENT_PAGES {
                return Err(AuthError::upstream(
                    "作业数量超过客户端分页安全上限，请使用关键词缩小查询范围。",
                ));
            }
        }

        Ok(AssignmentListResponse {
            records: assignments,
        })
    }

    pub async fn get_undone_assignments(
        &self,
        user_id: &str,
        access_token: &str,
    ) -> Result<AssignmentListResponse, AuthError> {
        let mut url = url::Url::parse(&self.endpoints.assignment_undone_url)
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        url.query_pairs_mut().append_pair("userId", user_id);
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Get,
                url: url.to_string(),
                headers: json_headers(access_token),
                body: None,
            })
            .await?;
        let data: RawUndoneList =
            parse_ucloud_envelope(response, "未完成作业加载失败，请稍后重试。")?;
        Ok(AssignmentListResponse {
            records: data
                .undone_list
                .unwrap_or_default()
                .into_iter()
                .filter(|item| item.kind == Some(3))
                .filter_map(|item| {
                    to_assignment_summary(
                        RawAssignmentSummary {
                            assignment_end_time: item.end_time,
                            assignment_title: item.activity_name,
                            id: item.activity_id,
                            site_id: item.site_id,
                            site_name: item.site_name,
                            ..RawAssignmentSummary::default()
                        },
                        "undone",
                        "",
                        "",
                    )
                })
                .collect(),
        })
    }

    pub async fn get_assignment_detail(
        &self,
        assignment_id: &str,
        access_token: &str,
    ) -> Result<AssignmentDetailResponse, AuthError> {
        let mut url = url::Url::parse(&self.endpoints.assignment_detail_url)
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        url.query_pairs_mut()
            .append_pair("assignmentId", assignment_id);
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Get,
                url: url.to_string(),
                headers: json_headers(access_token),
                body: None,
            })
            .await?;
        let detail: RawAssignmentDetail =
            parse_ucloud_envelope(response, "作业详情加载失败，请稍后重试。")?;
        let submitted_source = first_non_empty_resource_list([
            detail.submit_attachment_list.clone(),
            detail.student_attachment_list.clone(),
            detail.student_resource.clone(),
        ]);
        let teacher_resources = self
            .assignment_resources_from_refs(
                detail.assignment_resource.clone().unwrap_or_default(),
                access_token,
            )
            .await?;
        let submitted_attachments = self
            .assignment_resources_from_details(submitted_source, access_token)
            .await?;
        let summary = detail.summary();
        Ok(AssignmentDetailResponse {
            class_name: pick_string([detail.class_name.clone()]).unwrap_or_default(),
            comment: pick_string([detail.assignment_comment.clone()]).unwrap_or_default(),
            content: pick_string([detail.assignment_content.clone()]).unwrap_or_default(),
            end_time: pick_string([detail.assignment_end_time.clone(), detail.end_time.clone()])
                .unwrap_or_default(),
            id: value_to_string_opt(detail.id.clone()).unwrap_or_else(|| assignment_id.to_string()),
            is_overtime_commit: detail.is_overtime_commit == Some(1),
            score: score_value(detail.assignment_score.as_ref()),
            site_id: value_to_string_opt(detail.site_id.clone()).unwrap_or_default(),
            site_name: pick_string([detail.site_name.clone()]).unwrap_or_default(),
            start_time: pick_string([
                detail.assignment_begin_time.clone(),
                detail.start_time.clone(),
            ])
            .unwrap_or_default(),
            status: resolve_assignment_status(&summary),
            submitted_at: pick_string([detail.commit_time.clone(), detail.submit_time.clone()])
                .unwrap_or_default(),
            submitted_attachments,
            submitted_content: pick_string([
                detail.student_commit_content.clone(),
                detail.assignment_submit_content.clone(),
                detail.assignment_answer.clone(),
                detail.commit_content.clone(),
            ])
            .unwrap_or_default(),
            teacher_resources,
            title: pick_string([
                detail.assignment_title.clone(),
                detail.title.clone(),
                value_to_string_opt(detail.id.clone()),
            ])
            .unwrap_or_default(),
        })
    }

    pub async fn submit_assignment(
        &self,
        assignment_id: &str,
        user_id: &str,
        assignment_content: &str,
        attachment_ids: &[String],
        access_token: &str,
    ) -> Result<AssignmentSubmitResponse, AuthError> {
        let attachments = attachment_ids
            .iter()
            .map(|id| id.trim().to_string())
            .filter(|id| !id.is_empty())
            .collect::<Vec<_>>();
        if assignment_content.trim().is_empty() && attachments.is_empty() {
            return Err(AuthError::new(
                AuthErrorCode::InvalidInput,
                "请先填写作业内容或上传附件。",
            ));
        }
        let body = serde_json::json!({
            "assignmentContent": assignment_content,
            "assignmentId": assignment_id,
            "assignmentType": 0,
            "attachmentIds": attachments,
            "commitId": "",
            "groupId": "",
            "userId": user_id
        });
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Post,
                url: self.endpoints.assignment_submit_url.clone(),
                headers: json_headers(access_token),
                body: Some(HttpBody::text(body.to_string())),
            })
            .await?;
        parse_empty_success(response, "作业提交失败，请稍后重试。")?;
        Ok(AssignmentSubmitResponse { ok: true })
    }

    pub async fn upload_assignment_file(
        &self,
        assignment: &AssignmentDetailResponse,
        file_name: &str,
        bytes: &[u8],
        user_id: &str,
        access_token: &str,
    ) -> Result<AssignmentUploadResponse, AuthError> {
        validate_assignment_upload(file_name, bytes)?;
        let (content_type, body) = multipart_upload_body(file_name, bytes, user_id);
        let response = self
            .http
            .send(HttpRequest {
                method: HttpMethod::Post,
                url: self.endpoints.assignment_upload_url.clone(),
                headers: vec![
                    ("authorization".to_string(), PORTAL_BASIC_AUTH.to_string()),
                    ("Blade-Auth".to_string(), access_token.to_string()),
                    ("content-type".to_string(), content_type),
                ],
                body: Some(HttpBody::bytes(body)),
            })
            .await?;
        let resource_id: String = parse_ucloud_envelope(response, "附件上传失败，请稍后重试。")?;
        let preview_url = self
            .get_resource_download_url(&resource_id, access_token)
            .await?;
        Ok(AssignmentUploadResponse {
            assignment_id: assignment.id.clone(),
            file_name: file_name.to_string(),
            preview_url,
            resource_id,
            site_id: assignment.site_id.clone(),
            site_name: assignment.site_name.clone(),
        })
    }

    pub async fn upload_assignment_file_path(
        &self,
        assignment: &AssignmentDetailResponse,
        file_name: &str,
        path: &Path,
        user_id: &str,
        access_token: &str,
    ) -> Result<AssignmentUploadResponse, AuthError> {
        let metadata = tokio::fs::metadata(path)
            .await
            .map_err(|error| AuthError::file_system(error.to_string()))?;
        validate_assignment_upload_metadata(file_name, metadata.len() as usize)?;
        let response = self
            .http
            .send_multipart_file(
                HttpRequest {
                    method: HttpMethod::Post,
                    url: self.endpoints.assignment_upload_url.clone(),
                    headers: vec![
                        ("authorization".to_string(), PORTAL_BASIC_AUTH.to_string()),
                        ("Blade-Auth".to_string(), access_token.to_string()),
                    ],
                    body: None,
                },
                vec![
                    ("userId".to_string(), user_id.to_string()),
                    ("bizType".to_string(), "3".to_string()),
                ],
                "file".to_string(),
                file_name.to_string(),
                path.to_path_buf(),
            )
            .await?;
        let resource_id: String = parse_ucloud_envelope(response, "附件上传失败，请稍后重试。")?;
        let preview_url = self
            .get_resource_download_url(&resource_id, access_token)
            .await?;
        Ok(AssignmentUploadResponse {
            assignment_id: assignment.id.clone(),
            file_name: file_name.to_string(),
            preview_url,
            resource_id,
            site_id: assignment.site_id.clone(),
            site_name: assignment.site_name.clone(),
        })
    }

    async fn assignment_resources_from_refs(
        &self,
        resources: Vec<RawAssignmentResourceRef>,
        access_token: &str,
    ) -> Result<Vec<AssignmentResource>, AuthError> {
        let ids = resources
            .into_iter()
            .filter_map(|item| value_to_string_opt(item.resource_id))
            .collect::<Vec<_>>();
        let details = self.get_resource_details_by_ids(&ids, access_token).await?;
        self.assignment_resources_from_details(details, access_token)
            .await
    }

    async fn assignment_resources_from_details(
        &self,
        resources: Vec<RawResourceDetail>,
        access_token: &str,
    ) -> Result<Vec<AssignmentResource>, AuthError> {
        stream::iter(resources)
            .filter_map(|detail| async move {
                raw_resource_id(&detail).map(|resource_id| (detail, resource_id))
            })
            .map(|(detail, resource_id)| async move {
                let preview_url = self
                    .get_resource_download_url(&resource_id, access_token)
                    .await?;
                Ok(AssignmentResource {
                    ext: detail.ext,
                    name: pick_string([detail.name, detail.file_name, Some(resource_id.clone())])
                        .unwrap_or_default(),
                    preview_url,
                    resource_id,
                    storage_id: detail.storage_id,
                })
            })
            .buffered(PREVIEW_URL_CONCURRENCY)
            .collect::<Vec<_>>()
            .await
            .into_iter()
            .collect()
    }
}

fn first_non_empty_resource_list<const N: usize>(
    values: [Option<Vec<RawResourceDetail>>; N],
) -> Vec<RawResourceDetail> {
    values
        .into_iter()
        .flatten()
        .find(|resources| !resources.is_empty())
        .unwrap_or_default()
}

#[derive(Clone, Debug, Deserialize, Default, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawAssignmentSummary {
    assignment_begin_time: Option<String>,
    assignment_end_time: Option<String>,
    assignment_status_name: Option<String>,
    assignment_title: Option<String>,
    commit_id: Option<serde_json::Value>,
    commit_status: Option<serde_json::Value>,
    commit_time: Option<String>,
    end_time: Option<String>,
    id: Option<serde_json::Value>,
    is_commit: Option<serde_json::Value>,
    site_id: Option<serde_json::Value>,
    site_name: Option<String>,
    start_time: Option<String>,
    status_name: Option<String>,
    status_self: Option<String>,
    submit_time: Option<String>,
    title: Option<String>,
    user_commit_status: Option<serde_json::Value>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
struct RawAssignmentRecords {
    records: Option<Vec<RawAssignmentSummary>>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawUndoneItem {
    activity_id: Option<serde_json::Value>,
    activity_name: Option<String>,
    end_time: Option<String>,
    site_id: Option<serde_json::Value>,
    site_name: Option<String>,
    #[serde(rename = "type")]
    kind: Option<u8>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawUndoneList {
    undone_list: Option<Vec<RawUndoneItem>>,
}

#[derive(Clone, Debug, Deserialize, Default, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawAssignmentDetail {
    assignment_begin_time: Option<String>,
    assignment_answer: Option<String>,
    assignment_comment: Option<String>,
    assignment_content: Option<String>,
    assignment_end_time: Option<String>,
    assignment_resource: Option<Vec<RawAssignmentResourceRef>>,
    assignment_score: Option<serde_json::Value>,
    assignment_status_name: Option<String>,
    assignment_submit_content: Option<String>,
    assignment_title: Option<String>,
    class_name: Option<String>,
    commit_id: Option<serde_json::Value>,
    commit_content: Option<String>,
    commit_status: Option<serde_json::Value>,
    commit_time: Option<String>,
    end_time: Option<String>,
    id: Option<serde_json::Value>,
    is_commit: Option<serde_json::Value>,
    is_overtime_commit: Option<u8>,
    site_id: Option<serde_json::Value>,
    site_name: Option<String>,
    start_time: Option<String>,
    status_name: Option<String>,
    status_self: Option<String>,
    student_attachment_list: Option<Vec<RawResourceDetail>>,
    student_commit_content: Option<String>,
    student_resource: Option<Vec<RawResourceDetail>>,
    submit_time: Option<String>,
    submit_attachment_list: Option<Vec<RawResourceDetail>>,
    title: Option<String>,
    user_commit_status: Option<serde_json::Value>,
}

impl RawAssignmentDetail {
    fn summary(&self) -> RawAssignmentSummary {
        RawAssignmentSummary {
            assignment_begin_time: self.assignment_begin_time.clone(),
            assignment_end_time: self.assignment_end_time.clone(),
            assignment_status_name: self.assignment_status_name.clone(),
            assignment_title: self.assignment_title.clone(),
            commit_id: self.commit_id.clone(),
            commit_status: self.commit_status.clone(),
            commit_time: self.commit_time.clone(),
            end_time: self.end_time.clone(),
            id: self.id.clone(),
            is_commit: self.is_commit.clone(),
            site_id: self.site_id.clone(),
            site_name: self.site_name.clone(),
            start_time: self.start_time.clone(),
            status_name: self.status_name.clone(),
            status_self: self.status_self.clone(),
            submit_time: self.submit_time.clone(),
            title: self.title.clone(),
            user_commit_status: self.user_commit_status.clone(),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawAssignmentResourceRef {
    resource_id: Option<serde_json::Value>,
}

fn to_assignment_summary(
    record: RawAssignmentSummary,
    source: &str,
    fallback_site_id: &str,
    fallback_site_name: &str,
) -> Option<AssignmentSummary> {
    let id = value_to_string_opt(record.id.clone())?;
    if id.is_empty() {
        return None;
    }
    Some(AssignmentSummary {
        end_time: pick_string([record.assignment_end_time.clone(), record.end_time.clone()])
            .unwrap_or_default(),
        id,
        site_id: value_to_string_opt(record.site_id.clone())
            .or_else(|| (!fallback_site_id.is_empty()).then(|| fallback_site_id.to_string()))
            .unwrap_or_default(),
        site_name: pick_string([
            record.site_name.clone(),
            Some(fallback_site_name.to_string()),
        ])
        .unwrap_or_default(),
        source: source.to_string(),
        start_time: pick_string([
            record.assignment_begin_time.clone(),
            record.start_time.clone(),
        ])
        .unwrap_or_default(),
        status: resolve_assignment_status(&record),
        title: pick_string([
            record.assignment_title,
            record.title,
            value_to_string_opt(record.id),
        ])
        .unwrap_or_default(),
    })
}

fn resolve_assignment_status(record: &RawAssignmentSummary) -> AssignmentStatus {
    if text_matches(
        ["已截止", "已结束", "已关闭", "已过期"],
        [
            record.status_self.as_deref(),
            record.status_name.as_deref(),
            record.assignment_status_name.as_deref(),
        ],
    ) {
        return AssignmentStatus::Expired;
    }
    let end_time = pick_string([record.assignment_end_time.clone(), record.end_time.clone()]);
    if end_time.as_deref().is_some_and(is_past_time) {
        return AssignmentStatus::Expired;
    }
    if text_matches(
        ["已提交", "已完成", "已交"],
        [
            record.status_self.as_deref(),
            record.status_name.as_deref(),
            record.assignment_status_name.as_deref(),
        ],
    ) || truthy(record.commit_id.as_ref())
        || truthy(record.commit_status.as_ref())
        || truthy(record.user_commit_status.as_ref())
        || truthy(record.is_commit.as_ref())
        || record
            .commit_time
            .as_deref()
            .is_some_and(|value| !value.trim().is_empty())
        || record
            .submit_time
            .as_deref()
            .is_some_and(|value| !value.trim().is_empty())
    {
        return AssignmentStatus::Submitted;
    }
    AssignmentStatus::Pending
}

fn validate_assignment_upload(file_name: &str, bytes: &[u8]) -> Result<(), AuthError> {
    validate_assignment_upload_metadata(file_name, bytes.len())
}

fn validate_assignment_upload_metadata(file_name: &str, size: usize) -> Result<(), AuthError> {
    if file_name.contains(['\r', '\n']) {
        return Err(AuthError::new(
            AuthErrorCode::InvalidFileName,
            "上传文件名不能包含换行符。",
        ));
    }
    if size == 0 {
        return Err(AuthError::new(
            AuthErrorCode::EmptyUpload,
            "上传文件不能为空。",
        ));
    }
    if size > MAX_ASSIGNMENT_UPLOAD_BYTES {
        return Err(AuthError::new(
            AuthErrorCode::FileTooLarge,
            "单个附件不能超过 25 MB。",
        ));
    }
    let extension = file_name
        .rsplit_once('.')
        .map(|(_, extension)| extension.trim().to_ascii_lowercase());
    if extension
        .as_deref()
        .is_some_and(|extension| BLOCKED_UPLOAD_EXTENSIONS.contains(&extension))
    {
        return Err(AuthError::new(
            AuthErrorCode::FileTypeNotAllowed,
            "当前不支持上传可执行文件，请改用文档、图片、压缩包或代码文本。",
        ));
    }
    Ok(())
}

fn parse_empty_success(response: crate::HttpResponse, fallback: &str) -> Result<(), AuthError> {
    if !(200..300).contains(&response.status) {
        return Err(AuthError::upstream(format!(
            "{fallback} HTTP status {}.",
            response.status
        )));
    }
    let payload: serde_json::Value = serde_json::from_slice(&response.body)
        .map_err(|error| AuthError::upstream(error.to_string()))?;
    if payload.get("success").and_then(|value| value.as_bool()) == Some(false) {
        let message = payload
            .get("message")
            .or_else(|| payload.get("msg"))
            .and_then(|value| value.as_str())
            .filter(|value| !value.trim().is_empty())
            .unwrap_or(fallback);
        return Err(AuthError::upstream(message.to_string()));
    }
    Ok(())
}

fn json_headers(access_token: &str) -> Vec<(String, String)> {
    let mut headers = portal_json_headers(access_token);
    headers.push((
        "Content-Type".to_string(),
        "application/json;charset=UTF-8".to_string(),
    ));
    headers
}

fn multipart_upload_body(file_name: &str, bytes: &[u8], user_id: &str) -> (String, Vec<u8>) {
    let filename = multipart_quoted_string(file_name);
    let boundary = multipart_boundary(
        [
            user_id.as_bytes(),
            b"3".as_slice(),
            filename.as_bytes(),
            bytes,
        ]
        .as_slice(),
    );
    let mut body = Vec::new();
    push_field(&mut body, &boundary, "userId", user_id.as_bytes());
    push_field(&mut body, &boundary, "bizType", b"3");
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(
        format!("Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n\r\n")
            .as_bytes(),
    );
    body.extend_from_slice(bytes);
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());
    (format!("multipart/form-data; boundary={boundary}"), body)
}

fn multipart_boundary(values: &[&[u8]]) -> String {
    let seed = multipart_boundary_seed(values);
    let base = format!("----open-cloud-assignment-upload-boundary-{seed:016x}");
    for suffix in 0.. {
        let boundary = if suffix == 0 {
            base.clone()
        } else {
            format!("{base}-{suffix}")
        };
        let delimiter = format!("--{boundary}");
        if values
            .iter()
            .all(|value| !contains_bytes(value, delimiter.as_bytes()))
        {
            return boundary;
        }
    }
    unreachable!("unbounded boundary suffix search")
}

fn multipart_boundary_seed(values: &[&[u8]]) -> u64 {
    let mut hasher = DefaultHasher::new();
    for value in values {
        value.len().hash(&mut hasher);
        value.hash(&mut hasher);
    }
    hasher.finish()
}

fn multipart_quoted_string(value: &str) -> String {
    let mut output = String::new();
    for ch in value.chars() {
        match ch {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            other => output.push(other),
        }
    }
    output
}

fn contains_bytes(value: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty() && value.windows(needle.len()).any(|window| window == needle)
}

fn push_field(body: &mut Vec<u8>, boundary: &str, name: &str, value: &[u8]) {
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(
        format!("Content-Disposition: form-data; name=\"{name}\"\r\n\r\n").as_bytes(),
    );
    body.extend_from_slice(value);
    body.extend_from_slice(b"\r\n");
}

fn value_to_string_opt(value: Option<serde_json::Value>) -> Option<String> {
    value
        .and_then(value_to_string)
        .filter(|value| !value.is_empty())
}

fn score_value(value: Option<&serde_json::Value>) -> Option<f64> {
    match value {
        Some(serde_json::Value::Number(value)) => value.as_f64(),
        Some(serde_json::Value::String(value)) => value.trim().parse().ok(),
        _ => None,
    }
}

fn pick_string<const N: usize>(values: [Option<String>; N]) -> Option<String> {
    values
        .into_iter()
        .flatten()
        .map(|value| value.trim().to_string())
        .find(|value| !value.is_empty())
}

fn truthy(value: Option<&serde_json::Value>) -> bool {
    match value {
        Some(serde_json::Value::String(value)) => !value.trim().is_empty() && value.trim() != "0",
        Some(serde_json::Value::Number(value)) => value.as_i64().is_some_and(|value| value > 0),
        Some(serde_json::Value::Bool(value)) => *value,
        _ => false,
    }
}

fn text_matches<const N: usize, const M: usize>(
    needles: [&str; N],
    values: [Option<&str>; M],
) -> bool {
    values
        .into_iter()
        .flatten()
        .any(|value| needles.iter().any(|needle| value.contains(needle)))
}

fn is_past_time(value: &str) -> bool {
    let value = value.trim();
    let parsed = chrono::NaiveDateTime::parse_from_str(value, "%Y-%m-%d %H:%M:%S").or_else(|_| {
        chrono::NaiveDate::parse_from_str(value, "%Y-%m-%d")
            .map(|date| date.and_hms_opt(0, 0, 0).expect("valid midnight"))
    });
    parsed
        .ok()
        .is_some_and(|time| time < chrono::Local::now().naive_local())
}
