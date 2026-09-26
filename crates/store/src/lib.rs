use open_cloud_api::{RoleName, SessionUser};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use thiserror::Error;

pub const OPEN_CLOUD_KEYRING_SERVICE: &str = "open-cloud";
pub const OPEN_CLOUD_KEYRING_ACCOUNT: &str = "default-session";
pub const OPEN_CLOUD_KEYRING_DOCTOR_ACCOUNT: &str = "doctor-probe";
const OPEN_CLOUD_KEYRING_DOCTOR_PROBE_PASSWORD: &str = "open-cloud-doctor-probe";

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct AuthSession {
    pub access_token: String,
    pub access_token_expires_at_ms: u64,
    pub refresh_token: String,
    pub refresh_token_expires_at_ms: u64,
    pub role: RoleName,
    pub user: SessionUser,
}

pub trait SessionStore: Clone + Send + Sync + 'static {
    fn create(&self, session_id: String, session: AuthSession, expires_at_ms: u64);
    fn get(&self, session_id: &str, now_ms: u64) -> Option<AuthSession>;
    fn update(&self, session_id: String, session: AuthSession, expires_at_ms: u64);
    fn delete(&self, session_id: &str);
}

#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum StoreError {
    #[error("secure storage is unavailable: {0}")]
    Unavailable(String),
    #[error("secure storage payload could not be decoded")]
    Decode(String),
}

#[derive(Clone, Default)]
pub struct MemorySessionStore {
    sessions: Arc<Mutex<HashMap<String, SessionRecord>>>,
}

#[derive(Clone)]
struct SessionRecord {
    expires_at_ms: u64,
    session: AuthSession,
}

impl SessionStore for MemorySessionStore {
    fn create(&self, session_id: String, session: AuthSession, expires_at_ms: u64) {
        self.sessions
            .lock()
            .expect("memory session store lock")
            .insert(
                session_id,
                SessionRecord {
                    expires_at_ms,
                    session,
                },
            );
    }

    fn get(&self, session_id: &str, now_ms: u64) -> Option<AuthSession> {
        let mut sessions = self.sessions.lock().expect("memory session store lock");
        let record = sessions.get(session_id)?;
        if record.expires_at_ms <= now_ms {
            sessions.remove(session_id);
            return None;
        }
        Some(record.session.clone())
    }

    fn update(&self, session_id: String, session: AuthSession, expires_at_ms: u64) {
        self.create(session_id, session, expires_at_ms);
    }

    fn delete(&self, session_id: &str) {
        self.sessions
            .lock()
            .expect("memory session store lock")
            .remove(session_id);
    }
}

pub trait CredentialBackend: Clone + Send + Sync + 'static {
    fn get_password(&self, service: &str, account: &str) -> Result<Option<String>, StoreError>;
    fn set_password(&self, service: &str, account: &str, password: &str) -> Result<(), StoreError>;
    fn delete_password(&self, service: &str, account: &str) -> Result<(), StoreError>;
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CredentialProbe {
    pub status: CredentialProbeStatus,
    pub reason: Option<String>,
}

impl CredentialProbe {
    pub fn available() -> Self {
        Self {
            status: CredentialProbeStatus::Available,
            reason: None,
        }
    }

    pub fn unavailable(reason: impl Into<String>) -> Self {
        Self {
            status: CredentialProbeStatus::Unavailable,
            reason: Some(sanitize_probe_reason(reason.into())),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CredentialProbeStatus {
    Available,
    Unavailable,
}

impl CredentialProbeStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Available => "available",
            Self::Unavailable => "unavailable",
        }
    }
}

fn sanitize_probe_reason(reason: String) -> String {
    reason
        .replace(OPEN_CLOUD_KEYRING_DOCTOR_PROBE_PASSWORD, "[redacted]")
        .replace(['\r', '\n'], " ")
}

#[derive(Clone, Default)]
pub struct SecureSessionStore<B> {
    backend: B,
}

impl<B> SecureSessionStore<B>
where
    B: CredentialBackend,
{
    pub fn new(backend: B) -> Self {
        Self { backend }
    }

    pub fn save_current(&self, session: &AuthSession) -> Result<(), StoreError> {
        let payload = serde_json::to_string(session)
            .map_err(|error| StoreError::Decode(error.to_string()))?;
        self.backend.set_password(
            OPEN_CLOUD_KEYRING_SERVICE,
            OPEN_CLOUD_KEYRING_ACCOUNT,
            &payload,
        )
    }

    pub fn load_current(&self, now_ms: u64) -> Result<Option<AuthSession>, StoreError> {
        let Some(payload) = self
            .backend
            .get_password(OPEN_CLOUD_KEYRING_SERVICE, OPEN_CLOUD_KEYRING_ACCOUNT)?
        else {
            return Ok(None);
        };
        let session = serde_json::from_str::<AuthSession>(&payload)
            .map_err(|error| StoreError::Decode(error.to_string()))?;
        if session.refresh_token_expires_at_ms <= now_ms {
            self.clear_current()?;
            return Ok(None);
        }
        Ok(Some(session))
    }

    pub fn clear_current(&self) -> Result<(), StoreError> {
        self.backend
            .delete_password(OPEN_CLOUD_KEYRING_SERVICE, OPEN_CLOUD_KEYRING_ACCOUNT)
    }
}

