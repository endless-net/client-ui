# Source provenance

The application, packaging tools, tests, and documentation in this repository
are maintained by EndlessNet and licensed under Apache-2.0.

`contracts/client-v0.json` records the native IPC descriptor identity consumed
by the generated Dart SDK. The retired OpenAPI contract is no longer vendored.
`client-core.lock.json` pins `endless-net/client` release `v0.6.0` at commit
`95bd83cdb2f265713e7489a055689392a86b2ce7`, with release asset SHA-256 digests.
The release exposes IPC v0 and its binary descriptor matches the consumer identity.
The resolver verifies the pinned asset digests.
It also verifies SLSA build attestations for the service and recovery helper
against the producer workflow, immutable tag/commit, and GitHub-hosted runner.

`app/windows/runner` was created from the Flutter Windows application template.
Flutter is licensed under BSD-3-Clause. Generated Flutter dependency notices
remain in `data/flutter_assets/NOTICES.Z`.

The EndlessNet icons under `app/assets/icons` are project-owned product assets.
Apache-2.0 does not grant trademark rights to the EndlessNet name or marks.

The repository does not vendor the Go runtime client or Wintun binary. Release
jobs download immutable, hashed upstream artifacts and preserve their license
and provenance material in the final distribution.
