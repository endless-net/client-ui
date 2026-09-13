# Native stream owner revocation

The state controller now retains a typed producer Failure from gRPC error
details as well as from an explicit failure event. It uses the local transport's
existing strict decoder; diagnostic text is not parsed as an error code. The
retained failure is cloned/frozen. Any stream error still clears the private
snapshot, operations and domain caches and advances the context epoch.

`app/test/client_owner_revocation_test.dart` verifies owner-ready to
OWNER_REQUIRED to unavailable, journal retention without automatic command
replay/recovery/reconnect, explicit reconnection awaiting a fresh sequence-1
snapshot, and observer recovery denial without an RPC call. It also checks that
transport text alone cannot fabricate a typed owner-required failure.

These are UI session/state tests with controlled streams, not authenticated
installed-service acceptance. The producer-side send/queue revocation behavior
is owned by [client main](https://github.com/endless-net/client/blob/main/docs/native-event-cutover.md).
Combined real-host permission-change tests, OS lifecycle and UI presentation
remain separate acceptance work. No contract, SDK pin or version is changed.

The cross-platform `Client v0 consumer` workflow now runs the whole Flutter test
suite on Linux, Windows and macOS with the existing pinned native scenario host,
instead of a manually maintained file list that omitted this regression test.
A repository Go test guards full-suite discovery and host wiring. This schedules
coverage; only completed CI results establish whether each platform passes.
