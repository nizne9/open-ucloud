use clap::{Parser, Subcommand};
use open_cloud_api::{
    AssignmentDetailResponse, AssignmentListResponse, AssignmentSubmitResponse, AssignmentSummary,
    AssignmentUploadResponse, AttendanceStatusResponse, AuthErrorCode, AuthErrorResponse,
    AuthSessionResponse, ClientCapabilities, CourseActivityResponse, CourseDetailResponse,
    CourseListResponse, CourseResourceDetail, CourseResourceDownloadResponse,
    CourseResourceSummary, CourseResourcesResponse, CourseSite, GoingSite, RoleName,
};
use open_cloud_core::{
    client_capabilities, refresh_session_if_needed, resolve_course_detail, OpenCloudClient,
    OpenCloudEndpoints, ReqwestHttpClient,
};
use open_cloud_store::{
    credential_probe, system_credential_backend, system_credential_persistence, AuthSession,
    CredentialBackend, CredentialProbe, CredentialProbeStatus, SecureSessionStore, StoreError,
    SystemCredentialBackend, SystemSecureSessionStore,
};
use serde::Serialize;
use std::collections::HashSet;
use std::path::{Path, PathBuf};
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
    /// Print the current persisted session summary.
    Session {
        #[arg(long)]
        json: bool,
    },
    /// Print client capability flags.
    Capabilities {
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
    /// List, inspect, upload, and submit assignments.
    Assignments {
        #[command(subcommand)]
        command: AssignmentCommands,
    },
    /// List and download course resources.
    Resources {
        #[command(subcommand)]
        command: ResourceCommands,
    },
    /// Clear the current persisted session.
    Logout {
        #[arg(long)]
        yes: bool,
    },
}

#[derive(Debug, Subcommand)]
pub enum AssignmentCommands {
    /// List assignments for a course.
    List {
        #[arg(long)]
        site: String,
        #[arg(long)]
        site_name: Option<String>,
        #[arg(long, default_value = "")]
        keyword: String,
        #[arg(long)]
        json: bool,
    },
    /// List unfinished assignments for the current user.
    Undone {
        #[arg(long)]
        json: bool,
    },
    /// Show assignment details.
    Detail {
        assignment_id: String,
        #[arg(long)]
        json: bool,
    },
    /// Upload an assignment attachment.
    Upload {
        assignment_id: String,
        #[arg(long)]
        file: PathBuf,
        #[arg(long)]
        yes: bool,
        #[arg(long)]
        json: bool,
    },
    /// Submit assignment content and optional uploaded attachments.
    Submit {
        assignment_id: String,
        #[arg(long, conflicts_with = "content_file")]
        content: Option<String>,
        #[arg(long)]
        content_file: Option<PathBuf>,
        #[arg(long = "attachment")]
        attachments: Vec<String>,
        #[arg(long)]
        yes: bool,
        #[arg(long)]
        json: bool,
    },
}

