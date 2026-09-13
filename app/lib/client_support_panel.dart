import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'client_state_controller.dart';
import 'client_support_info.dart';
import 'client_locale.dart';

class ClientSupportPanel extends StatefulWidget {
  const ClientSupportPanel({
    super.key,
    required this.state,
    required this.load,
    required this.openBrowser,
    this.locale = ClientLocale.en,
  });
  final ClientStateController state;
  final ClientLocale locale;
  final Future<api.SupportInfo> Function() load;
  final Future<bool> Function(Uri, void Function()) openBrowser;
  @override
  State<ClientSupportPanel> createState() => _ClientSupportPanelState();
}

class _ClientSupportPanelState extends State<ClientSupportPanel> {
  api.SupportInfo? _info;
  String? _context;
  bool _failed = false;
  String _text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  String _linkLabel(String key) => switch (key) {
    'documentation' => _text('Open documentation', 'Открыть документацию'),
    'support' => _text('Open support', 'Открыть поддержку'),
    'privacy' => _text('Open privacy', 'Открыть политику конфиденциальности'),
    'license' => _text('Open license', 'Открыть лицензию'),
    _ => throw StateError('Unknown support link'),
  };
  bool _busy = false;
  bool _help = false;
  String get contextId =>
      '${widget.state.cacheEpoch}:${widget.state.domainEpoch(api.Domain.DOMAIN_SUPPORT)}';
  bool get allowed =>
      mounted &&
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null;
  bool get current => allowed && _context == contextId;
  void _reset() {
    _info = null;
    _context = null;
    _failed = false;
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
  void didUpdateWidget(covariant ClientSupportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
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

  String link(api.SupportInfo info, String key) => switch (key) {
    'documentation' => info.documentationUrl,
    'support' => info.supportUrl,
    'privacy' => info.privacyUrl,
    'license' => info.licenseUrl,
    _ => '',
  };
  Future<void> _run([String? key]) async {
    if (!allowed || _busy || (key != null && (!current || _info == null))) {
      return;
    }
    final original = key == null ? null : link(_info!, key);
    if (original == '') return;
    final context = contextId;
    final originalState = widget.state;
    final build = widget.state.snapshot!.runtime.build;
    void check() {
      if (!mounted ||
          !identical(widget.state, originalState) ||
          !current ||
          context != _context) {
        throw StateError('Support context changed');
      }
    }

    setState(() {
      _context = context;
      _busy = true;
      _failed = false;
      if (key == null) _info = null;
    });
    try {
      final loaded = await widget.load();
      check();
      final info = await readClientSupportInfo(
        installedRuntime: build,
        get: (_) async => api.GetSupportInfoResponse(info: loaded),
        checkContext: check,
      );
      check();
      if (key != null) {
        final destination = link(info, key);
        if (destination != original || destination.isEmpty) {
          throw StateError('Support destination changed');
        }
        check();
        final opened = await widget.openBrowser(Uri.parse(destination), check);
        check();
        if (!opened) throw StateError('Browser did not confirm opening');
      }
      setState(() => _info = info);
    } catch (_) {
      if (mounted &&
          identical(widget.state, originalState) &&
          current &&
          context == _context) {
        setState(() {
          _info = null;
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final info = current ? _info : null;
      final viewContext = _context;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            key: const Key('client-offline-help'),
            onPressed: () {
              if (mounted) setState(() => _help = !_help);
            },
            child: Text(_text('Offline help', 'Справка без интернета')),
          ),
          if (_help)
            Text(
              _text(
                'Built-in help: Reconnect runtime if its status is unavailable. '
                    'An accepted operation is not a completed result: recover pending operations before retrying. '
                    'Logout and Forget local enrollment are different actions. Never share enrollment tokens or private keys. '
                    'Use explicit diagnostics export when requesting support; inspect the file before sharing.',
                'Встроенная справка: переподключитесь к службе, если её состояние недоступно. '
                    'Принятие операции не означает завершения: восстановите незавершённые операции перед повтором. '
                    'Выход и удаление локальной регистрации — разные действия. Никому не передавайте токены регистрации и закрытые ключи. '
                    'Для обращения в поддержку явно экспортируйте диагностику; проверьте файл перед отправкой.',
              ),
            ),
          OutlinedButton(
            key: const Key('client-load-support'),
            onPressed: allowed && !_busy ? () => _run() : null,
            child: Text(
              _text(
                'Refresh support information',
                'Обновить сведения о поддержке',
              ),
            ),
          ),
          if (current && _failed)
            Semantics(
              liveRegion: true,
              child: Text(
                _text(
                  'Support information could not be confirmed. Refresh before opening a link.',
                  'Не удалось подтвердить сведения о поддержке. Обновите их перед открытием ссылки.',
                ),
              ),
            ),
          if (info != null) ...[
            Text('${_text('Product', 'Продукт')}: ${info.productName}'),
            if (info.offlineHelpKey.isNotEmpty)
              Text(
                _text(
                  'The runtime-requested offline topic is not bundled. Built-in help remains available.',
                  'Запрошенная службой тема отсутствует во встроенной справке. Общая справка остаётся доступной.',
                ),
              ),
            for (final key in [
              'documentation',
              'support',
              'privacy',
              'license',
            ])
              if (link(info, key).isNotEmpty)
                OutlinedButton(
                  key: Key('client-support-$key'),
                  onPressed: !_busy
                      ? () {
                          if (current &&
                              identical(info, _info) &&
                              viewContext == _context) {
                            _run(key);
                          }
                        }
                      : null,
                  child: Text(_linkLabel(key)),
                ),
          ],
        ],
      );
    },
  );
}
