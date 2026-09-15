# Adaptive client UI

The main screen puts connection status and explicit connection actions first.
Connection metadata is available in an expandable details section. Network
management, application settings and support occupy separate destinations.
Application autostart and reconnect/quit actions do not compete with connection
controls on the home screen.

## Layout

- Below 720 logical pixels, or in a short landscape window, use Material 3
  `NavigationBar` at the bottom. The selected destination has a visible label;
  all destinations retain accessible labels and tooltips.
- At 720 pixels and above with enough height, use `NavigationRail`. Expand its
  labels at 1100 pixels when the text scale leaves enough room.
- Choose layout with `LayoutBuilder`, not operating system or device type.
  Retain the content subtree and form state when switching navigation layouts.
- Keep content scrollable, account for system insets with `SafeArea`, use
  16-pixel mobile padding, and constrain long desktop content to 960 pixels.
- Support portrait, landscape, keyboard input, and 200% text. Do not lock
  orientation or shrink accessibility text to fit a desktop layout.

## Reference decisions

[NetBird iOS connection redesign](https://netbird.io/knowledge-hub/netbird-ios-v0-3-1)
uses a simple connection toggle. Its
[desktop redesign](https://netbird.io/knowledge-hub/new-desktop-app-release-candidate)
separates compact and advanced views. We adopt the separation of everyday
connection tasks from administration. Explicit Connect/Disconnect actions stay
bound to authoritative runtime state and the existing operation journal.

Flutter's [adaptive approach](https://docs.flutter.dev/ui/adaptive-responsive/general)
provides `LayoutBuilder`, `NavigationBar`, and `NavigationRail`. Its
[best practices](https://docs.flutter.dev/ui/adaptive-responsive/best-practices)
recommend touch-first layouts, window-size decisions, and preserving state.
Material and Cupertino offer platform-specific presentation where useful;
platform plugins/channels supply native capabilities rather than layout.

## Scope

This change adapts the shared interface and Windows desktop shell. It does not
establish an Android/iOS VPN client: the mobile native runtime adapter, VPN
permission/lifecycle integration, and device acceptance remain separate work.
The existing Windows named-pipe transport and IPC v0 identity are unchanged.
No Flutter SDK, dependency, application or protocol version is increased.
