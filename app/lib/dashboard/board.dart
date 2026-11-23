import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum TileSize {
  square(1, 1),
  wide(2, 1),
  large(2, 2);

  const TileSize(this.columns, this.rows);
  final int columns, rows;
  String get label => '$columns × $rows';
}

enum TileKind {
  hardware('Оборудование', 'Загрузка процессора и оперативная память.', [
    TileSize.square,
    TileSize.wide,
    TileSize.large,
  ], TileSize.large),
  network('Сеть', 'Приём и отправка на активных сетевых адаптерах.', [
    TileSize.square,
    TileSize.wide,
    TileSize.large,
  ], TileSize.wide),
  disk('Диск', 'Свободное место на системном томе.', [
    TileSize.square,
    TileSize.wide,
  ], TileSize.square),
  peripherals('Периферия', 'Клавиатуры и мыши, обнаруженные Windows.', [
    TileSize.square,
    TileSize.wide,
  ], TileSize.square),
  computer('Этот ПК', 'Имя компьютера, система и логические процессоры.', [
    TileSize.square,
    TileSize.wide,
  ], TileSize.square),
  tunnel('Туннель', 'Фактическое состояние соединения EndlessNet.', [
    TileSize.square,
    TileSize.wide,
  ], TileSize.square);

  const TileKind(this.title, this.description, this.sizes, this.defaultSize);
  final String title, description;
  final List<TileSize> sizes;
  final TileSize defaultSize;
}

enum SpaceImage {
  ribbon('Синяя лента'),
  cabin('Дом'),
  glass('Стекло');

  const SpaceImage(this.label);
  final String label;
  String get asset => 'assets/spaces/$name.png';
}

typedef BoardTile = ({TileKind kind, TileSize size});
typedef TilePosition = ({int column, int row, int columns, int rows});

class BoardSpace {
  BoardSpace(this.id, this.name, this.image, Iterable<BoardTile> tiles)
    : tiles = List.unmodifiable(tiles);
  final int id;
  final String name;
  final SpaceImage image;
  final List<BoardTile> tiles;

  BoardSpace withImage(SpaceImage image) => BoardSpace(id, name, image, tiles);

  BoardSpace withTiles(Iterable<BoardTile> value) =>
      BoardSpace(id, name, image, value);

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'image': image.name,
    'tiles': [
      for (final tile in tiles)
        {'kind': tile.kind.name, 'size': tile.size.name},
    ],
  };

  factory BoardSpace.fromJson(Object? value) {
    if (value is! Map ||
        value['id'] is! int ||
        value['name'] is! String ||
        value['image'] is! String ||
        value['tiles'] is! List) {
      throw const FormatException('Invalid space');
    }
    final name = value['name'] as String;
    if (name.trim().isEmpty || name.length > 48) {
      throw const FormatException('Invalid space name');
    }
    final tiles = <BoardTile>[];
    final kinds = <TileKind>{};
    for (final tile in value['tiles'] as List) {
      if (tile is! Map || tile['kind'] is! String || tile['size'] is! String) {
        throw const FormatException('Invalid tile');
      }
      final kind = TileKind.values.byName(tile['kind'] as String);
      final size = TileSize.values.byName(tile['size'] as String);
      if (!kinds.add(kind) || !kind.sizes.contains(size)) {
        throw const FormatException('Invalid tile placement');
      }
      tiles.add((kind: kind, size: size));
    }
    return BoardSpace(
      value['id'] as int,
      name,
      SpaceImage.values.byName(value['image'] as String),
      tiles,
    );
  }
}

class BoardDocument {
  BoardDocument(this.selected, Iterable<BoardSpace> spaces)
    : spaces = List.unmodifiable(spaces);

  factory BoardDocument.initial() => BoardDocument(0, [
    BoardSpace(0, 'Личное', SpaceImage.ribbon, [
      for (final kind in [
        TileKind.hardware,
        TileKind.network,
        TileKind.disk,
        TileKind.peripherals,
      ])
        (kind: kind, size: kind.defaultSize),
    ]),
  ]);

  final int selected;
  final List<BoardSpace> spaces;
  BoardSpace get active => spaces.firstWhere((space) => space.id == selected);

  BoardDocument select(int id) =>
      id == selected || !spaces.any((space) => space.id == id)
      ? this
      : BoardDocument(id, spaces);

  BoardDocument create(String value, SpaceImage image) {
    final name = value.trim();
    if (name.isEmpty || name.length > 48) return this;
    final id = spaces.map((space) => space.id).reduce(math.max) + 1;
    return BoardDocument(id, [
      ...spaces,
      BoardSpace(id, name, image, const []),
    ]);
  }

  BoardDocument _replace(List<BoardTile> tiles) => BoardDocument(selected, [
    for (final space in spaces)
      if (space.id == selected) space.withTiles(tiles) else space,
  ]);

  BoardDocument withImage(SpaceImage image) => image == active.image
      ? this
      : BoardDocument(selected, [
          for (final space in spaces)
            if (space.id == selected) space.withImage(image) else space,
        ]);

