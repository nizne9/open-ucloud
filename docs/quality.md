# Quality Assurance & Verification Gates

Quality gates ensure that autonomous agents and human developers can make changes safely, predictably, and without introducing architectural drift or security regressions.

---

## 1. Baseline Verification Gates

Before submitting pull requests or merging branches, every workspace change must satisfy the baseline verification suite.

### Rust Workspace Verification

```bash
# 1. Format check
cargo fmt --all -- --check

# 2. Strict static analysis (warnings treated as errors in CI)
cargo clippy --workspace --all-targets

# 3. Unit and integration tests
cargo test --workspace

# 4. CLI harness smoke tests
cargo run -p open-ucloud-cli -- --help
cargo run -p open-ucloud-cli -- doctor
cargo run -p open-ucloud-cli -- assignments --help
cargo run -p open-ucloud-cli -- resources --help
```

### Flutter Workspace Verification

```bash
cd apps/client

# 1. Dependency resolution
flutter pub get

# 2. Static analysis
dart analyze

# 3. Widget & unit tests
flutter test

cd ../..
```

---

## 2. Platform-Specific Build & Packaging Gates

### 2.1. Linux Desktop

Build hosts require GTK 3, libsecret, and native compilation tools:
```bash
sudo apt-get install -y clang cmake libgtk-3-dev libsecret-1-dev ninja-build pkg-config
```

#### Credential Packaging Matrix

Linux release artifacts must make credential persistence explicit:

| Artifact Name | Build Command | Credential Backend | Persistence | Recommended Use |
| --- | --- | --- | --- | --- |
| `open-ucloud-linux-keyutils` | `cargo build --release -p open-ucloud-cli` | Linux Kernel `keyutils` | Until reboot | Headless servers, CI runners, WSL |
| `open-ucloud-linux-secret-service` | `cargo build --release -p open-ucloud-cli --features linux-secret-service` | FreeDesktop Secret Service | Until deleted | Native Linux desktops (GNOME, KDE) |

- **Verification**: Run `open-ucloud doctor` to confirm `credentialBackend`, `credentialPersistence`, and `credentialStatus`.
- **Diagnostics Isolation**: The `doctor` command tests credential access using an isolated, temporary `doctor-probe` key. It must never read, overwrite, or delete real session tokens.

---

### 2.2. Windows Desktop

Windows builds must be executed on a Windows host with Visual Studio C++ build tools and the Flutter Windows desktop toolchain:

```powershell
# 1. Build Rust FFI dynamic library
cargo build --release -p open-ucloud-ffi

# 2. Build Flutter Windows bundle
cd apps/client
flutter build windows --release
```

- **Verification**: Ensure `build/windows/x64/runner/Release/` contains `open_ucloud_client.exe`, `flutter_windows.dll`, and `open_ucloud_ffi.dll`.

---

### 2.3. macOS Desktop

macOS builds must be executed on a macOS host with Xcode and Flutter macOS toolchains:

```bash
# 1. Build Rust FFI dynamic library
cargo build --release -p open-ucloud-ffi

# 2. Build Flutter macOS bundle
cd apps/client
flutter build macos --release
```

- **Verification**: Ensure the bundle contains `open_ucloud_client.app/Contents/Frameworks/libopen_ucloud_ffi.dylib`.

---

### 2.4. Android Client

Android builds require the Android SDK, NDK, and Rust Android toolchain targets:

```bash
# 1. Add toolchain targets
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

# 2. Build debug APK
cd apps/client
flutter build apk --debug

# 3. Verify Rust FFI shared library is packaged inside the APK
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libopen_ucloud_ffi.so
```

#### Android Signing & Security Policies

- **Release Signing**: Production APKs must use the project release keystore configured via `apps/client/android/key.properties` (or GitHub Actions `android-release` Environment secrets). If signing configuration is absent, release builds must fail explicitly rather than falling back to debug keys.
- **Backup Exclusion**: Android manifests (`AndroidManifest.xml`) must disable full application backup (`android:allowBackup="false"`) and data extraction rules to prevent session tokens from leaking via Google Drive cloud backup or adb transfer.

---

## 3. FFI & Code Generation Standards

Whenever functions, structs, or types in `crates/ffi` change:

```bash
# Regenerate Dart bindings and FFI bridges
flutter_rust_bridge_codegen generate
```

- All Dart bindings must be committed along with Rust FFI changes.
- FFI facades must remain DTO-oriented; never expose Rust lifetimes, traits, or complex generics to Dart.

---

## 4. Security, MSRV & Dependency Governance

### Minimum Supported Rust Version (MSRV)

- The project enforces **Rust 1.88** as its official MSRV.
- **Rationale**: Flutter Rust Bridge 2.12 requires modern Rust FFI features, while patched releases of the `time` crate addressing denial-of-service security advisories require Rust 1.88.
- CI includes a dedicated MSRV verification job.

### Dependency Auditing & Action Pinning

- **Cargo Audit**: CI runs a locked `cargo-audit` step to intercept vulnerable dependencies.
- **Dependabot**: Configured for weekly automated checks across Cargo crates, Pub packages, and GitHub Actions.
- **GitHub Actions Pinning**: All third-party GitHub Actions must be pinned to full immutable 40-character commit SHAs, accompanied by a trailing major version comment (e.g., `uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4`).

---

## 5. Structural Invariants

1. **Dependency Direction**: `crates/core` must never import UI concepts, CLI dependencies, or Flutter Bridge libraries.
2. **Strict Redaction**: User credentials, passwords, session tokens, and raw cookies must be redacted from all stdout/stderr logging.
3. **Mandatory `--yes` Gates**: Live mutating operations (`assignments upload`, `assignments submit`, `resources download-course`, `logout`) must reject unattended execution unless explicitly approved with `--yes`.
4. **Non-Overwriting File Allocation**: File downloads must require `--out-dir` and allocate collision-free names rather than clobbering existing files.
5. **No Plaintext Fallback**: If secure keyrings are unavailable, raise `SECURE_STORAGE_UNAVAILABLE`; never write tokens to plain text files.
