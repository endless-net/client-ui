# Native Client v0 consumer test host

This host imports the real shared UI consumer and reuses
`app/test/mobile_contract_widget_test.dart`, `app/test/client_profiles_test.dart`
and `app/test/client_intent_journal_test.dart`. Journal tests run in an isolated
test group and use the native sandbox temporary filesystem, including the real
4096-record admission boundary and reserved Disconnect record. Test inclusion
alone is not successful Android/iOS execution evidence.
The host also includes primary-action queued callback/context regressions and
lifecycle preference projection validation. Direct callback invocation here
models an already queued event; it does not replace real keyboard, touch or
assistive-technology activation tests. Subscription shutdown in widget tests
uses real async execution so cancellation is not stranded in Flutter fake time.
The mobile workflow generates native
Android/iOS project files using the existing pinned Flutter 3.38.1 SDK and runs
the integration test inside an emulator/simulator, not the host Dart VM.

This covers synthetic snapshot → controller → widget behavior and local outbox
file operations. It does not test process termination, device power loss,
runtime journal retention or secure storage permissions. It is not the product
shell, producer testserver IPC integration, Android VPN service, iOS Network
Extension, OS permission automation, background lifecycle or real traffic
acceptance. These are remaining requirements, not silently skipped passing tests.
No mobile capability is enabled by this host and no release artifact is produced.

Generated platform files and dependency resolution belong to the ephemeral CI
host. Do not publish the harness as an application or increase product versions.
