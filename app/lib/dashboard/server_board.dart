import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:grpc/grpc.dart' as grpc;

import '../client/call_failure.dart';
import '../client/dashboard_client.dart';
import 'board.dart';

class ServerBoardController extends BoardModel {
  ServerBoardController(this._client, this._profile, this._timeout);

  final DashboardClient? _client;
  final api.ProfileRef _profile;
  final Duration _timeout;
  final _accounts = <int, String>{};
  int _nextId = 1, _epoch = 0;
  bool _disposed = false;
  api.DashboardBoard? _verified;

  @override
  BoardDocument document = BoardDocument.initial();
  @override
  bool loading = false, saving = false;
  @override
  String? readProblem, writeProblem;
  @override
  bool get serverBacked => true;
  @override
  bool get readFailed => readProblem != null;
  @override
  bool get writeFailed => writeProblem != null;
  @override
  bool get canChange =>
      !loading && !saving && !readFailed && (_verified?.canEdit ?? false);
  @override
  bool get canSelect => !_disposed && !saving && _accounts.isNotEmpty;

  bool _isCurrent(int epoch) => !_disposed && epoch == _epoch;

  void sessionLost() {
    if (_disposed) return;
    _epoch++;
    _accounts.clear();
    _verified = null;
    loading = saving = false;
    readProblem = 'Войдите в учётную запись, чтобы открыть пространства.';
    writeProblem = null;
    document = _empty;
    notifyListeners();
  }

  BoardDocument get _empty =>
      BoardDocument(0, [BoardSpace(0, 'Личное', SpaceImage.ribbon, const [])]);

  static int _code(Object error) => error is ClientCallFailure
      ? error.transportCode
      : grpc.StatusCode.unknown;

  bool _authorizationFailure(Object error) =>
      _code(error) == grpc.StatusCode.unauthenticated ||
      _code(error) == grpc.StatusCode.permissionDenied ||
      _code(error) == grpc.StatusCode.notFound;

  String _readMessage(Object error) => switch (_code(error)) {
    grpc.StatusCode.unauthenticated =>
      'Войдите в учётную запись, чтобы открыть пространства.',
    grpc.StatusCode.permissionDenied || grpc.StatusCode.notFound =>
      'Доступ к пространству закрыт. Обновите список пространств.',
    _ => 'Серверная доска недоступна.',
  };

