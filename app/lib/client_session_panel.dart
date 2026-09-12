import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/widgets.dart';

import 'client_connection_panel.dart';
import 'client_session.dart';

/// Desktop application binding. A mobile runtime adapter can supply the same
/// shared connection panel without using a desktop local channel.
class ClientSessionPanel extends StatelessWidget {
  const ClientSessionPanel({super.key, required this.session});
  final ClientSession session;

  @override
  Widget build(BuildContext context) => ClientConnectionPanel(
    state: session.state,
    renewSession: () => session.submit(
      api.OperationKind.OPERATION_KIND_RENEW_SESSION,
      (commands, mutation) => commands.renewSession(
        api.RenewSessionRequest(
          mutation: mutation,
          profile: api.ProfileRef(
            profileId: session.state.snapshot!.status.activeProfileId,
          ),
        ),
      ),
    ),
    connect: () => session.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
      commands,
      mutation,
    ) {
      return commands.connect(
        api.ConnectRequest(
          mutation: mutation,
          profile: api.ProfileRef(
            profileId: session.state.snapshot!.status.activeProfileId,
          ),
        ),
      );
    }),
    disconnect: () => session.submit(
      api.OperationKind.OPERATION_KIND_DISCONNECT,
      (commands, mutation) {
        return commands.disconnect(
          api.DisconnectRequest(
            mutation: mutation,
            profile: api.ProfileRef(
              profileId: session.state.snapshot!.status.activeProfileId,
            ),
          ),
        );
      },
    ),
  );
}
