import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/test/client_intent_journal_test.dart' as journal;
import '../../../app/test/client_peers_test.dart' as peers;
import '../../../app/test/client_peer_bounds_test.dart' as peerBounds;
import '../../../app/test/client_peer_time_test.dart' as peerTime;
import '../../../app/test/mobile_contract_widget_test.dart' as shared;
import '../../../app/test/client_profiles_test.dart' as profiles;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  shared.main();
  profiles.main();
  group('Native sandbox durable intention journal', journal.main);
  group('Peer catalog contract projection', peers.main);
  group('Peer catalog admission bounds', peerBounds.main);
  group('Peer observation time validation', peerTime.main);
}
