# Attendance Sign And QR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit attendance sign-in and QR generation across Rust core, CLI, FFI, and the Linux-first Flutter client.

**Architecture:** Rust core owns the upstream attendance protocol and returns DTOs from `open-cloud-api`. CLI and FFI refresh sessions and expose stable contracts. Flutter keeps only UI state, calls `OpenCloudGateway`, persists updated opaque session payloads, and renders QR locally.

**Tech Stack:** Rust, Tokio, Clap, serde, Flutter Rust Bridge, Dart, Flutter Riverpod, Material, `qr_flutter`.

---

## File Structure

- Modify `crates/api/src/lib.rs`: add `AttendanceSignResponse` and `AttendanceQrResponse`.
- Modify `crates/core/src/client.rs`: add attendance endpoint URLs to `OpenCloudEndpoints`.
- Modify `crates/core/src/attendance.rs`: add protocol methods for checkout-basic, clock parameter, sign, and QR preparation.
- Modify `crates/core/tests/auth_flow.rs`: add TDD coverage for request shape, error mapping, and QR response normalization.
- Modify `crates/cli/src/lib.rs`: evolve `attendance` into a backward-compatible command with `status`, `sign`, and `qr` modes.
- Modify `crates/cli/tests/cli_contract.rs`: add parsing, `--yes` gating, JSON error, and format tests.
- Modify `crates/ffi/src/api.rs`: add FFI DTOs and public async functions for `attendanceSign` and `attendanceQr`.
- Regenerate `crates/ffi/src/frb_generated.rs` and `crates/ffi/dart/lib/src/rust/*` using `flutter_rust_bridge_codegen generate`.
- Modify `apps/client/pubspec.yaml` and `apps/client/pubspec.lock`: add `qr_flutter`.
- Modify `apps/client/lib/src/open_cloud_gateway.dart`: add gateway methods for attendance sign and QR.
- Modify `apps/client/lib/src/client_controller.dart`: add attendance action state and controller methods.
- Modify `apps/client/lib/src/home_screen.dart`: add course-card attendance buttons and QR dialog.
- Modify `apps/client/test/support/fakes.dart`: add fake gateway responses and call capture.
- Modify `apps/client/test/client_controller_test.dart`: add controller tests for sign and QR.
- Modify `README.md`, `docs/cli-contract.md`, `docs/quality.md`, and `docs/architecture.md`: document the new command contract and changed attendance boundary.

## Task 1: Core Attendance Protocol

**Files:**
- Modify: `crates/api/src/lib.rs`
- Modify: `crates/core/src/client.rs`
- Modify: `crates/core/src/attendance.rs`
- Test: `crates/core/tests/auth_flow.rs`

- [ ] **Step 1: Write failing core tests**

Add tests to `crates/core/tests/auth_flow.rs` near the existing `get_going_sites` tests:

