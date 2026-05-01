use open_cloud_api::{RoleName, SessionUser};
use open_cloud_store::{
    credential_probe, system_credential_backend, system_credential_persistence, AuthSession,
    CredentialBackend, CredentialProbeStatus, SecureSessionStore, StoreError,
    OPEN_CLOUD_KEYRING_ACCOUNT, OPEN_CLOUD_KEYRING_DOCTOR_ACCOUNT, OPEN_CLOUD_KEYRING_SERVICE,
};
use std::sync::{Arc, Mutex};

#[derive(Clone, Default)]
struct MockCredentialBackend {
    value: Arc<Mutex<Option<String>>>,
}

impl CredentialBackend for MockCredentialBackend {
    fn get_password(&self, service: &str, account: &str) -> Result<Option<String>, StoreError> {
        assert_eq!(service, OPEN_CLOUD_KEYRING_SERVICE);
        assert_eq!(account, OPEN_CLOUD_KEYRING_ACCOUNT);
        Ok(self.value.lock().expect("mock lock").clone())
    }

    fn set_password(&self, service: &str, account: &str, password: &str) -> Result<(), StoreError> {
        assert_eq!(service, OPEN_CLOUD_KEYRING_SERVICE);
        assert_eq!(account, OPEN_CLOUD_KEYRING_ACCOUNT);
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

#[test]
fn saves_loads_and_clears_current_session() {
    let store = SecureSessionStore::new(MockCredentialBackend::default());

    store.save_current(&session()).expect("session saves");

    assert_eq!(
        store.load_current(4_000).expect("session loads"),
        Some(session())
    );
    store.clear_current().expect("session clears");
    assert_eq!(
        store.load_current(4_000).expect("missing session loads"),
        None
    );
}

#[test]
fn expired_current_session_is_cleared_on_load() {
    let store = SecureSessionStore::new(MockCredentialBackend::default());
    store.save_current(&session()).expect("session saves");

    assert_eq!(store.load_current(9_100).expect("expired load"), None);
    assert_eq!(store.load_current(4_000).expect("cleared load"), None);
}

#[test]
fn corrupt_current_session_returns_decode_error_without_secret_text() {
    let backend = MockCredentialBackend::default();
    backend
        .set_password(
            OPEN_CLOUD_KEYRING_SERVICE,
            OPEN_CLOUD_KEYRING_ACCOUNT,
            "not-json-refresh-token-like-secret",
        )
        .expect("mock set");
    let store = SecureSessionStore::new(backend);

    let err = store
        .load_current(4_000)
        .expect_err("corrupt payload fails");

    assert!(matches!(err, StoreError::Decode(_)));
    assert!(!err
        .to_string()
        .contains("not-json-refresh-token-like-secret"));
}

#[test]
fn system_credential_backend_uses_stable_release_label() {
    assert!(matches!(
        system_credential_backend(),
        "keyutils" | "secret-service" | "mock" | "unknown"
    ));
}

#[test]
fn system_credential_persistence_uses_stable_release_label() {
    assert!(matches!(
        system_credential_persistence(),
        "until-reboot" | "until-delete" | "process-only" | "entry-only" | "unknown"
    ));
}

#[cfg(all(target_os = "linux", not(feature = "linux-secret-service")))]
#[test]
fn default_linux_backend_is_keyutils_until_reboot() {
    assert_eq!(system_credential_backend(), "keyutils");
    assert_eq!(system_credential_persistence(), "until-reboot");
}

#[derive(Clone, Default)]
struct RecordingCredentialBackend {
    operations: Arc<Mutex<Vec<(String, String, String)>>>,
    value: Arc<Mutex<Option<String>>>,
    fail: Arc<Mutex<Option<StoreError>>>,
}

impl RecordingCredentialBackend {
    fn fail_with(error: StoreError) -> Self {
        Self {
            fail: Arc::new(Mutex::new(Some(error))),
            ..Self::default()
        }
    }
}

impl CredentialBackend for RecordingCredentialBackend {
    fn get_password(&self, service: &str, account: &str) -> Result<Option<String>, StoreError> {
        self.operations.lock().expect("ops lock").push((
            "get".to_string(),
            service.to_string(),
            account.to_string(),
        ));
        if let Some(error) = &*self.fail.lock().expect("fail lock") {
            return Err(error.clone());
        }
        Ok(self.value.lock().expect("value lock").clone())
    }

    fn set_password(&self, service: &str, account: &str, password: &str) -> Result<(), StoreError> {
        self.operations.lock().expect("ops lock").push((
            "set".to_string(),
            service.to_string(),
            account.to_string(),
        ));
        if let Some(error) = &*self.fail.lock().expect("fail lock") {
            return Err(error.clone());
        }
        *self.value.lock().expect("value lock") = Some(password.to_string());
        Ok(())
    }

    fn delete_password(&self, service: &str, account: &str) -> Result<(), StoreError> {
        self.operations.lock().expect("ops lock").push((
            "delete".to_string(),
            service.to_string(),
            account.to_string(),
        ));
        if let Some(error) = &*self.fail.lock().expect("fail lock") {
            return Err(error.clone());
        }
        *self.value.lock().expect("value lock") = None;
        Ok(())
    }
}

#[test]
fn credential_probe_uses_ephemeral_doctor_entry_not_session_entry() {
    let backend = RecordingCredentialBackend::default();

    let probe = credential_probe(&backend);

    assert_eq!(probe.status, CredentialProbeStatus::Available);
    let operations = backend.operations.lock().expect("ops lock");
    assert_eq!(
        operations.as_slice(),
        [
            (
                "set".to_string(),
                OPEN_CLOUD_KEYRING_SERVICE.to_string(),
                OPEN_CLOUD_KEYRING_DOCTOR_ACCOUNT.to_string()
            ),
            (
                "get".to_string(),
                OPEN_CLOUD_KEYRING_SERVICE.to_string(),
                OPEN_CLOUD_KEYRING_DOCTOR_ACCOUNT.to_string()
            ),
            (
                "delete".to_string(),
                OPEN_CLOUD_KEYRING_SERVICE.to_string(),
                OPEN_CLOUD_KEYRING_DOCTOR_ACCOUNT.to_string()
            )
        ]
    );
    assert!(operations
        .iter()
        .all(|(_, _, account)| account != OPEN_CLOUD_KEYRING_ACCOUNT));
}

#[test]
fn credential_probe_reports_unavailable_reason_without_probe_secret() {
    let backend = RecordingCredentialBackend::fail_with(StoreError::Unavailable(
        "backend locked".to_string(),
    ));

    let probe = credential_probe(&backend);

    assert_eq!(probe.status, CredentialProbeStatus::Unavailable);
    assert_eq!(
        probe.reason.as_deref(),
        Some("secure storage is unavailable: backend locked")
    );
    assert!(!probe
        .reason
        .as_deref()
        .unwrap_or_default()
        .contains("open-cloud-doctor-probe"));
}
