# Quality Gates

Quality gates are part of the harness. They make agent work repeatable and keep boundaries from drifting.

## Baseline Commands

Once the workspace exists, expected verification is:

```bash
cargo fmt --all
cargo clippy --workspace --all-targets
cargo test --workspace
cargo run -p open-cloud-cli -- --help
```

Flutter work should also run:

```bash
flutter test
```

Document any new required command in this file and `README.md`.

## Structural Expectations

- `core` must not depend on CLI, FFI, Flutter, Web, or UI state.
- `ffi` exposes a facade with DTOs, not internal Rust types.
- `cli --json` output and error codes are stable contracts.
- Storage must avoid plaintext credentials by default.
- Logs must redact usernames, tokens, cookies, passwords, and upstream session data.

## Future Mechanical Checks

Add structural tests or custom lints once the workspace is initialized:

- dependency direction checks between crates
- CLI JSON snapshot tests
- file-size or module-size warnings
- secret scanning for fixtures and logs
- documentation freshness checks for command names and module boundaries
