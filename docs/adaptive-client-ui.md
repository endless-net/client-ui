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


## Appearance and home dashboard

The default appearance is dark navy, with light and system modes available in
Settings → Appearance. The choice is stored independently in the UI settings
`theme` file and does not reconnect the runtime or change profiles.

The home dashboard contains the authoritative connection state and primary
Connect/Disconnect action, a device card, and a compact peer summary. At 840
logical pixels of content width, the summary moves to a second column; smaller
widths stack the cards. Registration forms, additional session actions and
connection details are expandable. Expanded forms retain their state.

The compact peer summary reads the native peer catalog when an authorized active
profile becomes available and refreshes after relevant invalidations. Results
from a previous profile, network or caller context are discarded. Peer path
labels describe runtime observations, and are not fabricated online indicators.
No sample devices or addresses are included in the application.
