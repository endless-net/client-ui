import 'package:flutter/material.dart';

import 'client_locale.dart';
import 'client_state_controller.dart';

/// Only displays the current validated service snapshot; no inferred addresses.
class ClientDeviceCard extends StatelessWidget {
  const ClientDeviceCard({
    super.key,
    required this.state,
    required this.locale,
  });
  final ClientStateController state;
  final ClientLocale locale;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final status = state.link == ClientLinkState.ready
          ? state.snapshot?.status
          : null;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                locale.text(en: 'This device', ru: 'Это устройство'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.devices_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status?.hostname.isNotEmpty == true
                              ? status!.hostname
                              : locale.text(
                                  en: 'Device name not reported',
                                  ru: 'Имя устройства не сообщено',
                                ),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status?.network.name.isNotEmpty == true
                              ? status!.network.name
                              : locale.text(
                                  en: 'No network selected',
                                  ru: 'Сеть не выбрана',
                                ),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