#[derive(Debug, Subcommand)]
pub enum ResourceCommands {
    /// List resources for a course.
    List {
        #[arg(long)]
        site: String,
        #[arg(long)]
        site_name: Option<String>,
        #[arg(long)]
        json: bool,
    },
    /// Show resource detail and download URL.
    Detail {
        resource_id: String,
        #[arg(long)]
        site: String,
        #[arg(long)]
        site_name: Option<String>,
        #[arg(long)]
        json: bool,
    },
    /// Download one resource file.
    Download {
        resource_id: String,
        #[arg(long)]
        site: String,
        #[arg(long)]
        site_name: Option<String>,
        #[arg(long)]
        out_dir: PathBuf,
        #[arg(long)]
        json: bool,
    },
    /// Download all resources in a course.
    DownloadCourse {
        #[arg(long)]
        site: String,
        #[arg(long)]
        site_name: Option<String>,
        #[arg(long)]
        out_dir: PathBuf,
        #[arg(long)]
        yes: bool,
        #[arg(long)]
        json: bool,
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

pub fn capabilities_report_json() -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(&client_capabilities())
}

pub fn capabilities_report() -> String {
    format_capabilities(&client_capabilities())
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
        Commands::Capabilities { json } => {
            if json {
                println!(
                    "{}",
                    capabilities_report_json()
                        .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
                );
            } else {
                print!("{}", capabilities_report());
            }
            Ok(())
        }
        Commands::Courses { json, with_going } => {
            let http = ReqwestHttpClient::new().map_err(to_response_error)?;
            let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
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
            let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
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
            let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
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
        Commands::Assignments { command } => handle_assignment_command(command, &store).await,
        Commands::Resources { command } => handle_resource_command(command, &store).await,
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
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
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
    client: &OpenCloudClient<C>,
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

async fn handle_assignment_command<B>(
    command: AssignmentCommands,
    store: &SecureSessionStore<B>,
) -> Result<(), CliError>
where
    B: CredentialBackend,
{
    let json = assignment_json_flag(&command);
    if assignment_requires_yes(&command) {
        return cli_error_response(
            error(
                AuthErrorCode::UnknownAuthError,
                "assignment write commands are mutating; rerun with --yes.",
            ),
            json,
        );
    }
    let http = ReqwestHttpClient::new().map_err(to_response_error)?;
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
    let session = load_access_session_or_print(store, &client, json).await?;
    match command {
        AssignmentCommands::List {
            site,
            site_name,
            keyword,
            json,
        } => {
            let response = json_cli_result(
                client
                    .get_course_assignments(
                        &site,
                        site_name.as_deref().unwrap_or_default(),
                        &session.access_token,
                        &keyword,
                    )
                    .await
                    .map_err(to_response_error),
                json,
            )?;
            print_assignment_list(&response, json)?;
        }
        AssignmentCommands::Undone { json } => {
            let response = json_cli_result(
                client
                    .get_undone_assignments(&session.user.user_id, &session.access_token)
                    .await
                    .map_err(to_response_error),
                json,
            )?;
            print_assignment_list(&response, json)?;
        }
        AssignmentCommands::Detail {
            assignment_id,
            json,
        } => {
            let detail = json_cli_result(
                client
                    .get_assignment_detail(&assignment_id, &session.access_token)
                    .await
                    .map_err(to_response_error),
                json,
            )?;
            print_assignment_detail(&detail, json)?;
        }
        AssignmentCommands::Upload {
            assignment_id,
            file,
            json,
            ..
        } => {
            let detail = json_cli_result(
                client
                    .get_assignment_detail(&assignment_id, &session.access_token)
                    .await
                    .map_err(to_response_error),
                json,
            )?;
            if detail.status == open_cloud_api::AssignmentStatus::Expired {
                return cli_error_response(
                    error(
                        AuthErrorCode::UnknownAuthError,
                        "当前作业已截止，不能继续上传附件。",
                    ),
                    json,
                );
            }
            let bytes = json_cli_result(
                std::fs::read(&file)
                    .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string())),
                json,
            )?;
            let file_name = file
                .file_name()
                .and_then(|name| name.to_str())
                .ok_or_else(|| error(AuthErrorCode::UnknownAuthError, "invalid upload file name"));
            let file_name = json_cli_result(file_name, json)?;
            let response = json_cli_result(
                client
                    .upload_assignment_file(
                        &detail,
                        file_name,
                        &bytes,
                        &session.user.user_id,
                        &session.access_token,
                    )
                    .await
                    .map_err(to_response_error),
                json,
            )?;
            print_assignment_upload(&response, json)?;
        }
        AssignmentCommands::Submit {
            assignment_id,
            content,
            content_file,
            attachments,
            json,
            ..
        } => {
            let content = match (content, content_file) {
                (Some(content), None) => content,
                (None, Some(path)) => json_cli_result(
                    std::fs::read_to_string(path)
                        .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string())),
                    json,
                )?,
                (None, None) => String::new(),
                (Some(_), Some(_)) => unreachable!("clap prevents both content inputs"),
            };
            let response = json_cli_result(
                client
                    .submit_assignment(
                        &assignment_id,
                        &session.user.user_id,
                        &content,
                        &attachments,
                        &session.access_token,
                    )
                    .await
                    .map_err(to_response_error),
                json,
            )?;
            print_assignment_submit(&response, json)?;
        }
    }
    Ok(())
}