  BoardDocument add(TileKind kind, [TileSize? size]) {
    final target = size ?? kind.defaultSize;
    if (!kind.sizes.contains(target) ||
        active.tiles.any((tile) => tile.kind == kind)) {
      return this;
    }
    return _replace([...active.tiles, (kind: kind, size: target)]);
  }

  BoardDocument remove(TileKind kind) {
    final tiles = active.tiles.where((tile) => tile.kind != kind).toList();
    return tiles.length == active.tiles.length ? this : _replace(tiles);
  }

  BoardDocument resize(TileKind kind, TileSize size) {
    if (!kind.sizes.contains(size) ||
        !active.tiles.any((tile) => tile.kind == kind && tile.size != size)) {
      return this;
    }
    return _replace([
      for (final tile in active.tiles)
        if (tile.kind == kind) (kind: kind, size: size) else tile,
    ]);
  }

  BoardDocument move(TileKind kind, TileKind target) {
    final tiles = active.tiles.toList();
    final from = tiles.indexWhere((tile) => tile.kind == kind);
    final to = tiles.indexWhere((tile) => tile.kind == target);
    if (from < 0 || to < 0 || from == to) return this;
    tiles.insert(to, tiles.removeAt(from));
    return _replace(tiles);
  }

  String encode() => jsonEncode({
    'version': 1,
    'selected': selected,
    'spaces': [for (final space in spaces) space.toJson()],
  });

  factory BoardDocument.decode(String text) {
    final value = jsonDecode(text);
    if (value is! Map ||
        value['version'] != 1 ||
        value['selected'] is! int ||
        value['spaces'] is! List) {
      throw const FormatException('Unsupported board data');
    }
    final spaces = (value['spaces'] as List).map(BoardSpace.fromJson).toList();
    final selected = value['selected'] as int;
    final ids = spaces.map((space) => space.id).toSet();
    if (ids.length != spaces.length ||
        !ids.contains(0) ||
        !ids.contains(selected) ||
        ids.any((id) => id < 0)) {
      throw const FormatException('Invalid space selection');
    }
    return BoardDocument(selected, spaces);
  }
}

List<TilePosition> arrangeTiles(Iterable<BoardTile> tiles, int columns) {
  assert(columns > 0);
  final occupied = <int>{};
  final placements = <TilePosition>[];
  for (final tile in tiles) {
    final w = math.min(columns, tile.size.columns);
    final h = tile.size.rows;
    for (var cell = 0; ; cell++) {
      final x = cell % columns;
      if (x + w > columns) continue;
      final cells = [
        for (var y = 0; y < h; y++)
          for (var dx = 0; dx < w; dx++) cell + y * columns + dx,
      ];
      if (cells.any(occupied.contains)) continue;
      occupied.addAll(cells);
      placements.add((column: x, row: cell ~/ columns, columns: w, rows: h));
      break;
    }
  }
  return placements;
}

class BoardStore {
  const BoardStore(this.file);
  final File? file;

  Future<BoardDocument> load() async {
    final path = file;
    if (path == null) throw const FileSystemException('No user data directory');
    try {
      return BoardDocument.decode(await path.readAsString());
    } on PathNotFoundException {
      return BoardDocument.initial();
    }
  }

  Future<void> save(BoardDocument document) async {
    final path = file;
    if (path == null) throw const FileSystemException('No user data directory');
    await path.parent.create(recursive: true);
    final pending = await path.parent.createTemp('.dashboard-');
    final next = File(pending.uri.resolve('layout.json').toFilePath());
    try {
      await next.writeAsString(document.encode(), flush: true);
      await next.rename(path.path);
    } finally {
      try {
        if (await next.exists()) await next.delete();
        await pending.delete();
      } on FileSystemException {
        // A cleanup failure does not change the outcome of the replace.
      }
    }
  }
}

abstract class BoardModel extends ChangeNotifier {
  BoardDocument get document;
  bool get loading;
  bool get saving;
  bool get readFailed;
  bool get writeFailed;
  bool get canChange;
  bool get canSelect => canChange;
  bool get canCreate => false;
  bool get serverBacked => false;
  String? get readProblem => null;
  String? get writeProblem => null;
  Future<void> load();
  Future<bool> select(int id) => change((document) => document.select(id));
  Future<bool> change(BoardDocument Function(BoardDocument) edit);
}

class BoardController extends BoardModel {
  BoardController(this.store);
  final BoardStore store;
  @override
  BoardDocument document = BoardDocument.initial();
  @override
  bool loading = true, saving = false, readFailed = false, writeFailed = false;
  bool _disposed = false;

  @override
  Future<void> load() async {
    loading = true;
    readFailed = false;
    if (!_disposed) notifyListeners();
    try {
      final loaded = await store.load();
      if (!_disposed) document = loaded;
    } catch (_) {
      readFailed = true;
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  bool get canChange => !loading && !saving && !readFailed;

  @override
  bool get canCreate => canChange;

  @override
  Future<bool> change(BoardDocument Function(BoardDocument) edit) async {
    if (!canChange) return false;
    final changed = edit(document);
    if (identical(changed, document)) return false;
    saving = true;
    writeFailed = false;
    notifyListeners();
    try {
      await store.save(changed);
      if (!_disposed) document = changed;
      return true;
    } catch (_) {
      writeFailed = true;
      return false;
    } finally {
      saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