```rust
#[tokio::test]
async fn prepare_attendance_qr_loads_attendance_id_and_clock_param() {
    let http = MockHttp::with(vec![
        response(200, &[], r#"{"success":true,"data":{"attendanceBasicInfo":{"id":"attendance-1"}}}"#),
        response(200, &[], r#"{"success":true,"data":{"data":"clock-param"}}"#),
    ]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let qr = client
        .prepare_attendance_qr("site-1", "group-1", "access-token")
        .await
        .expect("qr payload loads");

    assert_eq!(qr.attendance_id, "attendance-1");
    assert_eq!(qr.site_id, "site-1");
    assert_eq!(qr.group_id, "group-1");
    assert_eq!(qr.create_time, "clock-param");

    let requests = http.requests();
    assert_eq!(requests.len(), 2);
    assert!(requests[0].url.ends_with("/ykt-site/attendancebasicinfo/basic"));
    assert_eq!(body_text(&requests[0]), r#"{"groupId":"group-1","siteId":"site-1"}"#);
    assert!(requests[1].url.ends_with("/ykt-site/common/v2/clock"));
}

#[tokio::test]
async fn sign_attendance_sends_documented_payload() {
    let http = MockHttp::with(vec![
        response(200, &[], r#"{"success":true,"data":{"attendanceBasicInfo":{"id":"attendance-1"}}}"#),
        response(200, &[], r#"{"success":true,"data":{"data":"clock-param"}}"#),
        response(200, &[], r#"{"success":true,"data":{}}"#),
    ]);
    let client = OpenCloudClient::new(http.clone(), OpenCloudEndpoints::default());

    let result = client
        .sign_attendance("site-1", "group-1", "user-1", "access-token")
        .await
        .expect("attendance sign succeeds");

    assert!(result.ok);
    assert_eq!(result.site_id, "site-1");
    assert_eq!(result.group_id, "group-1");
    let request = http.requests().pop().expect("sign request");
    assert!(request.url.ends_with("/ykt-site/attendancedetailinfo/sign"));
    let body: serde_json::Value = serde_json::from_str(body_text(&request)).expect("json body");
    assert_eq!(body["attendanceDetailInfo"]["attendanceId"], "attendance-1");
    assert_eq!(body["attendanceDetailInfo"]["classLessonId"], "group-1");
    assert_eq!(body["attendanceDetailInfo"]["siteId"], "site-1");
    assert_eq!(body["attendanceDetailInfo"]["userId"], "user-1");
    assert_eq!(body["qrCodeCreateTime"], "clock-param");
}

#[tokio::test]
async fn prepare_attendance_qr_rejects_missing_attendance_id() {
    let http = MockHttp::with(vec![response(
        200,
        &[],
        r#"{"success":true,"data":{"attendanceBasicInfo":{"id":""}}}"#,
    )]);
    let client = OpenCloudClient::new(http, OpenCloudEndpoints::default());

    let err = client
        .prepare_attendance_qr("site-1", "group-1", "access-token")
        .await
        .expect_err("missing id fails");

    assert_eq!(err.code, AuthErrorCode::UnknownAuthError);
    assert_eq!(err.message, "未找到签到 ID。");
}
```

- [ ] **Step 2: Run core tests to verify RED**

Run: `cargo test -p open-cloud-core --test auth_flow prepare_attendance_qr -- --nocapture`

Expected: compile failure or test failure because `prepare_attendance_qr`, `sign_attendance`, and DTO fields do not exist.

- [ ] **Step 3: Add API DTOs**

Add to `crates/api/src/lib.rs` after `AttendanceStatusResponse`:

```rust
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AttendanceSignResponse {
    pub ok: bool,
    pub site_id: String,
    pub group_id: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AttendanceQrResponse {
    pub attendance_id: String,
    pub site_id: String,
    pub group_id: String,
    pub create_time: String,
}
```

- [ ] **Step 4: Add endpoint configuration**

Add these fields to `OpenCloudEndpoints` in `crates/core/src/client.rs` and populate defaults:

```rust
pub attendance_basic_url: String,
pub attendance_clock_url: String,
pub attendance_sign_url: String,
```

Default values:

```rust
attendance_basic_url: "https://apiucloud.bupt.edu.cn/ykt-site/attendancebasicinfo/basic".to_string(),
attendance_clock_url: "https://apiucloud.bupt.edu.cn/ykt-site/common/v2/clock".to_string(),
attendance_sign_url: "https://apiucloud.bupt.edu.cn/ykt-site/attendancedetailinfo/sign".to_string(),
```

- [ ] **Step 5: Implement core protocol methods**

In `crates/core/src/attendance.rs`, import the new DTOs:

```rust
use open_cloud_api::{AttendanceQrResponse, AttendanceSignResponse, GoingSite};
```

Add raw payload structs and methods:

```rust
#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "camelCase")]
struct RawCheckoutBasic {
    attendance_basic_info: RawAttendanceBasicInfo,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
struct RawAttendanceBasicInfo {
    id: Option<serde_json::Value>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
struct RawClockParam {
    data: Option<serde_json::Value>,
}
```

Implement helper methods with `UcloudJsonHeaders::new(SWORD_BASIC_AUTH, access_token)`, JSON content type, `parse_ucloud_envelope`, and `value_to_string`. Empty `site_id`, `group_id`, `attendance_id`, or `create_time` must return `AuthError::unknown("...")` with Chinese messages used by tests.

- [ ] **Step 6: Run core tests to verify GREEN**

Run: `cargo test -p open-cloud-core --test auth_flow attendance -- --nocapture`

Expected: all attendance-related tests pass.

- [ ] **Step 7: Commit core protocol**

