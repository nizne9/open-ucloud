use clap::{CommandFactory, Parser};
use open_cloud_api::{AuthErrorCode, RoleName, SessionUser};
use open_cloud_cli::{Cli, Commands};
use open_cloud_store::{
    AuthSession, CredentialBackend, CredentialProbe, SecureSessionStore, StoreError,
    OPEN_CLOUD_KEYRING_ACCOUNT, OPEN_CLOUD_KEYRING_SERVICE,
};
use std::sync::{Arc, Mutex};

#[test]
fn exposes_documented_commands() {
    let mut command = Cli::command();

    command
        .try_get_matches_from_mut(["open-cloud", "doctor"])
        .expect("doctor parses");
    command
        .try_get_matches_from_mut(["open-cloud", "doctor", "--json"])
        .expect("doctor json parses");
    command
        .try_get_matches_from_mut(["open-cloud", "login", "--interactive", "--role", "学生"])
        .expect("login parses");
    command
        .try_get_matches_from_mut(["open-cloud", "session", "--json"])
        .expect("session parses");
    command
        .try_get_matches_from_mut(["open-cloud", "courses", "--json"])
        .expect("courses json parses");
    command
        .try_get_matches_from_mut(["open-cloud", "courses", "--json", "--with-going"])
        .expect("courses with going status parses");
    command
        .try_get_matches_from_mut(["open-cloud", "courses"])
        .expect("courses parses");
    command
        .try_get_matches_from_mut(["open-cloud", "course", "site-1", "--json"])
        .expect("course detail parses");
    command
        .try_get_matches_from_mut(["open-cloud", "attendance", "--site", "site-1", "--json"])
        .expect("attendance status parses");
    command
        .try_get_matches_from_mut(["open-cloud", "logout", "--yes"])
        .expect("logout parses");
}

#[test]
fn logout_requires_explicit_yes() {
    let cli = Cli::try_parse_from(["open-cloud", "logout"]).expect("logout parses");

    assert!(matches!(cli.command, Commands::Logout { yes: false }));
}

#[test]
fn doctor_json_flag_is_explicit() {
    let cli = Cli::try_parse_from(["open-cloud", "doctor", "--json"]).expect("doctor parses");

    assert!(matches!(cli.command, Commands::Doctor { json: true }));
}

#[test]
fn courses_json_flag_is_explicit() {
    let cli = Cli::try_parse_from(["open-cloud", "courses", "--json"]).expect("courses parses");

    assert!(matches!(cli.command, Commands::Courses { json: true, .. }));
}

#[test]
fn courses_with_going_flag_is_explicit() {
    let cli =
        Cli::try_parse_from(["open-cloud", "courses", "--with-going"]).expect("courses parses");

    assert!(matches!(
        cli.command,
        Commands::Courses {
            with_going: true,
            ..
        }
    ));
}

#[test]
fn course_detail_command_captures_site_id() {
    let cli =
        Cli::try_parse_from(["open-cloud", "course", "site-1", "--json"]).expect("course parses");

    assert!(matches!(
        cli.command,
        Commands::Course {
            site_id,
            json: true
        } if site_id == "site-1"
    ));
}

#[test]
fn attendance_status_command_captures_site_id() {
    let cli = Cli::try_parse_from(["open-cloud", "attendance", "--site", "site-1", "--json"])
        .expect("attendance parses");

    assert!(matches!(
        cli.command,
        Commands::Attendance {
            site,
            json: true
        } if site == "site-1"
    ));
}

#[tokio::test]
async fn courses_json_returns_failure_when_session_is_missing() {
    let cli = Cli::try_parse_from(["open-cloud", "courses", "--json"]).expect("courses parses");
    let store = SecureSessionStore::new(MockCredentialBackend::default());

    let err = open_cloud_cli::run_cli_with_store(cli, store)
        .await
        .expect_err("missing session fails");

    assert!(err.json_error_was_printed());
    assert_eq!(err.response().code, AuthErrorCode::SessionExpired);
}

#[tokio::test]
async fn attendance_json_returns_failure_when_session_is_missing() {
    let cli = Cli::try_parse_from(["open-cloud", "attendance", "--site", "site-1", "--json"])
        .expect("attendance parses");
    let store = SecureSessionStore::new(MockCredentialBackend::default());

    let err = open_cloud_cli::run_cli_with_store(cli, store)
        .await
        .expect_err("missing session fails");

    assert!(err.json_error_was_printed());
    assert_eq!(err.response().code, AuthErrorCode::SessionExpired);
}

