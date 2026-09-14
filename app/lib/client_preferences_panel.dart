import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_operation.dart';
import 'client_preferences.dart';
import 'client_state_controller.dart';
import 'client_locale.dart';
import 'client_preference_labels.dart';
import 'client_resource_labels.dart';
import 'client_update_labels.dart';
import 'client_operation_labels.dart';

enum _PreferenceNotice { received, unknown }

class ClientPreferencesPanel extends StatefulWidget {
  const ClientPreferencesPanel({
    super.key,
    required this.state,
    required this.load,
    required this.apply,
    required this.reset,
    this.locale = ClientLocale.en,
  });
  final ClientStateController state;
  final ClientLocale locale;
  final Future<ClientPreferences> Function() load;
  final Future<ClientOperation> Function(
    String,
    api.PreferencesPatch,
    void Function(),
  )
  apply;
  final Future<ClientOperation> Function(
    String,
    List<api.PreferenceKey>,
    void Function(),
  )
  reset;
  @override
  State<ClientPreferencesPanel> createState() => _ClientPreferencesPanelState();
}

class _ClientPreferencesPanelState extends State<ClientPreferencesPanel> {
  ClientPreferences? _projection;
  final _draft = <api.PreferenceKey, Object>{};
  String? _context;
  _PreferenceNotice? _notice;
  int _draftSerial = 0;
  String _text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  String _value(Object? value) => preferenceValueLabel(value, widget.locale);
  bool _busy = false;
  String get contextId =>
      '${widget.state.cacheEpoch}:'
      '${[api.Domain.DOMAIN_PROFILES, api.Domain.DOMAIN_PREFERENCES, api.Domain.DOMAIN_MANAGED_SETTINGS].map(widget.state.domainEpoch).join(',')}';
  bool get allowed =>
      mounted &&
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess !=
          api.Access.ACCESS_OBSERVER &&
      widget.state.snapshot!.status.activeProfileId.isNotEmpty &&
      widget.state.snapshot!.supports(api.Capability.CAPABILITY_PREFERENCES) &&
      widget.state.snapshot!.supports(
        api.Capability.CAPABILITY_MANAGED_SETTINGS,
      );
  bool get current => allowed && _context == contextId;
  void _clear() {
    _projection = null;
    _draft.clear();
    _draftSerial++;
    _context = null;
    _notice = null;
  }

