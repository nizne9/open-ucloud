# Open UCloud

Open UCloud is a client-first, agent-harnessed project for a personal Open UCloud client.

The initial direction is:

- Rust core for business logic and upstream protocol handling.
- Agent-friendly CLI as the first integration and verification surface.
- Flutter as the primary multi-platform user client.
- Optional Web support as an adapter, not the architectural center.

Current workspace:

- `crates/api`: public DTOs, role names, session responses, and auth error codes.
- `crates/core`: `OpenCloudClient` facade, upstream protocol handling, login, role/token refresh, courses, attendance state, assignments, resources, and session access refresh.
- `crates/store`: memory session storage plus system credential-store backed session persistence.
- `crates/cli`: `open-cloud` command-line harness.
- `crates/ffi`: Flutter Rust Bridge facade for Dart-facing authentication, course, assignment, and resource DTOs.
- `apps/client`: Linux-first Flutter client shell with Android and Windows platform runners for login, secure session storage, course listing, assignments, and resources.

The first CLI login is intentionally interactive and persists its session through the system credential store:

```bash
cargo run -p open-cloud-cli -- doctor
cargo run -p open-cloud-cli -- doctor --json
cargo run -p open-cloud-cli -- login --interactive
cargo run -p open-cloud-cli -- session --json
cargo run -p open-cloud-cli -- courses --json
cargo run -p open-cloud-cli -- courses --with-going --json
cargo run -p open-cloud-cli -- course <site-id> --json
cargo run -p open-cloud-cli -- attendance --site <site-id> --json
cargo run -p open-cloud-cli -- assignments list --site <site-id> [--site-name <name>] [--keyword <text>] --json
cargo run -p open-cloud-cli -- assignments undone --json
cargo run -p open-cloud-cli -- assignments detail <assignment-id> --json
cargo run -p open-cloud-cli -- assignments upload <assignment-id> --file <path> --yes --json
cargo run -p open-cloud-cli -- assignments submit <assignment-id> [--content <text>|--content-file <path>] [--attachment <resource-id>] --yes --json
cargo run -p open-cloud-cli -- resources list --site <site-id> [--site-name <name>] --json
cargo run -p open-cloud-cli -- resources detail <resource-id> --site <site-id> [--site-name <name>] --json
cargo run -p open-cloud-cli -- resources download <resource-id> --site <site-id> [--site-name <name>] --out-dir <dir> --json
cargo run -p open-cloud-cli -- resources download-course --site <site-id> [--site-name <name>] --out-dir <dir> --yes --json
cargo run -p open-cloud-cli -- logout --yes
```

`login` does not accept passwords as flags. Stored sessions use the platform credential store through `keyring`; if the platform backend is unavailable or locked, the CLI reports `SECURE_STORAGE_UNAVAILABLE` and does not fall back to plaintext files.

`courses --json` reads the stored session, refreshes the access token when needed, and returns the current student course list as stable DTOs without printing access tokens, refresh tokens, cookies, or upstream session data.

`capabilities --json` does not require a session and reports build capability flags used by adapters, including `selfAttendance` and `attendanceQrPayloadParsing`.

`courses --with-going --json` also queries the current in-progress course attendance state and returns `goingSites` records with `siteId` and `groupId`. The plain-text form prints `id<TAB>siteName<TAB>going|idle`.

The Flutter-facing FFI facade returns opaque session payloads for Dart secure storage. Flutter stores and returns those payloads unchanged; Rust core still owns login, token expiration checks, and token refresh. Regenerate Dart bindings after FFI API changes with:

```bash
flutter_rust_bridge_codegen generate
```

The Flutter client currently targets Linux desktop first. For local development, build the Rust library and run the client:

```bash
cargo build -p open-cloud-ffi
cd apps/client
flutter run -d linux
```

Windows desktop builds must run on a Windows host with Flutter's Windows
desktop toolchain installed. Build the Rust FFI DLL first so the Flutter
Windows bundle can copy it next to `open_cloud_client.exe`:

```bash
cargo build -p open-cloud-ffi
cd apps/client
flutter build windows --debug
```

For release builds:

```bash
cargo build --release -p open-cloud-ffi
cd apps/client
flutter build windows --release
```

Android builds package the Rust FFI library through the Flutter Gradle build.
Install the Android SDK, NDK, and Rust Android targets before building:

```bash
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cd apps/client
flutter build apk --debug
```

The Flutter client uses `file_selector` for Linux desktop file picking and save
locations. Assignment attachment upload reads the user-selected file path through
the Rust FFI boundary. Resource downloads write through Rust so the same
non-overwriting file allocation rules as the CLI are preserved.

`course <site-id> --json` returns one current course plus its optional `goingSite`. `attendance --site <site-id> --json` returns attendance status derived from the current course activity state. Rust core and FFI also expose parsing for `checkwork|...` QR payload text.

`assignments` supports course assignment lists, unfinished assignments, assignment detail, assignment-scoped attachment upload, and explicit assignment submission. Assignment lists accept an optional course name and keyword filter. Submission accepts inline content or `--content-file`, plus zero or more uploaded attachment resource IDs. Upload validates the target assignment before creating an attachment resource. Upload and submit are live write operations and require `--yes`.

`resources` supports course resource lists, resource detail, single-resource download, and explicit full-course batch download. Downloads require `--out-dir`, create the directory if needed, never overwrite existing files, and print or return the actual written paths.

## Linux Credential Packages

Linux releases are split by credential backend instead of silently pretending every build has the same persistence semantics:

| Artifact | Build command | Backend | Persistence | Best for |
| --- | --- | --- | --- | --- |
| `open-cloud-linux-keyutils` | `cargo build --release -p open-cloud-cli` | Linux keyutils | Until reboot | WSL, headless servers, and low-dependency CLI use |
| `open-cloud-linux-secret-service` | `cargo build --release -p open-cloud-cli --features linux-secret-service` | Secret Service | Until delete | Native Linux desktops with a running secret store |

The Secret Service artifact requires a DBus session and a provider such as GNOME Keyring, KWallet, or KeePassXC with an unlocked collection. Building it may also require `libdbus-1-dev` and `pkg-config`; use `--features linux-secret-service-vendored` only when the release environment intentionally needs vendored native dependencies.

Use `open-cloud doctor` to confirm the actual `credential backend`, `credential persistence`, and runtime `credential status` of the binary being run. The runtime probe uses a temporary `doctor-probe` credential entry, not the stored login session.

See:

- [AGENTS.md](AGENTS.md) for contributor and agent entry instructions.
- [docs/architecture.md](docs/architecture.md) for module boundaries.
- [docs/cli-contract.md](docs/cli-contract.md) for CLI behavior.
- [docs/task-guidelines.md](docs/task-guidelines.md) for task workflow.
- [docs/quality.md](docs/quality.md) for quality gates.

## License

MIT. See [LICENSE](LICENSE).
