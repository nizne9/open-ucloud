use clap::{Parser, Subcommand};
use open_cloud_api::{
    AttendanceStatusResponse, AuthErrorCode, AuthErrorResponse, AuthSessionResponse,
    CourseActivityResponse, CourseDetailResponse, CourseListResponse, CourseSite, GoingSite,
    RoleName,
};
use open_cloud_core::{
    refresh_session_if_needed, resolve_course_detail, AuthClient, AuthEndpoints, ReqwestHttpClient,
};
use open_cloud_store::{
    credential_probe, system_credential_backend, system_credential_persistence, AuthSession,
    CredentialBackend, CredentialProbe, CredentialProbeStatus, SecureSessionStore, StoreError,
    SystemCredentialBackend, SystemSecureSessionStore,
};
use serde::Serialize;
use std::collections::HashSet;
use std::str::FromStr;

#[derive(Debug, Parser)]
#[command(name = "open-cloud", version, about = "Client-first Open UCloud CLI")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Debug, Subcommand)]
pub enum Commands {
    /// Check local CLI and runtime readiness.
    Doctor {
        #[arg(long)]
        json: bool,
    },
    /// Start an interactive login flow.
    Login {
        #[arg(long)]
        interactive: bool,
        #[arg(long, value_parser = parse_role)]
        role: Option<RoleName>,
        #[arg(long)]
        json: bool,
    },
    /// Print the current in-process session.
    Session {
        #[arg(long)]
        json: bool,
    },
    /// List current student courses.
    Courses {
        #[arg(long)]
        json: bool,
        #[arg(long)]
        with_going: bool,
    },
    /// Show a current student course by id.
    Course {
        site_id: String,
        #[arg(long)]
        json: bool,
    },
    /// Show read-only attendance status for a course.
    Attendance {
        #[arg(long)]
        site: String,
        #[arg(long)]
        json: bool,
    },
    /// Clear the current in-process session.
    Logout {
        #[arg(long)]
        yes: bool,
    },
}

pub async fn run() -> i32 {
    let cli = Cli::parse();
    match run_cli(cli).await {
        Ok(()) => 0,
        Err(error) => {
            if let Some(message) = error.stderr_message() {
                eprintln!("{message}");
            }
            1
        }
    }
}

#[derive(Debug)]
pub enum CliError {
    Error(AuthErrorResponse),
    JsonErrorPrinted(AuthErrorResponse),
}

impl CliError {
    pub fn response(&self) -> &AuthErrorResponse {
        match self {
            Self::Error(response) | Self::JsonErrorPrinted(response) => response,
        }
    }

    pub fn json_error_was_printed(&self) -> bool {
        matches!(self, Self::JsonErrorPrinted(_))
    }

    fn stderr_message(&self) -> Option<&str> {
        match self {
            Self::Error(response) => Some(&response.message),
            Self::JsonErrorPrinted(_) => None,
        }
    }
}

impl From<AuthErrorResponse> for CliError {
    fn from(value: AuthErrorResponse) -> Self {
        Self::Error(value)
    }
}

pub fn doctor_report() -> String {
    let system_backend = SystemCredentialBackend;
    doctor_report_from_diagnostics(DoctorDiagnostics::from_probe(
        system_credential_backend(),
        system_credential_persistence(),
        credential_probe(&system_backend),
    ))
}

pub fn doctor_report_from(
    backend: &str,
    persistence: &str,
    credential_probe: CredentialProbe,
) -> String {
    doctor_report_from_diagnostics(DoctorDiagnostics::from_probe(
        backend,
        persistence,
        credential_probe,
    ))
}

pub fn doctor_report_json() -> Result<String, serde_json::Error> {
    let system_backend = SystemCredentialBackend;
    doctor_report_json_from(
        system_credential_backend(),
        system_credential_persistence(),
        credential_probe(&system_backend),
    )
}

pub fn doctor_report_json_from(
    backend: &str,
    persistence: &str,
    credential_probe: CredentialProbe,
) -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(&DoctorDiagnostics::from_probe(
        backend,
        persistence,
        credential_probe,
    ))
}

