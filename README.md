# EndlessNet Client UI

This repository owns the Flutter Windows desktop application and the complete
Windows distribution pipeline for EndlessNet Client. The Go runtime client and
the versioned local IPC producer contract are owned by
[`endless-net/client`](https://github.com/endless-net/client).

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

## Client core v0.3.1 integration

The packaged v0.3.1 service runs WireGuard Go as its only tunnel engine. The
MSI does not pass a backend-selection flag or fix the UDP listen port. Wintun
remains a required, verified runtime dependency beside `endlessnet-client.exe`.
The service owns the live WireGuard configuration in process; the MSI does not
pass the removed `--output` flag or create a rendered `endlessnet.conf` file.

Peers start on relay, authenticated probes evaluate direct candidates, and the
service promotes a reachable direct path using latency hysteresis. A failed
direct path returns to relay.

The UI reads selected paths, candidate health, STUN reachability, and relay
availability exclusively from the producer-defined `status.agent` schema.
The diagnostics response is consumed through `diagnostics.status.agent`; the UI
does not recognize fields that are absent from `client-ipc-v1.openapi.yaml`.

Core 0.3.1 uses the local-owner authorization model for enrollment and
other owner operations. The desktop UI first calls `/enroll` without elevation,
allowing a clean installation to bind ownership to the current Windows user.
Only an `owner_required` or `administrator_required` IPC response launches a
short-lived copy of `endlessnet.exe` with the Windows `runas` verb for migration
of ownerless legacy state. The optional IPC `server` field stays absent unless
the caller explicitly supplied an override; the Go service applies its own
public-server default.

Server identity recovery also keeps the desktop process unprivileged. After the
user reviews the changed key, an `administrator_required` response presents a
dedicated UAC action. A hidden, short-lived `endlessnet.exe` worker re-reads the
announced key, verifies that it still matches the confirmed key ID, and sends
the trust request directly to the protected pipe.

Resolve the reviewed public core input and build an unsigned validation MSI:

```powershell
.\scripts\resolve-client-core.ps1 -OutputDir .\.artifacts\client-core
.\scripts\build-windows-client-msi.ps1 `
  -UIVersion 1.0.4 `
  -CoreVersion 0.3.1 `
  -ClientExe .\.artifacts\client-core\endlessnet-client_windows_amd64.exe `
  -CoreMetadataDir .\.artifacts\client-core `
  -UISourceSBOM .\.artifacts\ui-source-sbom.spdx.json
```

`client-core.lock.json` is the reviewed release interface. It pins the public
core version, commit, immutable manifest, compliance files, and every SHA-256
needed to resolve the runtime input. The UI owns an independent stable SemVer in
`app/pubspec.yaml`; pushing the matching `v*` tag starts the release. That
version determines the MSI version, GitHub release, and WinGet manifests.
Releases sign both executables and the final MSI and publish source/distribution
SBOMs with provenance schema v3. The client-core version remains separate under
`client.version`.
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

The release environment contains only the signing variables and secrets listed
above. Public core artifacts are read with the built-in workflow token, and
pull-request CI never references signing material.
