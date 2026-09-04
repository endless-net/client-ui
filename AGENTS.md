# Agents

## Git workflow

- Work directly on `main`. Do not create feature branches or pull requests.
- After completing and validating a change, commit only its intended files and
  push the commit directly to `main` immediately.
- Format every commit message according to Conventional Commits, for example
  `feat: ...`, `fix: ...`, `docs: ...`, or `chore: ...`.

## Development policy

- Do not preserve legacy behavior, deprecated interfaces, or backward
  compatibility. Remove or replace obsolete paths rather than maintaining
  compatibility shims.

## Repository boundary

- Work only within this repository.
- Before reading from or writing to any path outside this repository, request
  and receive the user's explicit permission.

- This repository owns the EndlessNet Flutter desktop UI, Windows packaging,
  code signing, WinGet manifests, and Windows client releases.
- The Go runtime client and the producer IPC contract are owned by
  `endless-net/client`; never copy client-core runtime source into this
  repository.
- Runtime UI communication must use the protected local named pipe directly.
  Do not launch `endlessnet-client.exe` as an IPC adapter and do not read the
  backend's private state files.
- PR workflows must not receive signing or cross-repository release secrets.
- Published releases must verify the immutable Go-core manifest and sign both
  executables and the final MSI before publication.
- GitHub Actions runner-unit infrastructure, including installation,
  registration, host inventory, service configuration, restart and resource
  limits, guarded rollout, recovery, and rollback, is owned by
  `endless-net/observability`. Keep only the minimal `runs-on`
  scheduling selectors here; do not add runner-management workflows, scripts,
  units, secrets, or host configuration to this repository.
- `app/windows/runner` is the Flutter Windows application runner, not GitHub
  Actions infrastructure.
- Format changed Go files with `gofmt`; run `go test ./...`, `flutter analyze`,
  and `flutter test` before publishing changes.

## Version increases

- Never increase any version or generation number, including schema, configuration,
  API, protocol, contract, manifest, migration, artifact, or rollout versions,
  without the user's direct explicit permission for that exact increase.
- A request to implement, refactor, fix, remove compatibility, or make a breaking
  change does not authorize a version increase. Without explicit permission, keep
  the current version number.