  void _changed() {
    if (_context != null && !current) setState(_clear);
  }

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant ClientPreferencesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_changed);
      widget.state.addListener(_changed);
      _clear();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    _clear();
    super.dispose();
  }

  Future<void> _run({bool apply = false, api.PreferenceKey? reset}) async {
    if (!allowed || _busy) return;
    if (reset != null && _draft.isNotEmpty) return;
    final projection = _projection;
    if ((apply || reset != null) && (!current || projection == null)) return;
    final entries = projection == null ? <_Entry>[] : _entries(projection);
    if (apply &&
        (_draft.isEmpty ||
            _draft.entries.any(
              (draft) => !entries.any(
                (entry) =>
                    entry.key == draft.key &&
                    entry.editable &&
                    entry.values.contains(draft.value),
              ),
            ))) {
      return;
    }
    if (reset != null &&
        !entries.any(
          (entry) =>
              entry.key == reset && entry.editable && entry.requested != null,
        )) {
      return;
    }
    final patch = api.PreferencesPatch();
    for (final entry in _draft.entries) {
      switch (entry.key) {
        case api.PreferenceKey.PREFERENCE_KEY_UNSPECIFIED:
          throw StateError('Unknown preference key');
        case api.PreferenceKey.PREFERENCE_KEY_ALLOW_INBOUND:
          patch.allowInbound = entry.value as bool;
        case api.PreferenceKey.PREFERENCE_KEY_ACCEPT_DNS:
          patch.acceptDns = entry.value as bool;
        case api.PreferenceKey.PREFERENCE_KEY_ACCEPT_ROUTES:
          patch.acceptRoutes = entry.value as bool;
        case api.PreferenceKey.PREFERENCE_KEY_RUNTIME_START:
          patch.runtimeStart = entry.value as api.LifecycleBehavior;
        case api.PreferenceKey.PREFERENCE_KEY_UI_QUIT:
          patch.uiQuit = entry.value as api.LifecycleBehavior;
        case api.PreferenceKey.PREFERENCE_KEY_USER_LOGOFF:
          patch.userLogoff = entry.value as api.LifecycleBehavior;
        case api.PreferenceKey.PREFERENCE_KEY_SUSPEND:
          patch.suspend = entry.value as api.LifecycleBehavior;
        case api.PreferenceKey.PREFERENCE_KEY_RESUME:
          patch.resume = entry.value as api.LifecycleBehavior;
      }
    }
    patch.freeze();
    final context = contextId;
    final profile = widget.state.snapshot!.status.activeProfileId;
    void checkContext() {
      if (!mounted || !current || context != contextId || _context != context) {
        throw StateError('Preferences changed before command completion');
      }
    }

    setState(() {
      _context = context;
      _busy = true;
      _notice = null;
    });
    try {
      if (apply || reset != null) {
        checkContext();
        if (apply) {
          await widget.apply(profile, patch, checkContext);
        } else {
          await widget.reset(
            profile,
            List.unmodifiable([reset!]),
            checkContext,
          );
        }
        checkContext();
        setState(() {
          _projection = null;
          _draft.clear();
          _draftSerial++;
          _notice = _PreferenceNotice.received;
        });
      } else {
        setState(() {
          _projection = null;
          _draft.clear();
          _draftSerial++;
        });
        final loaded = await widget.load();
        checkContext();
        if (loaded.preferences.profileId != profile ||
            loaded.preferences.metadata.instanceId !=
                widget.state.snapshot!.runtime.instanceId ||
            loaded.preferences.metadata.revision <
                widget.state.snapshot!.status.metadata.revision) {
          throw const FormatException('Stale preference response');
        }
        setState(() => _projection = loaded);
      }
    } catch (_) {
      if (!mounted || !current || context != _context) return;
      setState(() {
        _projection = null;
        _draft.clear();
        _draftSerial++;
        _notice = _PreferenceNotice.unknown;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final view = _projection;
      final viewContext = _context;
      final serial = _draftSerial;
      bool validView() =>
          current &&
          serial == _draftSerial &&
          !_busy &&
          identical(view, _projection) &&
          viewContext == _context;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            key: const Key('client-load-preferences'),
            onPressed: allowed && !_busy ? () => _run() : null,
            child: Text(_text('Refresh preferences', 'Обновить настройки')),
          ),
          if (current && _notice != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _notice == _PreferenceNotice.received
                    ? _text(
                        'Preference operation received. Recover its result and refresh effective values.',
                        'Операция настройки получена. Восстановите её результат и обновите фактические значения.',
                      )
                    : _text(
                        'Preferences could not be confirmed. Recover pending operations before retrying.',
                        'Не удалось подтвердить настройки. Восстановите незавершённые операции перед повторной попыткой.',
                      ),
              ),
            ),
          if (current && _projection != null) ...[
            for (final entry in _entries(_projection!))
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(preferenceKeyLabel(entry.key, widget.locale)),
                  Text(
                    '${_text('Effective', 'Фактически')}: ${_value(entry.effective)}; ${_text('requested', 'Запрошено')}: ${_value(entry.requested)}',
                  ),
                  for (final control in entry.controls)
                    Text(
                      '${_text('Source', 'Источник')}: ${settingSourceLabel(control.source, widget.locale)}; ${_text('locked', 'Заблокировано')}: ${_value(control.locked)}; '
                      '${_text('availability', 'Доступность')}: ${updateAvailabilityLabel(control.mutation.availability, widget.locale)}; '
                      '${_text('reason', 'Код причины')}: ${control.mutation.reasonKey}; ${_text('owner', 'Ответственный')}: ${clientActionOwnerLabel(control.mutation.actionOwner, locale: widget.locale)}',
                    ),
                  DropdownButton<Object>(
                    itemHeight: null,
                    key: ValueKey('preference-${entry.key.value}'),
                    isExpanded: true,
                    value: _draft[entry.key],
                    hint: Text(
                      _text('Leave unchanged', 'Оставить без изменений'),
                    ),
                    items: [
                      for (final value in entry.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(_value(value)),
                        ),
                    ],
                    onChanged: !_busy && entry.editable
                        ? (value) {
                            if (value != null &&
                                validView() &&
                                entry.values.contains(value)) {
                              setState(() {
                                _draft[entry.key] = value;
                                _draftSerial++;
                              });
                            }
                          }
                        : null,
                  ),
                  TextButton(
                    key: ValueKey('reset-preference-${entry.key.value}'),
                    onPressed:
                        !_busy &&
                            _draft.isEmpty &&
                            entry.editable &&
                            entry.requested != null
                        ? () {
                            if (validView()) _run(reset: entry.key);
                          }
                        : null,
                    child: Text(
                      _text('Reset override', 'Сбросить переопределение'),
                    ),
                  ),
                ],
              ),
            OutlinedButton(
              key: const Key('client-discard-preferences'),
              onPressed: !_busy && _draft.isNotEmpty
                  ? () {
                      if (validView()) {
                        setState(() {
                          _draft.clear();
                          _draftSerial++;
                        });
                      }
                    }
                  : null,
              child: Text(_text('Discard draft', 'Отменить правки')),
            ),
            FilledButton(
              key: const Key('client-apply-preferences'),
              onPressed: !_busy && _draft.isNotEmpty
                  ? () {
                      if (validView()) _run(apply: true);
                    }
                  : null,
              child: Text(
                _text('Apply preference patch', 'Применить изменения настроек'),
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _Entry {
  _Entry(this.key, this.effective, this.requested, this.values, this.controls);
  final api.PreferenceKey key;
  final Object effective;
  final Object? requested;
  final List<Object> values;
  final List<api.SettingControl> controls;
  bool get editable =>
      values.isNotEmpty &&
      controls.isNotEmpty &&
      controls.every(
        (c) =>
            !c.locked &&
            c.mutation.availability == api.Availability.AVAILABILITY_AVAILABLE,
      );
}

List<_Entry> _entries(ClientPreferences projection) {
  final p = projection.preferences;
  final result = <_Entry>[];
  List<api.SettingControl> controls(
    api.PreferenceKey key,
    api.SettingControl control,
  ) => [
    control,
    for (final managed in projection.managed)
      if (managed.key == key) managed.control,
  ];
  void boolean(api.PreferenceKey key, api.BooleanSetting setting) {
    result.add(
      _Entry(
        key,
        setting.effective,
        setting.hasRequested() ? setting.requested : null,
        [false, true],
        controls(key, setting.control),
      ),
    );
  }

  void lifecycle(api.PreferenceKey key, api.LifecycleSetting setting) {
    result.add(
      _Entry(
        key,
        setting.effective,
        setting.hasRequested() ? setting.requested : null,
        setting.allowedValues
            .where(
              (v) => v != api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_UNSPECIFIED,
            )
            .toSet()
            .toList(),
        controls(key, setting.control),
      ),
    );
  }

  if (p.hasAllowInbound()) {
    boolean(api.PreferenceKey.PREFERENCE_KEY_ALLOW_INBOUND, p.allowInbound);
  }
  if (p.hasAcceptDns()) {
    boolean(api.PreferenceKey.PREFERENCE_KEY_ACCEPT_DNS, p.acceptDns);
  }
  if (p.hasAcceptRoutes()) {
    boolean(api.PreferenceKey.PREFERENCE_KEY_ACCEPT_ROUTES, p.acceptRoutes);
  }
  final l = p.lifecycle;
  if (l.hasRuntimeStart()) {
    lifecycle(api.PreferenceKey.PREFERENCE_KEY_RUNTIME_START, l.runtimeStart);
  }
  if (l.hasUiQuit()) {
    lifecycle(api.PreferenceKey.PREFERENCE_KEY_UI_QUIT, l.uiQuit);
  }
  if (l.hasUserLogoff()) {
    lifecycle(api.PreferenceKey.PREFERENCE_KEY_USER_LOGOFF, l.userLogoff);
  }
  if (l.hasSuspend()) {
    lifecycle(api.PreferenceKey.PREFERENCE_KEY_SUSPEND, l.suspend);
  }
  if (l.hasResume()) {
    lifecycle(api.PreferenceKey.PREFERENCE_KEY_RESUME, l.resume);
  }
  return result;
}
