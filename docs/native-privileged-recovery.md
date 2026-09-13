# Native privileged recovery adapter

The v0 consumer retains request/profile/snapshot context before elevation using
the normal session intent journal. `ClientPrivilegedSession` adds
`submitPrivilegedViaLookup` for launch mechanisms such as Windows ShellExecute
that do not supply trusted stdout. Process completion is not operation success.
Exited and uncertain waits are followed by authenticated GetOperation using the
original request UUID. Cancellation, lookup failure, context change or mismatched
results preserve the journal and never replay the command.

`launchClientWindowsRecovery` accepts only `ClientPrivilegedRecovery`, uses the
fixed installed helper path and runs UAC/wait in an isolate. It cannot receive an
alternate executable or IPC endpoint. Shared Windows process/argument-quoting
code is extracted from `main.dart`; its process-level result is explicitly
mapped to exited/canceled/unconfirmed, not runtime recovery completion.

Evidence on 2026-09-13: `app/test/client_privileged_session_test.dart` verifies
exited, unconfirmed, canceled and mismatched outcomes and prevents replay. Go
tests and Flutter analysis pass; the full current Flutter suite passes 190 tests
with 13 skipped. Local Flutter 3.47.0 differs from CI's pinned 3.38.1; analysis and
tests use `--no-pub`, not a fresh pinned CI dependency resolution. grpc 5.1.0 is
declared as a direct test dependency at its existing locked version solely for
the typed ResponseFuture test double; no dependency version is increased.

Remaining: bind the native session panel/application entrypoint to this adapter,
remove the old application recovery path, verify elevation and same-caller
operation lookup in Windows CI, and implement/verify the Linux/macOS elevation
adapters. Elevation under a different OS identity is not assumed to grant the
original user access to another caller's operation. No cross-platform or release
acceptance is claimed from unit tests.

## Native panel binding — 2026-09-13

`ClientSessionPanel` now supplies the fixed Windows adapter by default, or an
explicitly injected platform launcher. Owner trust/local-forget confirmations use
the journaled elevation-and-lookup path; administrators use direct typed RPC.
Shared panels require both runtime capability availability and either current
administrator access or an owner context with an available elevation adapter.
They disclose the system approval prompt before confirmation. Observer access
does not gain these actions. Logout failures never trigger privileged cleanup.

Widget tests in `client_elevation_panel_test.dart` prove explicit confirmation,
fresh identity inspection before trust and observer rejection for local forget. Existing identity/context and
no-logout-fallback tests remain green. Go tests and Flutter analysis pass; the
current full suite passes 195 tests, 13 skipped (same local SDK limitation above).
This binds the native panel, not the still-retired-contract application shell in
`main.dart`; full entrypoint removal/migration and actual UAC acceptance remain.
