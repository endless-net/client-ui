import 'dart:async';
import 'dart:typed_data';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/client/correlation_journal.dart';
import 'package:endlessnet_client_ui/client/call_failure.dart';
import 'package:endlessnet_client_ui/client/revocation_client.dart';
import 'package:endlessnet_client_ui/client/revocation_correlation.dart';
import 'package:endlessnet_client_ui/revocation/controller.dart';
import 'package:endlessnet_client_ui/revocation/panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:grpc/grpc.dart' as grpc;

import 'correlation_journal_test.dart' as journal;

const profileId = '0b6e11e3-3daa-4846-92ed-e07b6d8ce566';
const commandId = '00000000-0000-4000-8000-000000000001';
const origin = 'https://control.example';
api.Profile profile() => api.Profile(id: profileId, controlOrigin: origin);
api.NodeRevocationTarget target([String id = 'lost']) =>
    api.NodeRevocationTarget(
      accountId: 'account',
      networkId: 'network',
      nodeId: id,
      hostname: 'same-name',
      assignedIp: '100.70.0.2',
      status: 'active',
      networkRevision: api.SnapshotMetadata().revision + 7,
    );
RevocationCorrelation correlation([String id = 'lost']) =>
    RevocationCorrelation(
      profileId: profileId,
      controlOrigin: origin,
      commandId: commandId,
      target: target(id),
    );

final class Remote implements RevocationClient {
  int mutations = 0, queries = 0;
  bool lose = false,
      wrongDigest = false,
      foreignResult = false,
      staleInstance = false;
  api.RevokeNodeAccessRequest? original;
  @override
  Future<api.RuntimeInfo> runtimeInfo(Duration timeout) async =>
      api.RuntimeInfo(
        instanceId: 'instance',
        contractSha256: wrongDigest ? '2' * 64 : '1' * 64,
        protocol: 'endlessnet-client-ipc',
        ipcVersion: 0,
        callerAccess: api.Access.ACCESS_OWNER,
      );
  @override
  Future<api.Status> status(Duration timeout) async => api.Status(
    activeProfileId: profileId,
    accountId: 'account',
    nodeId: 'available',
    network: api.Network(id: 'network'),
  );
  @override
  Future<api.ListNodeRevocationTargetsResponse> revocationTargets(
    api.ListNodeRevocationTargetsRequest request,
    Duration timeout,
  ) async => api.ListNodeRevocationTargetsResponse(
    targets: [target(), target('other')],
    metadata: api.SnapshotMetadata(
      instanceId: 'instance',
      revision: api.SnapshotMetadata().revision + 3,
    ),
  );
  api.NodeRevocationResult receipt() {
    final at = DateTime.utc(2026, 11, 2, 12);
    return api.NodeRevocationResult(
      profileId: profileId,
      commandId: commandId,
      target: foreignResult ? target('foreign') : original!.target,
      phase: api.NodeRevocationPhase.NODE_REVOCATION_PHASE_ACCEPTED,
      acceptedAt: Timestamp.fromDateTime(at),
      enforceBy: Timestamp.fromDateTime(at.add(const Duration(seconds: 300))),
      committedNetworkRevision: api.SnapshotMetadata().revision + 8,
    );
  }

  @override
  Future<api.NodeRevocationResult> revokeNode(
    api.RevokeNodeAccessRequest request,
    Duration timeout,
  ) async {
    mutations++;
    original = api.RevokeNodeAccessRequest.fromBuffer(request.writeToBuffer());
    if (staleInstance) {
      throw ClientCallFailure.fromGrpc(grpc.GrpcError.aborted('private'), 4096);
    }
    if (lose) {
      throw TimeoutException('private detail');
    }
    return receipt();
  }

  @override
  Future<api.NodeRevocationResult> nodeRevocation(
    api.GetNodeRevocationRequest request,
    Duration timeout,
  ) async {
    queries++;
    expect(request.commandId, commandId);
    return receipt();
  }
}

RevocationController controller(Remote remote, JournalCorrelationStore store) =>
    RevocationController(
      client: remote,
      store: store,
      expectedContractSha256: '1' * 64,
      expectedInstanceId: 'instance',
      timeout: const Duration(seconds: 1),
      commandId: () => commandId,
    );

