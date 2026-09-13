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

Remaining work in client-ui: remove the unreachable old controller, bridge and
widgets from main.dart and replace their HTTP-based tests; migrate the emulator
and release pairing; complete native shell actions and destination adapters;
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
