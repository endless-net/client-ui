# Desktop local Client v0 channel

Direct generated Dart gRPC over local Windows named pipes and Linux/macOS Unix
sockets. The immutable SDK pin supplies protocol/version/digest metadata; no
HTTP v2, TCP fallback, CLI process adapter or private core state access exists.
Mobile throws unsupported: it needs a separately authorized native bridge.

Windows uses overlapped duplex I/O with impersonation-enabled pipe handles,
bounded output buffering and read backpressure. Shutdown cancels outstanding
kernel operations and waits for completion before freeing native buffers.
The Go runtime remains responsible for OS peer verification and owner policy.

Use `LocalClientChannel`, `localServiceClient`, and `bootstrapLocalClient` before
domain calls. The app controller is not yet migrated to this package. RPC
acceptance is not domain success; consumers must recover tracked operations and
verify terminal outcomes.

`dart test` locally checks endpoint restrictions. The `local-rpc.yml` job builds
the pinned producer scenario host and sets `ENDLESSNET_TESTSERVER`, making the
Go/Dart local bootstrap, unary, streaming and error scenario run
on Windows/Linux/macOS. Synthetic fixture success is transport evidence, not
production ownership, mobile or system acceptance.