```bash
git add crates/api/src/lib.rs crates/core/src/client.rs crates/core/src/attendance.rs crates/core/tests/auth_flow.rs
git commit -m "feat: add attendance sign protocol"
```

## Task 2: CLI Contract

**Files:**
- Modify: `crates/cli/src/lib.rs`
- Test: `crates/cli/tests/cli_contract.rs`

- [ ] **Step 1: Write failing CLI tests**

Add to `crates/cli/tests/cli_contract.rs`:

```rust
#[test]
fn attendance_subcommands_parse_status_sign_and_qr() {
    let status = Cli::try_parse_from([
        "open-cloud", "attendance", "status", "--site", "site-1", "--json",
    ])
    .expect("status parses");
    assert!(matches!(status.command, Commands::Attendance { .. }));

    let sign = Cli::try_parse_from([
        "open-cloud", "attendance", "sign", "--site", "site-1", "--group", "group-1", "--yes", "--json",
    ])
    .expect("sign parses");
    assert!(matches!(sign.command, Commands::Attendance { .. }));

    let qr = Cli::try_parse_from([
        "open-cloud", "attendance", "qr", "--site", "site-1", "--group", "group-1", "--json",
    ])
    .expect("qr parses");
    assert!(matches!(qr.command, Commands::Attendance { .. }));
}

#[tokio::test]
async fn attendance_sign_requires_yes_before_session_load() {
    let cli = Cli::try_parse_from([
        "open-cloud", "attendance", "sign", "--site", "site-1", "--group", "group-1",
    ])
    .expect("sign parses");
    let store = SecureSessionStore::new(MockCredentialBackend::default());

    let err = open_cloud_cli::run_cli_with_store(cli, store)
        .await
        .expect_err("missing yes fails");

    assert_eq!(err.response().code, AuthErrorCode::UnknownAuthError);
    assert!(err.response().message.contains("--yes"));
}

#[test]
fn formats_attendance_sign_and_qr() {
    let sign = open_cloud_api::AttendanceSignResponse {
        ok: true,
        site_id: "site-1".to_string(),
        group_id: "group-1".to_string(),
    };
    assert_eq!(open_cloud_cli::format_attendance_sign(&sign), "attendance signed\tsite-1\tgroup-1\n");

    let qr = open_cloud_api::AttendanceQrResponse {
        attendance_id: "attendance-1".to_string(),
        site_id: "site-1".to_string(),
        group_id: "group-1".to_string(),
        create_time: "clock-param".to_string(),
    };
    assert_eq!(
        open_cloud_cli::format_attendance_qr(&qr),
        "attendance-1\tsite-1\tgroup-1\tclock-param\n",
    );
}
```

- [ ] **Step 2: Run CLI tests to verify RED**

Run: `cargo test -p open-cloud-cli --test cli_contract attendance_subcommands_parse_status_sign_and_qr -- --nocapture`

Expected: fails because attendance subcommands and formatters do not exist.

- [ ] **Step 3: Implement CLI command shape**

Replace `Commands::Attendance { site, json }` with a backward-compatible struct:

```rust
Attendance {
    #[command(subcommand)]
    command: Option<AttendanceCommands>,
    #[arg(long)]
    site: Option<String>,
    #[arg(long)]
    json: bool,
}
```

Add:

```rust
#[derive(Debug, Subcommand)]
pub enum AttendanceCommands {
    Status { #[arg(long)] site: String, #[arg(long)] json: bool },
    Sign {
        #[arg(long)] site: String,
        #[arg(long)] group: String,
        #[arg(long)] yes: bool,
        #[arg(long)] json: bool,
    },
    Qr { #[arg(long)] site: String, #[arg(long)] group: String, #[arg(long)] json: bool },
}
```

Update `run_cli_with_store` to dispatch to `handle_attendance_command(command, site, json, &store).await`.

- [ ] **Step 4: Implement CLI attendance handler**

Add a `handle_attendance_command` helper that:

- maps old `attendance --site site-1 --json` to status;
- rejects missing `--site` on old style;
- rejects sign without `--yes` before loading the session;
- loads and refreshes the session once;
- calls `load_attendance_status`, `client.sign_attendance`, or `client.prepare_attendance_qr`;
- prints JSON using `serde_json::to_string_pretty`;
- prints human output through `format_attendance_status`, `format_attendance_sign`, and `format_attendance_qr`.

