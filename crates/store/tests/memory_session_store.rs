use open_cloud_api::{RoleName, SessionUser};
use open_cloud_store::{AuthSession, MemorySessionStore, SessionStore};

#[test]
fn stores_and_deletes_memory_sessions() {
    let store = MemorySessionStore::default();
    let session = AuthSession {
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
    };

    store.create("s-1".to_string(), session.clone(), 9_100);

    assert_eq!(store.get("s-1", 4_000), Some(session));
    store.delete("s-1");
    assert_eq!(store.get("s-1", 4_000), None);
}

#[test]
fn expires_memory_sessions_on_read() {
    let store = MemorySessionStore::default();
    store.create(
        "s-1".to_string(),
        AuthSession {
            access_token: "access".to_string(),
            access_token_expires_at_ms: 4_100,
            refresh_token: "refresh".to_string(),
            refresh_token_expires_at_ms: 5_000,
            role: RoleName::Student,
            user: SessionUser {
                account: "2024000000".to_string(),
                real_name: "Alice".to_string(),
                user_id: "u-1".to_string(),
                user_name: "2024000000".to_string(),
            },
        },
        5_000,
    );

    assert_eq!(store.get("s-1", 5_001), None);
    assert_eq!(store.get("s-1", 4_000), None);
}
