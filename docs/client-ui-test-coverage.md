# Client v0 test coverage ledger

US-14 command-announcement addition: `ClientConnectionPanel` exposes its fixed
command-result notice as a separate semantic live region. The shared typed-snapshot
widget regression checks the pending notice's exact accessible label and live-region
flag, then verifies removal on observer transition. Local Flutter validation passed
234 tests with 27 CI-only skips; this checks the semantics tree, not actual
screen-reader speech, OS notifications or localization acceptance. The extension
belongs to the existing desktop/mobile shared harness; prior runner results below
predate it and do not qualify the new assertion.

Status: incomplete. Owner: client-ui. Scope: the complete BA/SA goal, not the
subset already implemented. The canonical machine-readable trace is
[`tests/client-coverage.json`](../tests/client-coverage.json).

It maps all UF-01–23, UBR-01–40 and UI-AC-01–27 to US-01–14 and retains all five
target platforms. Test evidence describes only what a test actually checks.
Shared operation-envelope tests do not close enrollment, trust, profiles,
resources or other product flows. Historical HTTP v2 tests are not v0 evidence.

Current state: zero fully accepted SA scenarios. Some consumer foundations are
tested locally; GitHub evidence is scoped to the inspected jobs below and does
not close any full scenario. Production shell source cutover is recorded in
[native desktop cutover](native-desktop-cutover.md); complete
business scenarios, native mobile bridges and product/platform acceptance remain
required; deferred work does not count as completion.

## Inspected runner evidence (2026-09-13)