async fn handle_resource_command<B>(
    command: ResourceCommands,
    store: &SecureSessionStore<B>,
) -> Result<(), CliError>
where
    B: CredentialBackend,
{
    let json = resource_json_flag(&command);
    if resource_requires_yes(&command) {
        return cli_error_response(
            error(
                AuthErrorCode::UnknownAuthError,
                "resource batch download is mutating; rerun with --yes.",
            ),
            json,
        );
    }
    let http = ReqwestHttpClient::new().map_err(to_response_error)?;
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());
    let session = load_access_session_or_print(store, &client, json).await?;
    match command {
        ResourceCommands::List {
            site,
            site_name,
            json,
        } => {
            let response = json_cli_result(
                client
                    .get_course_resources(
                        &site,
                        site_name.as_deref().unwrap_or_default(),
                        &session.user.user_id,
                        &session.access_token,
                    )
                    .await
                    .map_err(to_response_error),
                json,
            )?;
            print_resource_list(&response, json)?;
        }
        ResourceCommands::Detail {
            resource_id,
            site,
            site_name,
            json,
        } => {
            let detail = json_cli_result(
                client
                    .get_resource_detail(
                        &resource_id,
                        &site,
                        site_name.as_deref().unwrap_or_default(),
                        &session.access_token,
                    )
                    .await
                    .map_err(to_response_error),
                json,
            )?;
            print_resource_detail(&detail, json)?;
        }
        ResourceCommands::Download {
            resource_id,
            site,
            site_name,
            out_dir,
            json,
        } => {
            let detail = json_cli_result(
                client
                    .get_resource_detail(
                        &resource_id,
                        &site,
                        site_name.as_deref().unwrap_or_default(),
                        &session.access_token,
                    )
                    .await
                    .map_err(to_response_error),
                json,
            )?;
            let path = json_cli_result(
                download_resource_to_dir(&client, &detail, &out_dir).await,
                json,
            )?;
            let response = CourseResourceDownloadResponse {
                records: vec![detail],
                written_paths: vec![path.display().to_string()],
            };
            print_download_response(&response, json)?;
        }
        ResourceCommands::DownloadCourse {
            site,
            site_name,
            out_dir,
            json,
            ..
        } => {
            let site_name_value = site_name.unwrap_or_default();
            let list = json_cli_result(
                client
                    .get_course_resources(
                        &site,
                        &site_name_value,
                        &session.user.user_id,
                        &session.access_token,
                    )
                    .await
                    .map_err(to_response_error),
                json,
            )?;
            let mut records = Vec::new();
            let mut paths = Vec::new();
            for resource in list.records {
                let detail = json_cli_result(
                    client
                        .get_resource_detail(
                            &resource.resource_id,
                            &site,
                            &site_name_value,
                            &session.access_token,
                        )
                        .await
                        .map_err(to_response_error),
                    json,
                )?;
                let path = json_cli_result(
                    download_resource_to_dir(&client, &detail, &out_dir).await,
                    json,
                )?;
                paths.push(path.display().to_string());
                records.push(detail);
            }
            print_download_response(
                &CourseResourceDownloadResponse {
                    records,
                    written_paths: paths,
                },
                json,
            )?;
        }
    }
    Ok(())
}

async fn load_access_session_or_print<B, C>(
    store: &SecureSessionStore<B>,
    client: &OpenCloudClient<C>,
    json: bool,
) -> Result<AuthSession, CliError>
where
    B: CredentialBackend,
    C: open_cloud_core::HttpClient,
{
    match load_access_session(store, client, now_ms()).await {
        Ok(session) => Ok(session),
        Err(error_response) if json => {
            print_json_error_response(&error_response)?;
            Err(CliError::JsonErrorPrinted(error_response))
        }
        Err(error_response) => Err(error_response.into()),
    }
}

fn json_cli_result<T>(result: Result<T, AuthErrorResponse>, json: bool) -> Result<T, CliError> {
    match result {
        Ok(value) => Ok(value),
        Err(error_response) => match cli_error_response(error_response, json) {
            Err(error) => Err(error),
            Ok(()) => unreachable!("cli_error_response always returns an error"),
        },
    }
}

