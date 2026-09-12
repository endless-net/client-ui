import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_operation.dart';
import 'client_profiles.dart';
import 'client_state_controller.dart';

class ClientProfilesPanel extends StatefulWidget {
  const ClientProfilesPanel({
    super.key,
    required this.state,
    required this.load,
    required this.select,
  });
  final ClientStateController state;
  final Future<ClientProfileCatalog> Function() load;
  final Future<ClientOperation> Function(String profileId) select;
  @override
  State<ClientProfilesPanel> createState() => _ClientProfilesPanelState();
}

class _ClientProfilesPanelState extends State<ClientProfilesPanel> {
  ClientProfileCatalog? _catalog;
  int? _epoch;
  bool _busy = false;
  String? _notice;
  bool get _owner =>
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess != api.Access.ACCESS_OBSERVER;

  Future<void> _run([String? profileId]) async {
    if (_busy || !_owner) return;
    final epoch = widget.state.cacheEpoch;
    setState(() {
      _busy = true;
      _notice = null;
      if (profileId == null || _epoch != epoch) _catalog = null;
      _epoch = epoch;
    });
    try {
      if (profileId == null) {
        final catalog = await widget.load();
        if (!mounted || !_owner || epoch != widget.state.cacheEpoch) return;
        setState(() => _catalog = catalog);
      } else {
        final operation = await widget.select(profileId);
        if (!mounted || !_owner || epoch != widget.state.cacheEpoch) return;
        setState(() {
          // Neither acceptance nor success is a replacement runtime snapshot.
          _catalog = null;
          _notice = operation.terminal
              ? 'Selection result received. Refresh profiles and runtime status.'
              : 'Selection accepted. Recover the operation to see its result.';
        });
      }
    } catch (_) {
      if (!mounted || !_owner || epoch != widget.state.cacheEpoch) return;
      setState(() {
        _catalog = null;
        _notice =
            'Profiles could not be updated. Recover any pending selection before retrying.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final visible = _owner && _epoch == widget.state.cacheEpoch;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            key: const Key('client-load-profiles'),
            onPressed: _owner && !_busy ? () => _run() : null,
            child: const Text('Refresh profiles'),
          ),
          if (visible && _notice != null) Text(_notice!),
          if (visible && _catalog != null) ...[
            if (_catalog!.profiles.isEmpty) const Text('No profiles'),
            for (final profile in _catalog!.profiles)
              ListTile(
                title: Text(profile.displayName),
                subtitle: Text(profile.id),
                trailing: profile.active
                    ? const Text('Active')
                    : TextButton(
                        key: ValueKey('select-profile-${profile.id}'),
                        onPressed:
                            !_busy &&
                                profile.selection.availability ==
                                    api.Availability.AVAILABILITY_AVAILABLE
                            ? () => _run(profile.id)
                            : null,
                        child: const Text('Select'),
                      ),
              ),
          ],
        ],
      );
    },
  );
}