#[tokio::test]
async fn session_json_returns_failure_when_session_is_missing() {
    let cli = Cli::try_parse_from(["open-cloud", "session", "--json"]).expect("session parses");
    let store = SecureSessionStore::new(MockCredentialBackend::default());

    let err = open_cloud_cli::run_cli_with_store(cli, store)
        .await
        .expect_err("missing session fails");

    assert!(err.json_error_was_printed());
    assert_eq!(err.response().code, AuthErrorCode::SessionExpired);
}

#[derive(Clone, Default)]
struct MockCredentialBackend {
    set_count: Arc<Mutex<usize>>,
    value: Arc<Mutex<Option<String>>>,
    fail: Option<StoreError>,
}

impl CredentialBackend for MockCredentialBackend {
    fn get_password(&self, service: &str, account: &str) -> Result<Option<String>, StoreError> {
        assert_eq!(service, OPEN_CLOUD_KEYRING_SERVICE);
        assert_eq!(account, OPEN_CLOUD_KEYRING_ACCOUNT);
        if let Some(error) = &self.fail {
            return Err(error.clone());
        }
        Ok(self.value.lock().expect("mock lock").clone())
    }

    fn set_password(&self, service: &str, account: &str, password: &str) -> Result<(), StoreError> {
        assert_eq!(service, OPEN_CLOUD_KEYRING_SERVICE);
        assert_eq!(account, OPEN_CLOUD_KEYRING_ACCOUNT);
        *self.set_count.lock().expect("set count lock") += 1;
        *self.value.lock().expect("mock lock") = Some(password.to_string());
        Ok(())
    }

    fn delete_password(&self, service: &str, account: &str) -> Result<(), StoreError> {
        assert_eq!(service, OPEN_CLOUD_KEYRING_SERVICE);
        assert_eq!(account, OPEN_CLOUD_KEYRING_ACCOUNT);
        *self.value.lock().expect("mock lock") = None;
        Ok(())
    }
}

fn session() -> AuthSession {
    AuthSession {
        access_token: "access".to_string(),
        access_token_expires_at_ms: 4_100,
        refresh_token: "refresh".to_string(),
        refresh_token_expires_at_ms: 9_100,
        role: RoleName::Student,
        user: SessionUser {
            account: "2024000000".to_string(),
            real_name: "Alice".to_string(),
            user_id: "u-1".to_string(),
            user_name: "2024000000".to_string(),
        },
    }
}

#[tokio::test]
async fn load_access_session_does_not_rewrite_unexpired_session() {
    let backend = MockCredentialBackend::default();
    let mut current = session();
    current.access_token_expires_at_ms = 120_000;
    *backend.value.lock().expect("mock lock") =
        Some(serde_json::to_string(&current).expect("session serializes"));
    let store = SecureSessionStore::new(backend.clone());
    let client = open_cloud_core::OpenCloudClient::new(
        open_cloud_core::ReqwestHttpClient::new().expect("http client creates"),
        open_cloud_core::OpenCloudEndpoints::default(),
    );

    let response = open_cloud_cli::load_access_session(&store, &client, 4_000)
        .await
        .expect("session loads");

    assert_eq!(response.user.real_name, "Alice");
    assert_eq!(*backend.set_count.lock().expect("set count lock"), 0);
}

#[test]
fn reads_persisted_session_profile_without_tokens() {
    let store = SecureSessionStore::new(MockCredentialBackend::default());
    store.save_current(&session()).expect("session saves");

    let response = open_cloud_cli::load_persisted_session(&store, 4_000)
        .expect("session loads")
        .expect("session exists");
    let json = serde_json::to_value(response).expect("session serializes");

    assert_eq!(json["selectedRole"], "学生");
    assert_eq!(json["user"]["realName"], "Alice");
    assert!(json.get("accessToken").is_none());
    assert!(json.get("refreshToken").is_none());
}

#[test]
fn maps_secure_storage_failures_to_stable_error_code() {
    let store = SecureSessionStore::new(MockCredentialBackend {
        set_count: Arc::default(),
        value: Arc::default(),
        fail: Some(StoreError::Unavailable("backend locked".to_string())),
    });

    let err =
        open_cloud_cli::load_persisted_session(&store, 4_000).expect_err("secure storage fails");

    assert_eq!(err.code, AuthErrorCode::SecureStorageUnavailable);
    assert!(err.message.contains("secure storage is unavailable"));
}

