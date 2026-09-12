import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_local_client_rpc/local_client_rpc.dart';

import 'client_event_stream.dart';
import 'client_mutations.dart';

/// Production local transport binding for the typed event consumer. The shell
/// must clear domain caches on disconnect and start a fresh subscription.
final class LocalClientEvents {
  LocalClientEvents._(this._channel, this._client, this.runtime);

  final LocalClientChannel _channel;
  final api.ClientServiceClient _client;
  final api.RuntimeInfo runtime;
  bool _watching = false;
  bool _closed = false;

  ClientMutations get mutations {
    if (_closed) throw StateError('Local client is closed');
    return ClientMutations(_client, instanceId: runtime.instanceId);
  }

  static Future<LocalClientEvents> open({String? endpoint}) async {
    final channel = LocalClientChannel(endpoint: endpoint);
    try {
      final client = localServiceClient(channel);
      final info = await bootstrapLocalClient(client);
      return LocalClientEvents._(channel, client, info..freeze());
    } catch (_) {
      await channel.terminate();
      rethrow;
    }
  }

  Stream<api.WatchEventsResponse> watch() async* {
    if (_closed || _watching) {
      throw StateError('Local event source is closed or already subscribed');
    }
    _watching = true;
    try {
      await for (final event in validateClientEvents(
        _client.watchEvents(api.WatchEventsRequest()),
      )) {
        if (event.metadata.instanceId != runtime.instanceId) {
          throw const FormatException('Runtime changed after bootstrap');
        }
        yield event;
      }
    } finally {
      _watching = false;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _channel.terminate();
  }
}