  @override
  Future<void> load() async {
    if (_disposed || saving) return;
    final client = _client;
    if (client == null) {
      readProblem = 'Подключите службу EndlessNet, чтобы открыть пространства.';
      notifyListeners();
      return;
    }
    final epoch = ++_epoch;
    loading = true;
    _verified = null;
    readProblem = null;
    writeProblem = null;
    notifyListeners();
    try {
      final catalog = await client.dashboardSpaces(
        api.ListDashboardSpacesRequest(profile: _profile),
        _timeout,
      );
      if (!_isCurrent(epoch)) return;
      final selected = _accounts[document.selected];
      final previous = {
        for (final row in _accounts.entries) row.value: row.key,
      };
      final cached = {for (final space in document.spaces) space.id: space};
      final next = <int, String>{};
      final spaces = <BoardSpace>[];
      final seen = <String>{};
      for (final account in catalog.spaces) {
        if (account.accountId.isEmpty ||
            account.displayName.trim().isEmpty ||
            !seen.add(account.accountId)) {
          throw ClientCallFailure.protocol();
        }
        final id = previous[account.accountId] ?? _nextId++;
        next[id] = account.accountId;
        final old = cached[id];
        final personal = account.accountId == catalog.primaryAccountId;
        spaces.add(
          BoardSpace(
            id,
            personal ? 'Личное' : account.displayName,
            old?.image ?? SpaceImage.ribbon,
            old?.tiles ?? const [],
          ),
        );
      }
      if (catalog.primaryAccountId.isNotEmpty &&
          !seen.contains(catalog.primaryAccountId)) {
        throw ClientCallFailure.protocol();
      }
      final preferred = selected ?? catalog.primaryAccountId;
      final id = next.entries
          .where((entry) => entry.value == preferred)
          .firstOrNull
          ?.key;
      _accounts
        ..clear()
        ..addAll(next);
      if (spaces.isEmpty) {
        document = _empty;
        readProblem = 'Нет доступных пространств.';
        return;
      }
      document = BoardDocument(id ?? spaces.first.id, spaces);
      await _read(epoch, document.selected);
    } catch (error) {
      if (!_isCurrent(epoch)) return;
      if (_authorizationFailure(error)) {
        _accounts.clear();
        document = _empty;
      }
      readProblem = _readMessage(error);
    } finally {
      if (_isCurrent(epoch)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  Future<bool> select(int id) async {
    if (!canSelect || !_accounts.containsKey(id) || document.selected == id) {
      return false;
    }
    final epoch = ++_epoch;
    document = document.select(id);
    _verified = null;
    readProblem = writeProblem = null;
    loading = true;
    notifyListeners();
    await _read(epoch, id);
    if (!_isCurrent(epoch)) return false;
    loading = false;
    notifyListeners();
    return true;
  }

  Future<void> _read(int epoch, int id) async {
    final account = _accounts[id]!;
    try {
      final board = await _client!.dashboardBoard(
        api.GetDashboardBoardRequest(profile: _profile, accountId: account),
        _timeout,
      );
      if (!_isCurrent(epoch)) return;
      _apply(account, board);
    } catch (error) {
      if (!_isCurrent(epoch)) return;
      if (_code(error) == grpc.StatusCode.unauthenticated) {
        _accounts.clear();
        document = _empty;
      } else if (_authorizationFailure(error)) {
        final active = document.active;
        _replaceSpace(
          BoardSpace(active.id, active.name, SpaceImage.ribbon, const []),
        );
      }
      readProblem = _readMessage(error);
    }
  }

  void _replaceSpace(BoardSpace updated) {
    document = BoardDocument(document.selected, [
      for (final space in document.spaces)
        if (space.id == updated.id) updated else space,
    ]);
  }

  void _apply(String account, api.DashboardBoard board) {
    final index = board.layout.image.value - 1;
    if (board.accountId != account ||
        !board.hasLayout() ||
        index < 0 ||
        index >= SpaceImage.values.length) {
      throw ClientCallFailure.protocol();
    }
    final kinds = <TileKind>{};
    final tiles = <BoardTile>[];
    for (final row in board.layout.widgets) {
      final kindIndex = row.kind.value - 1;
      final sizeIndex = row.size.value - 1;
      if (kindIndex < 0 ||
          kindIndex >= TileKind.values.length ||
          sizeIndex < 0 ||
          sizeIndex >= TileSize.values.length) {
        throw ClientCallFailure.protocol();
      }
      final kind = TileKind.values[kindIndex],
          size = TileSize.values[sizeIndex];
      if (!kinds.add(kind) || !kind.sizes.contains(size)) {
        throw ClientCallFailure.protocol();
      }
      tiles.add((kind: kind, size: size));
    }
    final current = document.active;
    _replaceSpace(
      BoardSpace(current.id, current.name, SpaceImage.values[index], tiles),
    );
    _verified = board;
  }

  @override
  Future<bool> change(BoardDocument Function(BoardDocument) edit) async {
    if (!canChange) return false;
    final changed = edit(document);
    if (identical(changed, document) || changed.selected != document.selected) {
      return false;
    }
    final current = _verified!;
    final epoch = ++_epoch;
    final active = changed.active;
    saving = true;
    writeProblem = null;
    notifyListeners();
    try {
      final board = await _client!.replaceDashboardBoard(
        api.ReplaceDashboardBoardRequest(
          profile: _profile,
          accountId: current.accountId,
          expectedRevision: current.revision,
          layout: api.DashboardLayout(
            image: api.DashboardImage.valueOf(active.image.index + 1),
            widgets: [
              for (final tile in active.tiles)
                api.DashboardWidget(
                  kind: api.DashboardWidgetKind.valueOf(tile.kind.index + 1),
                  size: api.DashboardWidgetSize.valueOf(tile.size.index + 1),
                ),
            ],
          ),
        ),
        _timeout,
      );
      if (!_isCurrent(epoch)) return false;
      _apply(current.accountId, board);
      return true;
    } catch (error) {
      if (!_isCurrent(epoch)) return false;
      _verified = null;
      if (_authorizationFailure(error)) {
        final space = document.active;
        _replaceSpace(
          BoardSpace(space.id, space.name, SpaceImage.ribbon, const []),
        );
      }
      writeProblem = switch (_code(error)) {
        grpc.StatusCode.aborted => 'Доску уже изменили. Проверьте актуальную раскладку перед новой правкой.',
        grpc.StatusCode.permissionDenied || grpc.StatusCode.unauthenticated =>
          'Права на изменение доски больше нет.',
        _ => 'Сохранение не подтверждено. Проверяем текущую раскладку.',
      };
      notifyListeners();
      await _read(epoch, document.selected);
      return false;
    } finally {
      if (_isCurrent(epoch)) {
        saving = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}
