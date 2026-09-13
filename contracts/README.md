# Consumer release identity

`client-v0.json` contains the exact protocol, version and descriptor SHA-256 of
the generated Dart SDK consumed by this repository. It is a consumer pairing
record, not a second source schema. `client_release_pairing_test.dart` compares
it with the resolved SDK. The producer owns proto sources, generated bindings
and the binary descriptor.

The Windows resolver accepts only a schema-2 manifest identifying IPC v0,
validates immutable release/tag/commit and asset provenance as before, and
compares the raw `client-v0.binpb` SHA-256 with this identity. Binary descriptors
must not undergo text decoding or newline normalization. No OpenAPI fallback.

The currently checked-in core lock still names old v0.4.1. It is intentionally
not rewritten to an unverified build; native packaging will reject that release.
Selecting a newly reviewed immutable native core artifact remains required.
No release, tag, manifest schema, package or protocol version increase was made.
