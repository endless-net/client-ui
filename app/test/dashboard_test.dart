import 'dart:async';
import 'dart:io';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/client/call_failure.dart';
import 'package:endlessnet_client_ui/client/dashboard_client.dart';
import 'package:endlessnet_client_ui/client/connectivity_client.dart';

import 'package:endlessnet_client_ui/dashboard/board.dart';
import 'package:endlessnet_client_ui/dashboard/home.dart';
import 'package:endlessnet_client_ui/dashboard/peer_list.dart';
import 'package:endlessnet_client_ui/dashboard/server_board.dart';
import 'package:endlessnet_client_ui/dashboard/telemetry.dart';
import 'package:endlessnet_ui/endlessnet_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;

class _MemoryStore extends BoardStore {
  _MemoryStore() : super(null);
  BoardDocument saved = BoardDocument.initial();
  bool fail = false;

  @override
  Future<BoardDocument> load() async => saved;

  @override
  Future<void> save(BoardDocument document) async {
    if (fail) throw const FileSystemException('write denied');
    saved = document;
  }
}

class _SharedBoards implements DashboardClient {
  final boards = <String, api.DashboardBoard>{
    'personal': api.DashboardBoard(
      accountId: 'personal',
      canEdit: true,
      layout: api.DashboardLayout(
        image: api.DashboardImage.DASHBOARD_IMAGE_RIBBON,
        widgets: [
          _tile(
            api.DashboardWidgetKind.DASHBOARD_WIDGET_KIND_HARDWARE,
            api.DashboardWidgetSize.DASHBOARD_WIDGET_SIZE_LARGE,
          ),
          _tile(
            api.DashboardWidgetKind.DASHBOARD_WIDGET_KIND_NETWORK,
            api.DashboardWidgetSize.DASHBOARD_WIDGET_SIZE_WIDE,
          ),
          _tile(
            api.DashboardWidgetKind.DASHBOARD_WIDGET_KIND_DISK,
            api.DashboardWidgetSize.DASHBOARD_WIDGET_SIZE_SQUARE,
          ),
        ],
      ),
    ),
    'work': api.DashboardBoard(
      accountId: 'work',
      layout: api.DashboardLayout(
        image: api.DashboardImage.DASHBOARD_IMAGE_GLASS,
      ),
    ),
  };
  Completer<api.DashboardBoard>? workReply;
  int writeCalls = 0;
  bool revoked = false;

  static api.DashboardWidget _tile(
    api.DashboardWidgetKind kind,
    api.DashboardWidgetSize size,
  ) => api.DashboardWidget(kind: kind, size: size);

  @override
  Future<api.ListDashboardSpacesResponse> dashboardSpaces(
    api.ListDashboardSpacesRequest request,
    Duration timeout,
  ) async {
    expect(request.profile.profileId, 'profile');
    return api.ListDashboardSpacesResponse(
      primaryAccountId: 'personal',
      spaces: [
        api.DashboardSpace(accountId: 'work', displayName: 'Работа'),
        api.DashboardSpace(accountId: 'personal', displayName: 'Имя в Billing'),
      ],
    );
  }

  @override
  Future<api.DashboardBoard> dashboardBoard(
    api.GetDashboardBoardRequest request,
    Duration timeout,
  ) async {
    if (request.accountId == 'work' && workReply != null) {
      return workReply!.future;
    }
    if (revoked) {
      throw ClientCallFailure.fromGrpc(grpc.GrpcError.permissionDenied(), 1024);
    }
    return boards[request.accountId]!.deepCopy();
  }

  @override
  Future<api.DashboardBoard> replaceDashboardBoard(
    api.ReplaceDashboardBoardRequest request,
    Duration timeout,
  ) async {
    writeCalls++;
    expect(request.accountId, 'personal');
    expect(request.hasExpectedRevision(), isTrue);
    final current = boards[request.accountId]!;
    if (request.expectedRevision != current.revision) {
      throw ClientCallFailure.fromGrpc(grpc.GrpcError.aborted(), 1024);
    }
    current.revision++;
    current.layout = request.layout.deepCopy();
    return current.deepCopy();
  }

  ServerBoardController controller() => ServerBoardController(
    this,
    api.ProfileRef(profileId: 'profile'),
    const Duration(seconds: 2),
  );
}