fn doctor_report_from_diagnostics(diagnostics: DoctorDiagnostics) -> String {
    let backend = diagnostics.credential_backend.as_str();
    let persistence = diagnostics.credential_persistence.as_str();
    let mut lines = vec![
        "open-cloud: ok".to_string(),
        "session storage: system credential store".to_string(),
        format!("credential backend: {backend}"),
        format!("credential persistence: {persistence}"),
        format!("credential status: {}", diagnostics.credential_status),
        "network: checked during login".to_string(),
    ];
    if diagnostics.credential_status == CredentialProbeStatus::Unavailable.as_str() {
        if let Some(reason) = diagnostics.credential_reason {
            lines.push(format!("credential reason: {reason}"));
        }
    }
    if backend == "mock" {
        lines.push(
            "warning: credential backend is mock; sessions are not persisted outside this process."
                .to_string(),
        );
    }
    if persistence == "process-only" {
        lines.push(
            "warning: credential persistence is process-only; sessions are not durable credentials."
                .to_string(),
        );
    }
    format!("{}\n", lines.join("\n"))
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct DoctorDiagnostics {
    open_cloud: &'static str,
    session_storage: &'static str,
    credential_backend: String,
    credential_persistence: String,
    credential_status: &'static str,
    credential_reason: Option<String>,
    network: &'static str,
}

impl DoctorDiagnostics {
    fn from_probe(backend: &str, persistence: &str, credential_probe: CredentialProbe) -> Self {
        Self {
            open_cloud: "ok",
            session_storage: "system credential store",
            credential_backend: backend.to_string(),
            credential_persistence: persistence.to_string(),
            credential_status: credential_probe.status.as_str(),
            credential_reason: credential_probe.reason,
            network: "checked during login",
        }
    }
}

pub async fn run_cli(cli: Cli) -> Result<(), CliError> {
    let store = SystemSecureSessionStore::new(SystemCredentialBackend);
    run_cli_with_store(cli, store).await
}

pub async fn run_cli_with_store<B>(cli: Cli, store: SecureSessionStore<B>) -> Result<(), CliError>
where
    B: CredentialBackend,
{
    match cli.command {
        Commands::Doctor { json } => {
            if json {
                println!(
                    "{}",
                    doctor_report_json()
                        .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
                );
            } else {
                print!("{}", doctor_report());
            }
            Ok(())
        }
        Commands::Login {
            interactive,
            role,
            json,
        } => {
            if !interactive {
                return Err(error(
                    AuthErrorCode::UnknownAuthError,
                    "login requires --interactive so credentials are not passed through shell history.",
                )
                .into());
            }
            login_interactive(&store, role, json).await?;
            Ok(())
        }
        Commands::Session { json } => {
            let session = match load_persisted_session(&store, now_ms()) {
                Ok(session) => session,
                Err(error_response) if json => {
                    print_json_error_response(&error_response)?;
                    return Err(CliError::JsonErrorPrinted(error_response));
                }
                Err(error_response) => return Err(error_response.into()),
            };
            let Some(response) = session else {
                let error_response = error(
                    AuthErrorCode::SessionExpired,
                    "No persisted session is available. Run login --interactive first.",
                );
                if json {
                    print_json_error_response(&error_response)?;
                    return Err(CliError::JsonErrorPrinted(error_response));
                }
                return Err(error_response.into());
            };
            if json {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&response)
                        .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
                );
            } else {
                println!(
                    "Logged in as {} ({})",
                    response.user.real_name,
                    response.selected_role.as_str()
                );
            }
            Ok(())
        }
        Commands::Courses { json, with_going } => {
            let http = ReqwestHttpClient::new().map_err(to_response_error)?;
            let client = AuthClient::new(http, AuthEndpoints::default());
            let session = match load_access_session(&store, &client, now_ms()).await {
                Ok(session) => session,
                Err(error_response) if json => {
                    print_json_error_response(&error_response)?;
                    return Err(CliError::JsonErrorPrinted(error_response));
                }
                Err(error_response) => return Err(error_response.into()),
            };
            let courses = match client
                .get_student_courses(&session.user.user_id, &session.access_token)
                .await
                .map_err(to_response_error)
            {
                Ok(courses) => courses,
                Err(error_response) if json => {
                    print_json_error_response(&error_response)?;
                    return Err(CliError::JsonErrorPrinted(error_response));
                }
                Err(error_response) => return Err(error_response.into()),
            };
            if json {
                if with_going {
                    let going_sites =
                        match load_going_sites(&client, &courses, &session.access_token)
                            .await
                            .map_err(to_response_error)
                        {
                            Ok(going_sites) => going_sites,
                            Err(error_response) => {
                                print_json_error_response(&error_response)?;
                                return Err(CliError::JsonErrorPrinted(error_response));
                            }
                        };
                    println!(
                        "{}",
                        serde_json::to_string_pretty(&CourseActivityResponse {
                            records: courses,
                            going_sites
                        })
                        .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
                    );
                } else {
                    println!(
                        "{}",
                        serde_json::to_string_pretty(&CourseListResponse { records: courses })
                            .map_err(|err| error(
                                AuthErrorCode::UnknownAuthError,
                                err.to_string()
                            ))?
                    );
                }
            } else if with_going {
                let going_sites = load_going_sites(&client, &courses, &session.access_token)
                    .await
                    .map_err(to_response_error)?;
                print!("{}", format_course_list_with_going(&courses, &going_sites));
            } else {
                print_course_list(&courses);
            }
            Ok(())
        }
        Commands::Course { site_id, json } => {
            let http = ReqwestHttpClient::new().map_err(to_response_error)?;
            let client = AuthClient::new(http, AuthEndpoints::default());
            let session = match load_access_session(&store, &client, now_ms()).await {
                Ok(session) => session,
                Err(error_response) if json => {
                    print_json_error_response(&error_response)?;
                    return Err(CliError::JsonErrorPrinted(error_response));
                }
                Err(error_response) => return Err(error_response.into()),
            };
            let detail = match load_course_detail(&client, &session, &site_id)
                .await
                .map_err(to_response_error)
            {
                Ok(detail) => detail,
                Err(error_response) if json => {
                    print_json_error_response(&error_response)?;
                    return Err(CliError::JsonErrorPrinted(error_response));
                }
                Err(error_response) => return Err(error_response.into()),
            };
            if json {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&detail)
                        .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
                );
            } else {
                print!("{}", format_course_detail(&detail));
            }
            Ok(())
        }
        Commands::Attendance { site, json } => {
            let http = ReqwestHttpClient::new().map_err(to_response_error)?;
            let client = AuthClient::new(http, AuthEndpoints::default());
            let session = match load_access_session(&store, &client, now_ms()).await {
                Ok(session) => session,
                Err(error_response) if json => {
                    print_json_error_response(&error_response)?;
                    return Err(CliError::JsonErrorPrinted(error_response));
                }
                Err(error_response) => return Err(error_response.into()),
            };
            let status = match load_attendance_status(&client, &session, &site)
                .await
                .map_err(to_response_error)
            {
                Ok(status) => status,
                Err(error_response) if json => {
                    print_json_error_response(&error_response)?;
                    return Err(CliError::JsonErrorPrinted(error_response));
                }
                Err(error_response) => return Err(error_response.into()),
            };
            if json {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&status)
                        .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
                );
            } else {
                print!("{}", format_attendance_status(&status));
            }
            Ok(())
        }
        Commands::Logout { yes } => {
            if !yes {
                return Err(error(
                    AuthErrorCode::UnknownAuthError,
                    "logout is a mutating command; rerun with --yes.",
                )
                .into());
            }
            store.clear_current().map_err(store_error)?;
            println!("stored session cleared");
            Ok(())
        }
    }
}

