import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_operation.dart';
import 'client_state_controller.dart';

class ClientCleanupPanel extends StatefulWidget {
  const ClientCleanupPanel({
    super.key,
    required this.state,
    required this.logout,
    required this.forget,
    this.canElevate = false,
  });
  final ClientStateController state;
  final Future<ClientOperation> Function(String profileId) logout;
  final Future<ClientOperation> Function(String profileId) forget;
  final bool canElevate;
  @override
  State<ClientCleanupPanel> createState() => _ClientCleanupPanelState();
}

class _ClientCleanupPanelState extends State<ClientCleanupPanel> {
  bool? _forget;
  int? _epoch;
  bool _busy = false;
  String? _notice;

  bool _allowed(bool forget) {
    final snapshot = widget.state.snapshot;
    return mounted &&
        !_busy &&
        widget.state.link == ClientLinkState.ready &&
        snapshot != null &&
        snapshot.status.activeProfileId.isNotEmpty &&
        (forget
            ? (snapshot.runtime.callerAccess ==
                      api.Access.ACCESS_ADMINISTRATOR ||
                  (snapshot.runtime.callerAccess == api.Access.ACCESS_OWNER &&
                      widget.canElevate))
            : snapshot.runtime.callerAccess != api.Access.ACCESS_OBSERVER) &&
        snapshot.supports(
          forget
              ? api.Capability.CAPABILITY_LOCAL_FORGET
              : api.Capability.CAPABILITY_LOGOUT,
        );
  }

  void _confirm(bool forget) {
    if (!_allowed(forget)) return;
    setState(() {
      _forget = forget;
      _epoch = widget.state.cacheEpoch;
      _notice = null;
    });
  }

  Future<void> _submit() async {
    final forget = _forget;
    final epoch = _epoch;
    if (forget == null ||
        epoch != widget.state.cacheEpoch ||
        !_allowed(forget)) {
      return;
    }
    final profileId = widget.state.snapshot!.status.activeProfileId;
    setState(() {
      _busy = true;
      _forget = null;
    });
    try {
      final operation = await (forget
          ? widget.forget(profileId)
          : widget.logout(profileId));
      if (!mounted || epoch != widget.state.cacheEpoch) return;
      setState(
        () => _notice = operation.terminal
            ? 'Cleanup result received. Recover it to inspect remote and local outcomes.'
            : 'Cleanup accepted. Recover the operation; removal is not yet confirmed.',
      );
    } catch (_) {
      if (!mounted || epoch != widget.state.cacheEpoch) return;
      setState(
        () => _notice =
            'Cleanup could not be confirmed. Recover the intention. No other cleanup command was sent.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final current = _epoch == widget.state.cacheEpoch;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            children: [
              OutlinedButton(
                key: const Key('client-logout'),
                onPressed: _allowed(false) ? () => _confirm(false) : null,
                child: const Text('Log out'),
              ),
              OutlinedButton(
                key: const Key('client-local-forget'),
                onPressed: _allowed(true) ? () => _confirm(true) : null,
                child: const Text('Forget local enrollment'),
              ),
            ],
          ),
          if (current && _forget != null) ...[
            if (_forget! &&
                widget.canElevate &&
                widget.state.snapshot!.runtime.callerAccess ==
                    api.Access.ACCESS_OWNER)
              const Text(
                'Confirmation will open the system administrator approval prompt.',
              ),
            Text(
              _forget!
                  ? 'Remove local registration without confirmed remote cleanup? Remote registration may remain. Installation ownership is retained.'
                  : 'Log out the selected profile? Remote cleanup must be confirmed before local registration is removed.',
            ),
            Wrap(
              children: [
                TextButton(
                  key: const Key('cancel-client-cleanup'),
                  onPressed: () {
                    if (mounted) setState(() => _forget = null);
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  key: const Key('confirm-client-cleanup'),
                  onPressed: _allowed(_forget!) ? _submit : null,
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ],
          if (current && _notice != null) Text(_notice!),
        ],
      );
    },
  );
}