fn cli_error_response(error_response: AuthErrorResponse, json: bool) -> Result<(), CliError> {
    if json {
        print_json_error_response(&error_response)?;
        return Err(CliError::JsonErrorPrinted(error_response));
    }
    Err(error_response.into())
}

fn assignment_json_flag(command: &AssignmentCommands) -> bool {
    match command {
        AssignmentCommands::List { json, .. }
        | AssignmentCommands::Undone { json }
        | AssignmentCommands::Detail { json, .. }
        | AssignmentCommands::Upload { json, .. }
        | AssignmentCommands::Submit { json, .. } => *json,
    }
}

fn assignment_requires_yes(command: &AssignmentCommands) -> bool {
    match command {
        AssignmentCommands::Upload { yes, .. } | AssignmentCommands::Submit { yes, .. } => !yes,
        _ => false,
    }
}

fn resource_json_flag(command: &ResourceCommands) -> bool {
    match command {
        ResourceCommands::List { json, .. }
        | ResourceCommands::Detail { json, .. }
        | ResourceCommands::Download { json, .. }
        | ResourceCommands::DownloadCourse { json, .. } => *json,
    }
}

fn resource_requires_yes(command: &ResourceCommands) -> bool {
    match command {
        ResourceCommands::DownloadCourse { yes, .. } => !yes,
        _ => false,
    }
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

fn format_capabilities(capabilities: &ClientCapabilities) -> String {
    format!(
        "selfAttendance: {}\nattendanceQrPayloadParsing: {}\n",
        capabilities.self_attendance, capabilities.attendance_qr_payload_parsing
    )
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

fn print_assignment_list(response: &AssignmentListResponse, json: bool) -> Result<(), CliError> {
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(response)
                .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
        );
        return Ok(());
    }
    print!("{}", format_assignment_list(&response.records));
    Ok(())
}

fn print_assignment_detail(detail: &AssignmentDetailResponse, json: bool) -> Result<(), CliError> {
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(detail)
                .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
        );
        return Ok(());
    }
    print!("{}", format_assignment_detail(detail));
    Ok(())
}

fn print_assignment_upload(
    response: &AssignmentUploadResponse,
    json: bool,
) -> Result<(), CliError> {
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(response)
                .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
        );
    } else {
        println!("{}\t{}", response.resource_id, response.file_name);
    }
    Ok(())
}

fn print_assignment_submit(
    response: &AssignmentSubmitResponse,
    json: bool,
) -> Result<(), CliError> {
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(response)
                .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
        );
    } else {
        println!("assignment submitted");
    }
    Ok(())
}

fn print_resource_list(response: &CourseResourcesResponse, json: bool) -> Result<(), CliError> {
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(response)
                .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
        );
        return Ok(());
    }
    print!("{}", format_resource_list(&response.records));
    Ok(())
}

fn print_resource_detail(detail: &CourseResourceDetail, json: bool) -> Result<(), CliError> {
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&open_cloud_api::CourseResourceDetailResponse {
                detail: detail.clone()
            })
            .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
        );
        return Ok(());
    }
    print!("{}", format_resource_detail(detail));
    Ok(())
}

fn print_download_response(
    response: &CourseResourceDownloadResponse,
    json: bool,
) -> Result<(), CliError> {
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(response)
                .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?
        );
    } else {
        for path in &response.written_paths {
            println!("{path}");
        }
    }
    Ok(())
}

