# EndlessNet tray UI

This Flutter Windows application communicates directly with the protected
EndlessNet service named pipe using the versioned local HTTP contract.

Run ordinary UI tests from this directory:

```powershell
flutter analyze
flutter test
```

The repository-level service emulator exercises the real IPC bridge and UI
callbacks without installing or launching the runtime service:

```powershell
..\scripts\test-ui-with-service-emulator.ps1
```

See [`../tools/service-emulator/README.md`](../tools/service-emulator/README.md)
for scenarios, fault injection, and manual desktop testing.