- [ ] **Step 5: Run CLI tests to verify GREEN**

Run: `cargo test -p open-cloud-cli --test cli_contract attendance -- --nocapture`

Expected: attendance CLI tests pass.

- [ ] **Step 6: Commit CLI contract**

```bash
git add crates/cli/src/lib.rs crates/cli/tests/cli_contract.rs
git commit -m "feat: expose attendance cli actions"
```

## Task 3: FFI Attendance Facade

**Files:**
- Modify: `crates/ffi/src/api.rs`
- Generated: `crates/ffi/src/frb_generated.rs`
- Generated: `crates/ffi/dart/lib/src/rust/api.dart`
- Generated: `crates/ffi/dart/lib/src/rust/frb_generated.dart`
- Generated: `crates/ffi/dart/lib/src/rust/frb_generated.io.dart`
- Generated: `crates/ffi/dart/lib/src/rust/frb_generated.web.dart`

- [ ] **Step 1: Write failing FFI tests if local harness exists**

Check for `#[cfg(test)]` in `crates/ffi/src/api.rs`. If tests already exist, add coverage for `attendance_sign_with_client` and `attendance_qr_with_client`. If no local harness exists, skip Rust unit tests for private FFI helpers and rely on core tests plus Flutter fake-gateway controller tests.

- [ ] **Step 2: Add FFI DTOs and public functions**

Add to `crates/ffi/src/api.rs`:

```rust
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiAttendanceSignResponse {
    pub ok: bool,
    pub site_id: String,
    pub group_id: String,
    pub updated_session_payload: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FfiAttendanceQrResponse {
    pub attendance_id: String,
    pub site_id: String,
    pub group_id: String,
    pub create_time: String,
    pub updated_session_payload: Option<String>,
}
```

Expose:

```rust
pub async fn attendance_sign(
    session_payload: String,
    site_id: String,
    group_id: String,
) -> Result<FfiAttendanceSignResponse, FfiAuthError>

pub async fn attendance_qr(
    session_payload: String,
    site_id: String,
    group_id: String,
) -> Result<FfiAttendanceQrResponse, FfiAuthError>
```

Both helpers must use `refreshed_session`, call the core method, and set `updated_session_payload`.

- [ ] **Step 3: Regenerate FRB bindings**

Run: `flutter_rust_bridge_codegen generate`

Expected: generated Rust and Dart bindings include `attendanceSign`, `attendanceQr`, `FfiAttendanceSignResponse`, and `FfiAttendanceQrResponse`.

- [ ] **Step 4: Run FFI verification**

Run: `cargo test -p open-cloud-ffi --lib`

Expected: FFI crate tests pass.

- [ ] **Step 5: Commit FFI facade**

```bash
git add crates/ffi/src/api.rs crates/ffi/src/frb_generated.rs crates/ffi/dart/lib/src/rust crates/ffi/dart/pubspec.lock
git commit -m "feat: add attendance ffi facade"
```

## Task 4: Flutter Controller And Gateway

**Files:**
- Modify: `apps/client/lib/src/open_cloud_gateway.dart`
- Modify: `apps/client/lib/src/client_controller.dart`
- Modify: `apps/client/test/support/fakes.dart`
- Test: `apps/client/test/client_controller_test.dart`

- [ ] **Step 1: Write failing controller tests**

Add tests to `apps/client/test/client_controller_test.dart`:

