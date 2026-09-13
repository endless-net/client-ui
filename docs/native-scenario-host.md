# Native v0 scenario host

The HTTP v2 emulator, its default-success state engine, JSON overlays and four
HTTP pipe integration tests were removed on 2026-09-13. They are recoverable in
Git history, not executable fallbacks. Their removal is not proof that every
old scenario is now covered by native acceptance.

The sole UI process fixture is producer-owned
[`clientipc/testserver` on client main](https://github.com/endless-net/client/tree/main/clientipc/testserver).
CI builds `clientipc/cmd/client-testserver` from the same immutable source pin
already used by `contract-consumer.yml`:
`c7a92e61558531147b9e12f18ad2cbe3549a5f3b`. No contract or dependency version changes.

This pin waits for producer handler completion (at most five seconds) after the
parent closes its channels and explicitly requests verification. Parent channel
termination can precede server-side stream cancellation; the previous host could
fail with `script has in-flight calls` during this interval. Strict verification
still rejects leaked calls, unexpected requests and unconsumed expectations.
No scenario is retried and no runtime or runner permission is changed.
The host implements generated v0 RPCs, strict per-method expected requests,
ordered event streams and typed failures. It rejects undeclared commands rather
than inventing successful outcomes. It is not the actual runtime or a durable
state engine.

`app/test/support/scenario_host.dart` checks the readiness descriptor digest,
uses a unique pipe/socket, and requires both explicit verification and successful
exit after consumer channels close. `client_session_process_test.dart` exercises
the real Dart session, journal and transport against it. CI runs this with the
host configured; local tests without `ENDLESSNET_TESTSERVER` skip process cases
and must not be cited as process evidence.

With a separately built, reviewed producer executable:

```powershell
.\scripts\test-ui-with-native-host.ps1 -HostExecutable C:\test-tools\client-testserver.exe
```

The runner restores the prior environment, performs no source checkout or
installation, and uses already resolved Flutter dependencies. Real service,
privileged networking, installer and release validation remain CI-only.

## Scenario migration ledger

| Retired scenario | Native evidence and remaining work |
| --- | --- |
| enrollment-approval | Browser/token process submission and operation recovery exist; timed approval/expiry with actual runtime remains pending. |
| owner-required | Enrollment denial/observer widgets and producer guards exist; full runtime competing-caller scenario remains pending. |
| connect-failure | Native operation/failure and transport tests exist; matching provider failure and degraded-state progression need system evidence. |
| server-identity-changed | Native identity confirmation and trust process fixture exist; actual elevated runtime recovery remains pending. |
| server-identity-toctou | Native context/confirmation tests exist; signed-announcement change during real UAC remains pending. |
| planned-signing-rotation | Old synthetic automatic success was removed; actual planned-rotation continuity needs native system evidence. |
| remote-cleanup-unconfirmed | Typed cleanup projection and no-logout-to-forget widget tests exist; real remote failure/local cleanup sequence needs process/system evidence. |
| control-plane-reset-recovery | Native recovery primitives exist; full real-provider reset-to-reenrollment scenario remains pending. |

The retired broad bridge test also touched network selection, diagnostics/logs
and local forget. Native unit checks are not a replacement for its complete
multi-operation transport sequence; extend the v0 process catalog and verify
against pinned runtime artifacts before claiming full BA/SA acceptance.
