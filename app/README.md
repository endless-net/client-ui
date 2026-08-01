# EndlessNet UI

This Flutter Windows application communicates directly with the protected
EndlessNet service named pipe using the versioned local HTTP contract.

The main window summarizes the service-reported direct/relay selection for each
peer. Connectivity diagnostics show authenticated candidate health, selection
reasons, STUN reachability, and relay availability from the producer-defined
`diagnostics.status.agent` schema. Relay is a normal path while direct
candidates are being evaluated or when no direct candidate is reachable. The UI
does not consume fields outside `client-ipc-v2.openapi.yaml` and never
reconstructs diagnostics from private state.

The current v1 response model distinguishes observer, local-owner, and
administrator operations. Enrollment responses are full status envelopes with
an optional `wireguard_apply` result only when the service synchronously starts
the tunnel.

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
