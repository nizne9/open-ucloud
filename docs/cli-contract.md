# CLI Contract

The CLI is a first-class harness for agents, scripts, and power users. It should be composable, predictable, and safe by default.

## Command Shape

Commands should be verb-first and stable:

```bash
open-cloud doctor
open-cloud doctor --json
open-cloud login --interactive
open-cloud session --json
open-cloud courses --json
open-cloud courses --with-going --json
open-cloud course <site-id> --json
open-cloud attendance --site <site-id> --json
open-cloud assignments --json
open-cloud materials --json
open-cloud logout
```

Use human-readable output by default. Add `--json` for machine output. JSON fields and error codes are public contracts and require tests.

`login --interactive` verifies the real login chain and stores the session in the system credential store. `session --json` reads that stored session and must not print access tokens, refresh tokens, cookies, passwords, or upstream session data. If secure storage is unavailable or locked, commands return `SECURE_STORAGE_UNAVAILABLE` instead of falling back to plaintext files.

`courses --json` reads the stored session, refreshes an expiring access token through core, and prints:

```json
{
  "records": [
    { "id": "site-1", "siteName": "软件测试" }
  ]
}
```

The human-readable `courses` output prints one `id<TAB>siteName` record per line, or `No courses found.` when the list is empty.

`courses --with-going --json` additionally calls the course activity endpoint and prints:

```json
{
  "records": [
    { "id": "site-1", "siteName": "软件测试" }
  ],
  "goingSites": [
    { "groupId": "group-1", "siteId": "site-1" }
  ]
}
```

The human-readable `courses --with-going` output prints one `id<TAB>siteName<TAB>going|idle` record per line.

`course <site-id> --json` reads the stored session, refreshes an expiring access token through core, resolves the current course by ID, and prints:

```json
{
  "course": { "id": "site-1", "siteName": "软件测试" },
  "goingSite": { "groupId": "group-1", "siteId": "site-1" }
}
```

`goingSite` is `null` when the current course has no in-progress attendance state. The human-readable output prints `id<TAB>siteName<TAB>going|idle`, plus `groupId` as a fourth column when present.

`attendance --site <site-id> --json` is read-only and derives status from the current course activity state:

```json
{
  "siteId": "site-1",
  "siteName": "软件测试",
  "going": true,
  "groupId": "group-1"
}
```

This command does not submit sign-ins, prepare QR signing data, fake location, or generate answers. The human-readable output uses the same `id<TAB>siteName<TAB>going|idle` shape and appends `groupId` only when available.

## Agent-Friendly Rules

- `doctor` checks version, config paths, secure storage availability, network reachability, and session state.
- `doctor` must print stable credential diagnostics:
  - `credential backend: keyutils|secret-service|mock|unknown`
  - `credential persistence: until-reboot|until-delete|process-only|entry-only|unknown`
  - `credential status: available|unavailable`
  - `credential reason: <redacted reason>` only when the runtime probe fails
  - a warning when the selected backend is `mock` or persistence is `process-only`
- `doctor --json` must expose the same credential diagnostics as camelCase fields: `credentialBackend`, `credentialPersistence`, `credentialStatus`, and nullable `credentialReason`.
- `doctor` may write and delete a temporary `doctor-probe` credential entry, but must not read, write, or delete the real `default-session` login entry.
- Discovery commands support small default output, `--json`, and stable identifiers.
- Exact-read commands take IDs from discovery output.
- Large payloads and downloads should write files and return paths instead of dumping huge content to stdout.
- Setup/auth failures must explain the missing action without exposing secrets.

## Write Safety

Mutating commands require explicit confirmation or `--yes`. This includes check-in submission, assignment submission, logout, credential clearing, and destructive cache changes. Agents may run read-only commands freely; live writes require user approval.
