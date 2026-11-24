import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_ui/endlessnet_ui.dart';
import 'package:flutter/material.dart';

import '../connectivity/controller.dart';
import '../connectivity/panel.dart';
import '../update/controller.dart';
import 'board.dart';
import 'board_view.dart';
import 'server_board.dart';
import 'telemetry.dart';
import 'tiles.dart';

enum _Section {
  overview('Обзор', Icons.space_dashboard_outlined),
  devices('Устройства', Icons.devices_outlined),
  catalog('Каталог виджетов', Icons.widgets_outlined);

  const _Section(this.title, this.icon);
  final String title;
  final IconData icon;
}

enum _Panel { account, tunnel, settings }

String _systemName() {
  final version = Platform.operatingSystemVersion.split('\n').first.trim();
  if (!Platform.isWindows) return version;
  final edition = RegExp(r'"([^"]+)"').firstMatch(version)?.group(1) ?? version;
  return edition.replaceFirst(RegExp(r'^(Microsoft|Майкрософт)\s+'), '');
}

class DashboardHome extends StatefulWidget {
  const DashboardHome({
    super.key,
    required this.host,
    required this.account,
    required this.tunnelDetails,
    required this.settings,
    this.connectivity,
    this.updates,
    this.blockingMessage,
    this.boardStore,
    this.serverBoard,
  });
  final String host;
  final Widget account, tunnelDetails, settings;
  final ConnectivityController? connectivity;
  final UpdateController? updates;
  final String? blockingMessage;
  final BoardStore? boardStore;
  final BoardModel? serverBoard;

  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome> {
  late final BoardModel _preview;
  BoardModel get _board =>
      widget.boardStore == null ? widget.serverBoard ?? _preview : _preview;
  final _monitor = HostMonitor();
  final _system = _systemName();
  _Section _section = _Section.overview;
  _Panel? _panel;
  bool _editing = false;
  bool _showDevice = false;

  @override
  void initState() {
    super.initState();
    final local = widget.boardStore;
    _preview = local == null
        ? ServerBoardController(
            null,
            api.ProfileRef(),
            const Duration(seconds: 5),
          )
        : BoardController(local);
    unawaited(_preview.load());
    _monitor.start();
  }

  @override
  void didUpdateWidget(DashboardHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.serverBoard, widget.serverBoard)) {
      _editing = false;
    }
  }

  @override
  void dispose() {
    _preview.dispose();
    _monitor.dispose();
    super.dispose();
  }

  void _openPanel(_Panel? panel) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _panel = _panel == panel ? null : panel);
  }

  void _openSection(_Section section, {bool showDevice = false}) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _section = section;
      _panel = null;
      _showDevice = showDevice;
      if (section == _Section.devices) _editing = false;
    });
  }

  Future<void> _select(int id) async {
    setState(() => _editing = false);
    if (await _board.select(id) && mounted) _openSection(_Section.overview);
  }

  Future<void> _newSpace() async {
    final value = await showDialog<(String, SpaceImage)>(
      context: context,
      builder: (context) => const _NewSpace(),
    );
    if (!mounted || value == null) return;
    if (await _board.change((doc) => doc.create(value.$1, value.$2)) &&
        mounted) {
      setState(() => _editing = false);
      _openSection(_Section.overview);
    }
  }

  void _edit(BoardDocument Function(BoardDocument) change) {
    final board = _board;
    unawaited(
      board.change(change).then((saved) {
        if (mounted &&
            identical(board, _board) &&
            !saved &&
            board.writeFailed) {
          setState(() => _editing = false);
        }
      }),
    );
  }

  Future<void> _changeImage() async {
    final board = _board;
    final selected = board.document.selected;
    final image = await showDialog<SpaceImage>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Изображение пространства'),
        children: [
          for (final image in SpaceImage.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, image),
              child: Row(
                children: [
                  _SpaceAvatar(
                    image,
                    selected: image == board.document.active.image,
                  ),
                  const SizedBox(width: 12),
                  Text(image.label),
                ],
              ),
            ),
        ],
      ),
    );
    if (mounted &&
        image != null &&
        identical(board, _board) &&
        board.document.selected == selected) {
      _edit((document) => document.withImage(image));
    }
  }

  String _status(ConnectivityController? controller, api.Status? snapshot) =>
      controller == null || !controller.hasDeviceContext
      ? 'Туннель недоступен'
      : ConnectivityPanel.statusLabel(
          controller,
          snapshot,
        ).replaceFirst('Соединение: ', '');

  Widget _toolbar() {
    final controller = widget.connectivity;
    final blocked = widget.blockingMessage != null;
    final width = MediaQuery.sizeOf(context).width;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, widget.updates]),
      builder: (context, _) {
        final snapshot = controller?.snapshot;
        final status = _status(controller, snapshot);
        final desired =
            snapshot?.intent.desiredState ==
            api.DesiredState.DESIRED_STATE_CONNECTED;
        final canChange =
            !blocked &&
            controller != null &&
            (desired ? controller.canDisconnect : controller.canConnect);
        final scheme = Theme.of(context).colorScheme;
        final badge = widget.updates?.status == UpdateStatus.available;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (width >= 560)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(width * .4, 292),
                ),
                child: TextButton.icon(
                  onPressed: blocked ? null : () => _openPanel(_Panel.tunnel),
                  icon: Icon(
                    Icons.circle,
                    size: 8,
                    color: status == 'Туннель готов'
                        ? BrandColors.of(context).success
                        : scheme.onSurfaceVariant,
                  ),
                  label: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
            else
              IconButton(
                tooltip: 'Подробности туннеля: $status',
                onPressed: blocked ? null : () => _openPanel(_Panel.tunnel),
                icon: const Icon(Icons.shield_outlined),
              ),
            Tooltip(
              message: 'Запрос подключения или отключения туннеля',
              child: Semantics(
                label: 'Запрос подключения туннеля',
                child: Switch(
                  value: desired,
                  onChanged: !canChange
                      ? null
                      : (enabled) {
                          if (enabled) {
                            unawaited(controller.connect());
                          } else {
                            unawaited(controller.disconnect());
                          }
                        },
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: badge
                  ? 'Настройки приложения. Доступно обновление'
                  : 'Настройки приложения',
              onPressed: blocked ? null : () => _openPanel(_Panel.settings),
              icon: Badge(
                isLabelVisible: badge,
                backgroundColor: scheme.primary,
                child: const Icon(Icons.settings_outlined),
              ),
            ),
            IconButton(
              tooltip: 'Учётная запись',
              onPressed: blocked ? null : () => _openPanel(_Panel.account),
              icon: CircleAvatar(
                radius: 15,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: const Icon(Icons.person_outline, size: 18),
              ),
            ),
            const SizedBox(width: 6),
          ],
        );
      },
    );
  }

  Widget _spaces(BuildContext context, BoardDocument document) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SizedBox(
        height: 56,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          children: [
            for (final space in document.spaces)
              SizedBox(
                width: 50,
                child: Semantics(
                  label: space.name,
                  selected: space.id == document.selected,
                  child: Column(
                    children: [
                      IconButton(
                        tooltip: space.name,
                        onPressed: _board.canSelect
                            ? () => unawaited(_select(space.id))
                            : null,
                        icon: _SpaceAvatar(
                          space.image,
                          selected: space.id == document.selected,
                        ),
                      ),
                      if (space.id == document.selected)
                        Container(
                          width: 28,
                          height: 3,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Center(
              child: IconButton(
                tooltip: _board.serverBacked
                    ? 'Обновить пространства'
                    : 'Новое пространство',
                onPressed: _board.serverBacked
                    ? (_board.loading || _board.saving ? null : _board.load)
                    : (_board.canCreate ? _newSpace : null),
                icon: Icon(_board.serverBacked ? Icons.refresh : Icons.add),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar(BuildContext context, bool compact) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: compact ? 64 : 216,
      child: Material(
        color: scheme.surfaceContainerLow,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            compact ? 5 : 12,
            18,
            compact ? 5 : 12,
            12,
          ),
          children: [
            if (compact)
              IconButton(
                tooltip: 'Текущий ПК: ${widget.host}',
                onPressed: () =>
                    _openSection(_Section.devices, showDevice: true),
                icon: Icon(
                  Icons.desktop_windows_outlined,
                  color: scheme.primary,
                ),
              )
            else
              Tooltip(
                message: 'Открыть сведения о текущем ПК',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openSection(_Section.devices, showDevice: true),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.desktop_windows_outlined,
                            color: scheme.primary,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.host,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _system,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const Divider(height: 24),
            for (final section in _Section.values)
              if (compact)
                IconButton(
                  tooltip: section.title,
                  isSelected: _section == section,
                  style: IconButton.styleFrom(
                    backgroundColor: _section == section
                        ? scheme.primaryContainer
                        : null,
                    foregroundColor: _section == section
                        ? scheme.primary
                        : null,
                  ),
                  onPressed: () => _openSection(section),
                  icon: Icon(section.icon),
                )
              else
                ListTile(
                  leading: Icon(
                    section.icon,
                    color: _section == section ? scheme.primary : null,
                  ),
                  minLeadingWidth: 20,
                  horizontalTitleGap: 10,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  title: Text(
                    section.title,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  selected: _section == section,
                  onTap: () => _openSection(section),
                ),
          ],
        ),
      ),
    );
  }

  Widget _devices() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          selected: _showDevice,
          leading: const Icon(Icons.desktop_windows_outlined),
          title: Text(widget.host),
          subtitle: const Text('Текущий ПК'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => _showDevice = true),
        ),
      ),
      if (_showDevice) ...[
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_system),
                const SizedBox(height: 8),
                Text('Логических процессоров: ${Platform.numberOfProcessors}'),
              ],
            ),
          ),
        ),
      ],
    ],
  );

  Widget _workspace(BuildContext context, BoardSpace space) {
    final theme = Theme.of(context);
    final editing = _editing && _board.canChange;
    final controller = widget.connectivity;
    final data = TileData(
      host: widget.host,
      system: _system,
      processors: Platform.numberOfProcessors,
      monitor: _monitor,
      tunnelStatus: _status(controller, controller?.snapshot),
    );
    return SingleChildScrollView(
      key: PageStorageKey((space.id, _section)),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            space.name,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(_section.title, style: theme.textTheme.headlineSmall),
              if (_section == _Section.overview)
                Wrap(
                  spacing: 8,
                  children: [
                    if (_board.serverBacked && editing)
                      OutlinedButton.icon(
                        onPressed: _changeImage,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Изображение'),
                      ),
                    if (editing)
                      OutlinedButton.icon(
                        onPressed: () => _openSection(_Section.catalog),
                        icon: const Icon(Icons.add),
                        label: const Text('Добавить виджет'),
                      ),
                    if (_board.serverBacked &&
                        !_board.canChange &&
                        !_board.loading &&
                        !_board.saving &&
                        !_board.readFailed)
                      const Chip(label: Text('Только просмотр')),
                    if (!_board.serverBacked || _board.canChange)
                      FilledButton.tonalIcon(
                        onPressed: _board.canChange
                            ? () => setState(() => _editing = !_editing)
                            : null,
                        icon: Icon(editing ? Icons.check : Icons.tune),
                        label: Text(editing ? 'Готово' : 'Настроить доску'),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (_board.loading || _board.saving) const LinearProgressIndicator(),
          if (_board.readFailed)
            ListTile(
              title: Text(
                _board.readProblem ?? 'Не удалось загрузить раскладку.',
              ),
              trailing: TextButton(
                onPressed: _board.load,
                child: const Text('Повторить'),
              ),
            ),
          if (_board.writeFailed)
            ListTile(
              title: Text(
                _board.writeProblem ??
                    'Не удалось сохранить изменение. Повторите действие.',
              ),
            ),
          switch (_section) {
            _Section.overview => BoardView(
              key: ValueKey(space.id),
              space: space,
              data: data,
              editing: editing,
              canChange: _board.canChange,
              onEdit: _edit,
              openCatalog: () => _openSection(_Section.catalog),
            ),
            _Section.devices => _devices(),
            _Section.catalog => WidgetCatalog(
              key: ValueKey(space.id),
              space: space,
              data: data,
              canChange: _board.canChange,
              onEdit: _edit,
            ),
          },
        ],
      ),
    );
  }

  Widget _panelSurface(BuildContext context, String title, Widget content) =>
      Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Вернуться к пространству',
                    onPressed: () => _openPanel(null),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: content),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final block = widget.blockingMessage;
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(8),
          child: BrandMark(size: 32),
        ),
        title: const Text('EndlessNet', overflow: TextOverflow.ellipsis),
        actions: [_toolbar()],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          TickerMode(
            enabled: block == null,
            child: AbsorbPointer(
              absorbing: block != null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeFocus(
                    excluding: _panel != null,
                    child: ExcludeSemantics(
                      excluding: _panel != null,
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          _board,
                          _monitor,
                          widget.connectivity,
                        ]),
                        builder: (context, _) {
                          final document = _board.document;
                          return Column(
                            children: [
                              _spaces(context, document),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) => Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _sidebar(
                                        context,
                                        constraints.maxWidth < 800,
                                      ),
                                      Expanded(
                                        child: _workspace(
                                          context,
                                          document.active,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  TickerMode(
                    enabled: _panel == _Panel.account,
                    child: Offstage(
                      offstage: _panel != _Panel.account,
                      child: ExcludeFocus(
                        excluding: _panel != _Panel.account,
                        child: _panelSurface(
                          context,
                          'Учётная запись',
                          widget.account,
                        ),
                      ),
                    ),
                  ),
                  if (_panel == _Panel.settings)
                    _panelSurface(
                      context,
                      'Настройки приложения',
                      widget.settings,
                    ),
                  if (_panel == _Panel.tunnel)
                    _panelSurface(
                      context,
                      'Состояние туннеля',
                      widget.tunnelDetails,
                    ),
                ],
              ),
            ),
          ),
          if (block != null)
            ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Center(child: Text(block, textAlign: TextAlign.center)),
            ),
        ],
      ),
    );
  }
}

class _SpaceAvatar extends StatelessWidget {
  const _SpaceAvatar(this.image, {this.selected = false});
  final SpaceImage image;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: selected ? Border.all(color: scheme.primary, width: 1.5) : null,
      ),
      padding: const EdgeInsets.all(1),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(
          image.asset,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

class _NewSpace extends StatefulWidget {
  const _NewSpace();

  @override
  State<_NewSpace> createState() => _NewSpaceState();
}

class _NewSpaceState extends State<_NewSpace> {
  final _name = TextEditingController();
  SpaceImage _image = SpaceImage.ribbon;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Новое пространство'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 48,
            decoration: const InputDecoration(labelText: 'Название'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          const Text('Изображение'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final image in SpaceImage.values)
                Semantics(
                  selected: image == _image,
                  child: IconButton(
                    tooltip: image.label,
                    onPressed: () => setState(() => _image = image),
                    icon: _SpaceAvatar(image, selected: image == _image),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (_name.text, _image)),
        child: const Text('Создать'),
      ),
    ],
  );
}
