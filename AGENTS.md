# Agents

- This repository owns the EndlessNet Flutter desktop UI, Windows packaging,
  code signing, WinGet manifests, and Windows client releases.
- The Go runtime client and the producer IPC contract are owned by
  `unng-lab/endlessnet-client`; never copy client-core runtime source into this
  repository.
- Runtime UI communication must use the protected local named pipe directly.
  Do not launch `endlessnet-client.exe` as an IPC adapter and do not read the
  backend's private state files.
- PR workflows must not receive signing or cross-repository release secrets.
- Published releases must verify the immutable Go-core manifest and sign both
  executables and the final MSI before publication.
- Format changed Go files with `gofmt`; run `go test ./...`, `flutter analyze`,
  and `flutter test` before publishing changes.
