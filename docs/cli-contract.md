# CLI Contract

The CLI is a first-class harness for agents, scripts, and power users. It should be composable, predictable, and safe by default.

## Command Shape

Commands should be verb-first and stable:

```bash
open-cloud doctor
open-cloud login --interactive
open-cloud session --json
open-cloud courses --json
open-cloud assignments --json
open-cloud materials --json
open-cloud logout
```

Use human-readable output by default. Add `--json` for machine output. JSON fields and error codes are public contracts and require tests.

## Agent-Friendly Rules

- `doctor` checks version, config paths, secure storage availability, network reachability, and session state.
- Discovery commands support small default output, `--json`, and stable identifiers.
- Exact-read commands take IDs from discovery output.
- Large payloads and downloads should write files and return paths instead of dumping huge content to stdout.
- Setup/auth failures must explain the missing action without exposing secrets.

## Write Safety

Mutating commands require explicit confirmation or `--yes`. This includes check-in submission, assignment submission, logout, credential clearing, and destructive cache changes. Agents may run read-only commands freely; live writes require user approval.