At `c228aeebade053e2b799a68302c192c8f291cc3d`, all
[three desktop jobs](https://github.com/endless-net/client-ui/actions/runs/34743127619)
passed 261 tests each. Logs explicitly confirm the gated Network selection and
direct observer peer RPC scenarios. The
[iOS job](https://github.com/endless-net/client-ui/actions/runs/34743127637/job/103686151851)
passed 87 simulator tests, including shared identity context and rejecting resource
opening after Network changes. This supersedes the pending-execution notes below
for those additions only; historical limits remain relevant.
The [Android job](https://github.com/endless-net/client-ui/actions/runs/34743127637/job/103686151891)
failed KVM preflight before tests. The
[Windows packaging job](https://github.com/endless-net/client-ui/actions/runs/34743127621/job/103686145581)
passed 261 tests before rejecting the incompatible core manifest target/IPC pairing.
No installed-service, native mobile VPN or traffic acceptance follows from this run.

UBR-09 connection context now displays Account, Network name/ID and device
hostname/node ID from the current Status for owners with an active profile.
The shared typed-snapshot widget regression checks Unknown for missing values,
Network replacement and removal of private context for observers. Local tests
cover this addition; its runner execution and full localization/accessibility
acceptance remain pending.

The shared application-resource widget test now switches Network from a to b
while the browser action's fresh-catalog validation is pending. It requires the
old action to disappear and the late old-network response to open no browser and
submit no mutation. This locally passed UI-AC-14 regression is included in the
existing desktop/mobile shared suite; runner execution is pending and no real
external application, native browser integration or traffic was exercised.

The peer process suite also bypasses ClientSession's local observer guard and
calls ListPeers through LocalClientEvents directly. It expects a typed
OWNER_REQUIRED from the producer guard, with no ListPeers expectation in the
script; verification must reject accidental handler admission. This desktop
test is pending runner execution and tests a fixture-configured role, not actual
OS owner assignment or full observer privacy across all RPCs.

At `f2cc6d738699cebd474895b18a027dabaaad96fd`, the
[iOS job](https://github.com/endless-net/client-ui/actions/runs/34741635033/job/103682207409)
passed 86 simulator tests, including `peer panel network-visible` and
`peer panel network-pending`. This confirms those shared widget regressions on
the simulator, not producer-process interoperability or actual VPN switching.

The Network process scenario now uses producer `80d9cdc` response gates: only
after operation recovery and old-context assertions does the parent release the
new StatusChanged. The test separately waits for the consumer to observe the new
Network/revision and checks cache invalidation; release acknowledgement alone is
not event-delivery evidence. Runner execution is pending. This adds the synthetic
IPC sequence that earlier snapshots below explicitly lacked; it does not prove
native tunnel switching or mobile bridge acceptance.

Shared peer widget scenarios `network-visible` and `network-pending` cover
StatusChanged replacing Network: clear the old visible catalog and search,
require explicit refresh, and discard an old in-flight result even after a new
query has completed. Both passed locally and are imported by the existing mobile
harness. Runner execution is pending; these synthetic stream checks do not close
the producer-process event sequence or native Network-switch acceptance.

At `e4a06abac6d2f4a39dc9a091140410c2c8120210`, the
[Linux consumer job](https://github.com/endless-net/client-ui/actions/runs/34741391970/job/103681568115)
passed 256 tests, including all three newly added producer-host peer scenarios.
This establishes Linux synthetic IPC execution, not actual runtime reachability.

The session process suite now additionally scripts ListNetworks, exact
SelectNetwork and GetOperation recovery using one durable request ID. Assertions
keep the original network snapshot after both pending acceptance and successful
selection outcome, with continuity still UNKNOWN. Runner execution of this
addition is pending. Streamed new-network context replacement, runtime tunnel
switch and mobile native bridge remain separate missing acceptance evidence.

At `c0026dcaccbd59c87ea817b52f641999330022e8`, all three
[desktop jobs](https://github.com/endless-net/client-ui/actions/runs/34740892688)
passed 252 tests each, including the Windows trust process scenario. A single
successful run does not establish that the intermittent rejection is fixed.
The [iOS job](https://github.com/endless-net/client-ui/actions/runs/34740892717/job/103680327024)
passed 84 simulator tests, now including the separate peer bounds/time suites.
The Android job in that run failed KVM preflight before test execution. The
[Windows packaging job](https://github.com/endless-net/client-ui/actions/runs/34740892692/job/103680299006)
passed 252 tests before rejecting the core manifest target/IPC pairing.
These are scoped mock/simulator results, not complete platform acceptance.

`client_peers_process_test.dart` adds exact two-page peer requests, revision-drift
rejection and observer denial through the pinned producer host with WatchEvents
held open. It also checks that the local journal stays empty and verifies no
unexpected RPCs. Its local fixture check is separate from the three desktop-only
process tests; runner execution of these additions is pending, and the counts
above do not include them. No actual peer endpoint is contacted.

At `d7746b8fbf475d29264e757b0ca385e374138145`, the
[Windows consumer job](https://github.com/endless-net/client-ui/actions/runs/34740483570/job/103679234050)
passed 251 tests and failed the trust process scenario with an aggregate stale
server-identity context error. Its initial-snapshot barrier and scripted response
were inspected; the failing predicate is not yet established. Identity rejection
now reports fixed reason codes (session/cache/domain, readiness, response shape
or revision) without identity values, keys, origins or transport payloads. This
is diagnostic instrumentation, not proof that the underlying race is fixed.
The separate [Windows packaging job](https://github.com/endless-net/client-ui/actions/runs/34740483666/job/103679234038)
passed its consumer suite but rejected the pinned v0.4.1 core manifest because it
declares IPC v2. Public v0.4.2 and v0.5.0 manifests also declare v2. No release,
lock, compatibility fallback or version was changed to bypass that gate.

Latest completed inspected snapshot: `02515e07deed10b40da72c4fac17097ae28331b5`.
[Windows](https://github.com/endless-net/client-ui/actions/runs/34740023685/job/103678075723),
[Linux](https://github.com/endless-net/client-ui/actions/runs/34740023685/job/103678075876)
and [macOS](https://github.com/endless-net/client-ui/actions/runs/34740023685/job/103678075814)
each passed 252 tests. Logs confirm both previously failing process scenarios,
peer UI and the durable outbox; the desktop workflow completed successfully.
[iOS](https://github.com/endless-net/client-ui/actions/runs/34740023703/job/103678076431)
passed 80 simulator tests, explicitly including peer panel query/invalidation
and the full outbox boundary. The separate peer bounds and time-validation files
were not imported into that mobile run; they are now included for a future run.
[Android](https://github.com/endless-net/client-ui/actions/runs/34740023703/job/103678076374)
failed KVM preflight before tests. The overall mobile workflow failed; no native
VPN/traffic acceptance or full SA scenario is established by these results.

At `0fec352f2fb6e9391b1ae0fcb956548349f9a782`, inspected
[macOS](https://github.com/endless-net/client-ui/actions/runs/34739507905/job/103676688251)
passed 248 tests including the peer panel and full outbox boundary.
[Linux](https://github.com/endless-net/client-ui/actions/runs/34739507905/job/103676688110)
passed 246 and failed two process scenarios (failed-exit and update
VERIFICATION_FAILED) during host teardown with `script has in-flight calls`.
The corrected producer host pin synchronizes completion before strict Verify;
its inclusion is not a successful CI rerun. Android
[preflight](https://github.com/endless-net/client-ui/actions/runs/34739507716/job/103676687658)
failed KVM access before tests; no host permission changes were made.

### Peer reader foundation

`client_peers.dart` and its shared tests collect one producer-filtered catalog
with immutable entries and consistent runtime revision, snapshot state and
applied/target map revisions across pages. Exact search text and opaque page
tokens are preserved. Empty and unavailable snapshots do not imply healthy
connectivity; selected endpoints and reason keys are data, never probe targets.
The desktop suite discovers these tests and the Android/iOS host imports them.
The reader is bound to the native ListPeers RPC through ClientSession. Each page
checks session/cache and PEERS/NETWORKS/PROFILES invalidation epochs, with owner
and active-profile admission and stale final revision rejection. Shared tests
cover repeated invalidations and profile/network/owner changes before a later
page can be requested; reads leave the intention journal untouched.
ClientPeersPanel is connected to the session and displays explicit search,
snapshot/map state and expandable path observations without launching probes.
Shared widget tests cover previous snapshot/unreachable candidate display,
observer gating, late response after query replacement and invalidation cleanup.
Producer-process scenarios, complete localization/accessibility and native
IPC/path acceptance remain open.

Consumer `5d5c979f0ac539e23c4e2b6e102201f3b4cb9bce` has verified individual
[Windows](https://github.com/endless-net/client-ui/actions/runs/34737934018/job/103672549796)
and [Linux](https://github.com/endless-net/client-ui/actions/runs/34737934018/job/103672549878)
passes: 237 tests each. Both logs explicitly include observer support and all six
owner update-state producer-host cases. macOS and both mobile jobs were still
queued at inspection; this is not a whole-run or five-platform pass. Synthetic
build identities in these scenarios do not attest the runner platform, actual
update signature verification, browser launch or installer outcomes.

Earlier inspected evidence: consumer `e2e6f6cca085125592aca899f5d7ede9acabf082`.
The [desktop run](https://github.com/endless-net/client-ui/actions/runs/34736166400)
passed with 136 consumer and 39 shared panel/desktop lifecycle tests per OS:
[Windows](https://github.com/endless-net/client-ui/actions/runs/34736166400/job/103667880332),
[Linux](https://github.com/endless-net/client-ui/actions/runs/34736166400/job/103667880446),
[macOS](https://github.com/endless-net/client-ui/actions/runs/34736166400/job/103667880478).
Each inspected log confirms select-exit, clear-exit, failed-exit and ui-quit
producer-host cases. The
[iOS job](https://github.com/endless-net/client-ui/actions/runs/34736166389/job/103667879995)
passed 51 shared simulator tests, including exit UI select/clear/lock/invalidation.
The [Android job](https://github.com/endless-net/client-ui/actions/runs/34736166389/job/103667880100)
failed the existing `/dev/kvm` read/write preflight before tests. Its log explicitly
requires runner-owner approval for permission changes; no such change was made.
This does not validate the subsequently added update reader, native OS lifecycle,
mobile VPN bridges, actual routing or installer outcomes. The mobile run as a
whole did not pass; all 14 full scenarios remain incomplete.

### Disconnect outbox admission correction

The UI outbox now reserves one additional durable Disconnect record when its
normal 4096-record admission bound is reached. No retained work is evicted and
an uncertain send preserves its original UUID across reopening. The filesystem
test fills the real bound, rejects ordinary admission, recovers the Disconnect
record, rejects overflow and releases the reserve only after explicit terminal
acknowledgement. This is local consumer evidence pending CI; it does not prove
the producer's 31 ordinary plus one Disconnect nonterminal admission policy or
its 24-hour terminal retention. The session's existing same-kind recovery guard
still prevents treating a fresh Disconnect UUID as a retry of unresolved work.
The Android/iOS integration host now imports the same journal suite in a scoped
test group. Its temporary files are native sandbox files, not host-side mocks;
this schedules the boundary checks but does not establish mobile execution,
crash durability, filesystem permission enforcement or actual runtime behavior.
Filesystem transactions on the session journal are serialized: two ordinary
commands competing for its last normal slot admit only one, and admission
failure does not poison subsequent recovery or Disconnect admission. A stalled
command RPC does not hold this filesystem queue or delay a separate Disconnect
submission. The shared suite checks both cases. This is in-process serialization
for one journal object, not a cross-process or cross-isolate locking claim.

Earlier inspected desktop evidence: consumer `3b5ad34ead11173c32c22e537cd06e74468968f9`.
The [desktop run](https://github.com/endless-net/client-ui/actions/runs/34733301626)
passed on Windows, Linux and macOS: each job reports 124 consumer tests and 15
profile/network tests, including bundle and exact Set/Reset producer-host scenarios.
The [iOS job](https://github.com/endless-net/client-ui/actions/runs/34733301621/job/103660029431)
was cancelled after building and waiting for a VM Service connection; zero tests
passed. The debug log reader error at cancellation does not establish its root
cause. Android job 103660029312 failed KVM preflight before tests. No new resource
catalog execution is covered by these runs, and no full scenario is accepted.

Earlier inspected evidence: consumer `ed43df36c8feab083abd9b7b7b41e9ad3112dbd4`.
The [desktop run](https://github.com/endless-net/client-ui/actions/runs/34730432514)
passed on all three OSes, each with 109 consumer tests and 15 profile/network
tests, including exact trust/read requests and terminal recovery. The
[iOS job](https://github.com/endless-net/client-ui/actions/runs/34730432531/job/103652189494)
passed 23 simulator tests, including trust confirmation and pre-frame
invalidation races. The
[Android job](https://github.com/endless-net/client-ui/actions/runs/34730432531/job/103652189664)
failed KVM preflight before tests. Desktop and mobile suites have different
scopes; this is not five-platform product acceptance. A preceding Windows
connect fixture EOF did not recur; its cause remains undiagnosed. All 14 full
product scenarios remain incomplete.

Earlier inspected evidence (diagnostic history retained):

- Desktop consumer commit `840a6f5634b23fbda982ace08be988d325cb19d8`:
  [Linux](https://github.com/endless-net/client-ui/actions/runs/34727879150/job/103645176217),
  [Windows](https://github.com/endless-net/client-ui/actions/runs/34727879150/job/103645176299)
  and [macOS](https://github.com/endless-net/client-ui/actions/runs/34727879150/job/103645176387)
  passed, each with 103 consumer tests and 15 profile/network tests. This includes
  the exact-request browser/token enrollment producer fixtures and same-channel
  transport regressions, not real enrollment or installed-daemon acceptance.
- Consumer commit `b2d218420af01e69739447c9b3d802554dd8912b`:
  [iOS simulator job](https://github.com/endless-net/client-ui/actions/runs/34729192852/job/103648732270)
  passed 22 shared widget/profile/network tests after the SafeArea correction.
  This is individual-job evidence, not a claim that the entire mobile run passed.
  The harness does not execute the desktop Go fixture process or a native VPN
  bridge. The earlier intermittent VM Service timeout remains undiagnosed.
- Android native execution remains unproven; prior KVM preflight failure happened
  before tests. No host permission change or infrastructure approval is implied.

These are different immutable consumer commits, not same-manifest five-platform
acceptance. All 14 full product scenarios remain incomplete.

### Earlier transport and simulator diagnosis

For consumer commit `eec22c3c6c28bfcb72e998059fcdd173f81262c6`, the
[Windows contract job](https://github.com/endless-net/client-ui/actions/runs/34723624375/job/103633802799)
passed. The same run failed on
[Linux](https://github.com/endless-net/client-ui/actions/runs/34723624375/job/103633802753)
and [macOS](https://github.com/endless-net/client-ui/actions/runs/34723624375/job/103633802712)
in `local_client_events_test.dart`: reusing the channel after a terminal event
stream produced HTTP/2 `PROTOCOL_ERROR`. The cause is not established. The
held-open session fixture passed on Linux; this does not prove reconnect safety.

The fixture harness captures bounded GOAWAY diagnostics from the synthetic Go
child to investigate the next run without retaining request or response dumps.
These jobs exercise producer mock interoperability and consumer foundations,
not the installed daemon, VPN dataplane, full production UI, or mobile native
bridges. No complete SA scenario or five-platform execution group is accepted.

Transport diagnosis: the pinned Dart `http2` 2.3.1 implementation treats HEADERS
received after local stream cancellation as a new server connection attempt,
then terminates the whole connection. This matches
[upstream issue 1799](https://github.com/dart-lang/http/issues/1799) and the
[pinned source](https://github.com/dart-lang/http/blob/http2-v2.3.1/pkgs/http2/lib/src/streams/stream_handler.dart#L496).
The 82-byte `ProtocolError` text also matches the observed 90-byte GOAWAY payload
(8-byte fixed fields). This is a strong diagnosis, not yet a verified fix:
capture the full debug reason, reproduce late trailers deterministically, then
validate the correction with same-channel unary calls and all desktop runners.
Do not hide it with sleeps, mutation replay, or channel-per-call replacement.
No dependency version increase is authorized; upstream correction must be
evaluated within that constraint before changing the pinned transport.

The socket-free
[`probe_late_headers.dart`](../packages/local_client_rpc/tool/probe_late_headers.dart)
now reproduces this deterministically with pinned `http2` 2.3.1: cancel stream 1,
deliver its already-in-flight HEADERS, observe `ProtocolError` and closed shared
connection. Run `dart run tool/probe_late_headers.dart` from
`packages/local_client_rpc`. Before the backport its exit was **1**, not a passing regression;
the corrected transport must return 0. This isolates the dependency defect but
does not replace the producer interoperability jobs or prove their fix.

Local correction now uses the explicitly documented
[`http2` backport](../packages/http2/ENDLESSNET_BACKPORT.md), retaining version
2.3.1 and upstream license. The same probe returns 0 and completes a subsequent
response on the same connection. It is required in the local-RPC desktop CI
workflow. App, transport package and mobile harness select this same source;
the later desktop job evidence above verifies these consumer regressions on all
three desktop runners, without proving installed-runtime or product acceptance.

The [Android job](https://github.com/endless-net/client-ui/actions/runs/34723624391/job/103633802852)
for the same consumer commit failed before Flutter tests started: software-only
emulation took about 12 minutes to boot, then `adb shell input keyevent 82`
failed with `Broken pipe` (exit 224). This is test-host failure, not consumer test
failure or Android acceptance. The workflow now requires existing KVM access and
hardware acceleration, without changing host permissions, udev rules or runner
services. Missing access must be escalated to the runner owner; it must not be
hidden by software-emulation fallback or a skipped green job.

The [iOS job](https://github.com/endless-net/client-ui/actions/runs/34723624391/job/103633802770)
built the native test host successfully but timed out waiting for its debug
connection (12 minutes, zero tests executed). The workflow enables verbose
Flutter startup diagnostics; the cause is not yet established. Do not count
successful compilation as simulator execution or extend the timeout as proof.

## Validation

### Update read foundation (2026-09-13)

The typed update reader preserves unknown/source-unavailable/verification-failed
states instead of treating them as up-to-date. Shared tests cover immutable
identity/context-bound results and rejection of expired or future-verified
metadata, wrong target, mismatched runtime/UI identities and unsafe URLs.
ClientSession now reads through the generated local binding, without an active
profile requirement for this installation-level owner RPC. Its test rejects
observer reads before RPC, repeated UPDATES invalidations and stale revisions,
and verifies an unchanged intention journal. These changes have local execution
evidence only until their own jobs finish. Signature verification/trusted source
ownership, installer outcome and actual platform acceptance are separate.
The production desktop panel now exposes UI/core build identities and an explicit
Check updates button, with distinct source and installed-pair states. Shared
widget tests cover observer denial, unavailable source, incompatible pair, expired
metadata, invalidated late results and timer expiry after display without reread.
Mandatory notices do not install, launch URLs or disconnect. UI identity comes
from the executable's compile-time version fields (tested against versionText),
not from runtime attestation. About/Help and distribution actions remain open.

### Support read foundation (2026-09-13)

The information process suite adds seven pinned-producer scenarios: observer
support and UNKNOWN/UP_TO_DATE/AVAILABLE/EXTERNAL_MANAGER_REQUIRED/
SOURCE_UNAVAILABLE/VERIFICATION_FAILED owner update reads. It expects an exact
UI build claim, keeps WatchEvents open and verifies the journal remains empty
without extra RPCs. Available security metadata is synthetic; no signature or
installer is executed. The fixed fixture platform identity does not attest the
host OS. Local tests validate the typed fixtures; actual process cases require
desktop CI and are skipped locally. Observer update denial is tested before RPC,
not as a producer-side authorization rejection.

Shared reader tests bind support runtime identity, retain immutable results and
the opaque offline-help key, permit absent links and reject HTTP/file URLs,
credentials and whitespace/control characters in all four destinations. This
does not establish ownership of a domain; trusted source configuration remains
producer-owned. The session test allows observer access with no active profile,
rejects repeated SUPPORT invalidation and confirms no intention journal writes.
SupportInfo has no revision field in v0; none is fabricated. The session panel
now includes basic UI-owned offline help that needs no runtime or network, and
an explicit support refresh available to observers. Five shared widget cases
use a fake launcher to test opening only an unchanged freshly read URL, changed
and unsafe URLs, invalidation and launcher refusal. Missing links produce no
buttons; unknown offline keys are not paths or invented mapped topics. The
production binding uses the external browser launcher with a context guard.
Native browser acceptance, complete localized offline content and platform
evidence remain open. These new UI tests have local evidence only until CI runs.

### Desktop lifecycle foundation (2026-09-13)

Desktop shell widget tests invoke the explicit Quit callback with native
window/tray integration disabled. Owner quit sends exactly one UI_QUIT with
the active profile and snapshot mutation context, retains the pending UUID and
closes the UI connection. Observer quit sends no mutation. Launch sends no
lifecycle event; the existing unavailable-runtime test chooses Stay in the
unconfirmed-exit dialog. These tests now run in the three desktop consumer jobs.
The ui-quit producer-process case requires exact NotifyLifecycle and original
UUID recovery while WatchEvents is open; acceptance is not an inferred runtime
disconnect or shutdown. Local fixture validation passes, process execution awaits
GitHub. OS logoff/suspend/resume, actual preference effects, crash-versus-quit,
native tray/window behavior and mobile lifecycle acceptance remain unproven.

### Exit-node reader and UI foundation (2026-09-13)

The typed exit reader requires one catalog/status revision and both address-family
states. Shared tests preserve IPv4 applied / IPv6 failed without inventing dual-stack
success or aggregate fail-closed, retain an unavailable current selection, and
reject missing families, invalid modes, duplicate IDs, token loops and mixed pages.
Session tests guard owner context and repeated exit/profile/peer/network invalidation.
The reader also rejects aggregate APPLIED/effective IDs before requested family
and LAN convergence, hidden family failures, mismatched family intent and
fail-closed claims without enforcement flags for each requested family. Valid
dual-stack, v4-only, v6-only, LAN-pending and partial-clear states remain distinct.
This validates producer claims for consistency, not actual routing enforcement.
Four shared widget tests additionally cover explicit node/family/LAN selection,
rejection of an unavailable dual-stack mode, cancel/confirm Clear, policy lock
and invalidation including a callback retained before repaint. Dropdown values
are supplied through callbacks, while action buttons are tapped. A pending
operation never becomes an optimistic applied state. The production session
panel binds Select/Clear to the existing operation journal. These shared tests
are included by desktop and mobile host suites, but this change has only local
widget execution evidence until its GitHub jobs finish. The producer process
suite adds select-exit, clear-exit and failed-exit with a joint catalog/status
read, exact mutation context and explicit dual-stack/BLOCK selection, held-open
WatchEvents and recovery by the original UUID. Typed selection (including empty
Clear selection) and UNSUPPORTED failure remain distinct; the previous partial
family projection is not rewritten from operation success. Host verification
rejects extra commands, including implicit clear, downgrade or retry. Local
offline tests validate outcome fixtures; these new process cases are skipped
locally and await execution on the pinned producer host in desktop CI. They do
not prove actual routing/fail-closed platform acceptance or mobile native IPC.

### Resource reader foundation (2026-09-13)

The resource reader and local/session bindings preserve one profile/query/revision
across pages. Shared tests cover all four target kinds, immutable filters and
results, UTF-8 query/ID/name bounds, duplicates, type mismatches, mixed revisions,
token cycles and context invalidation without retries or partial publication.
Overlap IDs are not resolved: visible resources outside a filtered result are
valid, and UI must not probe hidden resources. Session tests additionally guard
owner context and repeated resource/profile/network invalidations. Resource UI
widget tests additionally cover explicit disable, policy locks, requested/effective,
late-query rejection and stale callbacks. The session panel binds changes to the
intention journal without optimistic apply. Application browser tests use a fake
launcher and require explicit click, a fresh same-query/profile result and an
unchanged available HTTPS URL without credentials. Changed destinations, denial
and invalidation never launch. Native browser acceptance, producer-process
resource scenarios, mutation effects and platform acceptance remain open.

Resource producer-host fixtures now include exact ListResources query parameters,
Enable/Disable and terminal RESOURCE_CONFLICT with separate control correlation.
They recover the original UUID, retain the intention until explicit acknowledgement
and leave cached effective state unchanged. Local envelope validation passes;
the new process cases are skipped without the CI producer-host. The local full
suite passed 196 tests with 16 skips, analyze and Go tests passed. Actual conflict
detection, hidden-resource authorization and OS route effects remain unproven.

### Preferences/policy read foundation (2026-09-13)

`client_preferences.dart` combines typed GetPreferences/ListManagedSettings only
at one runtime revision. Shared tests preserve absent versus explicit false,
requested versus effective lifecycle values and immutable policy locks; they
reject malformed context, mixed revisions, duplicate keys and wrong value kinds.
Session tests reject observer/stale reads and repeated domain invalidations.
The shared test file is already imported by the Android/iOS integration host;
this is test inclusion, not verified runner execution. Local validation passed
177 Flutter tests (11 skipped), analyze and Go tests. The new paths do not yet
have producer-process evidence, a preference editor or actual apply acceptance.
The full migration gate remains 0/14, not completed.

The next editor increment adds shared widget vectors for one explicit eight-field
Set patch, a separate Reset key, policy lock enforcement, allowed lifecycle values
and invalidated draft/callback rejection. Session panel binds these actions to
the existing journaled mutations. Tests exercise typed inputs and explicit Apply/
Reset buttons; lifecycle value selections are injected through widget callbacks,
not full native dropdown gestures. Producer-process mutation/apply evidence,
localized presentation and production shell integration are still missing.

Producer-host fixtures now cover GetPreferences/ListManagedSettings before Set
or Reset, exact Set presence for all eight fields (including three explicit false
values), two-key Reset, journal contents limited to UUID/kind and recovery by the
original UUID. Accepted/succeeded operations do not mutate the previously read
effective projection. Execution of these new fixtures is pending on desktop
runners; local tests skip them without ENDLESSNET_TESTSERVER. Current local
validation: 179 passed, 13 skipped, analyze and Go tests passed. These scripted
responses do not prove actual atomic validation, policy enforcement or OS apply.

### Operation envelope checks (2026-09-13)

The mutation boundary rejects nil/malformed request UUIDs before submission or
recovery lookup and compares valid UUID identities case-insensitively, matching
native normalization. Successful operation envelopes require explicit continuity;
unknown continuity must be UNKNOWN, not omitted. UserAction is valid only in
WAITING_FOR_USER. Consumer vectors and journal/mobile fixtures now express these
accepted v0 requirements explicitly.

Local checks passed: Go tests, Flutter analysis and Flutter tests (146 passed,
7 skipped). This strengthens consumer validation; it is not evidence of full
runtime/UI cutover or production system acceptance.

### Snapshot/acceptance race (2026-09-13)

The native producer may publish a full refreshed Snapshot before its mutation
response arrives. `ClientStateController` now distinguishes cache replacement
from caller/profile/account/network context changes. `ClientSession` still
checks the current cache before sending, but uses the identity-context epoch
after sending so an ordinary same-context snapshot does not turn a validated
acceptance into an uncertain result. Reconnect, stream loss and actual context
changes still retain the intention for explicit recovery.

Two `client_session_test.dart` regressions cover same-context snapshot-before-
response and actual profile change during submission. Local validation passed:
`go test ./...`, `flutter analyze --no-pub`, and `flutter test --no-pub`
(144 passed, 7 skipped). These are local consumer tests, not production pairing
or system acceptance; `main.dart` still uses the old HTTP IPC bridge and must be
cut over together with the producer, without a dual-protocol fallback.

Run from the repository root:

```sh
node --test scripts/check-client-coverage.test.mjs
node scripts/check-client-coverage.mjs
```

This checks trace integrity: IDs cannot disappear, evidence files must exist in
the owning repository, and Windows/Linux/macOS cannot substitute for Android/iOS.
This green check is **not** a claim of functional coverage.

The completion audit command is deliberately separate:

```sh
node scripts/check-client-coverage.mjs --require-complete
```

It currently fails because the objective is incomplete. Completion requires every
scenario, every platform and immutable product-level acceptance evidence, not
just mocks or test-file paths. Even a valid completed ledger requires human/agent
inspection of the referenced runs/artifacts and their exact scope; the checker
does not download evidence or prove behavior from a URL.

Keep test references and limitations current as production flows are migrated.
Record platform-specific restrictions explicitly, but do not remove a platform
or requirement to make the gate pass. No deployment, signing or production
approval is implied by this ledger.

### Native privileged recovery consumer foundation — 2026-09-13

`ClientSession.submitPrivileged` uses the durable intent journal before invoking
a platform launcher. `ClientPrivilegedRecovery` builds only the two fixed helper
operations, binds profile/request/CAS and the full trust announcement, and checks
native Operation/Failure output. Mismatched request, kind, profile, instance or
revision, malformed output and untyped diagnostics are rejected. Acceptance is
not treated as completed recovery and does not remove the pending intention.

Evidence: `app/test/client_privileged_recovery_test.dart` and the privileged
recovery case in `app/test/client_session_test.dart`. Local validation: Go tests,
Flutter analysis and 182 Flutter tests passed, 13 skipped. The installed SDK is
Flutter 3.47.0/Dart 3.13.0, whereas CI pins Flutter 3.38.1. Analysis/tests used
`--no-pub` after restoring unintended automatic lockfile updates; this is not
verification of the pinned CI dependency resolution. No versions were committed.

This is native-session integration, not a completed application cutover: the
old `main.dart` launcher still needs replacement, actual elevation must supply
validated output or authorized operation lookup, and cross-platform caller
identity/correlation remains to be verified. No release acceptance is claimed.
