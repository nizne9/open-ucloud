use open_ucloud_api::ClientCapabilities;

pub fn client_capabilities() -> ClientCapabilities {
    ClientCapabilities {
        self_attendance: false,
        attendance_qr_payload_parsing: true,
    }
}
