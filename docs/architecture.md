# Architecture

Open Cloud is client-first. The first reusable harness is Rust core plus CLI; Flutter is the primary user client; Web is optional and must remain an adapter.

## Module Boundaries

- `crates/core/`: business facts and operations. It owns upstream protocol handling, authentication, token refresh, courses, check-ins, assignments, and materials.
- `crates/api/`: stable DTOs, command/response shapes, and error codes shared by CLI, FFI, and future adapters.
- `crates/store/`: storage abstractions and implementations for secure storage, SQLite, local cache, and downloaded files.
- `crates/cli/`: agent-friendly command-line client. It is the first integration surface and smoke-test harness for core.
- `crates/ffi/`: Dart-facing facade for Flutter. It must hide Rust lifetimes, traits, generics, and internal session types.
- `apps/client/`: Flutter UI, navigation, local presentation state, permissions, and platform UX.

## Dependency Direction

Core must not depend on CLI, FFI, Flutter, Web, or UI concepts. API must stay DTO-oriented. Store must expose interfaces that core can use without knowing platform details. Adapters depend inward on API/core/store.

## Product Boundary

The project is a personal client and self-hosted entry point for legitimate account use. Do not add bypass, fake-location, account delegation, automatic answer generation, or unattended platform-rule evasion features.
