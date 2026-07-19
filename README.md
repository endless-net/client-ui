# EndlessNet Client UI

This repository owns the Flutter Windows desktop application and the complete
Windows distribution pipeline for EndlessNet Client. The Go runtime client and
the versioned local IPC producer contract are owned by
[`unng-lab/endlessnet-client`](https://github.com/unng-lab/endlessnet-client).

## Local checks

```powershell
go test ./...
Push-Location app
flutter analyze
flutter test
Pop-Location
```

Run the UI component and IPC end-to-end suite against a hermetic named-pipe
service emulator:

```powershell
.\scripts\test-ui-with-service-emulator.ps1
```

The emulator implements the checked-in OpenAPI surface, supports deterministic
state transitions and fault injection, and records a redacted JSONL request
journal. See [`tools/service-emulator/README.md`](tools/service-emulator/README.md)
for manual UI testing and custom scenarios.

## Backend v0.2.0 integration

The packaged v0.2.0 service runs WireGuard Go as its only tunnel engine. The
MSI does not pass a backend-selection flag or fix the UDP listen port. Wintun
remains a required, verified runtime dependency beside `endlessnet-client.exe`.

Peers start on relay, authenticated probes evaluate local, STUN, PCP, and
NAT-PMP candidates, and the service promotes a reachable direct path using
latency hysteresis. A failed direct path returns to relay. Mixed-version peers
remaining on relay is expected compatibility behavior, not by itself an error.

The UI reads selected paths and candidate health from the producer's
`status.agent` extension and reads the full STUN, port-mapping, and path snapshot
from `diagnostics.agent_state`. The IPC version remains v1. The current OpenAPI
contract permits these objects through `additionalProperties` but does not yet
define their nested schemas; the UI therefore treats absent extension data as
"not reported" instead of synthesizing it. Formal nested diagnostics schemas
are a producer-contract follow-up, not a blocker for v0.2.0.

Build an unsigned validation MSI from a previously verified Go-core artifact:

```powershell
.\scripts\build-windows-client-msi.ps1 `
  -Version 1.2.3 `
  -ClientExe .\.artifacts\endlessnet-client_windows_amd64.exe
```

Production releases are initiated by an immutable `client-core-published`
`repository_dispatch` from the client-core release workflow. They sign both executables and the final MSI,
publish private release provenance, mirror public artifacts through
`unng-lab/endlessnetfront`, and trigger `unng-lab/endlessnet-system-tests`.
The owning workflow uses `scripts/resolve-release-idempotency.ps1` to distinguish
an expected missing release (continue with `noop=false`) from real GitHub CLI or
API failures. Existing releases are no-ops only when their provenance names the
same immutable core manifest.

## Release configuration

The `release` environment is restricted to `main` and has no required
reviewers. Configure `WINDOWS_CODESIGN_PFX_BASE64` and
`WINDOWS_CODESIGN_PFX_PASSWORD` as environment secrets. Configure these
repository secrets with separate fine-grained tokens:

- `CLIENT_CORE_RELEASE_TOKEN`: read-only Contents access to
  `unng-lab/endlessnet-client`;
- `FRONT_RELEASE_TOKEN`: Contents write access only to
  `unng-lab/endlessnetfront`, for `repository_dispatch`.

No signing material is referenced by pull-request CI.
