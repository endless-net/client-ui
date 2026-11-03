import 'package:flutter/material.dart';

import 'controls.dart';

@immutable
class EnTableRow {
  const EnTableRow({
    required this.id,
    required this.cells,
    this.enabled = true,
  });
  final String id;
  final List<String> cells;
  final bool enabled;
}

/// C07. Caller sorts/pages the data; the table only emits intent.
class EnTable extends StatelessWidget {
  const EnTable({
    super.key,
    required this.columns,
    required this.rows,
    this.selected = const {},
    this.onSelect,
    this.sortColumn,
    this.ascending = true,
    this.onSort,
  });
  final List<String> columns;
  final List<EnTableRow> rows;
  final Set<String> selected;
  final void Function(String id, bool selected)? onSelect;
  final int? sortColumn;
  final bool ascending;
  final void Function(int column, bool ascending)? onSort;
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Text('Нет записей');
    if (columns.isEmpty) return const Text('Нет столбцов');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        sortColumnIndex:
            sortColumn != null &&
                sortColumn! >= 0 &&
                sortColumn! < columns.length
            ? sortColumn
            : null,
        sortAscending: ascending,
        dataRowMaxHeight: double.infinity,
        columns: [
          for (var index = 0; index < columns.length; index++)
            DataColumn(
              label: Text(columns[index]),
              onSort: onSort == null
                  ? null
                  : (column, value) => onSort!(column, value),
            ),
        ],
        rows: [
          for (final row in rows)
            DataRow(
              key: ValueKey(row.id),
              selected: selected.contains(row.id),
              onSelectChanged: onSelect != null && row.enabled
                  ? (value) => onSelect!(row.id, value ?? false)
                  : null,
              cells: [
                for (var index = 0; index < columns.length; index++)
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          index < row.cells.length
                              ? row.cells[index]
                              : 'Нет значения',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

@immutable
class EnListItem {
  const EnListItem({
    required this.id,
    required this.label,
    this.description,
    this.enabled = true,
    this.leading,
    this.trailing,
  });
  final String id, label;
  final String? description;
  final bool enabled;
  final Widget? leading, trailing;
}

/// C08. Stable row IDs; scrolling and fetching remain with the caller.
class EnList extends StatelessWidget {
  const EnList({
    super.key,
    required this.items,
    this.selected,
    this.onActivate,
  });
  final List<EnListItem> items;
  final String? selected;
  final ValueChanged<String>? onActivate;
  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const Text('Нет записей')
      : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              ListTile(
                key: ValueKey(item.id),
                leading: item.leading,
                trailing: item.trailing,
                title: Text(item.label),
                subtitle: item.description == null
                    ? null
                    : Text(item.description!),
                selected: selected == item.id,
                enabled: item.enabled,
                onTap: item.enabled && onActivate != null
                    ? () => onActivate!(item.id)
                    : null,
              ),
          ],
        );
}

/// C09. Loaded count is not total count. No hidden fetch on rebuild.
class EnPager extends StatelessWidget {
  const EnPager({
    super.key,
    required this.loadedCount,
    this.total,
    this.hasNext = false,
    this.hasPrevious = false,
    this.loading = false,
    this.onNext,
    this.onPrevious,
  });
  final int loadedCount;
  final int? total;
  final bool hasNext, hasPrevious, loading;
  final VoidCallback? onNext, onPrevious;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text('Загружено: $loadedCount; всего: ${total ?? 'неизвестно'}'),
      EnButton(
        label: 'Назад',
        kind: EnButtonKind.secondary,
        enabled: hasPrevious,
        pending: loading,
        onPressed: onPrevious,
      ),
      EnButton(
        label: 'Далее',
        kind: EnButtonKind.secondary,
        enabled: hasNext,
        pending: loading,
        onPressed: onNext,
      ),
    ],
  );
}
