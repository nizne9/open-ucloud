use crate::AuthError;
use async_trait::async_trait;
use futures_util::StreamExt;
use open_cloud_api::AuthErrorCode;
use std::path::{Path, PathBuf};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::time::Duration;
use tokio::io::AsyncWriteExt;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const READ_TIMEOUT: Duration = Duration::from_secs(30);
const API_REQUEST_TIMEOUT: Duration = Duration::from_secs(45);
const MULTIPART_REQUEST_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const MAX_BUFFERED_RESPONSE_BYTES: usize = 8 * 1024 * 1024;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum HttpMethod {
    Get,
    Post,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HttpRequest {
    pub method: HttpMethod,
    pub url: String,
    pub headers: Vec<(String, String)>,
    pub body: Option<HttpBody>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum HttpBody {
    Text(String),
    Bytes(Vec<u8>),
}

pub type DownloadProgressCallback = Arc<dyn Fn(u64) + Send + Sync + 'static>;

#[derive(Clone, Default)]
pub struct DownloadProgress {
    callback: Option<DownloadProgressCallback>,
}

impl DownloadProgress {
    pub fn new(callback: impl Fn(u64) + Send + Sync + 'static) -> Self {
        Self {
            callback: Some(Arc::new(callback)),
        }
    }

    pub fn add(&self, bytes: u64) {
        if let Some(callback) = &self.callback {
            callback(bytes);
        }
    }
}

#[derive(Clone, Default)]
pub struct DownloadCancelFlag {
    cancelled: Arc<AtomicBool>,
}

impl DownloadCancelFlag {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::SeqCst)
    }
}

impl HttpBody {
    pub fn text(value: impl Into<String>) -> Self {
        Self::Text(value.into())
    }

    pub fn bytes(value: impl Into<Vec<u8>>) -> Self {
        Self::Bytes(value.into())
    }

    pub fn as_text(&self) -> Option<&str> {
        match self {
            Self::Text(value) => Some(value.as_str()),
            Self::Bytes(_) => None,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HttpResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl HttpResponse {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(key, _)| key.eq_ignore_ascii_case(name))
            .map(|(_, value)| value.as_str())
    }

    pub fn text(&self) -> Result<String, AuthError> {
        String::from_utf8(self.body.clone())
            .map_err(|_| AuthError::upstream("invalid upstream text"))
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HttpResponseHead {
    pub status: u16,
    pub headers: Vec<(String, String)>,
}

impl HttpResponseHead {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(key, _)| key.eq_ignore_ascii_case(name))
            .map(|(_, value)| value.as_str())
    }
}

#[async_trait]
pub trait HttpClient: Clone + Send + Sync + 'static {
    async fn send(&self, request: HttpRequest) -> Result<HttpResponse, AuthError>;

    async fn send_multipart_file(
        &self,
        mut request: HttpRequest,
        fields: Vec<(String, String)>,
        file_field_name: String,
        file_name: String,
        path: PathBuf,
    ) -> Result<HttpResponse, AuthError> {
        let bytes = tokio::fs::read(&path)
            .await
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        let boundary = format!(
            "open-cloud-boundary-{}-{}",
            fields.len(),
            file_name.len() + bytes.len()
        );
        request.headers.push((
            "content-type".to_string(),
            format!("multipart/form-data; boundary={boundary}"),
        ));
        request.body = Some(HttpBody::bytes(multipart_file_body(
            &boundary,
            fields,
            &file_field_name,
            &file_name,
            &bytes,
        )));
        self.send(request).await
    }

    async fn download_to_path(
        &self,
        request: HttpRequest,
        path: &Path,
        progress: DownloadProgress,
        cancel: DownloadCancelFlag,
    ) -> Result<HttpResponseHead, AuthError> {
        if cancel.is_cancelled() {
            return Err(cancelled_error());
        }
        let response = self.send(request).await?;
        if cancel.is_cancelled() {
            return Err(cancelled_error());
        }
        let head = HttpResponseHead {
            status: response.status,
            headers: response.headers.clone(),
        };
        if !(200..300).contains(&response.status) {
            return Ok(head);
        }
        let mut file = tokio::fs::File::create(path)
            .await
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        file.write_all(&response.body)
            .await
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        progress.add(response.body.len() as u64);
        file.flush()
            .await
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        Ok(head)
    }
}

#[derive(Clone, Default)]
pub struct ReqwestHttpClient {
    client: reqwest::Client,
}

impl ReqwestHttpClient {
    pub fn new() -> Result<Self, AuthError> {
        let client = reqwest::Client::builder()
            .connect_timeout(CONNECT_TIMEOUT)
            .read_timeout(READ_TIMEOUT)
            .redirect(reqwest::redirect::Policy::none())
            .user_agent(concat!("open-cloud/", env!("CARGO_PKG_VERSION")))
            .build()
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        Ok(Self { client })
    }
}

#[async_trait]
impl HttpClient for ReqwestHttpClient {
    async fn send(&self, request: HttpRequest) -> Result<HttpResponse, AuthError> {
        let method = match request.method {
            HttpMethod::Get => reqwest::Method::GET,
            HttpMethod::Post => reqwest::Method::POST,
        };
        let mut builder = self.client.request(method, &request.url);
        for (name, value) in &request.headers {
            builder = builder.header(name, value);
        }
        if let Some(body) = request.body {
            builder = match body {
                HttpBody::Text(value) => builder.body(value),
                HttpBody::Bytes(value) => builder.body(value),
            };
        }
        let response = builder
            .timeout(API_REQUEST_TIMEOUT)
            .send()
            .await
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        buffered_response(response).await
    }

