# EndlessNet Client UI

This repository owns the Flutter Windows desktop application and the complete
Windows distribution pipeline for EndlessNet Client. The Go runtime client and
the versioned local IPC producer contract are owned by
[`unng-lab/endlessnet-client`](https://github.com/unng-lab/endlessnet-client).

Architecture, accepted decisions, known limitations, and possible development
directions are documented in
[`docs/architecture-and-future.md`](docs/architecture-and-future.md).

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

Peers start on relay, authenticated probes evaluate direct candidates, and the
service promotes a reachable direct path using latency hysteresis. A failed
direct path returns to relay.

The UI reads selected paths, candidate health, STUN reachability, and relay
availability exclusively from the producer-defined `status.agent` schema.
The diagnostics response is consumed through `diagnostics.status.agent`; the UI
does not recognize fields that are absent from `client-ipc-v1.openapi.yaml`.

Build an unsigned validation MSI from a previously verified Go-core artifact:

```powershell
.\scripts\build-windows-client-msi.ps1 `
  -UIVersion 1.2.3 `
  -CoreVersion 0.2.0 `
  -ClientExe .\.artifacts\endlessnet-client_windows_amd64.exe
```

Production releases are initiated by an immutable `client-core-published`
`repository_dispatch` from the `unng-lab/endlessnet-client` release workflow.
The client-core version identifies only the verified runtime input. The UI owns
an independent stable SemVer in `app/pubspec.yaml`; that version determines the
MSI version, GitHub tag, WinGet manifests, and public mirror payload. Releases
sign both executables and the final MSI,
publish private release provenance, mirror public artifacts through
`unng-lab/endlessnetfront`, and trigger `unng-lab/endlessnet-system-tests`.
Provenance schema v2 records the UI version at the top level and preserves the
client-core version separately under `client.version`.
The owning workflow uses `scripts/resolve-release-idempotency.ps1` to distinguish
an expected missing release (continue with `noop=false`) from real GitHub CLI or
API failures. Existing UI releases are no-ops only when their provenance names
the same UI version and immutable client-core inputs. A new core input therefore
requires an intentional UI SemVer bump before another UI release is published.

## Release configuration

The `release` environment is restricted to `main` and has no required
reviewers. The current signing mode is deliberately temporary: a stable
self-signed code-signing certificate is reused between releases. Its signatures
do not provide public Windows trust or Microsoft SmartScreen reputation.

Configure the protected `release` environment with:

- `WINDOWS_CODESIGN_MODE=temporary-self-signed` as an environment variable;
- `WINDOWS_CODESIGN_EXPECTED_THUMBPRINT` as an environment variable containing
  the stable certificate's 40-character SHA-1 thumbprint;
- `WINDOWS_CODESIGN_PFX_BASE64` and `WINDOWS_CODESIGN_PFX_PASSWORD` as
  environment secrets containing that same stable PFX and its password.

Do not generate a new PFX per run. The release job imports the PFX as
non-exportable, verifies signature integrity and the exact signer without adding
a trusted root, and removes the certificate, private-key container, and
temporary files in an `if: always()` cleanup step.

Migration to a publicly trusted PFX requires no packaging change: replace the
two PFX secrets and expected thumbprint, then set
`WINDOWS_CODESIGN_MODE=public-authenticode`. That mode rejects self-signed
certificates and requires Windows trust validation. A future cloud signer can
replace the isolated import/signing adapter while retaining the exact-signer
checks, Wintun verification, provenance, and publication gates.

Configure these repository secrets with separate fine-grained tokens:

- `CLIENT_CORE_RELEASE_TOKEN`: read-only Contents access to
  `unng-lab/endlessnet-client`;
- `FRONT_RELEASE_TOKEN`: Contents write access only to
  `unng-lab/endlessnetfront`, for `repository_dispatch`.

No signing material is referenced by pull-request CI.
