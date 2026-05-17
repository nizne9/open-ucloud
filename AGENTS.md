# Repository Guidelines

## Purpose

This file is the short entry point for agents. Keep durable project details in `docs/`, not here.

Read these before non-trivial work:

- `docs/architecture.md` for module boundaries and dependency direction.
- `docs/cli-contract.md` for CLI behavior, JSON output, and write-safety rules.
- `docs/task-guidelines.md` for task shape, workflow, and completion reports.
- `docs/quality.md` for verification gates and structural expectations.

Do not store transient plans, chat conclusions, research notes, or issue-specific findings in `AGENTS.md`.

## Direction

This is a client-first Open UCloud project. Rust core and CLI form the first harness; Flutter is the primary user client; Web support is optional and adapter-only.

Keep UI state outside Rust core. Keep FFI facades DTO-oriented; do not expose Rust lifetimes, traits, generics, or internal session types.

## Verification

Once the workspace exists, prefer:

- `cargo fmt --all`
- `cargo clippy --workspace --all-targets`
- `cargo test --workspace`
- `cargo run -p open-cloud-cli -- --help`
- `flutter test` for Flutter changes

Document new required commands in `README.md` and `docs/quality.md`.

## Style & Commits

Use short directory names and full package names. Example: `crates/core` publishes as `open-cloud-core` and imports as `open_cloud_core`.

Rust follows `rustfmt`; Flutter/Dart follows `dart format`. CLI commands should be verb-first, for example `open-cloud courses --json`.

Use the existing concise conventional-style commit messages, for example `feat: add login facade`.

## Security

Never commit real credentials, tokens, cookies, captures, or student data. This is a personal client/self-hosted entry point for legitimate account use; do not add automation for bypassing platform rules, fake location, answer generation, or account delegation.
