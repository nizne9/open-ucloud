use open_cloud_core::{refresh_session_if_needed, AuthError, HttpClient, OpenCloudClient};
use open_cloud_store::AuthSession;
use std::sync::OnceLock;
use tokio::sync::Mutex;

#[derive(Default)]
pub(crate) struct SessionCoordinator {
    current: Mutex<Option<AuthSession>>,
}

impl SessionCoordinator {
    pub(crate) async fn resolve<C>(
        &self,
        client: &OpenCloudClient<C>,
        incoming: AuthSession,
        now_ms: u64,
    ) -> Result<AuthSession, AuthError>
    where
        C: HttpClient,
    {
        let mut current = self.current.lock().await;
        let candidate = current
            .as_ref()
            .filter(|cached| same_principal(cached, &incoming))
            .filter(|cached| cached.refresh_token_expires_at_ms > now_ms)
            .cloned()
            .unwrap_or(incoming);
        let refreshed = refresh_session_if_needed(client, candidate, now_ms).await?;
        *current = Some(refreshed.clone());
        Ok(refreshed)
    }

    pub(crate) async fn replace(&self, session: AuthSession) {
        *self.current.lock().await = Some(session);
    }

    pub(crate) async fn clear(&self) {
        *self.current.lock().await = None;
    }
}

pub(crate) fn shared_session_coordinator() -> &'static SessionCoordinator {
    static COORDINATOR: OnceLock<SessionCoordinator> = OnceLock::new();
    COORDINATOR.get_or_init(SessionCoordinator::default)
}

fn same_principal(left: &AuthSession, right: &AuthSession) -> bool {
    left.user.user_id == right.user.user_id && left.role == right.role
}
