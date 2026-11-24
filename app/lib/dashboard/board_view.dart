import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'board.dart';
import 'tiles.dart';

typedef EditBoard = void Function(BoardDocument Function(BoardDocument) edit);
typedef _DragTile = ({int space, TileKind kind});

enum _TileCommand { earlier, later, remove }

class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.space,
    required this.data,
    required this.editing,
    required this.canChange,
    required this.onEdit,
    required this.openCatalog,
  });
  final BoardSpace space;
  final TileData data;
  final bool editing, canChange;
  final EditBoard onEdit;
  final VoidCallback openCatalog;

  @override
  Widget build(BuildContext context) {
    if (space.tiles.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: openCatalog,
          icon: const Icon(Icons.add),
          label: const Text('Добавить первый виджет'),
        ),
      );
    }
    const gap = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth + gap) / 232).floor().clamp(
          1,
          6,
        );
        final cell = (constraints.maxWidth - gap * (columns - 1)) / columns;
        final height = math.max(180.0, cell);
        final positions = arrangeTiles(space.tiles, columns);
        final rows = positions.map((p) => p.row + p.rows).reduce(math.max);
        return SizedBox(
          height: rows * (height + gap) - gap,
          child: Stack(
            children: [
              for (var i = 0; i < positions.length; i++)
                Positioned(
                  key: ValueKey(space.tiles[i].kind),
                  left: positions[i].column * (cell + gap),
                  top: positions[i].row * (height + gap),
                  width: positions[i].columns * (cell + gap) - gap,
                  height: positions[i].rows * (height + gap) - gap,
                  child: _BoardCard(
                    spaceId: space.id,
                    tile: space.tiles[i],
                    previous: i == 0 ? null : space.tiles[i - 1].kind,
                    next: i + 1 == positions.length
                        ? null
                        : space.tiles[i + 1].kind,
                    data: data,
                    editing: editing,
                    canChange: canChange,
                    onEdit: onEdit,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.spaceId,
    required this.tile,
    required this.previous,
    required this.next,
    required this.data,
    required this.editing,
    required this.canChange,
    required this.onEdit,
  });
  final int spaceId;
  final BoardTile tile;
  final TileKind? previous, next;
  final TileData data;
  final bool editing, canChange;
  final EditBoard onEdit;

  @override
  Widget build(BuildContext context) {
    final kind = tile.kind;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controls = editing
        ? [
            if (canChange)
              Draggable<_DragTile>(
                data: (space: spaceId, kind: kind),
                hitTestBehavior: HitTestBehavior.opaque,
                feedback: Material(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(kind.title),
                  ),
                ),
                child: const Tooltip(
                  message: 'Перетащить виджет',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: SizedBox(
                      width: 30,
                      height: 36,
                      child: Icon(Icons.drag_indicator),
                    ),
                  ),
                ),
              ),
            PopupMenuButton<Object>(
              tooltip: 'Настроить виджет: ${kind.title}',
              enabled: canChange,
              icon: const Icon(Icons.more_horiz),
              padding: EdgeInsets.zero,
              itemBuilder: (context) => [
                for (final size in kind.sizes)
                  CheckedPopupMenuItem(
                    value: size,
                    checked: size == tile.size,
                    child: Text(size.label),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _TileCommand.earlier,
                  enabled: previous != null,
                  child: const Text('Переместить раньше'),
                ),
                PopupMenuItem(
                  value: _TileCommand.later,
                  enabled: next != null,
                  child: const Text('Переместить позже'),
                ),
                const PopupMenuItem(
                  value: _TileCommand.remove,
                  child: Text('Убрать с доски'),
                ),
              ],
              onSelected: (value) => onEdit(
                (document) => switch (value) {
                  TileSize size => document.resize(kind, size),
                  _TileCommand.earlier => document.move(kind, previous!),
                  _TileCommand.later => document.move(kind, next!),
                  _TileCommand.remove => document.remove(kind),
                  _ => document,
                },
              ),
            ),
          ]
        : <Widget>[];

    Widget card(bool target) => Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: target ? scheme.primary : scheme.outlineVariant,
          width: target ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(tileIcon(kind), size: 19, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kind.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                ...controls,
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: TileContents(kind: kind, size: tile.size, data: data),
              ),
            ),
          ],
        ),
      ),
    );
    if (!editing) return card(false);
    return DragTarget<_DragTile>(
      onWillAcceptWithDetails: (details) =>
          canChange &&
          details.data.space == spaceId &&
          details.data.kind != kind,
      onAcceptWithDetails: (details) => onEdit(
        (document) => document.selected == spaceId
            ? document.move(details.data.kind, kind)
            : document,
      ),
      builder: (context, candidates, rejected) => card(candidates.isNotEmpty),
    );
  }
}

class WidgetCatalog extends StatefulWidget {
  const WidgetCatalog({
    super.key,
    required this.space,
    required this.data,
    required this.canChange,
    required this.onEdit,
  });
  final BoardSpace space;
  final TileData data;
  final bool canChange;
  final EditBoard onEdit;

  @override
  State<WidgetCatalog> createState() => _WidgetCatalogState();
}

class _WidgetCatalogState extends State<WidgetCatalog> {
  String _search = '';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: TextField(
          onChanged: (value) =>
              setState(() => _search = value.trim().toLowerCase()),
          decoration: const InputDecoration(
            labelText: 'Поиск виджетов',
            prefixIcon: Icon(Icons.search),
          ),
        ),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) {
          final kinds = TileKind.values
              .where(
                (kind) =>
                    kind.title.toLowerCase().contains(_search) ||
                    kind.description.toLowerCase().contains(_search),
              )
              .toList();
          if (kinds.isEmpty) return const Text('Виджеты не найдены');
          const gap = 12.0;
          final columns = ((constraints.maxWidth + gap) / 320).floor().clamp(
            1,
            3,
          );
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final kind in kinds)
                SizedBox(
                  key: ValueKey(kind),
                  width: width,
                  height: 360,
                  child: _CatalogTile(
                    kind: kind,
                    data: widget.data,
                    attached: widget.space.tiles.any(
                      (tile) => tile.kind == kind,
                    ),
                    onAdd: widget.canChange
                        ? (size) => widget.onEdit((doc) => doc.add(kind, size))
                        : null,
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _CatalogTile extends StatefulWidget {
  const _CatalogTile({
    required this.kind,
    required this.data,
    required this.attached,
    this.onAdd,
  });
  final TileKind kind;
  final TileData data;
  final bool attached;
  final ValueChanged<TileSize>? onAdd;

  @override
  State<_CatalogTile> createState() => _CatalogTileState();
}

class _CatalogTileState extends State<_CatalogTile> {
  late TileSize _size = widget.kind.defaultSize;

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                primary: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          tileIcon(kind),
                          color: theme.colorScheme.primary,
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            kind.title,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(kind.description),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final size in kind.sizes)
                          ChoiceChip(
                            label: Text(size.label),
                            selected: size == _size,
                            onSelected: (_) => setState(() => _size = size),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 128,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: SingleChildScrollView(
                        primary: false,
                        child: TileContents(
                          kind: kind,
                          size: _size,
                          data: widget.data,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (widget.attached)
              const Text('На доске')
            else
              OutlinedButton.icon(
                onPressed: widget.onAdd == null
                    ? null
                    : () => widget.onAdd!(_size),
                icon: const Icon(Icons.add),
                label: const Text('Добавить в это пространство'),
              ),
          ],
        ),
      ),
    );
  }
}
