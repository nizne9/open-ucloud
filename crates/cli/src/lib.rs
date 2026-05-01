use clap::{Parser, Subcommand};
use open_cloud_api::{AuthErrorCode, AuthErrorResponse, AuthSessionResponse, RoleName};
use open_cloud_core::{AuthClient, AuthEndpoints, ReqwestHttpClient};
use open_cloud_store::{
    credential_probe, system_credential_backend, system_credential_persistence, AuthSession,
    CredentialBackend, CredentialProbe, CredentialProbeStatus, SecureSessionStore, StoreError,
    SystemCredentialBackend, SystemSecureSessionStore,
};
use serde::Serialize;
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
            eprintln!("{}", error.message);
            1
        }
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

pub async fn run_cli(cli: Cli) -> Result<(), AuthErrorResponse> {
    let store = SystemSecureSessionStore::new(SystemCredentialBackend);
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
                ));
            }
            login_interactive(&store, role, json).await
        }
        Commands::Session { json } => {
            let session = match load_persisted_session(&store, now_ms()) {
                Ok(session) => session,
                Err(error_response) if json => {
                    println!(
                        "{}",
                        serde_json::to_string_pretty(&error_response).map_err(|err| error(
                            AuthErrorCode::UnknownAuthError,
                            err.to_string()
                        ))?
                    );
                    return Ok(());
                }
                Err(error_response) => return Err(error_response),
            };
            let Some(response) = session else {
                let error_response = error(
                    AuthErrorCode::SessionExpired,
                    "No persisted session is available. Run login --interactive first.",
                );
                if json {
                    println!(
                        "{}",
                        serde_json::to_string_pretty(&error_response).map_err(|err| error(
                            AuthErrorCode::UnknownAuthError,
                            err.to_string()
                        ))?
                    );
                    return Ok(());
                }
                return Err(error_response);
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
        Commands::Logout { yes } => {
            if !yes {
                return Err(error(
                    AuthErrorCode::UnknownAuthError,
                    "logout is a mutating command; rerun with --yes.",
                ));
            }
            store.clear_current().map_err(store_error)?;
            println!("stored session cleared");
            Ok(())
        }
    }
}

async fn login_interactive(
    store: &SystemSecureSessionStore,
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
