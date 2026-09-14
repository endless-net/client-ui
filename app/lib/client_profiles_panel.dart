import 'dart:convert';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_operation.dart';
import 'client_locale.dart';
import 'client_profiles.dart';
import 'client_profile_labels.dart';
import 'client_operation_labels.dart';
import 'client_update_labels.dart';
import 'client_state_controller.dart';

enum _ProfileNotice {
  selectionPending,
  selectionResult,
  renamePending,
  renameResult,
  removalPending,
  removalResult,
  failed,
}

class ClientProfilesPanel extends StatefulWidget {
  const ClientProfilesPanel({
    super.key,
    required this.state,
    required this.load,
    required this.select,
    required this.rename,
    required this.remove,
    this.locale = ClientLocale.en,
  });
  final ClientLocale locale;
  final ClientStateController state;
  final Future<ClientProfileCatalog> Function() load;
  final Future<ClientOperation> Function(String profileId) select;
  final Future<ClientOperation> Function(String profileId, String name) rename;
  final Future<ClientOperation> Function(String profileId) remove;
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
  ClientStateController? _catalogState;
  int? _epoch;
  int? _domainEpoch;
  bool get _catalogCurrent =>
      identical(_catalogState, widget.state) &&
      _epoch == widget.state.cacheEpoch &&
      _domainEpoch == widget.state.domainEpoch(api.Domain.DOMAIN_PROFILES);
  bool _busy = false;
  _ProfileNotice? _notice;
  String _text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  String _reported(String value) =>
      value.isEmpty ? _text('Not reported', 'Нет данных') : value;
  String _noticeText(_ProfileNotice notice) => switch (notice) {
    _ProfileNotice.selectionPending => _text(
      'Selection accepted. Recover the operation to see its result.',
      'Выбор профиля принят. Восстановите операцию, чтобы узнать результат.',
    ),
    _ProfileNotice.selectionResult => _text(
      'Selection result received. Refresh profiles and runtime status.',
      'Получен результат выбора профиля. Обновите профили и состояние клиента.',
    ),
    _ProfileNotice.renamePending => _text(
      'Rename accepted. Recover the operation to see its result.',
      'Переименование принято. Восстановите операцию, чтобы узнать результат.',
    ),
    _ProfileNotice.renameResult => _text(
      'Rename result received. Refresh profiles and runtime status.',
      'Получен результат переименования. Обновите профили и состояние клиента.',
    ),
    _ProfileNotice.removalPending => _text(
      'Removal accepted. Recover the operation to see its result.',
      'Удаление принято. Восстановите операцию, чтобы узнать результат.',
    ),
    _ProfileNotice.removalResult => _text(
      'Removal result received. Refresh profiles and runtime status.',
      'Получен результат удаления. Обновите профили и состояние клиента.',
    ),
    _ProfileNotice.failed => _text(
      'Profiles could not be updated. Recover any pending operation before retrying.',
      'Не удалось обновить профили. Восстановите незавершённую операцию перед повторной попыткой.',
    ),
  };
  String? _pendingRemoval;
  Object? _pendingRemovalSnapshot;
  int _confirmationEpoch = 0;
  bool get _owner =>
      mounted &&
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess != api.Access.ACCESS_OBSERVER;

