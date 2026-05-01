use crate::{get_token_expiration_ms, AuthError, HttpClient, OpenCloudClient};
use open_cloud_api::{AuthErrorCode, SessionUser};
use open_cloud_store::{AuthSession, SessionStore};

#[derive(Clone)]
pub struct SessionManager<C, S> {
    auth: OpenCloudClient<C>,
    store: S,
}

impl<C, S> SessionManager<C, S>
where
    C: HttpClient,
    S: SessionStore,
{
    pub fn new(auth: OpenCloudClient<C>, store: S) -> Self {
        Self { auth, store }
    }

    pub async fn resolve_access_token(
        &self,
        session_id: &str,
        now_ms: u64,
    ) -> Result<String, AuthError> {
        let session = self.store.get(session_id, now_ms).ok_or_else(|| {
            AuthError::new(
                AuthErrorCode::SessionExpired,
                "登录会话已失效，请重新登录。",
            )
        })?;
        if session.access_token_expires_at_ms.saturating_sub(now_ms) > 60_000 {
            return Ok(session.access_token);
        }

        let next = refresh_session_if_needed(&self.auth, session, now_ms).await?;
        let access_token = next.access_token.clone();
        let refresh_token_expires_at_ms = next.refresh_token_expires_at_ms;
        self.store
            .update(session_id.to_string(), next, refresh_token_expires_at_ms);
        Ok(access_token)
    }
}

pub async fn refresh_session_if_needed<C>(
    auth: &OpenCloudClient<C>,
    session: AuthSession,
    now_ms: u64,
) -> Result<AuthSession, AuthError>
where
    C: HttpClient,
{
    if session.access_token_expires_at_ms.saturating_sub(now_ms) > 60_000 {
        return Ok(session);
    }

    let roles = auth.get_user_roles(&session.refresh_token).await?;
    let refreshed = auth
        .refresh_user_info(&session.refresh_token, Some(session.role.clone()), &roles)
        .await?;
    let access_token_expires_at_ms = get_token_expiration_ms(&refreshed.access_token)
        .ok_or_else(|| AuthError::new(AuthErrorCode::SessionExpired, "登录会话缺少过期时间。"))?;
    let refresh_token_expires_at_ms = get_token_expiration_ms(&refreshed.refresh_token)
        .ok_or_else(|| AuthError::new(AuthErrorCode::SessionExpired, "登录会话缺少过期时间。"))?;
    Ok(AuthSession {
        access_token: refreshed.access_token,
        access_token_expires_at_ms,
        refresh_token: refreshed.refresh_token,
        refresh_token_expires_at_ms,
        role: session.role,
        user: SessionUser {
            account: refreshed.account,
            real_name: refreshed.real_name,
            user_id: refreshed.user_id,
            user_name: refreshed.user_name,
        },
    })
}