async fn login_interactive(
    store: &SecureSessionStore<impl CredentialBackend>,
    role: Option<RoleName>,
    json: bool,
) -> Result<(), AuthErrorResponse> {
    let username = prompt("Username: ")?;
    let password = rpassword::prompt_password("Password: ")
        .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?;
    let http = ReqwestHttpClient::new().map_err(to_response_error)?;
    let client = AuthClient::new(http, AuthEndpoints::default());
    let flow = client
        .start_login(&username)
        .await
        .map_err(to_response_error)?;
    let captcha = if flow.captcha_image.is_some() {
        println!(
            "Captcha image: {}",
            flow.captcha_image.as_deref().unwrap_or("")
        );
        Some(prompt("Captcha: ")?)
    } else {
        None
    };
    let result = client
        .finish_login(flow, &password, role, captcha.as_deref())
        .await
        .map_err(to_response_error)?;
    store
        .save_current(&AuthSession {
            access_token: result.access_token,
            access_token_expires_at_ms: result.access_token_expires_at_ms,
            refresh_token: result.refresh_token,
            refresh_token_expires_at_ms: result.refresh_token_expires_at_ms,
            role: result.selected_role.clone(),
            user: result.user.clone(),
        })
        .map_err(store_error)?;
    let response = AuthSessionResponse {
        selected_role: result.selected_role,
        user: result.user,
    };
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&response)
                .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
        );
    } else {
        println!(
            "Logged in as {} ({})",
            response.user.real_name,
            response.selected_role.as_str()
        );
    }
    Ok(())
}

