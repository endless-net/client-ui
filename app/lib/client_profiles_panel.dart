import 'dart:convert';

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
    required this.rename,
  });
  final ClientStateController state;
  final Future<ClientProfileCatalog> Function() load;
  final Future<ClientOperation> Function(String profileId) select;
  final Future<ClientOperation> Function(String profileId, String name) rename;
  @override
  State<ClientProfilesPanel> createState() => _ClientProfilesPanelState();
}

class _ClientProfilesPanelState extends State<ClientProfilesPanel> {
  final _name = TextEditingController();
  bool get _validName =>
      _name.text.trim().isNotEmpty &&
      utf8.encode(_name.text.trim()).length <= 128 &&
      !RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(_name.text);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ClientProfileCatalog? _catalog;
  int? _epoch;
  int? _domainEpoch;
  bool get _catalogCurrent =>
      _epoch == widget.state.cacheEpoch &&
      _domainEpoch == widget.state.domainEpoch(api.Domain.DOMAIN_PROFILES);
  bool _busy = false;
  String? _notice;
  bool get _owner =>
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess != api.Access.ACCESS_OBSERVER;

  Future<void> _run([String? profileId, String? name]) async {
    if (_busy || !_owner) return;
    final epoch = widget.state.cacheEpoch;
    final domainEpoch = widget.state.domainEpoch(api.Domain.DOMAIN_PROFILES);
    setState(() {
      _busy = true;
      _notice = null;
      _name.clear();
      if (profileId == null || _epoch != epoch) _catalog = null;
      _epoch = epoch;
      _domainEpoch = domainEpoch;
    });
    try {
      if (profileId == null) {
        final catalog = await widget.load();
        if (!mounted || !_owner || !_catalogCurrent) return;
        setState(() => _catalog = catalog);
      } else {
        final operation = name == null
            ? await widget.select(profileId)
            : await widget.rename(profileId, name);
        if (!mounted || !_owner || !_catalogCurrent) return;
        setState(() {
          // Neither acceptance nor success is a replacement runtime snapshot.
          _catalog = null;
          final action = name == null ? 'Selection' : 'Rename';
          _notice = operation.terminal
              ? '$action result received. Refresh profiles and runtime status.'
              : '$action accepted. Recover the operation to see its result.';
        });
      }
    } catch (_) {
      if (!mounted || !_owner || !_catalogCurrent) return;
      setState(() {
        _catalog = null;
        _notice =
            'Profiles could not be updated. Recover any pending operation before retrying.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final visible = _owner && _catalogCurrent;
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
            if (_catalog!.profiles.isNotEmpty)
              TextField(
                key: const Key('client-profile-name'),
                controller: _name,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'New profile name (1–128 UTF-8 bytes)',
                ),
              ),
            for (final profile in _catalog!.profiles)
              ListTile(
                title: Text(profile.displayName),
                subtitle: Text(profile.id),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      key: ValueKey('rename-profile-${profile.id}'),
                      onPressed: !_busy && _validName
                          ? () => _run(profile.id, _name.text.trim())
                          : null,
                      child: const Text('Rename'),
                    ),
                    profile.active
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
                  ],
                ),
              ),
          ],
        ],
      );
    },
  );
}
