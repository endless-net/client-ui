# EndlessNet Client UI

This repository owns the Flutter Windows desktop application and the complete
Windows distribution pipeline for EndlessNet Client. The Go runtime client and
the versioned local IPC producer contract are owned by
[`endless-net/client`](https://github.com/endless-net/client).

The target multiplatform design, BA traceability and acceptance scenarios for
Client Protobuf v0 are documented in
[`docs/client-ui-system-analysis.md`](docs/client-ui-system-analysis.md).
[`docs/architecture-and-future.md`](docs/architecture-and-future.md) preserves the
dated Windows HTTP v2 implementation description. The native entrypoint is now
active; remaining cutover work is tracked in
[`docs/native-desktop-cutover.md`](docs/native-desktop-cutover.md).

## Local checks

```powershell
go test ./...
Push-Location app
flutter analyze
flutter test
Pop-Location
```

Run the native IPC process suite with a reviewed producer scenario host:

```powershell
.\scripts\test-ui-with-native-host.ps1 -HostExecutable C:\test-tools\client-testserver.exe
```

The strict producer fixture uses Protobuf v0 over a local pipe/socket. The old
HTTP emulator is removed. See [`docs/native-scenario-host.md`](docs/native-scenario-host.md)
for fixture ownership, verification and explicit scenario coverage gaps.

## Client core release pin

`client-core.lock.json` pins client release v0.6.0 with its immutable commit
and release asset SHA-256 digests. Its Windows manifest identifies IPC v0,
and the published binary descriptor matches the native UI consumer identity.
Installer and real-device acceptance remain separate from release pairing.

### Historical v0.4.1 integration

The packaged v0.4.1 service runs WireGuard Go as its only tunnel engine. The
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
does not recognize fields that are absent from `client-ipc-v2.openapi.yaml`.

Core 0.4.1 uses the local-owner authorization model for enrollment and
other owner operations. The desktop UI first calls `/enroll` without elevation,
allowing a clean installation to bind ownership to the current Windows user.
Only an `owner_required` or `administrator_required` IPC response launches a
short-lived copy of `endlessnet.exe` with the Windows `runas` verb for migration
of ownerless legacy state. The optional IPC `server` field stays absent unless
the caller explicitly supplied an override; the Go service applies its own
public-server default.

Server identity recovery also keeps the desktop process unprivileged. After the
user reviews the changed key, an `administrator_required` response presents a
dedicated UAC action that launches the installed, signed
`endlessnet-client-recovery-helper.exe` with its fixed trust operation and the
confirmed origin/key ID. The UI then re-reads service status and identity so a
key change during UAC cannot silently trust a different identity.

Resolve the public core input and build an unsigned validation MSI:

```powershell
.\scripts\resolve-client-core.ps1 -OutputDir .\.artifacts\client-core
.\scripts\build-windows-client-msi.ps1 `
  -UIVersion 1.0.4 `
  -CoreVersion 0.6.0 `
  -ClientExe .\.artifacts\client-core\endlessnet-client_windows_amd64.exe `
  -RecoveryHelperExe .\.artifacts\client-core\endlessnet-client-recovery-helper_windows_amd64.exe `
  -CoreMetadataDir .\.artifacts\client-core `
  -UISourceSBOM .\.artifacts\ui-source-sbom.spdx.json
```

`client-core.lock.json` is the reviewed release interface. It pins the public
core version, commit, immutable manifest, compliance files, and every SHA-256
needed to resolve the runtime input. The UI owns an independent stable SemVer in
`app/pubspec.yaml`; pushing the matching `v*` tag starts the release. That
version determines the MSI version, GitHub release, and WinGet manifests.
Releases sign the service, recovery helper, desktop UI, and final MSI and
publish source/distribution SBOMs with provenance schema v3. The client-core
version remains separate under `client.version`.
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
