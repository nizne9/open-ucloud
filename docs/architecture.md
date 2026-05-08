# Architecture

Open Cloud is client-first. The first reusable harness is Rust core plus CLI; Flutter is the primary user client; Web is optional and must remain an adapter.

## Module Boundaries

- `crates/core/`: business facts and operations. It currently owns upstream protocol handling, authentication, token refresh, courses, read-only attendance state, user-supplied attendance QR payload parsing, assignments, and resources.
- `crates/api/`: stable DTOs, command/response shapes, and error codes shared by CLI, FFI, and future adapters.
- `crates/store/`: storage abstractions and implementations for secure storage, SQLite, local cache, and downloaded files.
- `crates/cli/`: agent-friendly command-line client. It is the first integration surface and smoke-test harness for core.
- `crates/ffi/`: Dart-facing facade for Flutter. It must hide Rust lifetimes, traits, generics, and internal session types.
- `apps/client/`: Flutter UI, navigation, local presentation state, permissions, and platform UX.

The current implemented harness contains `api`, `core`, `store`, `cli`, `ffi`, and the first Linux-focused Flutter client shell.

## Core Internal Boundaries

`crates/core/src/lib.rs` is a public facade only. Keep implementation details in focused modules:

- `client.rs`: `OpenCloudClient` and endpoint configuration shared by core operations.
- `transport.rs`: HTTP request/response abstractions and the reqwest adapter.
- `error.rs`: core error type and stable API error-code mapping.
- `auth.rs`: login, ticket exchange, role lookup, and token refresh protocol.
- `session.rs`: session refresh orchestration using store abstractions.
- `courses.rs`: course list loading and course detail resolution.
- `attendance.rs`: check-in/attendance state loading and pure parsing for user-supplied official QR payload text.
- `assignments.rs`: assignment list/detail normalization, attachment upload, and assignment submit protocol.
- `resources.rs`: course resource tree flattening, resource detail resolution, preview/download URL lookup, and raw download bytes.
- `protocol.rs`: shared UCloud response envelope parsing and primitive value normalization.

Do not move shared transport, client, error, or protocol helpers back into a business module just because one module uses them first.

## Dependency Direction

Core must not depend on CLI, FFI, Flutter, Web, or UI concepts. API must stay DTO-oriented. Store must expose interfaces that core can use without knowing platform details. Adapters depend inward on API/core/store.

## Product Boundary

The project is a personal client and self-hosted entry point for legitimate account use. Do not add bypass, fake-location, account delegation, automatic answer generation, or unattended platform-rule evasion features.

The default CLI and Flutter product surface must remain a compliant client. Capabilities that cannot be open-sourced should live in a separate private product workspace rather than in this repository behind feature flags or disabled stubs.

Public attendance support is limited to read-only activity state and pure parsing of an official QR payload that the user has already scanned. This repository must not actively fetch missing QR signing fields, generate attendance QR codes, or submit attendance sign-ins.

## Current Auth Core

The Rust core owns the real login chain: unified auth page initialization, optional captcha image loading, credential POST, ticket extraction, UCloud token exchange, role lookup, role-scoped refresh, JWT expiration parsing, and access-token refresh. CLI and future FFI adapters must call this core instead of duplicating protocol logic.

The store crate now has two session stores: memory storage for tests and short-lived adapters, and secure session persistence through the operating system credential store for the CLI. If the platform credential backend is unavailable, adapters must surface a storage error instead of writing tokens to plaintext files.
