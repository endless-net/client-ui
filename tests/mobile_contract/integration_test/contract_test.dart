import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/test/client_intent_journal_test.dart' as journal;
import '../../../app/test/mobile_contract_widget_test.dart' as shared;
import '../../../app/test/client_profiles_test.dart' as profiles;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  shared.main();
  profiles.main();
  group('Native sandbox durable intention journal', journal.main);
}
