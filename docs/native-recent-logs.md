# Native recent-log UI

The diagnostic panel can explicitly load ListRecentLogs for the active profile
through the native session/channel. It renders a bounded scrollable local window;
it neither uploads nor copies logs, and does not claim complete history. As with
the rest of this panel, access requires a ready owner/admin snapshot and the
DIAGNOSTICS capability. The producer currently withholds that whole-family
capability; this UI wiring does not claim the whole runtime family is ready.

Reads collect at most five 100-entry pages / 500 entries, with messages bounded
to 4096 UTF-8 bytes. They require one instance/revision, valid chronological
timestamps, bounded nonrepeating tokens and no empty continuation pages. Results
are cloned/frozen; inconsistent or stale reads never return partial data. Context
is checked before/after each page. Profile/caller/stream changes discard results;
the panel clears its retained window on invalidation. Failure displays fixed text
and offers explicit refresh, with no automatic restart or HTTP fallback.

`client_recent_logs_test.dart` covers page/request binding, immutable snapshots,
malformed pages/entries, stale failure without retry, context change between
pages, and widget gating/display/clearing. `client_session_test.dart` verifies an
in-flight read cannot survive an active-profile change. Real producer-host log
pagination and installed-service tests remain open; controlled reader/widget
tests do not establish those outcomes. Runtime source scope and retention are
owned by [client main](https://github.com/endless-net/client/blob/main/docs/native-cli-catalogs.md).
