# Native Client v0 consumer test host

This host imports the real shared UI consumer and reuses
`app/test/mobile_contract_widget_test.dart`. The mobile workflow generates native
Android/iOS project files using the existing pinned Flutter 3.38.1 SDK and runs
the integration test inside an emulator/simulator, not the host Dart VM.

This is a synthetic snapshot → controller → widget test. It is not the product
shell, producer testserver IPC integration, Android VPN service, iOS Network
Extension, OS permission automation, background lifecycle or real traffic
acceptance. These are remaining requirements, not silently skipped passing tests.
No mobile capability is enabled by this host and no release artifact is produced.

Generated platform files and dependency resolution belong to the ephemeral CI
host. Do not publish the harness as an application or increase product versions.