pub fn format_assignment_list(assignments: &[AssignmentSummary]) -> String {
    if assignments.is_empty() {
        return "No assignments found.\n".to_string();
    }
    assignments
        .iter()
        .map(|assignment| {
            format!(
                "{}\t{}\t{}\t{}\t{}",
                assignment.id,
                assignment.site_id,
                assignment.site_name,
                assignment.status.as_str(),
                assignment.title
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
        + "\n"
}

pub fn format_assignment_detail(detail: &AssignmentDetailResponse) -> String {
    format!(
        "{}\t{}\t{}\t{}\t{}\t{}\n",
        detail.id,
        detail.site_id,
        detail.site_name,
        detail.status.as_str(),
        detail
            .score
            .map(|score| score.to_string())
            .unwrap_or_default(),
        detail.title
    )
}

pub fn format_resource_list(resources: &[CourseResourceSummary]) -> String {
    if resources.is_empty() {
        return "No resources found.\n".to_string();
    }
    resources
        .iter()
        .map(|resource| {
            format!(
                "{}\t{}\t{}\t{}",
                resource.resource_id,
                resource.site_id,
                resource
                    .size_bytes
                    .map(|size| size.to_string())
                    .unwrap_or_default(),
                resource.name
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
        + "\n"
}

pub fn format_resource_detail(detail: &CourseResourceDetail) -> String {
    format!(
        "{}\t{}\t{}\t{}\n",
        detail.resource_id,
        detail.site_id,
        detail
            .size_bytes
            .map(|size| size.to_string())
            .unwrap_or_default(),
        detail.name
    )
}

async fn download_resource_to_dir<C>(
    client: &OpenCloudClient<C>,
    detail: &CourseResourceDetail,
    out_dir: &Path,
) -> Result<PathBuf, AuthErrorResponse>
where
    C: open_cloud_core::HttpClient,
{
    let url = detail.download_url.as_deref().ok_or_else(|| {
        error(
            AuthErrorCode::UpstreamUnavailable,
            "resource does not have a downloadable URL.",
        )
    })?;
    std::fs::create_dir_all(out_dir)
        .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?;
    let path = next_download_path(out_dir, &detail.name)?;
    let bytes = client
        .download_url_bytes(url)
        .await
        .map_err(to_response_error)?;
    std::fs::write(&path, bytes)
        .map_err(|err| error(AuthErrorCode::UnknownAuthError, err.to_string()))?;
    Ok(path)
}

pub fn next_download_path(out_dir: &Path, file_name: &str) -> Result<PathBuf, AuthErrorResponse> {
    let clean_name = sanitize_file_name(file_name);
    let candidate = out_dir.join(&clean_name);
    if !candidate.exists() {
        return Ok(candidate);
    }
    let path = Path::new(&clean_name);
    let stem = path
        .file_stem()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .unwrap_or("download");
    let extension = path.extension().and_then(|value| value.to_str());
    for index in 1..10_000 {
        let name = match extension {
            Some(extension) => format!("{stem} ({index}).{extension}"),
            None => format!("{stem} ({index})"),
        };
        let candidate = out_dir.join(name);
        if !candidate.exists() {
            return Ok(candidate);
        }
    }
    Err(error(
        AuthErrorCode::UnknownAuthError,
        "could not allocate a non-overwriting download path.",
    ))
}

fn sanitize_file_name(file_name: &str) -> String {
    let cleaned = file_name
        .chars()
        .map(|ch| match ch {
            '/' | '\\' | '\0' => '_',
            other => other,
        })
        .collect::<String>()
        .trim()
        .to_string();
    if cleaned.is_empty() {
        "download".to_string()
    } else {
        cleaned
    }
}

trait AssignmentStatusLabel {
    fn as_str(&self) -> &'static str;
}

impl AssignmentStatusLabel for open_cloud_api::AssignmentStatus {
    fn as_str(&self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Submitted => "submitted",
            Self::Expired => "expired",
        }
    }
}

async fn load_going_sites<C>(
    client: &OpenCloudClient<C>,
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
    client: &OpenCloudClient<C>,
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
    client: &OpenCloudClient<C>,
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
        let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

        let err = load_course_detail(&client, &session(), "missing")
            .await
            .expect_err("missing course wins before going state");

        assert_eq!(err.code, AuthErrorCode::UnknownAuthError);
        assert_eq!(err.message, "未找到课程：missing。");
        assert_eq!(http.request_count(), 1);
    }

    #[test]
    fn json_cli_error_is_marked_as_already_printed() {
        let response = error(AuthErrorCode::UpstreamUnavailable, "upstream failed");

        let err = cli_error_response(response, true).expect_err("json error returns cli error");

        assert!(err.json_error_was_printed());
        assert_eq!(err.response().code, AuthErrorCode::UpstreamUnavailable);
    }
}