fn parse_role(value: &str) -> Result<RoleName, String> {
    RoleName::from_str(value)
}

fn prompt(label: &str) -> Result<String, AuthErrorResponse> {
    use std::io::Write;
    print!("{label}");
    std::io::stdout()
        .flush()
        .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?;
    let mut value = String::new();
    std::io::stdin()
        .read_line(&mut value)
        .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?;
    Ok(value.trim().to_string())
}

fn to_response_error(error_value: open_cloud_core::AuthError) -> AuthErrorResponse {
    error(error_value.code, error_value.message)
}

pub fn load_persisted_session<B>(
    store: &SecureSessionStore<B>,
    now_ms: u64,
) -> Result<Option<AuthSessionResponse>, AuthErrorResponse>
where
    B: CredentialBackend,
{
    let Some(session) = store.load_current(now_ms).map_err(store_error)? else {
        return Ok(None);
    };
    Ok(Some(AuthSessionResponse {
        selected_role: session.role,
        user: session.user,
    }))
}

pub async fn load_access_session<B, C>(
    store: &SecureSessionStore<B>,
    client: &AuthClient<C>,
    now_ms: u64,
) -> Result<AuthSession, AuthErrorResponse>
where
    B: CredentialBackend,
    C: open_cloud_core::HttpClient,
{
    let Some(session) = store.load_current(now_ms).map_err(store_error)? else {
        return Err(error(
            AuthErrorCode::SessionExpired,
            "No persisted session is available. Run login --interactive first.",
        ));
    };
    let original = session.clone();
    let refreshed = refresh_session_if_needed(client, session, now_ms)
        .await
        .map_err(to_response_error)?;
    if refreshed != original {
        store.save_current(&refreshed).map_err(store_error)?;
    }
    Ok(refreshed)
}

pub fn print_course_list(courses: &[CourseSite]) {
    if courses.is_empty() {
        println!("No courses found.");
        return;
    }
    for course in courses {
        println!("{}\t{}", course.id, course.site_name);
    }
}

pub fn format_course_list_with_going(courses: &[CourseSite], going_sites: &[GoingSite]) -> String {
    if courses.is_empty() {
        return "No courses found.\n".to_string();
    }
    let going_site_ids = going_sites
        .iter()
        .map(|site| site.site_id.as_str())
        .collect::<HashSet<_>>();
    let mut output = String::new();
    for course in courses {
        let status = if going_site_ids.contains(course.id.as_str()) {
            "going"
        } else {
            "idle"
        };
        output.push_str(&format!(
            "{}\t{}\t{}\n",
            course.id, course.site_name, status
        ));
    }
    output
}

pub fn format_course_detail(detail: &CourseDetailResponse) -> String {
    let status = if detail.going_site.is_some() {
        "going"
    } else {
        "idle"
    };
    match &detail.going_site {
        Some(going_site) => format!(
            "{}\t{}\t{}\t{}\n",
            detail.course.id, detail.course.site_name, status, going_site.group_id
        ),
        None => format!(
            "{}\t{}\t{}\n",
            detail.course.id, detail.course.site_name, status
        ),
    }
}

pub fn format_attendance_status(status: &AttendanceStatusResponse) -> String {
    let label = if status.going { "going" } else { "idle" };
    match &status.group_id {
        Some(group_id) => format!(
            "{}\t{}\t{}\t{}\n",
            status.site_id, status.site_name, label, group_id
        ),
        None => format!("{}\t{}\t{}\n", status.site_id, status.site_name, label),
    }
}

async fn load_going_sites<C>(
    client: &AuthClient<C>,
    courses: &[CourseSite],
    access_token: &str,
) -> Result<Vec<GoingSite>, open_cloud_core::AuthError>
where
    C: open_cloud_core::HttpClient,
{
    let site_ids = courses
        .iter()
        .map(|course| course.id.clone())
        .collect::<Vec<_>>();
    client.get_going_sites(&site_ids, access_token).await
}

