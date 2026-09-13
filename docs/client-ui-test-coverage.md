# Client v0 test coverage ledger

Status: incomplete. Owner: client-ui. Scope: the complete BA/SA goal, not the
subset already implemented. The canonical machine-readable trace is
[`tests/client-coverage.json`](../tests/client-coverage.json).

It maps all UF-01–23, UBR-01–40 and UI-AC-01–27 to US-01–14 and retains all five
target platforms. Test evidence describes only what a test actually checks.
Shared operation-envelope tests do not close enrollment, trust, profiles,
resources or other product flows. Existing HTTP v2 tests are not v0 evidence.

Current state: zero fully accepted SA scenarios. Some consumer foundations are
tested locally; GitHub evidence is scoped to the inspected jobs below and does
not close any full scenario. Production shell cutover, complete
business scenarios, native mobile bridges and product/platform acceptance remain
required; deferred work does not count as completion.

## Inspected runner evidence (2026-09-13)

Latest inspected desktop evidence: consumer `3b5ad34ead11173c32c22e537cd06e74468968f9`.
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