#[test]
fn serializes_auth_errors_for_json_output() {
    let payload = open_cloud_cli::json_error(AuthErrorCode::SecureStorageUnavailable, "locked")
        .expect("json error serializes");

    assert!(payload.contains("\"code\": \"SECURE_STORAGE_UNAVAILABLE\""));
    assert!(payload.contains("\"message\": \"locked\""));
}

#[test]
fn formats_course_list_with_going_status() {
    let courses = vec![
        open_cloud_api::CourseSite {
            id: "site-1".to_string(),
            site_name: "软件测试".to_string(),
        },
        open_cloud_api::CourseSite {
            id: "site-2".to_string(),
            site_name: "操作系统".to_string(),
        },
    ];
    let going_sites = vec![open_cloud_api::GoingSite {
        group_id: "group-1".to_string(),
        site_id: "site-2".to_string(),
    }];

    let output = open_cloud_cli::format_course_list_with_going(&courses, &going_sites);

    assert_eq!(output, "site-1\t软件测试\tidle\nsite-2\t操作系统\tgoing\n");
}

#[test]
fn formats_course_detail_with_going_site() {
    let detail = open_cloud_api::CourseDetailResponse {
        course: open_cloud_api::CourseSite {
            id: "site-1".to_string(),
            site_name: "软件测试".to_string(),
        },
        going_site: Some(open_cloud_api::GoingSite {
            group_id: "group-1".to_string(),
            site_id: "site-1".to_string(),
        }),
    };

    let output = open_cloud_cli::format_course_detail(&detail);

    assert_eq!(output, "site-1\t软件测试\tgoing\tgroup-1\n");
}

#[test]
fn formats_attendance_status_without_group_id() {
    let status = open_cloud_api::AttendanceStatusResponse {
        site_id: "site-1".to_string(),
        site_name: "软件测试".to_string(),
        going: false,
        group_id: None,
    };

    let output = open_cloud_cli::format_attendance_status(&status);

    assert_eq!(output, "site-1\t软件测试\tidle\n");
}

#[test]
fn doctor_report_exposes_credential_backend_and_persistence() {
    let report = open_cloud_cli::doctor_report();

    assert!(report.contains("credential backend: "));
    assert!(report.contains("credential persistence: "));
}

#[test]
fn doctor_report_exposes_runtime_credential_status() {
    let report = open_cloud_cli::doctor_report_from(
        "keyutils",
        "until-reboot",
        CredentialProbe::available(),
    );

    assert!(report.contains("credential status: available"));
}

#[test]
fn doctor_report_exposes_unavailable_runtime_reason_without_probe_secret() {
    let report = open_cloud_cli::doctor_report_from(
        "secret-service",
        "until-delete",
        CredentialProbe::unavailable("backend locked\nopen-cloud-doctor-probe"),
    );

    assert!(report.contains("credential status: unavailable"));
    assert!(report.contains("credential reason: backend locked"));
    assert!(!report.contains("open-cloud-doctor-probe"));
}

#[test]
fn doctor_json_exposes_stable_credential_fields() {
    let payload = open_cloud_cli::doctor_report_json_from(
        "keyutils",
        "until-reboot",
        CredentialProbe::available(),
    )
    .expect("doctor json serializes");
    let json: serde_json::Value = serde_json::from_str(&payload).expect("doctor json parses");

    assert_eq!(json["credentialBackend"], "keyutils");
    assert_eq!(json["credentialPersistence"], "until-reboot");
    assert_eq!(json["credentialStatus"], "available");
    assert!(json["credentialReason"].is_null());
    assert!(json.get("accessToken").is_none());
    assert!(json.get("refreshToken").is_none());
}

#[test]
fn doctor_json_includes_unavailable_reason_without_probe_secret() {
    let payload = open_cloud_cli::doctor_report_json_from(
        "secret-service",
        "until-delete",
        CredentialProbe::unavailable("backend locked\nopen-cloud-doctor-probe"),
    )
    .expect("doctor json serializes");
    let json: serde_json::Value = serde_json::from_str(&payload).expect("doctor json parses");

    assert_eq!(json["credentialStatus"], "unavailable");
    assert_eq!(json["credentialReason"], "backend locked [redacted]");
    assert!(!payload.contains("open-cloud-doctor-probe"));
}
