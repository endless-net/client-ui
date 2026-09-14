# Native privileged recovery adapter

Source audit: client-ui `f192138`, 2026-09-14. This document describes current
source and remaining dependencies, not installed-service acceptance.
Local verification: 863 Flutter tests passed, 30 integration tests skipped;
pinned Flutter analyze, Go tests and the 104-requirement coverage check passed.

## Current consumer path

`ClientSessionPanel` supplies `launchClientWindowsRecovery` on Windows and accepts
an explicitly injected launcher on other hosts. Owner trust/local-forget actions
require the corresponding runtime capability, fresh confirmation and an available
launcher. Administrator callers use the typed RPC directly. Observer callers do
not gain either privileged action. Logout failure does not trigger local forget.

`ClientPrivilegedRecovery` accepts only TrustServerIdentity and
ForgetLocalEnrollment. Arguments bind the original request UUID, profile,
expected instance/revision and the complete identity confirmation or explicit
local-forget confirmation. Requests cannot choose an executable, endpoint or
shell. Identity display data are not permission to change trust.

`ClientSession.submit` persists the intention before launch.
`submitPrivilegedViaLookup` then verifies the request kind, mutation context and
active profile. Windows uses the fixed installed path
`C:\Program Files\EndlessNet\endlessnet-client-recovery-helper.exe` and
ShellExecute/UAC in an isolate. UI runtime communication still uses the protected
named pipe directly; the helper is only the explicitly authorized privileged
operation, not an IPC adapter.

Process exit is not runtime success. Exited and unconfirmed launch outcomes are
followed by authenticated GetOperation under the original request ID. The returned
operation must match kind, profile, instance and revision. Canceled authorization,
changed caller/profile context, failed lookup or mismatched result preserve the
intention; they never generate a replacement request or replay the mutation.
A capability or snapshot refresh alone is not treated as a different owner.

The Windows release path resolves the helper from the immutable producer manifest,
checks its installed name/hash, signs the packaged helper and records both hashes
in release provenance. Relevant sources are `scripts/resolve-client-core.ps1`,
`scripts/build-windows-client-msi.ps1`, `scripts/write-release-provenance.ps1` and
`.github/workflows/release.yml`. Source checks do not prove an installed UAC flow.

## Evidence and boundaries

- `app/test/client_privileged_recovery_test.dart`: request binding and response
  validation at the consumer boundary.
- `app/test/client_privileged_session_test.dart`: controlled launch/lookup
  outcomes, retained request and no replay.
- `app/test/client_elevation_panel_test.dart`: explicit trust/local-forget
  confirmation, fresh identity inspection and observer rejection.
- `app/lib/client_session_panel.dart`, `app/lib/client_windows_recovery.dart` and
  `app/lib/client_privileged_session.dart`: production desktop wiring.

The product entrypoint already uses this path; old notes saying shell binding is
still missing are obsolete. Current validation uses the repository-pinned
Flutter 3.38.1. Native UAC display, cancellation under another Windows identity,
operation-lookup authorization, installed helper pairing and real trust/cleanup
outcomes still require separate integration and platform acceptance evidence.

## Dependencies before adding non-Windows launchers

The reviewed producer main is `f77191cfdf60a56889bc8d73c4f48cbaad2840c8`.
Its `proto/client/v0` and `packages/client_api` trees are identical to UI pin
`cd05fcddb858877b10ecefe7b0b4a3819d2c6f3b`. No pin or version change is required.
The reviewed SDK README and IPC contract define desktop local transport and
administrator RPC access; they do not specify a concrete Linux/macOS elevation
launcher and installed helper identity. The UI currently has no such adapter.

A product implementation needs the accepted installation location/service identity,
OS authorization mechanism, allowed operation/argument boundary, cancellation
semantics and correlation/lookup rights when elevation changes OS identity.
Choosing `pkexec`, a shell command or a macOS privileged service without that
contract would invent a distribution and security boundary. These dependencies
belong to the producer/distribution agreement; the UI adapter can be implemented
once those concrete inputs exist. No runtime/helper source is copied into UI.

The mobile SDK explicitly excludes the native bridge. Android/iOS additionally
need the producer-owned service/extension ABI, authenticated caller binding,
platform permission/cancellation and lifecycle rules. Desktop elevation or Unix
sockets cannot stand in for that bridge. Capability absence remains unavailable,
not permission to guess an operation or transport.

These are dependencies of specific privileged/mobile flows. They neither close
the overall source gate nor prevent work on other UI-owned requirements. The full
status remains in [current implementation](client-ui-current-implementation.md)
and [coverage ledger](client-ui-test-coverage.md).
