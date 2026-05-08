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
open-cloud assignments list --site <site-id> --json
open-cloud assignments undone --json
open-cloud assignments detail <assignment-id> --json
open-cloud assignments upload <assignment-id> --file <path> --yes --json
open-cloud assignments submit <assignment-id> --content <text> --yes --json
open-cloud resources list --site <site-id> --json
open-cloud resources detail <resource-id> --site <site-id> --json
open-cloud resources download <resource-id> --site <site-id> --out-dir <dir> --json
open-cloud resources download-course --site <site-id> --out-dir <dir> --yes --json
open-cloud logout --yes
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

This command does not submit sign-ins, actively fetch or generate QR signing data, fake location, or generate answers. The human-readable output uses the same `id<TAB>siteName<TAB>going|idle` shape and appends `groupId` only when available.

Core and FFI may parse official `checkwork|...` QR payload text that the user has already scanned. The public repository must not derive that payload from course state, generate attendance QR codes, or submit attendance sign-ins.

`assignments list --site <site-id> --json` reads the stored session, refreshes tokens through core, and prints:

```json
{
  "records": [
    {
      "endTime": "2026-05-03 23:59:59",
      "id": "work-1",
      "siteId": "site-1",
      "siteName": "软件测试",
      "source": "course",
      "startTime": "2026-05-01 08:00:00",
      "status": "pending",
      "title": "实验报告"
    }
  ]
}
```

`assignments undone --json` returns the same shape with `source: "undone"`. `assignments detail <assignment-id> --json` returns assignment content, status, score, teacher resources, submitted content, and submitted attachments without tokens.

`assignments upload <assignment-id> --file <path> --yes --json` loads the assignment detail first, rejects missing or expired assignments before uploading, uploads one attachment resource, and prints:

```json
{
  "assignmentId": "work-1",
  "fileName": "report.pdf",
  "previewUrl": "https://files.example/report",
  "resourceId": "resource-1",
  "siteId": "site-1",
  "siteName": "软件测试"
}
```

`assignments submit <assignment-id> --content <text> --attachment <resource-id> --yes --json` submits live assignment content and returns `{ "ok": true }`. Upload and submit commands are mutating and must require `--yes`.

Assignment uploads use RFC 7578-style `multipart/form-data` with a single UTF-8 `filename` parameter. The client must not send `filename*` in multipart part headers. File names containing CR or LF are rejected before any request is sent because they cannot be represented safely in part headers.

`resources list --site <site-id> --json` prints:

```json
{
  "records": [
    {
      "ext": "pdf",
      "name": "课件.pdf",
      "resourceId": "resource-1",
      "siteId": "site-1",
      "siteName": "软件测试",
      "sizeBytes": 1024,
      "updatedAt": "2026-05-02 10:00:00"
    }
  ]
}
```

`resources detail <resource-id> --site <site-id> --json` wraps the detail as `{ "detail": { ... } }` and includes `downloadUrl` when upstream provides one. `resources download` and `resources download-course` require `--out-dir`; they create the directory if needed, do not overwrite existing files, and return `writtenPaths` with the actual saved paths.

## Agent-Friendly Rules

- `doctor` reports local CLI readiness and credential-store diagnostics. Network login is checked during `login --interactive`, not during `doctor`.
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
- Resource file downloads must require explicit `--out-dir`, allocate non-overwriting paths, and return the paths written.
- Setup/auth failures must explain the missing action without exposing secrets.

## Write Safety

Mutating commands require explicit confirmation or `--yes`. This includes check-in submission, assignment upload, assignment submission, full-course batch downloads, logout, credential clearing, and destructive cache changes. Agents may run read-only commands freely; live writes require user approval.