```dart
test('signs selected going course and persists refreshed payload', () async {
  final storage = MemorySessionStorage('payload');
  final gateway = FakeOpenCloudGateway(
    session: _session(),
    attendanceSignResponse: const FfiAttendanceSignResponse(
      ok: true,
      siteId: 'site-1',
      groupId: 'group-1',
      updatedSessionPayload: 'sign-payload',
    ),
    courseResponse: const FfiCourseResponse(
      records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
      goingSites: [FfiGoingSite(groupId: 'group-1', siteId: 'site-1')],
    ),
  );
  final container = _container(storage: storage, gateway: gateway);
  await container.read(clientControllerProvider.notifier).bootstrap();

  await container
      .read(clientControllerProvider.notifier)
      .signAttendance(container.read(clientControllerProvider).courses.single);

  expect(gateway.lastAttendanceSignSiteId, 'site-1');
  expect(gateway.lastAttendanceSignGroupId, 'group-1');
  expect(storage.payload, 'sign-payload');
  expect(container.read(clientControllerProvider).attendanceSigningCourseId, isNull);
});

test('loads qr for selected going course and persists refreshed payload', () async {
  final storage = MemorySessionStorage('payload');
  final gateway = FakeOpenCloudGateway(
    session: _session(),
    attendanceQrResponse: const FfiAttendanceQrResponse(
      attendanceId: 'attendance-1',
      siteId: 'site-1',
      groupId: 'group-1',
      createTime: 'clock-param',
      updatedSessionPayload: 'qr-payload',
    ),
  );
  final container = _container(storage: storage, gateway: gateway);

  await container.read(clientControllerProvider.notifier).loadAttendanceQr(
        const CourseItem(id: 'site-1', name: '软件测试', going: true, groupId: 'group-1'),
      );

  final state = container.read(clientControllerProvider);
  expect(gateway.lastAttendanceQrSiteId, 'site-1');
  expect(gateway.lastAttendanceQrGroupId, 'group-1');
  expect(state.attendanceQr?.attendanceId, 'attendance-1');
  expect(storage.payload, 'qr-payload');
  expect(state.attendanceQrLoadingCourseId, isNull);
});
```

- [ ] **Step 2: Run Flutter tests to verify RED**

Run: `cd apps/client && flutter test test/client_controller_test.dart`

Expected: fails because gateway methods, DTO fake fields, and controller state do not exist.

- [ ] **Step 3: Extend gateway**

Add to `OpenCloudGateway` and `FfiOpenCloudGateway`:

```dart
Future<open_cloud_ffi.FfiAttendanceSignResponse> attendanceSign({
  required String sessionPayload,
  required String siteId,
  required String groupId,
});

Future<open_cloud_ffi.FfiAttendanceQrResponse> attendanceQr({
  required String sessionPayload,
  required String siteId,
  required String groupId,
});
```

Implement with `open_cloud_ffi.attendanceSign` and `open_cloud_ffi.attendanceQr`.

- [ ] **Step 4: Extend controller state and methods**

Add fields to `ClientState`:

```dart
this.attendanceSigningCourseId,
this.attendanceQrLoadingCourseId,
this.attendanceQr,
this.attendanceNotice,
```

with matching `final` fields, `copyWith` args, `clearAttendanceQr`, and `clearAttendanceNotice` flags.

Add methods to `ClientController`:

```dart
Future<void> signAttendance(CourseItem course) async
Future<void> loadAttendanceQr(CourseItem course) async
void clearAttendanceQr()
```

Both action methods must reject courses with missing `groupId`, call `_readSessionPayloadForAction`, persist `updatedSessionPayload`, and clear only their own loading course ID in `catch` and `finally` paths.

- [ ] **Step 5: Extend fake gateway**

Add fake response fields and call-capture fields in `apps/client/test/support/fakes.dart`:

```dart
final FfiAttendanceSignResponse attendanceSignResponse;
final FfiAttendanceQrResponse attendanceQrResponse;
String? lastAttendanceSignSiteId;
String? lastAttendanceSignGroupId;
String? lastAttendanceQrSiteId;
String? lastAttendanceQrGroupId;
```

Implement `attendanceSign` and `attendanceQr` by setting captures and returning configured responses.

- [ ] **Step 6: Run controller tests to verify GREEN**

Run: `cd apps/client && flutter test test/client_controller_test.dart`

Expected: controller tests pass.

- [ ] **Step 7: Commit Flutter controller/gateway**

```bash
git add apps/client/lib/src/open_cloud_gateway.dart apps/client/lib/src/client_controller.dart apps/client/test/support/fakes.dart apps/client/test/client_controller_test.dart
git commit -m "feat: add attendance client actions"
```

## Task 5: Flutter UI And QR Rendering

**Files:**
- Modify: `apps/client/pubspec.yaml`
- Modify: `apps/client/pubspec.lock`
- Modify: `apps/client/lib/src/home_screen.dart`
- Test: `apps/client/test/widget_test.dart`

- [ ] **Step 1: Add QR dependency**

