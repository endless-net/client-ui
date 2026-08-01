# Vendored client IPC contract

`client-ipc-v2.openapi.yaml` is an unmodified copy of the producer-owned
contract published by `endless-net/client`:

- release: `v0.4.1`;
- source commit: `517780f5d748a241ca9975fe75d02de2cd074182`;
- release asset: `client-ipc-v2.openapi.yaml`;
- asset SHA-256: `996103b8bfc8ed60ec9cd5ea9407662388e48bf35e75d70f96cef3c159971eca`;
- exact Git blob: `6c9013ed51810ec65606358f81f5eb6750aeb638`.

The release resolver requires a schema-v2 Windows manifest and verifies this
contract plus the service and recovery-helper artifact names, URLs, versions,
commit, installed helper name, and SHA-256 digests before packaging. The
reviewed `client-core.lock.json` pins this compatible producer release.