  Future<void> _run({
    String? profileId,
    String? name,
    bool remove = false,
  }) async {
    if (_busy || !_owner) return;
    if (profileId != null && !_catalogCurrent) return;
    if (profileId != null) {
      final profiles = _catalog?.profiles.where((p) => p.id == profileId);
      if (profiles == null || profiles.length != 1) return;
      final profile = profiles.single;
      if (!remove &&
          name == null &&
          (profile.active ||
              profile.selection.availability !=
                  api.Availability.AVAILABILITY_AVAILABLE)) {
        return;
      }
      if (name != null &&
          (name.trim().isEmpty ||
              utf8.encode(name).length > 128 ||
              RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(name))) {
        return;
      }
      if (remove &&
          (_pendingRemoval != profileId ||
              !identical(_pendingRemovalSnapshot, widget.state.snapshot))) {
        return;
      }
    }
    if (remove &&
        !(_catalog?.profiles.any(
              (p) =>
                  p.id == profileId &&
                  !p.active &&
                  p.state == api.ProfileState.PROFILE_STATE_EMPTY,
            ) ??
            false)) {
      return;
    }
    final epoch = widget.state.cacheEpoch;
    final domainEpoch = widget.state.domainEpoch(api.Domain.DOMAIN_PROFILES);
    setState(() {
      _busy = true;
      _notice = null;
      _pendingRemoval = null;
      _pendingRemovalSnapshot = null;
      _confirmationEpoch++;
      _name.clear();
      if (profileId == null || _epoch != epoch) _catalog = null;
      _epoch = epoch;
      _catalogState = widget.state;
      _domainEpoch = domainEpoch;
    });
    try {
      if (profileId == null) {
        final catalog = await widget.load();
        if (!mounted || !_owner || !_catalogCurrent) return;
        setState(() => _catalog = catalog);
      } else {
        final operation = remove
            ? await widget.remove(profileId)
            : name == null
            ? await widget.select(profileId)
            : await widget.rename(profileId, name);
        if (!mounted || !_owner || !_catalogCurrent) return;
        setState(() {
          // Neither acceptance nor success is a replacement runtime snapshot.
          _catalog = null;
          _notice = remove
              ? (operation.terminal
                    ? _ProfileNotice.removalResult
                    : _ProfileNotice.removalPending)
              : name == null
              ? (operation.terminal
                    ? _ProfileNotice.selectionResult
                    : _ProfileNotice.selectionPending)
              : (operation.terminal
                    ? _ProfileNotice.renameResult
                    : _ProfileNotice.renamePending);
        });
      }
    } catch (_) {
      if (!mounted || !_owner || !_catalogCurrent) return;
      setState(() {
        _catalog = null;
        _notice = _ProfileNotice.failed;
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
      final renderedState = widget.state;
      final renderedSnapshot = widget.state.snapshot;
      final renderedCatalog = _catalog;
      final renderedEpoch = widget.state.cacheEpoch;
      final renderedDomain = widget.state.domainEpoch(
        api.Domain.DOMAIN_PROFILES,
      );
      final renderedName = _name.text.trim();
      final removal = identical(_pendingRemovalSnapshot, renderedSnapshot)
          ? _pendingRemoval
          : null;
      final confirmationEpoch = _confirmationEpoch;
      bool current() =>
          mounted &&
          identical(widget.state, renderedState) &&
          identical(widget.state.snapshot, renderedSnapshot) &&
          identical(_catalog, renderedCatalog) &&
          _confirmationEpoch == confirmationEpoch &&
          widget.state.cacheEpoch == renderedEpoch &&
          widget.state.domainEpoch(api.Domain.DOMAIN_PROFILES) ==
              renderedDomain;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            key: const Key('client-load-profiles'),
            onPressed: _owner && !_busy
                ? () {
                    if (current()) _run();
                  }
                : null,
            child: Text(_text('Refresh profiles', 'Обновить профили')),
          ),
          if (visible && _notice != null)
            Semantics(liveRegion: true, child: Text(_noticeText(_notice!))),
          if (visible && _catalog != null) ...[
            if (_catalog!.profiles.isEmpty)
              Text(_text('No profiles', 'Нет профилей')),
            if (_catalog!.profiles.isNotEmpty)
              TextField(
                key: const Key('client-profile-name'),
                controller: _name,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _text(
                    'New profile name (1–128 UTF-8 bytes)',
                    'Новое имя профиля (1–128 байт UTF-8)',
                  ),
                ),
              ),
            for (final profile in _catalog!.profiles)
              ListTile(
                title: Text(profile.displayName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.id),
                    Text(
                      '${_text('Account identity', 'Идентичность аккаунта')}: ${_reported(profile.identityDisplayName)}',
                    ),
                    Text(
                      '${_text('Account ID', 'ID аккаунта')}: ${_reported(profile.accountId)}',
                    ),
                    Text(
                      '${_text('Control origin', 'Адрес сервера управления')}: ${_reported(profile.controlOrigin)}',
                    ),
                    Text(
                      '${_text('Selected network ID', 'ID выбранной сети')}: ${_reported(profile.selectedNetworkId)}',
                    ),
                    Text(
                      '${_text('Profile state', 'Состояние профиля')}: ${clientProfileStateLabel(profile.state, widget.locale)}',
                    ),
                    if (!profile.active) ...[
                      Text(
                        '${_text('Selection', 'Выбор')}: ${updateAvailabilityLabel(profile.selection.availability, widget.locale)}',
                      ),
                      Text(
                        '${_text('Action owner', 'Ответственный за действие')}: ${clientActionOwnerLabel(profile.selection.actionOwner, locale: widget.locale)}',
                      ),
                    ],
                    Wrap(
                      children: [
                        TextButton(
                          key: ValueKey('rename-profile-${profile.id}'),
                          onPressed: !_busy && _validName
                              ? () {
                                  if (!current() ||
                                      !_validName ||
                                      _name.text.trim() != renderedName) {
                                    return;
                                  }
                                  _run(
                                    profileId: profile.id,
                                    name: renderedName,
                                  );
                                }
                              : null,
                          child: Text(
                            _text('Rename', 'Переименовать'),
                            semanticsLabel: _text(
                              'Rename profile ${profile.displayName}, ID ${profile.id}',
                              'Переименовать профиль ${profile.displayName}, ID ${profile.id}',
                            ),
                          ),
                        ),
                        profile.active
                            ? Text(_text('Active', 'Активный'))
                            : TextButton(
                                key: ValueKey('select-profile-${profile.id}'),
                                onPressed:
                                    !_busy &&
                                        profile.selection.availability ==
                                            api
                                                .Availability
                                                .AVAILABILITY_AVAILABLE
                                    ? () {
                                        if (current()) {
                                          _run(profileId: profile.id);
                                        }
                                      }
                                    : null,
                                child: Text(
                                  _text('Select', 'Выбрать'),
                                  semanticsLabel: _text(
                                    'Select profile ${profile.displayName}, ID ${profile.id}',
                                    'Выбрать профиль ${profile.displayName}, ID ${profile.id}',
                                  ),
                                ),
                              ),
                        TextButton(
                          key: ValueKey('remove-profile-${profile.id}'),
                          onPressed:
                              !_busy &&
                                  !profile.active &&
                                  profile.state ==
                                      api.ProfileState.PROFILE_STATE_EMPTY
                              ? () {
                                  if (current()) {
                                    setState(() {
                                      _pendingRemoval = profile.id;
                                      _pendingRemovalSnapshot =
                                          widget.state.snapshot;
                                      _confirmationEpoch++;
                                    });
                                  }
                                }
                              : null,
                          child: Text(
                            _text('Remove', 'Удалить'),
                            semanticsLabel: _text(
                              'Remove profile ${profile.displayName}, ID ${profile.id}',
                              'Удалить профиль ${profile.displayName}, ID ${profile.id}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (removal != null) ...[
              Text(
                _text(
                  'Remove profile $removal? This does not log out or clean up a remote registration.',
                  'Удалить профиль $removal? Это не выполняет выход и не удаляет регистрацию на сервере.',
                ),
              ),
              Wrap(
                children: [
                  TextButton(
                    key: const Key('cancel-profile-removal'),
                    onPressed: !_busy
                        ? () {
                            if (current() && _pendingRemoval == removal) {
                              setState(() {
                                _pendingRemoval = null;
                                _confirmationEpoch++;
                              });
                            }
                          }
                        : null,
                    child: Text(_text('Cancel', 'Отмена')),
                  ),
                  TextButton(
                    key: const Key('confirm-profile-removal'),
                    onPressed: !_busy
                        ? () {
                            if (current() && _pendingRemoval == removal) {
                              _run(profileId: removal, remove: true);
                            }
                          }
                        : null,
                    child: Text(
                      _text('Confirm removal', 'Подтвердить удаление'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      );
    },
  );
}
