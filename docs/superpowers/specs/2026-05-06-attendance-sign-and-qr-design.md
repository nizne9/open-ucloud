# Attendance Sign And QR Design

## Goal

Implement full-platform attendance actions for the Linux-first client: the CLI, Rust core, FFI facade, and Flutter UI can submit a legitimate current-course check-in and generate the platform QR payload for an in-progress attendance session.

## Scope

- Read the current course attendance state from the existing `goingSites` flow.
- Submit attendance only for a user-selected current course with a real `siteId` and `groupId`.
- Generate QR payload data only for a selected current course with a real `siteId` and `groupId`.
- Expose the behavior through CLI commands, FFI DTOs, Flutter controller state, and Flutter UI controls.
- Update durable docs for the new CLI contract and quality checks.

## Non-Goals

- No fake location, location spoofing, account delegation, unattended auto-signing, answer generation, or bypass of platform rules.
- No background polling that submits attendance without an explicit user action.
- No expansion to teacher-side attendance management.
- No web port. `../open-ucloud-web` is a protocol reference only.

## Architecture

`crates/core/src/attendance.rs` remains the protocol owner. It will keep `get_going_sites` and add small operations for checkout-basic lookup, clock/encryption parameter lookup, attendance sign submission, and QR payload preparation. These methods use `OpenCloudEndpoints` entries rather than hard-coded URLs inside callers.

`crates/api` receives DTOs for mutating attendance responses and QR payloads. `crates/cli` maps them to stable JSON and human-readable output. Mutating check-in submission requires `--yes`; QR preparation is read-like but still explicit through a subcommand because it prepares platform signing data.

`crates/ffi` exposes Dart-owned DTOs and keeps session refresh semantics in Rust. Flutter stores only the opaque updated session payload, shows current-course attendance controls in the course pane, and routes all network behavior through `OpenCloudGateway`.

## Protocol Flow

The sign flow is:

1. Use existing course state to obtain `siteId` and `groupId` for an in-progress attendance session.
2. POST `/ykt-site/attendancebasicinfo/basic` with `{ "groupId": "...", "siteId": "..." }`.
3. Extract `attendanceBasicInfo.id` as `attendanceId`.
4. GET `/ykt-site/common/v2/clock` and extract the returned `data`.
5. POST `/ykt-site/attendancedetailinfo/sign` with:

```json
{
  "attendanceDetailInfo": {
    "attendanceId": "attendance-1",
    "classLessonId": "group-1",
    "siteId": "site-1",
    "userId": "user-1"
  },
  "qrCodeCreateTime": "clock-param"
}
```

The QR flow reuses steps 1-4 and returns `{ attendanceId, siteId, groupId, createTime }` to the adapter. Flutter renders the QR locally from a deterministic payload string using a small QR widget dependency such as `qr_flutter`.

## CLI Contract

Keep the old read-only command shape working:

```bash
open-cloud attendance --site <site-id> --json
```

Add subcommands:

```bash
open-cloud attendance status --site <site-id> --json
open-cloud attendance sign --site <site-id> --group <group-id> --yes --json
open-cloud attendance qr --site <site-id> --group <group-id> --json
```

`attendance sign` returns:

```json
{
  "ok": true,
  "siteId": "site-1",
  "groupId": "group-1"
}
```

`attendance qr` returns:

```json
{
  "attendanceId": "attendance-1",
  "siteId": "site-1",
  "groupId": "group-1",
  "createTime": "clock-param"
}
```

## Flutter UX

The course pane remains the attendance entry surface. Each current-course card keeps resource navigation on the main tile. If `going == true`, the card also shows:

- a `签到` button that calls `attendanceSign`;
- a `二维码` button that calls `attendanceQr`;
- a per-course loading state so one active attendance action cannot be mistaken for another course.

Successful sign submission shows a short success message and refreshes courses with going state. QR generation displays a compact dialog or bottom sheet with the selected course name, rendered QR code, and the payload fields needed for manual inspection.

## Error Handling

- Empty `siteId`, `groupId`, missing `attendanceId`, and empty clock parameter are client errors mapped to stable `UNKNOWN_AUTH_ERROR` messages.
- Upstream envelope failures map to `UPSTREAM_UNAVAILABLE` with the upstream message when available.
- Session refresh remains in `crates/ffi` and `crates/cli`; Flutter never manipulates tokens.
- Flutter clears only the active per-course loading state on failure and keeps current course data visible.

## Testing

Use TDD for production behavior:

- Core tests verify request URLs, headers, JSON bodies, normalized QR payload, missing attendance ID, and upstream error mapping.
- CLI tests verify old status compatibility, new subcommand parsing, `sign --yes` gating before session load, JSON error preservation, and human-readable formatting.
- FFI tests verify session refresh propagation for sign and QR when existing FFI test harness supports it.
- Flutter controller tests verify gateway calls use the selected course's `siteId/groupId`, stale course actions do not leak across courses, session payload updates are persisted, success refreshes courses, and failures clear loading flags.

Verification target:

```bash
cargo fmt --all
cargo test -p open-cloud-core --test auth_flow
cargo test -p open-cloud-cli --test cli_contract
cargo test -p open-cloud-ffi --lib
cd apps/client && dart analyze
cd apps/client && flutter test
```
