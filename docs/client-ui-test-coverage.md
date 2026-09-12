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
`packages/local_client_rpc`. Current exit is **1**, not a passing regression;
the corrected transport must return 0. This isolates the dependency defect but
does not replace the producer interoperability jobs or prove their fix.

Local correction now uses the explicitly documented
[`http2` backport](../packages/http2/ENDLESSNET_BACKPORT.md), retaining version
2.3.1 and upstream license. The same probe returns 0 and completes a subsequent
response on the same connection. It is required in the local-RPC desktop CI
workflow. App, transport package and mobile harness select this same source;
runner results for the corrected source still need inspection.

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
