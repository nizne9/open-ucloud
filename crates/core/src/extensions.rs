use open_ucloud_api::ClientCapabilities;

/// Protocol-level capability defaults.
///
/// Core supports an explicit, user-triggered check-in. Adapters that should
/// not surface self sign-in (the FFI/Flutter client) deliberately overwrite
/// `self_attendance` when they map these defaults.
pub fn client_capabilities() -> ClientCapabilities {
    ClientCapabilities {
        self_attendance: true,
        attendance_qr_payload_parsing: true,
    }
}
