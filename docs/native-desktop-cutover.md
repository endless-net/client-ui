# Native desktop entrypoint cutover

As of 2026-09-13, `app/lib/main.dart` creates `ClientSession` and
`ClientDesktopApp`, not the retired HTTP controller. Runtime state and mutations
flow through the accepted client.v0 session and its persisted intention journal.
Opening a channel does not enable commands before a validated snapshot. Native
connection failures have no HTTP fallback and expose only a fixed UI message.
Startup enrollment flags are rejected; enrollment belongs to the native panel.

The desktop shell provides explicit reconnect, single-instance show signalling,
close-to-tray and quit. Owner quit with an active profile submits UI_QUIT through
the normal journal. An accepted operation is not reported as completed. If the
notification is not confirmed, the UI requires a separate exit confirmation and
does not replay the operation. Observer/no-profile exit does not mutate owner
intent. The journal path is scoped to the OS home and a hash of the endpoint;
this alone is not evidence of filesystem permission enforcement on all platforms.

`app/test/client_desktop_app_test.dart` covers awaiting the first snapshot,
readiness, sanitized transport failure, explicit reconnect, and declining exit
without a confirmed runtime notification. These are widget/session tests with
desktop plugins disabled, not acceptance of real windows, tray or UAC behaviour.
Local checks use Flutter 3.47.0 and `--no-pub`; CI pins Flutter 3.38.1. No SDK,
dependency, or contract version increase is part of this change.

Local verification on 2026-09-13: Go tests and Flutter analysis passed; the
current working-tree Flutter suite passed 207 tests with 16 skipped. The suite
still includes retired-contract tests and concurrent native exit-node work;
its aggregate result is not a native-only coverage claim.

Remaining work in client-ui: complete the native scenario catalog and release
pairing; complete native shell actions and destination adapters;
validate actual desktop integration and elevation on supported platforms.
Client owns remaining runtime providers/capabilities. System acceptance against
pinned artifacts remains separate. This entrypoint change does not establish
full UF-01–UF-23 coverage or complete the hard cutover goal.

## Retired enrollment elevation removed — 2026-09-13

Removed the old automatic owner-denial-to-UAC enrollment launcher, its token
command-line argument builder and controller injection points. Parsing the
retired `--elevated-enroll` flag now fails. Privileged identity recovery/local
forget are separate explicitly confirmed native operations, not enrollment
fallbacks. Their remaining old controller code is still pending removal.

Old tests expecting automatic elevated enrollment were removed. Native widget
tests in `client_enrollment_denial_test.dart` instead check owner denial without
automatic resubmission, token clearing before dispatch, sanitized failure text,
and observer gating. They do not claim end-to-end OS/process or runtime admission
coverage. The rest of the retired HTTP controller/test suite still needs cutover.

## Retired privileged recovery removed — 2026-09-13

Removed the old request model and launcher that omitted the v0 request UUID,
profile and CAS fields, old UAC result-to-runtime-success inference, and the
logout-error-to-local-forget fallback. Their obsolete dialogs/controller actions
and tests were removed, as was the unused fire-and-forget enrollment process
launcher. Native explicitly confirmed recovery remains available in the current
entrypoint. Remaining direct HTTP bridge/controller methods are not a fallback
for that entrypoint and still require deletion.

Replacement evidence: `client_privileged_recovery_test.dart` checks immutable
arguments and exact operation correlation; `client_privileged_session_test.dart`
checks exited/uncertain/canceled/mismatched results and now context changes during
elevation and launcher exceptions, preserving the journal without replay;
`client_elevation_panel_test.dart` checks owner confirmation and observer gating;
the US-08 scenario in `mobile_contract_widget_test.dart` checks that failed logout
never triggers local forget. These do not replace real platform UAC acceptance.

## Native tray commands — 2026-09-13

`ClientTray` projects runtime status and Connect/Disconnect from the native
snapshot. The desktop shell binds actions to `ClientSession.submit`, sharing the
same request journal as window actions. Menu action keys expire on state changes;
stale OS clicks cannot target a newly selected profile/caller. Connect requires
current owner/admin access, a profile, connection capability and an eligible
state. Disconnect remains available during connect/recovery, with authorization
still enforced by the producer. Quit/reconnect temporarily disable tray commands.
Accepted operations are not displayed as completed. The shell serializes menu
updates and clears commands when the subscription loses ready state.

`client_tray_test.dart` covers stale menu keys, observer/capability gating,
disconnect during connect, duplicate queued clicks, context changes during an
operation and sanitized errors. Tests use native projections with injected
actions, not real OS tray clicks. Window/session tests and durable journal tests
remain separate evidence; OS integration and release acceptance remain pending.

The subsequent emulator removal, pinned native host wiring and unfulfilled
scenario coverage are recorded in [Native v0 scenario host](native-scenario-host.md).

## HTTP UI implementation removed — 2026-09-13

Removed `named_pipe_http.dart`, `service_contract.dart`, the old bridge,
controller, widgets and HTTP envelope/transport tests. `main.dart` now contains
only native startup, logging and single-instance support. Startup validates the
local endpoint, rejects missing/unknown/retired options without echoing input,
uses platform-neutral home-relative paths and limits the FindWindow call to
Windows. Enrollment URLs/tokens are not accepted as startup mutations; the MSI
deep-link registration still requires a native, explicit-confirmation design.

Replacement evidence is split by responsibility: `client_startup_test.dart`
covers endpoint/defaults/options/redaction/quoting; `client_desktop_app_test.dart`
and `client_tray_test.dart` cover the shell; native snapshot/event/operation tests
cover projections; `mobile_contract_widget_test.dart` covers shared actions;
local transport and session process suites replace HTTP framing checks.
Removal does not prove former peer-path UI layout and broad multi-command
transport scenario parity. Those checks must use the native diagnostics/catalogs
and remain part of system coverage work. The upstream OpenAPI file still exists
solely for unconverted release pairing, not for application runtime use.

Local validation: Go tests, Flutter analysis and 180 Flutter tests passed;
14 process/platform cases were skipped without the native host. The same local
SDK versus pinned-CI limitation applies. Full 104-ID trace scope remains intact,
with zero of 14 scenarios claimed complete. CI was queued at inspection time.

## Native Windows release pairing — 2026-09-13

The resolver now requires IPC v0 and raw `client-v0.binpb` SHA-256 equal to the
consumer identity in `contracts/client-v0.json`. A Dart test compares that record
with the resolved generated SDK. Old v2 manifests and tampered/mismatched
descriptors fail closed. Executable attestations and immutable release/tag/commit
checks remain. The vendored OpenAPI file is removed, recoverable only in Git.

Producer publication is updated in client main; no new release/tag or version
was created. `client-core.lock.json` still pins v0.4.1 and must fail native
packaging until a reviewed compatible release is explicitly selected. Completing
that pairing and real platform acceptance remains required; this is not a
successful distribution build. Linux/other consumers need their own review.
