# Architecture

Open Cloud is client-first. The first reusable harness is Rust core plus CLI; Flutter is the primary user client; Web is optional and must remain an adapter.

## Module Boundaries

- `crates/core/`: business facts and operations. It currently owns upstream protocol handling, authentication, token refresh, courses, read-only attendance state, user-supplied attendance QR payload parsing, public capability defaults, assignments, and resources.
- `crates/api/`: stable DTOs, command/response shapes, and error codes shared by CLI, FFI, and future adapters.
- `crates/store/`: storage abstractions and implementations for in-memory session storage, system credential-store persistence, and credential backend diagnostics.
- `crates/cli/`: agent-friendly command-line client. It is the first integration surface and smoke-test harness for core.
- `crates/ffi/`: Dart-facing facade for Flutter. It must hide Rust lifetimes, traits, generics, and internal session types.
- `apps/client/`: Flutter UI, navigation, local presentation state, permissions, and platform UX.

The current implemented harness contains `api`, `core`, `store`, `cli`, `ffi`, and the first Linux-focused Flutter client shell.

The FFI adapter coordinates session refreshes inside Rust. Concurrent Dart calls
may carry the same opaque session payload, but only one refresh chain may run for
that principal; later calls reconcile with the newest in-process session before
performing business requests. Download tasks refresh before they are spawned so
polling cannot overwrite secure storage with an older payload.

## Core Internal Boundaries

`crates/core/src/lib.rs` is a public facade only. Keep implementation details in focused modules:

- `client.rs`: `OpenCloudClient` and endpoint configuration shared by core operations.
- `transport.rs`: HTTP request/response abstractions and the reqwest adapter.
- `error.rs`: core error type and stable API error-code mapping.
- `auth.rs`: login, ticket exchange, role lookup, and token refresh protocol.
- `session.rs`: session refresh orchestration using store abstractions.
- `courses.rs`: course list loading and course detail resolution.
- `attendance.rs`: check-in/attendance state loading and pure parsing for user-supplied `checkwork|...` QR payload text.
- `extensions.rs`: client capability defaults shared by adapters.
- `assignments.rs`: assignment list/detail normalization, attachment upload, and assignment submit protocol.
- `resources.rs`: course resource tree flattening, resource detail resolution, preview/download URL lookup, and streamed, non-overwriting file downloads.
- `protocol.rs`: shared UCloud response envelope parsing and primitive value normalization.

Do not move shared transport, client, error, or protocol helpers back into a business module just because one module uses them first.

## Dependency Direction

Core must not depend on CLI, FFI, Flutter, Web, or UI concepts. API must stay DTO-oriented. Store must expose interfaces that core can use without knowing platform details. Adapters depend inward on API/core/store.

## Product Scope

The project is a personal client and self-hosted entry point for regular Open UCloud account use.

Attendance-related core support currently covers course activity status and parsing `checkwork|...` QR payload text for clients that need to display it.

Capability reporting keeps these surfaces explicit: `selfAttendance` describes whether a self-attendance flow is available in the current build, while `attendanceQrPayloadParsing` describes whether adapters can offer pasted QR payload parsing.

## Current Auth Core

The Rust core owns the real login chain: unified auth page initialization, optional captcha image loading, credential POST, ticket extraction, UCloud token exchange, role lookup, role-scoped refresh, JWT expiration parsing, and access-token refresh. Authentication HTML is parsed as a document rather than by tag-string matching, and all response cookies are normalized into the follow-up login request. CLI and future FFI adapters must call this core instead of duplicating protocol logic.

Course and assignment collection endpoints are consumed with bounded pagination. Pages are merged in upstream order, stable identifiers are deduplicated, short pages terminate normally, and repeated full pages terminate defensively instead of causing an unbounded request loop. Reaching the hard page limit with more data is an explicit error rather than a silently truncated success.

The store crate now has two session stores: memory storage for tests and short-lived adapters, and secure session persistence through the operating system credential store for the CLI. If the platform credential backend is unavailable, adapters must surface a storage error instead of writing tokens to plaintext files.