async fn load_course_detail<C>(
    client: &AuthClient<C>,
    session: &AuthSession,
    site_id: &str,
) -> Result<CourseDetailResponse, open_cloud_core::AuthError>
where
    C: open_cloud_core::HttpClient,
{
    let courses = client
        .get_student_courses(&session.user.user_id, &session.access_token)
        .await?;
    let base_detail = resolve_course_detail(&courses, &[], site_id)?;
    let going_sites = client
        .get_going_sites(
            std::slice::from_ref(&base_detail.course.id),
            &session.access_token,
        )
        .await?;
    resolve_course_detail(&courses, &going_sites, site_id)
}

async fn load_attendance_status<C>(
    client: &AuthClient<C>,
    session: &AuthSession,
    site_id: &str,
) -> Result<AttendanceStatusResponse, open_cloud_core::AuthError>
where
    C: open_cloud_core::HttpClient,
{
    let detail = load_course_detail(client, session, site_id).await?;
    let going_site = detail.going_site;
    Ok(AttendanceStatusResponse {
        site_id: detail.course.id,
        site_name: detail.course.site_name,
        going: going_site.is_some(),
        group_id: going_site.map(|site| site.group_id),
    })
}

fn print_json_error_response(error_response: &AuthErrorResponse) -> Result<(), AuthErrorResponse> {
    println!(
        "{}",
        serde_json::to_string_pretty(&error_response)
            .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
    );
    Ok(())
}

pub fn json_error(
    code: AuthErrorCode,
    message: impl Into<String>,
) -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(&error(code, message))
}

fn store_error(error_value: StoreError) -> AuthErrorResponse {
    error(
        AuthErrorCode::SecureStorageUnavailable,
        format!("secure storage is unavailable: {error_value}"),
    )
}

fn error(code: AuthErrorCode, message: impl Into<String>) -> AuthErrorResponse {
    AuthErrorResponse {
        code,
        message: message.into(),
        retry_after_seconds: None,
    }
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;
    use open_cloud_core::{AuthError, HttpClient, HttpRequest, HttpResponse};
    use std::collections::VecDeque;
    use std::sync::{Arc, Mutex};

    #[derive(Clone, Default)]
    struct MockHttp {
        responses: Arc<Mutex<VecDeque<HttpResponse>>>,
        requests: Arc<Mutex<Vec<HttpRequest>>>,
    }

    impl MockHttp {
        fn with(responses: Vec<HttpResponse>) -> Self {
            Self {
                responses: Arc::new(Mutex::new(VecDeque::from(responses))),
                requests: Arc::new(Mutex::new(Vec::new())),
            }
        }

        fn request_count(&self) -> usize {
            self.requests.lock().expect("requests lock").len()
        }
    }

    #[async_trait]
    impl HttpClient for MockHttp {
        async fn send(&self, request: HttpRequest) -> Result<HttpResponse, AuthError> {
            self.requests.lock().expect("requests lock").push(request);
            self.responses
                .lock()
                .expect("responses lock")
                .pop_front()
                .ok_or_else(|| AuthError::upstream("missing mock response"))
        }
    }

    fn response(status: u16, body: &str) -> HttpResponse {
        HttpResponse {
            status,
            headers: Vec::new(),
            body: body.as_bytes().to_vec(),
        }
    }

    fn session() -> AuthSession {
        AuthSession {
            access_token: "access".to_string(),
            access_token_expires_at_ms: 120_000,
            refresh_token: "refresh".to_string(),
            refresh_token_expires_at_ms: 240_000,
            role: RoleName::Student,
            user: open_cloud_api::SessionUser {
                account: "2024000000".to_string(),
                real_name: "Alice".to_string(),
                user_id: "u-1".to_string(),
                user_name: "2024000000".to_string(),
            },
        }
    }

    #[tokio::test]
    async fn load_course_detail_reports_missing_course_before_loading_going_sites() {
        let http = MockHttp::with(vec![
            response(
                200,
                r#"{"success":true,"data":{"records":[{"id":"site-1","siteName":"软件测试"}]}}"#,
            ),
            response(502, r#"{"success":false,"msg":"going unavailable"}"#),
        ]);
        let client = AuthClient::new(http.clone(), AuthEndpoints::default());

        let err = load_course_detail(&client, &session(), "missing")
            .await
            .expect_err("missing course wins before going state");

        assert_eq!(err.code, AuthErrorCode::UnknownAuthError);
        assert_eq!(err.message, "未找到课程：missing。");
        assert_eq!(http.request_count(), 1);
    }
}
