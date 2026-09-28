# CLI Contract & Specification

The `open-ucloud` command-line interface provides a first-class, scriptable harness for power users, automation pipelines, and autonomous AI agents. This document defines the formal behavioral contract, command shapes, JSON schemas, error codes, and safety guarantees of the CLI.

---

## 1. Core Principles

1. **Verb-First & Composable**: Commands follow a consistent `<noun> <verb>` or `<verb>` structure (e.g., `open-ucloud courses`, `open-ucloud assignments list`).
2. **Dual-Mode Output**:
   - **Human-Readable Mode (Default)**: Clean, tabular, or brief text output tailored for terminal inspection.
   - **Machine-Readable Mode (`--json`)**: Strict JSON schema with stable camelCase properties, predictable arrays, and no decorative terminal markup.
3. **Strict Secret Redaction**: Neither stdout nor stderr ever outputs raw credentials, passwords, JWT tokens, refresh tokens, or upstream session cookies.
4. **Mandatory Write-Safety**: Mutating commands (creating, uploading, submitting, downloading large batches, or deleting data) require explicit interactive confirmation or the `--yes` flag.
5. **No Plaintext Fallback**: If the system credential store is unavailable or locked, commands immediately fail with `SECURE_STORAGE_UNAVAILABLE` rather than creating unencrypted fallback files.

---

## 2. Standard Machine-Readable Formats (`--json`)

### Success Envelopes

JSON responses return flat, strongly-typed objects or resource lists. Collections return a top-level `records` array alongside relevant metadata:

```json
{
  "records": [
    {
      "id": "site-101",
      "siteName": "Distributed Systems"
    }
  ]
}
```

Single-resource commands return the resource directly or wrapped in an identifying key:

```json
{
  "course": {
    "id": "site-101",
    "siteName": "Distributed Systems"
  },
  "goingSite": null
}
```

Mutating operations confirm success with an explicit boolean status:

```json
{
  "ok": true
}
```

### Error Envelope

All machine-readable failures adhere to a uniform schema:

```json
{
  "code": "SESSION_EXPIRED",
  "message": "Your session has expired. Please run 'open-ucloud login --interactive'.",
  "retryAfterSeconds": null
}
```

### Stable Error Code Taxonomy

| Error Code | HTTP / Cause | Meaning & Actionable Resolution |
| --- | --- | --- |
| `SESSION_EXPIRED` | 401 / 403 | Upstream session expired or refresh token invalid. Re-authenticate via `login --interactive`. |
| `SECURE_STORAGE_UNAVAILABLE` | OS Keyring | The system credential backend is missing, locked, or unresponsive. Check `doctor`. |
| `INVALID_INPUT` | 400 / CLI validation | Malformed arguments, invalid IDs, or invalid file paths provided. |
| `NOT_FOUND` | 404 | The requested course, assignment, or resource ID does not exist or is inaccessible. |
| `FILE_SYSTEM` | Local I/O | Failed to read an input file, create target directory, or stream downloaded content. |
| `RATE_LIMITED` | 429 | Upstream request rate limit exceeded. `retryAfterSeconds` will be populated if supplied. |
| `CANCELLED` | User Abort | Operation was aborted due to missing `--yes` flag or negative interactive confirmation. |

---

## 3. Command Reference

### 3.1. System Health & Diagnostics

#### `open-ucloud doctor [--json]`

Inspects local environment readiness, probe keyrings, and reports credential persistence.

- **Human Output**:
  ```text
  open-ucloud doctor
  credential backend: secret-service
  credential persistence: until-delete
  credential status: available
  ```
- **JSON Output (`--json`)**:
  ```json
  {
    "credentialBackend": "secret-service",
    "credentialPersistence": "until-delete",
    "credentialStatus": "available",
    "credentialReason": null
  }
  ```
- **Behavior**: Uses a temporary `doctor-probe` key to verify read/write access. Never modifies or clears the stored session.

#### `open-ucloud capabilities [--json]`

Reports the feature capability flags for the current binary build.

- **JSON Output (`--json`)**:
  ```json
  {
    "selfAttendance": true,
    "attendanceQrPayloadParsing": true
  }
  ```

---

### 3.2. Authentication & Session

#### `open-ucloud login --interactive`

Performs interactive SSO authentication. Prompts securely for username and password without echo.

- **Flags**: `--interactive` (Required. Passwords are never accepted as command-line flags).
- **Behavior**: Performs ticket exchange, requests user roles, obtains JWT, and stores the session in the OS credential store.

#### `open-ucloud session [--json]`

Validates and displays active session metadata.

- **JSON Output (`--json`)**: Returns user role, principal identifier, and session expiration timestamp without exposing tokens.

#### `open-ucloud logout --yes`

Removes stored session credentials from the system credential vault.

- **Flags**: `--yes` (Required for non-interactive execution).

---

### 3.3. Course Discovery

#### `open-ucloud courses [--with-going] [--json]`

Lists active courses for the authenticated user.

- **Options**:
  - `--with-going`: Simultaneously queries active in-progress attendance sessions.
- **Human Output**:
  ```text
  site-101	Distributed Systems	going
  site-102	Database Engineering	idle
  ```
- **JSON Output (`--with-going --json`)**:
  ```json
  {
    "records": [
      { "id": "site-101", "siteName": "Distributed Systems" }
    ],
    "goingSites": [
      { "groupId": "group-55", "siteId": "site-101" }
    ]
  }
  ```

