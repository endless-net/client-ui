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
