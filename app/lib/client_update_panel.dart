import 'dart:async';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'client_state_controller.dart';
import 'client_locale.dart';
import 'client_update_labels.dart';
import 'client_operation_labels.dart';

enum _UpdateNotice { expired, unknown }

class ClientUpdatePanel extends StatefulWidget {
  const ClientUpdatePanel({
    super.key,
    required this.state,
    required this.uiBuild,
    required this.load,
    this.locale = ClientLocale.en,
  });
  final ClientStateController state;
  final ClientLocale locale;
  final api.BuildIdentity uiBuild;
  final Future<api.UpdateInfo> Function(api.BuildIdentity) load;
  @override
  State<ClientUpdatePanel> createState() => _ClientUpdatePanelState();
}

class _ClientUpdatePanelState extends State<ClientUpdatePanel> {
  api.UpdateInfo? _info;
  String? _context;
  _UpdateNotice? _notice;
  String _text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  String get _unknown => _text('Unknown', 'Неизвестно');
  bool _busy = false;
  Object? _request;
  Timer? _expiry;
  String get contextId =>
      '${widget.state.cacheEpoch}:${widget.state.domainEpoch(api.Domain.DOMAIN_UPDATES)}';
  bool get allowed =>
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess != api.Access.ACCESS_OBSERVER;
  bool get current => allowed && _context == contextId;
  void _reset() {
    _request = null;
    _busy = false;
    _expiry?.cancel();
    _expiry = null;
    _info = null;
    _context = null;
    _notice = null;
  }

  void _changed() {
    if (_context != null && !current) setState(_reset);
  }

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant ClientUpdatePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.uiBuild != widget.uiBuild) {
      oldWidget.state.removeListener(_changed);
      widget.state.addListener(_changed);
      _reset();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    _reset();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted || !allowed || _busy) return;
    final context = contextId;
    final request = Object();
    final originalState = widget.state;
    final ui = api.BuildIdentity.fromBuffer(widget.uiBuild.writeToBuffer())
      ..freeze();
    setState(() {
      _reset();
      _request = request;
      _context = context;
      _busy = true;
    });
    try {
      final result = await widget.load(ui);
      if (!mounted ||
          !identical(request, _request) ||
          !identical(originalState, widget.state) ||
          !current ||
          context != _context ||
          widget.uiBuild != ui) {
        return;
      }
      if (result.metadata.instanceId !=
              widget.state.snapshot!.runtime.instanceId ||
          result.metadata.revision <
              widget.state.snapshot!.status.metadata.revision ||
          result.reportedUi != ui) {
        throw const FormatException('Stale update projection');
      }
      final info = api.UpdateInfo.fromBuffer(result.writeToBuffer())..freeze();
      if (info.hasAvailable()) {
        final remaining = info.available.expiresAt.toDateTime().difference(
          DateTime.now().toUtc(),
        );
        if (remaining <= Duration.zero) {
          throw const FormatException('Expired update projection');
        }
        _expiry = Timer(remaining, () {
          if (mounted && current && identical(_info, info)) {
            setState(() {
              _info = null;
              _notice = _UpdateNotice.expired;
            });
          }
        });
      }
      setState(() => _info = info);
    } catch (_) {
      if (mounted &&
          identical(request, _request) &&
          identical(originalState, widget.state) &&
          current &&
          context == _context) {
        setState(() => _notice = _UpdateNotice.unknown);
      }
    } finally {
      if (mounted && identical(request, _request)) {
        setState(() => _busy = false);
      }
    }
  }

  String identity(api.BuildIdentity value) =>
      '${value.version.isEmpty ? _unknown : value.version}; ${_text('commit', 'коммит')} ${value.commit.isEmpty ? _unknown : value.commit}; ${_text('built', 'собрано')} ${value.buildDate.isEmpty ? _unknown : value.buildDate}; ${buildPlatformLabel(value.platform, widget.locale)}/${value.architecture}';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final info = current ? _info : null;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_text('UI build', 'Сборка интерфейса')}: ${identity(widget.uiBuild)}',
          ),
          if (widget.state.snapshot != null)
            Text(
              '${_text('Runtime build', 'Сборка службы')}: ${identity(widget.state.snapshot!.runtime.build)}',
            ),
          OutlinedButton(
            key: const Key('client-check-updates'),
            onPressed: allowed && !_busy ? _load : null,
            child: Text(_text('Check updates', 'Проверить обновления')),
          ),
          if (current && _notice != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _notice == _UpdateNotice.expired
                    ? _text(
                        'Update metadata expired. Check again.',
                        'Срок действия сведений об обновлении истёк. Проверьте снова.',
                      )
                    : _text(
                        'Update information could not be confirmed.',
                        'Не удалось подтвердить сведения об обновлении.',
                      ),
              ),
            ),
          if (info != null) ...[
            Text(
              '${_text('Update source', 'Источник обновлений')}: ${updateStateLabel(info.state, widget.locale)}',
            ),
            Text(
              '${_text('Installed pair', 'Установленная пара')}: ${compatibilityLabel(info.installedPair.state, widget.locale)}; ${info.installedPair.reasonKey}',
            ),
            Text(
              '${_text('Discovery', 'Поиск обновлений')}: ${updateAvailabilityLabel(info.discovery.availability, widget.locale)}; ${info.discovery.reasonKey}; ${clientActionOwnerLabel(info.discovery.actionOwner, locale: widget.locale)}',
            ),
            if (info.hasAvailable()) ...[
              Text(
                '${_text('Release', 'Выпуск')}: ${info.available.releaseId}; ${updateClassificationLabel(info.available.classification, widget.locale)}',
              ),
              Text(
                '${_text('Offered runtime', 'Предлагаемая служба')}: ${identity(info.available.runtime)}; ${_text('paired UI', 'парный интерфейс')}: ${info.available.pairedUiVersion}',
              ),
              Text(
                '${_text('Distribution', 'Распространение')}: ${distributionLabel(info.available.channel, widget.locale)}; ${_text('pair', 'пара')}: ${compatibilityLabel(info.available.compatibility.state, widget.locale)}',
              ),
              Text(
                '${_text('Verified until', 'Проверено до')}: ${info.available.expiresAt.toDateTime().toUtc().toIso8601String()}',
              ),
              Text(
                _text(
                  'Installation and its outcome belong to the distribution provider. This notice does not install or disconnect.',
                  'Установку и её результат обеспечивает поставщик канала распространения. Это уведомление ничего не устанавливает и не отключает.',
                ),
              ),
            ],
          ],
        ],
      );
    },
  );
}
