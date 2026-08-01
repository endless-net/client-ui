# EndlessNet service emulator

The emulator is a standalone test process for the Windows desktop UI. It serves
the checked-in v2 HTTP contract directly over a local Windows named pipe and
does not start the Go runtime client, read runtime state, or expose a TCP port.

The built-in stateful model implements every path in
`contracts/upstream/client-ipc-v2.openapi.yaml`:

- status and finite `application/x-ndjson` event snapshots;
- connect, disconnect, logout, and enrollment transitions, including the
  optional successful-enrollment `wireguard_apply` result;
- server identity inspection and explicit trust recovery;
- network listing and selection;
- redacted diagnostics snapshots with peer-path status, bounded bundle
  metadata, and recent logs.

The OpenAPI privilege metadata is verified by tests: status/events/identity and
network reads are observers; enrollment, connect/disconnect, logout, and network
selection and redacted diagnostics are owner operations; identity trust and
explicit local forget are administrator operations. The emulator does not impersonate Windows SIDs;
authorization failures can be injected as scripted contract errors.

## Quick start

Build and run the hermetic Flutter tests from the repository root:

```powershell
.\scripts\test-ui-with-service-emulator.ps1
```

New Flutter tests can reuse `app/test/support/service_emulator.dart` to start a
unique process with an inline scenario and inspect its redacted interactions.
The helper owns readiness, output draining, shutdown, and temporary cleanup.

For manual UI testing, use two terminals:

```powershell
go run ./tools/service-emulator/cmd/endlessnet-service-emulator `
  --pipe \\.\pipe\endlessnet-service-emulator-dev `
  --scenario ./tools/service-emulator/scenarios/server-identity-changed.json `
  --requests-file ./.artifacts/emulator-requests.jsonl
```

```powershell
Push-Location app
flutter run -d windows -- `
  --ipc-pipe \\.\pipe\endlessnet-service-emulator-dev `
  --show-window
Pop-Location
```

The emulator deliberately refuses `\\.\pipe\endlessnet-service` unless
`--allow-default-pipe` is supplied. Prefer a unique pipe per test worker so
large suites can run independently.

## Scenarios

A scenario is a strict JSON overlay on the built-in connected fixture. Unknown
fields and incompatible schema versions fail at startup. Validate a scenario
without opening a pipe:

```powershell
go run ./tools/service-emulator/cmd/endlessnet-service-emulator `
  --scenario ./tools/service-emulator/scenarios/connect-failure.json `
  --validate-only
```

Top-level fields:

| Field | Purpose |
| --- | --- |
| `schema_version` | Required; currently `1`. |
| `name` | Human-readable scenario name. |
| `initial_status` | Recursive overlay on the initial status. A `null` value removes a field. |
| `networks` | Replaces the built-in network list. |
| `server_identity` | Recursive overlay on the signing identity response. |
| `logs` | Replaces redacted recent log entries. |
| `routes` | Per-method/path scripted response queues. |

Each route has `method`, `path`, `responses`, and optional `repeat_last`.
Responses are consumed atomically, which keeps concurrent tests deterministic.
A response supports:

| Field | Purpose |
| --- | --- |
| `expect_body` | Require exact JSON-object equality before responding. |
| `status` | HTTP status; defaults to `200`. |
| `body` | JSON body. The IPC envelope is added automatically. |
| `raw_body` | Send bytes exactly as written, useful for malformed JSON tests. |
| `content_type` | Override the response content type. |
| `delay_ms` | Delay the response for timeout/loading tests. |
| `close_connection` | Close the pipe without a response. |
| `status_patch` | Recursively update the value returned by later `/status` calls. |

If a scripted queue is exhausted, the emulator returns a contract-shaped
`request_failed` response. This makes unexpected retries visible rather than
silently accepting them.

Ready-to-use examples live in `scenarios/`:

- `enrollment-approval.json` models pending approval followed by enrollment;
- `owner-required.json` rejects an owner operation for a different local user;
- `server-identity-changed.json` drives explicit signing-key recovery;
- `planned-signing-rotation.json` requires administrator trust and enters recovery;
- `server-identity-toctou.json` changes the announced key before confirmation;
- `control-plane-reset-recovery.json` walks the typed recovery states;
- `remote-cleanup-unconfirmed.json` exercises safe explicit local forget;
- `connect-failure.json` injects a delayed control-plane failure.

## Process coordination and request journal

Use `--ready-file` when a test runner needs a race-free readiness signal. The
JSON file contains the PID, pipe, and scenario name. `--max-requests` lets
short-lived tests stop the process after a known number of accepted requests.

`--requests-file` writes one JSON object per completed interaction and flushes
each record immediately. Enrollment tokens, private keys, and authorization
values are always replaced with `<redacted>`. Tests can assert method, target,
body shape, scripted/default dispatch, response status, and ordering without
handling service secrets.
