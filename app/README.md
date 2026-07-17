# EndlessNet UI

This Flutter Windows application communicates directly with the protected
EndlessNet service named pipe using the versioned local HTTP contract.

The main window summarizes the service-reported direct/relay selection for each
peer. Connectivity diagnostics show authenticated candidate health, selection
reasons, STUN mappings, and PCP/NAT-PMP results from `/diagnostics`. Relay is a
normal compatible path, including while direct candidates are being evaluated
or when the remote peer runs an older client. Missing optional v1 extension data
is displayed as unavailable and is never reconstructed from private state.

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