Run: `cd apps/client && flutter pub add qr_flutter`

Expected: `pubspec.yaml` and `pubspec.lock` contain `qr_flutter`.

- [ ] **Step 2: Add QR payload helper**

In `home_screen.dart`, add:

```dart
String _attendanceQrPayload(FfiAttendanceQrResponse qr) {
  return '${qr.attendanceId}:${qr.siteId}:${qr.groupId}:${qr.createTime}';
}
```

Import:

```dart
import 'package:qr_flutter/qr_flutter.dart';
```

- [ ] **Step 3: Add UI controls**

In `_CoursePane`, replace the current single `ListTile` card body with a `Column` containing the existing `ListTile` and, for `course.going`, a `ButtonBar` or `Wrap` with:

```dart
OutlinedButton.icon(
  onPressed: state.attendanceSigningCourseId == course.id
      ? null
      : () => controller.signAttendance(course),
  icon: const Icon(Icons.how_to_reg_outlined),
  label: Text(state.attendanceSigningCourseId == course.id ? '签到中' : '签到'),
)
OutlinedButton.icon(
  onPressed: state.attendanceQrLoadingCourseId == course.id
      ? null
      : () async {
          await controller.loadAttendanceQr(course);
          final qr = ref.read(clientControllerProvider).attendanceQr;
          if (qr != null && context.mounted) {
            _showAttendanceQrDialog(context, ref, course, qr);
          }
        },
  icon: const Icon(Icons.qr_code_2_outlined),
  label: Text(state.attendanceQrLoadingCourseId == course.id ? '生成中' : '二维码'),
)
```

- [ ] **Step 4: Add QR dialog**

Add `_showAttendanceQrDialog` that calls `showDialog`, displays `QrImageView(data: _attendanceQrPayload(qr), size: 220)`, and lists `attendanceId`, `siteId`, `groupId`, and `createTime`. Close action calls `controller.clearAttendanceQr()`.

- [ ] **Step 5: Run Flutter checks**

Run: `cd apps/client && dart analyze`

Run: `cd apps/client && flutter test`

Expected: analyzer and Flutter tests pass.

- [ ] **Step 6: Commit Flutter UI**

```bash
git add apps/client/pubspec.yaml apps/client/pubspec.lock apps/client/lib/src/home_screen.dart apps/client/test/widget_test.dart
git commit -m "feat: render attendance controls"
```

## Task 6: Documentation And Full Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/cli-contract.md`
- Modify: `docs/quality.md`

- [ ] **Step 1: Update docs**

Document:

- `open-cloud attendance status --site <site-id> --json`
- `open-cloud attendance sign --site <site-id> --group <group-id> --yes --json`
- `open-cloud attendance qr --site <site-id> --group <group-id> --json`
- the old `attendance --site` compatibility path;
- the safety boundary: explicit user action only, no fake location, no account delegation, no unattended auto-submit.

- [ ] **Step 2: Run formatters**

Run: `cargo fmt --all`

Run: `cd apps/client && dart format lib test`

Expected: commands exit 0.

- [ ] **Step 3: Run targeted verification**

Run:

```bash
cargo test -p open-cloud-core --test auth_flow
cargo test -p open-cloud-cli --test cli_contract
cargo test -p open-cloud-ffi --lib
cd apps/client && dart analyze
cd apps/client && flutter test
```

Expected: all commands exit 0.

- [ ] **Step 4: Run broader verification if time permits**

Run:

```bash
cargo clippy --workspace --all-targets
cargo test --workspace
cargo run -p open-cloud-cli -- --help
cargo run -p open-cloud-cli -- attendance --help
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit docs and verification fixes**

```bash
git add README.md docs/architecture.md docs/cli-contract.md docs/quality.md
git commit -m "docs: update attendance commands"
```

## Self-Review

- Spec coverage: core protocol, CLI contract, FFI session refresh, Flutter controls, QR rendering, docs, and verification are mapped to tasks.
- Placeholder scan: no unresolved placeholders or vague test-only instructions remain.
- Type consistency: DTO names use Rust snake_case fields with serde camelCase and Dart generated camelCase accessors.
- Risk: adding `qr_flutter` needs network access for `flutter pub add` if it is not already cached. If network fails in sandbox, rerun the dependency command with escalation per workspace policy.
