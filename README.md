# Open UCloud

Open UCloud is a client-first, agent-harnessed project for a personal Open UCloud client.

The initial direction is:

- Rust core for business logic and upstream protocol handling.
- Agent-friendly CLI as the first integration and verification surface.
- Flutter as the primary multi-platform user client.
- Optional Web support as an adapter, not the architectural center.

Current workspace:

- `crates/api`: public DTOs, role names, session responses, and auth error codes.
- `crates/core`: `OpenCloudClient` facade, upstream protocol handling, login, role/token refresh, courses, attendance state, and session access refresh.
- `crates/store`: memory session storage plus system credential-store backed session persistence.
- `crates/cli`: `open-cloud` command-line harness.

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
cargo run -p open-cloud-cli -- logout --yes
```

`login` does not accept passwords as flags. Stored sessions use the platform credential store through `keyring`; if the platform backend is unavailable or locked, the CLI reports `SECURE_STORAGE_UNAVAILABLE` and does not fall back to plaintext files.

`courses --json` reads the stored session, refreshes the access token when needed, and returns the current student course list as stable DTOs without printing access tokens, refresh tokens, cookies, or upstream session data.

`courses --with-going --json` also queries the current in-progress course attendance state and returns `goingSites` records with `siteId` and `groupId`. The plain-text form prints `id<TAB>siteName<TAB>going|idle`.

`course <site-id> --json` returns one current course plus its optional `goingSite`. `attendance --site <site-id> --json` returns read-only attendance status derived from the current course activity state. These commands do not submit sign-ins or prepare QR signing data.

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