#[derive(Clone, Default)]
pub struct SystemCredentialBackend;

impl CredentialBackend for SystemCredentialBackend {
    fn get_password(&self, service: &str, account: &str) -> Result<Option<String>, StoreError> {
        let entry = keyring::Entry::new(service, account).map_err(to_store_error)?;
        match entry.get_password() {
            Ok(password) => Ok(Some(password)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(error) => Err(to_store_error(error)),
        }
    }

    fn set_password(&self, service: &str, account: &str, password: &str) -> Result<(), StoreError> {
        let entry = keyring::Entry::new(service, account).map_err(to_store_error)?;
        entry.set_password(password).map_err(to_store_error)
    }

    fn delete_password(&self, service: &str, account: &str) -> Result<(), StoreError> {
        let entry = keyring::Entry::new(service, account).map_err(to_store_error)?;
        match entry.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(error) => Err(to_store_error(error)),
        }
    }
}

pub type SystemSecureSessionStore = SecureSessionStore<SystemCredentialBackend>;

pub fn credential_probe<B>(backend: &B) -> CredentialProbe
where
    B: CredentialBackend,
{
    if let Err(error) = backend.set_password(
        OPEN_CLOUD_KEYRING_SERVICE,
        OPEN_CLOUD_KEYRING_DOCTOR_ACCOUNT,
        OPEN_CLOUD_KEYRING_DOCTOR_PROBE_PASSWORD,
    ) {
        return CredentialProbe::unavailable(error.to_string());
    }

    match backend.get_password(
        OPEN_CLOUD_KEYRING_SERVICE,
        OPEN_CLOUD_KEYRING_DOCTOR_ACCOUNT,
    ) {
        Ok(Some(value)) if value == OPEN_CLOUD_KEYRING_DOCTOR_PROBE_PASSWORD => {}
        Ok(_) => {
            let _ = backend.delete_password(
                OPEN_CLOUD_KEYRING_SERVICE,
                OPEN_CLOUD_KEYRING_DOCTOR_ACCOUNT,
            );
            return CredentialProbe::unavailable("credential probe read did not match write");
        }
        Err(error) => {
            let _ = backend.delete_password(
                OPEN_CLOUD_KEYRING_SERVICE,
                OPEN_CLOUD_KEYRING_DOCTOR_ACCOUNT,
            );
            return CredentialProbe::unavailable(error.to_string());
        }
    }

    if let Err(error) = backend.delete_password(
        OPEN_CLOUD_KEYRING_SERVICE,
        OPEN_CLOUD_KEYRING_DOCTOR_ACCOUNT,
    ) {
        return CredentialProbe::unavailable(error.to_string());
    }

    CredentialProbe::available()
}

pub fn system_credential_persistence() -> &'static str {
    credential_persistence_label(keyring::default::default_credential_builder().persistence())
}

pub fn system_credential_backend() -> &'static str {
    system_credential_backend_label()
}

fn credential_persistence_label(
    persistence: keyring::credential::CredentialPersistence,
) -> &'static str {
    match persistence {
        keyring::credential::CredentialPersistence::EntryOnly => "entry-only",
        keyring::credential::CredentialPersistence::ProcessOnly => "process-only",
        keyring::credential::CredentialPersistence::UntilReboot => "until-reboot",
        keyring::credential::CredentialPersistence::UntilDelete => "until-delete",
        _ => "unknown",
    }
}

fn system_credential_backend_label() -> &'static str {
    if cfg!(all(target_os = "linux", feature = "linux-secret-service")) {
        "secret-service"
    } else if cfg!(all(target_os = "linux", feature = "desktop-keyring")) {
        "keyutils"
    } else if cfg!(all(target_os = "macos", feature = "desktop-keyring")) {
        "keychain"
    } else if cfg!(all(target_os = "windows", feature = "desktop-keyring")) {
        "credential-manager"
    } else if cfg!(any(
        feature = "desktop-keyring",
        feature = "linux-secret-service"
    )) {
        "unknown"
    } else {
        // keyring falls back to its in-process mock store without platform features.
        "mock"
    }
}

fn to_store_error(error: keyring::Error) -> StoreError {
    StoreError::Unavailable(error.to_string())
}
