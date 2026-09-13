import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'client_locale.dart';
import 'client_operation.dart';
import 'client_operation_details.dart';
import 'client_operation_labels.dart';
import 'client_state_controller.dart';

/// Stream projection independent of the local journal. Never replays work.
class ClientRuntimeOperationsPanel extends StatelessWidget {
  const ClientRuntimeOperationsPanel({
    super.key,
    required this.state,
    this.locale = ClientLocale.en,
  });
  final ClientStateController state;
  final ClientLocale locale;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      if (state.link != ClientLinkState.ready ||
          state.snapshot == null ||
          state.snapshot!.runtime.callerAccess == api.Access.ACCESS_OBSERVER) {
        return const SizedBox.shrink();
      }
      final operations = state.operations.values;
      if (operations.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(locale.text(en: 'Runtime operations', ru: 'Операции службы')),
          Text(
            locale.text(
              en: 'Reported by the runtime. Recover saved intentions separately.',
              ru: 'Получены от службы. Сохранённые намерения восстанавливаются отдельно.',
            ),
          ),
          for (final value in operations)
            Column(
              key: ValueKey('runtime-operation-${value.id}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(clientOperationKindLabel(value.kind, locale: locale)),
                Text(
                  locale.text(
                    en: 'Profile: ${value.profileId.isEmpty ? 'Not specified' : value.profileId}',
                    ru: 'Профиль: ${value.profileId.isEmpty ? 'Не указан' : value.profileId}',
                  ),
                ),
                ClientOperationDetails(
                  operation: ClientOperation.fromProto(value),
                  locale: locale,
                ),
              ],
            ),
        ],
      );
    },
  );
}
