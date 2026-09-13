import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/test/client_intent_journal_test.dart' as journal;
import '../../../app/test/client_peers_test.dart' as peers;
import '../../../app/test/client_peer_bounds_test.dart' as peerBounds;
import '../../../app/test/client_peer_time_test.dart' as peerTime;
import '../../../app/test/mobile_contract_widget_test.dart' as shared;
import '../../../app/test/client_profiles_test.dart' as profiles;
import '../../../app/test/client_disposed_actions_test.dart' as disposedActions;
import '../../../app/test/client_connection_activation_test.dart' as activation;
import '../../../app/test/client_session_layout_test.dart' as sessionLayout;
import '../../../app/test/client_operation_labels_test.dart' as operationLabels;
import '../../../app/test/client_loopback_contract_test.dart' as wireMock;
import '../../../app/test/client_rebootstrap_test.dart' as rebootstrap;
import '../../../app/test/client_runtime_operations_panel_test.dart' as runtimeOperations;
import '../../../app/test/client_operation_details_locale_test.dart' as operationLocales;
import '../../../app/test/client_identity_activation_test.dart'
    as identityActivation;
import '../../../app/test/client_preferences_validation_test.dart'
    as preferences;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  shared.main();
  profiles.main();
  group('Disposed panel action admission', disposedActions.main);
  group('Queued primary action context binding', activation.main);
  group('Active session large-text layout', sessionLayout.main);
  group('Typed operation presentation', operationLabels.main);
  group('Synthetic protobuf wire contract server', wireMock.main);
  group('Runtime readiness rebootstrap', rebootstrap.main);
  group('Initial snapshot and stream operation presentation', runtimeOperations.main);
  group('Bilingual operation outcomes', operationLocales.main);
  group('Queued identity confirmation binding', identityActivation.main);
  group('Lifecycle preference projection validation', preferences.main);
  group('Native sandbox durable intention journal', journal.main);
  group('Peer catalog contract projection', peers.main);
  group('Peer catalog admission bounds', peerBounds.main);
  group('Peer observation time validation', peerTime.main);
}