class _NetworkPeers implements PeerClient {
  final calls = <String>[];
  final metadata = api.SnapshotMetadata(instanceId: 'client-instance');

  @override
  Future<api.ListPeersResponse> listPeers(
    api.ListPeersRequest request,
    Duration timeout,
  ) async {
    expect(request.profile.profileId, 'active-profile');
    final token = request.page.pageToken;
    calls.add(token);
    return api.ListPeersResponse(
      snapshotState: api.AgentSnapshotState.AGENT_SNAPSHOT_STATE_CURRENT,
      mapRevision: api.Status().mapRevision + 8,
      peers: [
        if (token.isEmpty)
          api.Peer(
            id: 'one',
            hostname: 'Ноутбук',
            overlayAddresses: ['100.64.0.8'],
          )
        else
          api.Peer(id: 'two', hostname: 'Станция'),
      ],
      page: api.PageResponse(
        metadata: metadata,
        nextPageToken: token.isEmpty ? 'second-page' : '',
      ),
    );
  }
}

void main() {
  testWidgets('devices load peer names, addresses and subsequent pages', (
    tester,
  ) async {
    final client = _NetworkPeers();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkPeerList(
            client: client,
            timeout: const Duration(seconds: 1),
            status: api.Status(
              metadata: client.metadata,
              activeProfileId: 'active-profile',
              agent: api.AgentStatus(mapRevision: api.Status().mapRevision + 8),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ноутбук'), findsOneWidget);
    expect(find.text('100.64.0.8'), findsOneWidget);
    expect(find.text('Станция'), findsNothing);
    await tester.tap(find.text('Показать ещё'));
    await tester.pumpAndSettle();
    expect(find.text('Ноутбук'), findsOneWidget);
    expect(find.text('Станция'), findsOneWidget);
    expect(client.calls, ['', 'second-page']);
  });

  test(
    'shared board re-reads on a conflict and ignores an older space reply',
    () async {
      final remote = _SharedBoards();
      final board = remote.controller();
      addTearDown(board.dispose);
      await board.load();
      expect(board.document.active.name, 'Личное');
      expect(board.canChange, isTrue);
      final personal = board.document.selected;
      final work = board.document.spaces
          .firstWhere((s) => s.name == 'Работа')
          .id;
      remote.workReply = Completer();
      final pending = board.select(work);
      expect(board.canChange, isFalse);
      await board.select(personal);
      remote.workReply!.complete(remote.boards['work']!);
      expect(await pending, isFalse);
      expect(board.document.selected, personal);
      expect(board.document.active.tiles, hasLength(3));

      final concurrent = remote.boards['personal']!;
      concurrent.revision++;
      concurrent.layout.widgets.removeLast();
      expect(
        await board.change((doc) => doc.remove(TileKind.hardware)),
        isFalse,
      );
      expect(remote.writeCalls, 1);
      expect(board.writeProblem, contains('уже изменили'));
      expect(board.document.active.tiles, hasLength(2));
      expect(
        await board.change((doc) => doc.remove(TileKind.hardware)),
        isTrue,
      );
      expect(remote.writeCalls, 2);
      expect(board.document.active.tiles.single.kind, TileKind.network);

      remote.revoked = true;
      await board.load();
      expect(board.document.active.tiles, isEmpty);
      expect(board.canChange, isFalse);
    },
  );

  testWidgets('reader sees shared space with no edit action', (tester) async {
    tester.view
      ..physicalSize = const Size(1260, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final remote = _SharedBoards();
    final board = remote.controller();
    addTearDown(board.dispose);
    await board.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark(),
        home: DashboardHome(
          host: 'ATLAS-PC',
          account: const SizedBox(),
          tunnelDetails: const SizedBox(),
          settings: const SizedBox(),
          serverBoard: board,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ATLAS-PC'), findsOneWidget);
    expect(find.text('Настроить доску'), findsOneWidget);
    final spaceNameTop = tester.getTopLeft(find.text('Личное')).dy;
    await tester.tap(find.byTooltip('Работа'));
    await tester.pumpAndSettle();
    expect(find.text('Только просмотр'), findsOneWidget);
    expect(find.text('Настроить доску'), findsNothing);
    expect(tester.getTopLeft(find.text('Работа')).dy, spaceNameTop);

    await tester.tap(find.widgetWithText(ListTile, 'Каталог виджетов'));
    await tester.pumpAndSettle();
    expect(
      find.text('Добавлять виджеты может владелец пространства.'),
      findsOneWidget,
    );
    final add = find.widgetWithText(
      OutlinedButton,
      'Добавить в это пространство',
    );
    expect(tester.widget<OutlinedButton>(add.first).onPressed, isNull);
    expect(remote.writeCalls, 0);

    await tester.tap(find.byTooltip('Личное'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Каталог виджетов'));
    await tester.pumpAndSettle();
    final tunnel = find.byKey(const ValueKey(TileKind.tunnel));
    final addTunnel = find.descendant(of: tunnel, matching: add);
    expect(tester.widget<OutlinedButton>(addTunnel).onPressed, isNotNull);
    await tester.ensureVisible(addTunnel);
    await tester.tap(addTunnel);
    await tester.pumpAndSettle();
    expect(remote.writeCalls, 1);
    expect(board.document.active.tiles.last.kind, TileKind.tunnel);
    board.sessionLost();
    await tester.pumpAndSettle();
    expect(
      find.text('Войдите в учётную запись, чтобы открыть пространства.'),
      findsOneWidget,
    );
    expect(tester.getTopLeft(find.text('Личное')).dy, spaceNameTop);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('stores tile order and sizes independently for every space', () async {
    final directory = await Directory.systemTemp.createTemp(
      'endlessnet-board-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = BoardStore(
      File.fromUri(directory.uri.resolve('dashboard.json')),
    );
    final initial = await store.load();
    expect(initial.active.name, 'Личное');
    expect(initial.active.tiles.map((tile) => tile.size), [
      TileSize.large,
      TileSize.wide,
      TileSize.square,
      TileSize.square,
    ]);
    final personal = initial
        .resize(TileKind.hardware, TileSize.square)
        .move(TileKind.hardware, TileKind.disk)
        .remove(TileKind.peripherals);
    await store.save(personal);
    final second = personal
        .create('  Дом  ', SpaceImage.cabin)
        .add(TileKind.network, TileSize.large);
    await store.save(second);
    final restored = await store.load();
    expect(restored.active.name, 'Дом');
    expect(restored.active.tiles.single.size, TileSize.large);
    expect(restored.select(0).active.tiles.map((tile) => tile.kind), [
      TileKind.network,
      TileKind.disk,
      TileKind.hardware,
    ]);
    expect(restored.select(0).active.tiles.last.size, TileSize.square);
    expect(restored.add(TileKind.network), same(restored));
    expect(restored.resize(TileKind.disk, TileSize.large), same(restored));
  });

  test(
    'reports read errors and keeps the last confirmed write on failures',
    () async {
      final inaccessible = BoardController(const BoardStore(null));
      addTearDown(inaccessible.dispose);
      await inaccessible.load();
      expect(inaccessible.readFailed, isTrue);
      expect(inaccessible.canChange, isFalse);
      final store = _MemoryStore();
      final controller = BoardController(store);
      addTearDown(controller.dispose);
      await controller.load();
      store.fail = true;
      expect(
        await controller.change((doc) => doc.remove(TileKind.hardware)),
        isFalse,
      );
      expect(controller.writeFailed, isTrue);
      expect(controller.document.active.tiles.length, 4);
      store.fail = false;
      expect(
        await controller.change((doc) => doc.remove(TileKind.hardware)),
        isTrue,
      );
      expect(controller.writeFailed, isFalse);
      expect(controller.document.active.tiles.length, 3);
    },
  );

  test('does not replace a file that uses an unsupported schema', () async {
    final directory = await Directory.systemTemp.createTemp(
      'endlessnet-invalid-board-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = await File.fromUri(directory.uri.resolve('dashboard.json'))
        .writeAsString('{"version": 99}');
    final controller = BoardController(BoardStore(file));
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.readFailed, isTrue);
    expect(
      await controller.change((doc) => doc.remove(TileKind.hardware)),
      isFalse,
    );
    expect(await file.readAsString(), '{"version": 99}');
  });

  test(
    'layout places three sizes without overlap and keeps the saved sizes',
    () {
      final tiles = BoardDocument.initial().active.tiles;
      expect(arrangeTiles(tiles, 4), [
        (column: 0, row: 0, columns: 2, rows: 2),
        (column: 2, row: 0, columns: 2, rows: 1),
        (column: 2, row: 1, columns: 1, rows: 1),
        (column: 3, row: 1, columns: 1, rows: 1),
      ]);
      expect(arrangeTiles(tiles, 1).every((tile) => tile.columns == 1), isTrue);
      expect(tiles.first.size, TileSize.large);
    },
  );

  test(
    'rates require valid snapshots from matching adapters and CPU counters',
    () {
      const before = HostSample(
        time: Duration.zero,
        cpu: (idle: 10, total: 20),
        interfaces: {1: (received: 10, sent: 20)},
      );
      const after = HostSample(
        time: Duration(seconds: 2),
        cpu: (idle: 35, total: 120),
        interfaces: {1: (received: 1000010, sent: 500020)},
      );
      expect(measure(null, after), (cpu: null, receive: null, send: null));
      expect(measure(before, after), (cpu: .75, receive: 4.0, send: 2.0));
      const changedAdapter = HostSample(
        time: Duration(seconds: 4),
        cpu: (idle: 1, total: 9),
        interfaces: {2: (received: 5000010, sent: 500030)},
      );
      expect(measure(after, changedAdapter), (
        cpu: null,
        receive: null,
        send: null,
      ));
      const resumed = HostSample(
        time: Duration(seconds: 40),
        cpu: (idle: 65, total: 180),
        interfaces: {1: (received: 2000010, sent: 750020)},
      );
      expect(measure(after, resumed), (cpu: null, receive: null, send: null));
    },
  );

  testWidgets(
    'creates a space, chooses a tile variant, edits it and switches boards',
    (tester) async {
      final store = _MemoryStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark(),
          home: DashboardHome(
            host: 'ATLAS-PC',
            account: const Center(child: Text('Регистрация устройства')),
            tunnelDetails: const Text('Подробности соединения'),
            settings: const Text('Журналы'),
            boardStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Оборудование'), findsOneWidget);
      expect(find.text('Туннель недоступен'), findsOneWidget);

      await tester.tap(find.byTooltip('Новое пространство'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Название'),
        'Работа',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Стекло'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();
      expect(store.saved.active.name, 'Работа');
      expect(store.saved.active.image, SpaceImage.glass);

      await tester.tap(find.text('Добавить первый виджет'));
      await tester.pumpAndSettle();
      final networkCard = find.byKey(const ValueKey(TileKind.network));
      final diskCard = find.byKey(const ValueKey(TileKind.disk));
      final cardSize = tester.getSize(networkCard);
      expect(tester.getSize(diskCard), cardSize);
      await tester.enterText(
        find.widgetWithText(TextField, 'Поиск виджетов'),
        'приём',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, '1 × 1'));
      await tester.tap(find.widgetWithText(ChoiceChip, '1 × 1'));
      await tester.pumpAndSettle();
      expect(tester.getSize(networkCard), cardSize);
      await tester.ensureVisible(find.text('Добавить в это пространство'));
      await tester.tap(find.text('Добавить в это пространство'));
      await tester.pumpAndSettle();
      expect(store.saved.active.tiles.single, (
        kind: TileKind.network,
        size: TileSize.square,
      ));

      await tester.tap(find.widgetWithText(ListTile, 'Обзор'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Настроить доску'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Настроить виджет: Сеть'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<Object>, '2 × 2'),
      );
      await tester.pumpAndSettle();
      expect(store.saved.active.tiles.single.size, TileSize.large);

      await tester.tap(find.byTooltip('Личное'));
      await tester.pumpAndSettle();
      expect(find.text('Оборудование'), findsOneWidget);
      expect(store.saved.active.tiles.length, 4);
      await tester.tap(find.byTooltip('Настройки приложения'));
      await tester.pumpAndSettle();
      expect(find.text('Журналы'), findsOneWidget);
      await tester.tap(find.byTooltip('Учётная запись'));
      await tester.pumpAndSettle();
      expect(find.text('Регистрация устройства'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
