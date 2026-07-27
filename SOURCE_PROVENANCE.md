# Source provenance

The application, packaging tools, tests, and documentation in this repository
are maintained by EndlessNet and licensed under Apache-2.0.

`contracts/upstream/client-ipc-v1.openapi.yaml` is an exact checked-in copy of
the protected local IPC contract published by
`endless-net/client`. Its authoritative release revision and digest are
recorded in `client-core.lock.json` and verified by CI.

`app/windows/runner` was created from the Flutter Windows application template.
Flutter is licensed under BSD-3-Clause. Generated Flutter dependency notices
remain in `data/flutter_assets/NOTICES.Z`.

The EndlessNet icons under `app/assets/icons` are project-owned product assets.
Apache-2.0 does not grant trademark rights to the EndlessNet name or marks.

The repository does not vendor the Go runtime client or Wintun binary. Release
jobs download immutable, hashed upstream artifacts and preserve their license
and provenance material in the final distribution.
