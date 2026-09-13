# EndlessNet UI

The desktop entrypoint uses Client Protobuf v0 over local named pipes or Unix
sockets. It never launches the core as an IPC adapter or reads private state.
Commands require a validated snapshot and use a persistent request journal.
Remaining release-pairing and scenario work is tracked in
[native desktop cutover](../docs/native-desktop-cutover.md). The retired HTTP
bridge, DTOs, controller and widgets have been removed.

Run ordinary checks from this directory:

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

For native transport fixtures, supply a built, reviewed producer host:

```powershell
..\scripts\test-ui-with-native-host.ps1 -HostExecutable C:\test-tools\client-testserver.exe
```

Without a host, process cases are skipped. See
[native scenario host](../docs/native-scenario-host.md) for pinned CI ownership
and coverage gaps. Scripted fixtures do not establish real runtime, platform,
installer or release acceptance.
