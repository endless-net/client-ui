# EndlessNet Client UI

This repository owns the Flutter Windows tray application and the complete
Windows distribution pipeline for EndlessNet Client. The Go runtime client and
the versioned local IPC producer contract remain in
[`unng-lab/endlessnet`](https://github.com/unng-lab/endlessnet).

## Local checks

```powershell
go test ./...
Push-Location app
flutter analyze
flutter test
Pop-Location
```

Build an unsigned validation MSI from a previously verified Go-core artifact:

```powershell
.\scripts\build-windows-client-msi.ps1 `
  -Version 1.2.3 `
  -ClientExe .\.artifacts\endlessnet-client_windows_amd64.exe
```

Production releases are initiated by an immutable `repository_dispatch` from
the backend release workflow. They sign both executables and the final MSI,
publish private release provenance, mirror public artifacts through
`unng-lab/endlessnetfront`, and trigger `unng-lab/endlessnet-system-tests`.
