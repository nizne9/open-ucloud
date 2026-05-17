# Quality Gates

Quality gates are part of the harness. They make agent work repeatable and keep boundaries from drifting.

## Baseline Commands

Once the workspace exists, expected verification is:

```bash
cargo fmt --all
cargo clippy --workspace --all-targets
cargo test --workspace
cargo run -p open-cloud-cli -- --help
cargo run -p open-cloud-cli -- assignments --help
cargo run -p open-cloud-cli -- resources --help
cargo run -p open-cloud-cli -- doctor
```

Flutter work should also run:

```bash
cd apps/client
flutter pub get
dart analyze
flutter test
```

Windows desktop client builds must run on a Windows host. Verify that the Rust
FFI DLL is built before Flutter and copied into the executable directory:

```bash
cargo build -p open-cloud-ffi
cd apps/client
flutter build windows --debug
```

The debug output directory should contain `open_cloud_client.exe`,
`flutter_windows.dll`, `open_cloud_ffi.dll`, and `data/`. Release builds use the
release Rust DLL:

```bash
cargo build --release -p open-cloud-ffi
cd apps/client
flutter build windows --release
```

macOS desktop client builds must run on a macOS host. Verify that the Rust FFI
dylib is built before Flutter and copied into the app bundle:

```bash
cargo build -p open-cloud-ffi
cd apps/client
flutter build macos --debug
```

The debug app bundle should contain:

```text
build/macos/Build/Products/Debug/open_cloud_client.app/Contents/Frameworks/libopen_cloud_ffi.dylib
```

Release builds use the release Rust dylib:

```bash
cargo build --release -p open-cloud-ffi
cd apps/client
flutter build macos --release
```

Android client changes should also verify the Rust FFI library is packaged:

```bash
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cd apps/client
flutter build apk --debug
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libopen_cloud_ffi.so
```

Widget tests should cover current user-visible behavior and active regressions.
When a UI element is removed, delete tests that only assert the old label or
card is absent unless the absence is the product behavior being protected.

FFI API changes should also regenerate Flutter Rust Bridge bindings:

```bash
flutter_rust_bridge_codegen generate
```

Document any new required command in this file and `README.md`.

## Linux Release Credential Matrix

Linux release artifacts must make credential persistence explicit:

| Artifact | Build command | Expected `doctor` fields |
| --- | --- | --- |
| `open-cloud-linux-keyutils` | `cargo build --release -p open-cloud-cli` | `credential backend: keyutils`, `credential persistence: until-reboot`, and `credential status: available` in a working runtime |
| `open-cloud-linux-secret-service` | `cargo build --release -p open-cloud-cli --features linux-secret-service` | `credential backend: secret-service`, `credential persistence: until-delete`, and `credential status: available` in a working desktop runtime |

Run `cargo run -p open-cloud-cli -- doctor` for the default Linux package. Verify the Secret Service build on a native Linux desktop with a DBus session, a Secret Service provider such as GNOME Keyring, KWallet, or KeePassXC, and an unlocked collection. Build hosts may need `libdbus-1-dev` and `pkg-config`; use `linux-secret-service-vendored` only for a release environment that intentionally vendors native dependencies.

## CI/CD Artifact Boundary

GitHub Actions separates verification, temporary packages, and formal releases:

- `.github/workflows/ci.yml` runs baseline Rust and Flutter verification for pull requests and pushes to `main`.
- `.github/workflows/build-artifacts.yml` builds temporary Actions artifacts for `main` and manual test runs. These artifacts are retained for 14 days and are development test packages, not official release packages.
- `.github/workflows/release.yml` publishes only from existing `v*` tags. The upload job is the only job with `contents: write`; all build jobs remain `contents: read`.

Release assets include CLI packages for Linux keyutils, Linux Secret Service, Windows, and macOS, plus unsigned Flutter desktop client packages for Linux, Windows, and macOS. Each asset must have a matching `.sha256` file.

Android release signing is intentionally out of scope until keystore secrets and Gradle release signing are configured. The Android artifact produced by the build workflow is a `debug-signed` APK for development testing only and must not be treated as a formal release asset.

The workflows use maintained major-version action tags such as `actions/checkout@v6`, `actions/cache@v5`, and `subosito/flutter-action@v2` instead of commit SHAs to keep this early CI readable and maintainable. If the project later requires high-assurance release provenance, pin those actions to audited commit SHAs in a dedicated hardening pass.

## Structural Expectations

- `core` must not depend on CLI, FFI, Flutter, Web, or UI state.
- `ffi` exposes a facade with DTOs, not internal Rust types.
- `cli --json` output and error codes are stable contracts.
- Storage must avoid plaintext credentials by default.
- Logs must redact usernames, tokens, cookies, passwords, and upstream session data.
- CLI login must remain interactive unless a future secure credential handoff is explicitly designed.
- Assignment upload, assignment submit, and full-course resource download must keep explicit `--yes` gates.
- Resource downloads must require `--out-dir` and avoid overwriting existing files.
- Secure session persistence must use the platform credential store and return a stable error when unavailable; do not add plaintext fallback storage for tokens.

## Future Mechanical Checks

Add structural tests or custom lints once the workspace is initialized:

- dependency direction checks between crates
- CLI JSON snapshot tests
- file-size or module-size warnings
- secret scanning for fixtures and logs
- documentation freshness checks for command names and module boundaries