#### `open-ucloud course <site-id> [--json]`

Retrieves detail for a specific course by its site ID.

- **JSON Output (`--json`)**:
  ```json
  {
    "course": { "id": "site-101", "siteName": "Distributed Systems" },
    "goingSite": { "groupId": "group-55", "siteId": "site-101" }
  }
  ```

---

### 3.4. Attendance & Check-in

#### `open-ucloud attendance status --site <site-id> [--json]`
*(Also available as: `open-ucloud attendance --site <site-id> [--json]`)*

Queries whether a course currently has an active check-in window.

- **JSON Output (`--json`)**:
  ```json
  {
    "siteId": "site-101",
    "siteName": "Distributed Systems",
    "going": true,
    "groupId": "group-55"
  }
  ```

#### `open-ucloud attendance sign --site <site-id> --group <group-id> --yes [--json]`

Executes an explicit check-in submission for an active session.

- **Flags**: `--site <id>`, `--group <id>`, `--yes` (Required mutating gate).
- **JSON Output (`--json`)**:
  ```json
  {
    "ok": true,
    "siteId": "site-101",
    "groupId": "group-55"
  }
  ```

#### `open-ucloud attendance qr --site <site-id> --group <group-id> [--json]`

Resolves the parameters required to display the in-progress attendance QR code.

- **JSON Output (`--json`)**:
  ```json
  {
    "attendanceId": "att-9981",
    "siteId": "site-101",
    "groupId": "group-55",
    "createTime": "1714546800"
  }
  ```

---

### 3.5. Assignments

#### `open-ucloud assignments list --site <site-id> [--keyword <text>] [--json]`

Lists assignments belonging to a specific course.

- **Options**: `--keyword <text>` (Filters titles upstream), `--site-name <name>` (Optional caching hint).
- **JSON Output (`--json`)**:
  ```json
  {
    "records": [
      {
        "id": "hw-201",
        "siteId": "site-101",
        "siteName": "Distributed Systems",
        "title": "Raft Consensus Lab",
        "status": "pending",
        "startTime": "2026-05-01 08:00:00",
        "endTime": "2026-05-15 23:59:59",
        "source": "course"
      }
    ]
  }
  ```

#### `open-ucloud assignments undone [--json]`

Returns all pending or uncompleted assignments across all enrolled courses (`source: "undone"`).

#### `open-ucloud assignments detail <assignment-id> [--json]`

Fetches full assignment instructions, teacher attachments, submitted answers, and score/grading feedback.

#### `open-ucloud assignments upload <assignment-id> --file <path> --yes [--json]`

Uploads an attachment file for a specific assignment.

- **Flags**: `--file <path>`, `--yes` (Required mutating gate).
- **Validation**: Verifies assignment exists and is not expired before initiating upload. Rejects file paths with CR/LF characters.
- **JSON Output (`--json`)**:
  ```json
  {
    "assignmentId": "hw-201",
    "resourceId": "res-887",
    "fileName": "lab1_report.pdf",
    "previewUrl": "https://files.ucloud.example/report",
    "siteId": "site-101",
    "siteName": "Distributed Systems"
  }
  ```

#### `open-ucloud assignments submit <assignment-id> [--content <text> | --content-file <path>] [--attachment <resource-id>...] --yes [--json]`

Submits final assignment work.

- **Flags**: `--content` or `--content-file`, `--attachment` (repeatable), `--yes` (Required).
- **JSON Output (`--json`)**: `{ "ok": true }`

---

### 3.6. Course Resources & Downloads

#### `open-ucloud resources list --site <site-id> [--json]`

Retrieves the flattened tree of course resource materials.

- **JSON Output (`--json`)**:
  ```json
  {
    "records": [
      {
        "resourceId": "res-501",
        "siteId": "site-101",
        "siteName": "Distributed Systems",
        "name": "Lecture01.pdf",
        "ext": "pdf",
        "sizeBytes": 2048576,
        "updatedAt": "2026-04-10 14:30:00"
      }
    ]
  }
  ```

#### `open-ucloud resources detail <resource-id> --site <site-id> [--json]`

Fetches metadata and direct download URL for a specific resource.

#### `open-ucloud resources download <resource-id> --site <site-id> --out-dir <dir> [--json]`

Streams a single resource to disk.

- **Flags**: `--out-dir <path>` (Required; created if absent).
- **Collision Protection**: Automatically increments filename suffixes (`file (1).pdf`) if a file with the same name already exists.
- **JSON Output (`--json`)**:
  ```json
  {
    "writtenPaths": [
      "/home/user/downloads/Lecture01.pdf"
    ]
  }
  ```

#### `open-ucloud resources download-course --site <site-id> --out-dir <dir> --yes [--json]`

Batch downloads all materials for a course. Requires `--yes` confirmation.

---

## 4. Agent Interaction Guidelines

Autonomous AI agents calling `open-ucloud` must adhere to the following rules:

1. **Always Use `--json`**: Ensure all command invocations append `--json` for predictable schema consumption.
2. **Handle Non-Zero Exit Codes**: Inspect the `code` field in error payloads. If `SESSION_EXPIRED` is returned, prompt the user for interactive login.
3. **Respect Write Safety**: Never attempt to run mutating commands (`upload`, `submit`, `sign`, `download-course`, `logout`) without ensuring `--yes` is supplied and authorized by the user.
4. **Discover Before Acting**: Use listing commands (`courses`, `assignments list`, `resources list`) to obtain verified IDs before invoking detail or download commands.