    async fn download_to_path(
        &self,
        request: HttpRequest,
        path: &Path,
        progress: DownloadProgress,
        cancel: DownloadCancelFlag,
    ) -> Result<HttpResponseHead, AuthError> {
        if cancel.is_cancelled() {
            return Err(cancelled_error());
        }
        let method = match request.method {
            HttpMethod::Get => reqwest::Method::GET,
            HttpMethod::Post => reqwest::Method::POST,
        };
        let mut builder = self.client.request(method, &request.url);
        for (name, value) in &request.headers {
            builder = builder.header(name, value);
        }
        if let Some(body) = request.body {
            builder = match body {
                HttpBody::Text(value) => builder.body(value),
                HttpBody::Bytes(value) => builder.body(value),
            };
        }
        let response = builder
            .send()
            .await
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        let status = response.status().as_u16();
        let headers = response
            .headers()
            .iter()
            .filter_map(|(name, value)| {
                value
                    .to_str()
                    .ok()
                    .map(|value| (name.as_str().to_string(), value.to_string()))
            })
            .collect();
        let head = HttpResponseHead { status, headers };
        if !(200..300).contains(&status) {
            return Ok(head);
        }
        let mut file = tokio::fs::File::create(path)
            .await
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        let mut stream = response.bytes_stream();
        while let Some(chunk) = stream.next().await {
            if cancel.is_cancelled() {
                return Err(cancelled_error());
            }
            let chunk = chunk.map_err(|error| AuthError::upstream(error.to_string()))?;
            file.write_all(&chunk)
                .await
                .map_err(|error| AuthError::upstream(error.to_string()))?;
            progress.add(chunk.len() as u64);
        }
        file.flush()
            .await
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        Ok(head)
    }

    async fn send_multipart_file(
        &self,
        request: HttpRequest,
        fields: Vec<(String, String)>,
        file_field_name: String,
        file_name: String,
        path: PathBuf,
    ) -> Result<HttpResponse, AuthError> {
        let method = match request.method {
            HttpMethod::Get => reqwest::Method::GET,
            HttpMethod::Post => reqwest::Method::POST,
        };
        let mut builder = self.client.request(method, &request.url);
        for (name, value) in &request.headers {
            builder = builder.header(name, value);
        }
        let mut form = reqwest::multipart::Form::new();
        for (name, value) in fields {
            form = form.text(name, value);
        }
        let file_part = reqwest::multipart::Part::file(path)
            .await
            .map_err(|error| AuthError::upstream(error.to_string()))?
            .file_name(file_name);
        form = form.part(file_field_name, file_part);
        let response = builder
            .multipart(form)
            .timeout(MULTIPART_REQUEST_TIMEOUT)
            .send()
            .await
            .map_err(|error| AuthError::upstream(error.to_string()))?;
        buffered_response(response).await
    }
}

async fn buffered_response(response: reqwest::Response) -> Result<HttpResponse, AuthError> {
    if response
        .content_length()
        .is_some_and(|length| length > MAX_BUFFERED_RESPONSE_BYTES as u64)
    {
        return Err(response_too_large());
    }
    let status = response.status().as_u16();
    let headers = response
        .headers()
        .iter()
        .filter_map(|(name, value)| {
            value
                .to_str()
                .ok()
                .map(|value| (name.as_str().to_string(), value.to_string()))
        })
        .collect();
    let mut body = Vec::with_capacity(
        response
            .content_length()
            .unwrap_or_default()
            .min(MAX_BUFFERED_RESPONSE_BYTES as u64) as usize,
    );
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|error| AuthError::upstream(error.to_string()))?;
        append_buffered_chunk(&mut body, &chunk)?;
    }
    Ok(HttpResponse {
        status,
        headers,
        body,
    })
}

fn append_buffered_chunk(body: &mut Vec<u8>, chunk: &[u8]) -> Result<(), AuthError> {
    if body.len().saturating_add(chunk.len()) > MAX_BUFFERED_RESPONSE_BYTES {
        return Err(response_too_large());
    }
    body.extend_from_slice(chunk);
    Ok(())
}

fn response_too_large() -> AuthError {
    AuthError::upstream("upstream response exceeded the 8 MiB safety limit")
}

fn multipart_file_body(
    boundary: &str,
    fields: Vec<(String, String)>,
    file_field_name: &str,
    file_name: &str,
    bytes: &[u8],
) -> Vec<u8> {
    let mut body = Vec::new();
    for (name, value) in fields {
        body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
        body.extend_from_slice(
            format!(
                "Content-Disposition: form-data; name=\"{}\"\r\n\r\n",
                multipart_quoted_string(&name)
            )
            .as_bytes(),
        );
        body.extend_from_slice(value.as_bytes());
        body.extend_from_slice(b"\r\n");
    }
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(
        format!(
            "Content-Disposition: form-data; name=\"{}\"; filename=\"{}\"\r\n\r\n",
            multipart_quoted_string(file_field_name),
            multipart_quoted_string(file_name)
        )
        .as_bytes(),
    );
    body.extend_from_slice(bytes);
    body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
    body
}

fn multipart_quoted_string(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\r', "%0D")
        .replace('\n', "%0A")
}

fn cancelled_error() -> AuthError {
    AuthError::new(AuthErrorCode::UnknownAuthError, "下载已取消。")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buffered_response_rejects_chunks_over_the_limit() {
        let mut body = vec![0; MAX_BUFFERED_RESPONSE_BYTES];

        let error = append_buffered_chunk(&mut body, &[1]).expect_err("response is capped");

        assert_eq!(error.code, AuthErrorCode::UpstreamUnavailable);
        assert_eq!(body.len(), MAX_BUFFERED_RESPONSE_BYTES);
    }
}