void main() {
  test(
    'stale local instance cannot resolve an unknown original command',
    () async {
      final remote = Remote()..staleInstance = true;
      final c = controller(
        remote,
        JournalCorrelationStore(journal.MemoryIO(), maxBytes: 16384),
      );
      await c.bind(profile());
      await c.revoke(target());
      expect(c.canChoose, isFalse);
      expect(c.hasOriginal, isTrue);
      expect(c.result, isNull);
      c.dispose();
    },
  );
  test('mixed durable journal preserves enrollment and refuses unresolved retargeting', () async {
    final io = journal.MemoryIO();
    final store = JournalCorrelationStore(io, maxBytes: 16384);
    await store.save(journal.record());
    await store.saveRevocation(correlation());
    expect(
      (await store.read('profile-A', origin))!.requestId,
      journal.record().requestId,
    );
    expect(
      (await store.readRevocation(profileId, origin))!.commandId,
      commandId,
    );
    await expectLater(
      store.saveRevocation(correlation('other')),
      journal.problem(CorrelationStoreProblem.conflict),
    );
    final reopened = JournalCorrelationStore(io, maxBytes: 16384);
    expect(
      (await reopened.readRevocation(profileId, origin))!.target.nodeId,
      'lost',
    );
    io.bytes = Uint8List.fromList(io.bytes)..[io.bytes.length - 1] ^= 1;
    await expectLater(
      reopened.readRevocation(profileId, origin),
      journal.problem(CorrelationStoreProblem.corrupt),
    );
  });

  test(
    'first mutation waits for durable flush and failed flush sends nothing',
    () async {
      final io = journal.MemoryIO()..pendingFlush = Completer<void>();
      final remote = Remote();
      final c = controller(
        remote,
        JournalCorrelationStore(io, maxBytes: 16384),
      );
      await c.bind(profile());
      final pending = c.revoke(target());
      await Future<void>.delayed(Duration.zero);
      expect(remote.mutations, 0);
      io.pendingFlush!.complete();
      await pending;
      expect(remote.mutations, 1);
      expect(
        c.result!.phase,
        api.NodeRevocationPhase.NODE_REVOCATION_PHASE_ACCEPTED,
      );
      c.dispose();
      final failed = journal.MemoryIO()..failFlush = true;
      final other = Remote();
      final blocked = controller(
        other,
        JournalCorrelationStore(failed, maxBytes: 16384),
      );
      await blocked.bind(profile());
      await blocked.revoke(target());
      expect(other.mutations, 0);
      expect(blocked.result, isNull);
      blocked.dispose();
    },
  );

  test('lost answer reopens by original UUID using query only', () async {
    final io = journal.MemoryIO();
    final remote = Remote()..lose = true;
    final c = controller(remote, JournalCorrelationStore(io, maxBytes: 16384));
    await c.bind(profile());
    await c.revoke(target());
    expect(remote.mutations, 1);
    expect(c.result, isNull);
    expect(c.canChoose, isFalse);
    c.dispose();
    remote.lose = false;
    final reopened = controller(
      remote,
      JournalCorrelationStore(io, maxBytes: 16384),
    );
    await reopened.bind(profile());
    expect(remote.mutations, 1);
    expect(remote.queries, 1);
    expect(reopened.result!.commandId, commandId);
    expect(reopened.result!.target.nodeId, 'lost');
    await reopened.retryOriginal();
    expect(remote.mutations, 2);
    expect(remote.original!.commandId, commandId);
    reopened.dispose();
  });

  test(
    'mismatched runtime and foreign receipt never become accepted',
    () async {
      final remote = Remote()..wrongDigest = true;
      final c = controller(
        remote,
        JournalCorrelationStore(journal.MemoryIO(), maxBytes: 16384),
      );
      await c.bind(profile());
      await c.revoke(target());
      expect(remote.mutations, 0);
      c.dispose();
      final foreign = Remote()..foreignResult = true;
      final other = controller(
        foreign,
        JournalCorrelationStore(journal.MemoryIO(), maxBytes: 16384),
      );
      await other.bind(profile());
      await other.revoke(target());
      expect(other.result, isNull);
      expect(other.canChoose, isFalse);
      other.dispose();
    },
  );

  testWidgets(
    'exact target confirmation and elapsed deadline never claim enforcement',
    (tester) async {
      final remote = Remote();
      final c = controller(
        remote,
        JournalCorrelationStore(journal.MemoryIO(), maxBytes: 16384),
      );
      await c.bind(profile());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: RevocationPanel(controller: c)),
          ),
        ),
      );
      await tester.tap(find.text('Отозвать').first);
      await tester.pumpAndSettle();
      expect(remote.mutations, 0);
      expect(find.textContaining('Node: lost'), findsWidgets);
      await tester.tap(find.text('Отозвать доступ'));
      await tester.pumpAndSettle();
      expect(remote.mutations, 1);
      expect(find.text('Отзыв принят'), findsOneWidget);
      await tester.pump(const Duration(minutes: 6));
      expect(find.text('Запрет подтверждён'), findsNothing);
      expect(
        find.textContaining(
          'Локальная очистка потерянного устройства неизвестна',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
