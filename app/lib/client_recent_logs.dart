import 'dart:convert';
import 'package:endlessnet_client_api/client_api.dart' as api;

/// One bounded, immutable profile log window. No partial result survives an
/// invalid/stale page, and no automatic restart combines different windows.
Future<List<api.LogEntry>> readClientRecentLogs(
  Future<api.ListRecentLogsResponse> Function(api.ListRecentLogsRequest) read, {
  required String instanceId,
  required String profileId,
  required int minimumRevision,
  required void Function() checkContext,
}) async {
  if (instanceId.isEmpty || profileId.isEmpty || minimumRevision <= 0) {
    throw const FormatException('Logs require an owner profile snapshot');
  }
  final entries = <api.LogEntry>[];
  final tokens = <String>{};
  var token = '';
  int? revision;
  do {
    checkContext();
    if (!tokens.add(token) ||
        tokens.length > 5 ||
        utf8.encode(token).length > 2048) {
      throw const FormatException('Invalid log pagination');
    }
    final response = await read(
      api.ListRecentLogsRequest(
        profile: api.ProfileRef(profileId: profileId),
        page: api.PageRequest(pageSize: 100, pageToken: token),
      ),
    );
    checkContext();
    final page = response.page;
    if (!response.hasPage() ||
        !page.hasMetadata() ||
        page.metadata.instanceId != instanceId ||
        page.metadata.revision.toInt() < minimumRevision ||
        (revision != null && page.metadata.revision.toInt() != revision) ||
        response.logs.length > 100 ||
        entries.length + response.logs.length > 500 ||
        (response.logs.isEmpty && page.nextPageToken.isNotEmpty)) {
      throw const FormatException('Inconsistent log snapshot');
    }
    revision ??= page.metadata.revision.toInt();
    for (final log in response.logs) {
      final time = log.timestamp;
      if (!log.hasTimestamp() ||
          time.seconds.toInt() < -62135596800 ||
          time.seconds.toInt() > 253402300799 ||
          time.nanos < 0 ||
          time.nanos >= 1000000000 ||
          utf8.encode(log.message).length > 4096) {
        throw const FormatException('Invalid log entry');
      }
      if (entries.isNotEmpty) {
        final previous = entries.last.timestamp;
        if (time.seconds < previous.seconds ||
            (time.seconds == previous.seconds && time.nanos < previous.nanos)) {
          throw const FormatException('Unordered log snapshot');
        }
      }
      entries.add(api.LogEntry.fromBuffer(log.writeToBuffer())..freeze());
    }
    token = page.nextPageToken;
  } while (token.isNotEmpty);
  return List.unmodifiable(entries);
}
