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
