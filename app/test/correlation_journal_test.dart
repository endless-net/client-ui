import 'dart:async';
import 'dart:typed_data';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/client/correlation_journal.dart';
import 'package:endlessnet_client_ui/client/enrollment_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:endlessnet_client_ui/enrollment/controller.dart';

import 'enrollment_controller_test.dart' as fixture;

final class MemoryIO implements CorrelationJournalIO {
  Uint8List bytes = Uint8List(0);
  int flushes = 0;
  int writes = 0;
  bool failWrite = false;
  bool failFlush = false;
  bool closed = false;
  Completer<void>? pendingFlush;
  @override
  Future<Uint8List> read(int maxBytes) async {
    if (bytes.length > maxBytes) throw StateError('budget');
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> append(Uint8List value) async {
    writes++;
    bytes = Uint8List.fromList([...bytes, ...value]);
    if (failWrite) throw StateError('raw-write-diagnostic');
  }

  @override
  Future<void> flush() async {
    flushes++;
    await pendingFlush?.future;
    if (failFlush) throw StateError('raw-flush-diagnostic');
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

EnrollmentCorrelation record({
  String profile = 'profile-A',
  String origin = 'https://control.example',
  String? uuid,
  DateTime? until,
}) => EnrollmentCorrelation(
  profileId: profile,
  controlOrigin: origin,
  requestId: uuid ?? '00000000-0000-4000-8000-000000000001',
  hostname: 'host',
  mode: api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION,
  recoveryDeadline: until,
);

Matcher problem(CorrelationStoreProblem value) => throwsA(
  isA<CorrelationStoreFailure>().having((e) => e.problem, 'problem', value),
);

void main() {
  testWidgets(
    'failed flush of an earlier recovery boundary halts polling and reopen keeps the shorter frame',
    (tester) async {
      var clock = fixture.now;
      final io = MemoryIO();
      final store = JournalCorrelationStore(io, maxBytes: 8192);
      final client = fixture.FakeClient()..lostEnroll = true;
      var c = fixture.automaticController(client, store, () => clock);
      await c.bind(fixture.profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      client.value = fixture.makeAttempt(
        phase: api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERING,
      )..certainty = api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_UNCERTAIN;
      client.value.recoveryDeadline = fixture.makeAttempt().createdAt.deepCopy()
        ..seconds += 2;
      io.failFlush = true;
      await c.refresh();
      expect(c.reasonKey, 'ui.correlation_save_failed');
      final reads = client.lookups;
      clock = fixture.now.add(const Duration(minutes: 3));
      await tester.pump(const Duration(minutes: 3));
      expect(client.lookups, reads);
      c.dispose();
      await store.close();
      final freshIO = MemoryIO()..bytes = Uint8List.fromList(io.bytes);
      final reopened = JournalCorrelationStore(freshIO, maxBytes: 8192);
      c = fixture.automaticController(client, reopened, () => clock);
      await c.bind(fixture.profile());
      expect(
        c.correlation!.recoveryDeadline,
        fixture.now.add(const Duration(seconds: 2)),
      );
      expect(client.enrolls, 1);
      c.dispose();
      await reopened.close();
    },
  );
  test('authoritative earlier recovery bound survives reopen and can never be extended or cleared', () async {
    final io = MemoryIO();
    final store = JournalCorrelationStore(io, maxBytes: 8192);
    final first = DateTime.utc(2026, 10, 30, 12, 2);
    final earlier = first.subtract(const Duration(seconds: 30));
    await store.save(record(until: first));
    await store.save(record(until: earlier));
    final reopened = JournalCorrelationStore(io, maxBytes: 8192);
    expect(
      (await reopened.read(
        'profile-A',
        'https://control.example',
      ))!.recoveryDeadline,
      earlier,
    );
    await expectLater(
      reopened.save(record(until: first)),
      problem(CorrelationStoreProblem.conflict),
    );
    await expectLater(
      reopened.save(record()),
      problem(CorrelationStoreProblem.conflict),
    );
    expect(
      record(until: first).uncertainUntil(earlier).recoveryDeadline,
      earlier,
    );
    expect(
      record(until: earlier).uncertainUntil(first).recoveryDeadline,
      earlier,
    );
  });
  EnrollmentController controller(
    fixture.FakeClient client,
    JournalCorrelationStore store,
  ) => EnrollmentController(
    client: client,
    store: store,
    expectedContractSha256: 'a' * 64,
    now: () => fixture.now,
    callTimeout: const Duration(seconds: 1),
    recoveryPollInterval: const Duration(seconds: 1),
    requestId: () => fixture.requestId,
    automaticPolling: false,
  );

  test('controller cannot send Enroll before journal flush or after storage failure', () async {
    final io = MemoryIO()..pendingFlush = Completer<void>();
    final store = JournalCorrelationStore(io, maxBytes: 8192);
    final client = fixture.FakeClient();
    final c = controller(client, store);
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    final started = c.start(
      'host',
      api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION,
    );
    await Future<void>.delayed(Duration.zero);
    expect(client.enrolls, 0);
    io.failFlush = true;
    io.pendingFlush!.complete();
    await started;
    expect(client.enrolls, 0);
    expect(c.reasonKey, 'ui.correlation_save_failed');
    await store.close();
    io.failFlush = false;
    final reopened = controller(
      client,
      JournalCorrelationStore(io, maxBytes: 8192),
    );
    addTearDown(reopened.dispose);
    await reopened.bind(fixture.profile());
    expect(client.lookup!.requestId, fixture.requestId);
    expect(client.enrolls, 0);
    expect(reopened.correlation!.requestId, fixture.requestId);
  });

  test(
    'corrupt journal bind shows storage failure and cannot start a new UUID',
    () async {
      final io = MemoryIO()..bytes = Uint8List.fromList([1, 2, 3]);
      final client = fixture.FakeClient();
      final c = controller(client, JournalCorrelationStore(io, maxBytes: 8192));
      addTearDown(c.dispose);
      await c.bind(fixture.profile());
      expect(c.canEnroll, false);
      expect(c.reasonKey, 'ui.correlation_store_failed');
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      expect(client.enrolls, 0);
      expect(io.writes, 0);
    },
  );
  test(
    'save awaits flush; exact replay also flushes after uncertain prior write',
    () async {
      final io = MemoryIO()..pendingFlush = Completer<void>();
      final store = JournalCorrelationStore(io, maxBytes: 8192);
      var saved = false;
      final work = store.save(record()).then((_) => saved = true);
      await Future<void>.delayed(Duration.zero);
      expect(io.writes, 1);
      expect(saved, false);
      io.pendingFlush!.complete();
      await work;
      expect(saved, true);
      final size = io.bytes.length;
      await store.save(record());
      expect(io.bytes.length, size);
      expect(io.writes, 1);
      expect(io.flushes, 2);
      await store.close();
    },
  );

  test(
    'reopen recovers immutable UUID and precise first recovery deadline',
    () async {
      final io = MemoryIO();
      final original = JournalCorrelationStore(io, maxBytes: 8192);
      await original.save(record());
      final until = DateTime.utc(2026, 10, 30, 12, 2, 0, 123, 456);
      await original.save(record(until: until));
      final reopened = JournalCorrelationStore(io, maxBytes: 8192);
      final saved = await reopened.read('profile-A', 'https://control.example');
      expect(saved!.requestId, record().requestId);
      expect(saved.recoveryDeadline, until);
      expect(await reopened.read('profile-A', 'https://other.example'), isNull);
      await expectLater(
        reopened.save(record(until: until.add(const Duration(seconds: 1)))),
        problem(CorrelationStoreProblem.conflict),
      );
      await expectLater(
        reopened.save(record()),
        problem(CorrelationStoreProblem.conflict),
      );
      await expectLater(
        reopened.save(record(uuid: '00000000-0000-4000-8000-000000000002')),
        problem(CorrelationStoreProblem.conflict),
      );
      expect(
        (await reopened.read(
          'profile-A',
          'https://control.example',
        ))!.recoveryDeadline,
        until,
      );
    },
  );

  test(
    'write/flush failures do not report success or leak raw diagnostics',
    () async {
      for (final write in [true, false]) {
        final io = MemoryIO()
          ..failWrite = write
          ..failFlush = !write;
        final store = JournalCorrelationStore(io, maxBytes: 8192);
        await expectLater(
          store.save(record()),
          problem(CorrelationStoreProblem.inaccessible),
        );
        io.failWrite = false;
        io.failFlush = false;
        // The failed call may have left a complete frame: recover it, no new UUID.
        expect(
          (await store.read('profile-A', 'https://control.example'))!.requestId,
          record().requestId,
        );
        await store.save(record());
        expect(io.writes, 1);
        expect(io.flushes, write ? 1 : 2);
        const failure = CorrelationStoreFailure(
          CorrelationStoreProblem.inaccessible,
        );
        expect(failure.toString().contains('raw-'), false);
      }
    },
  );

  test('partial frames and bit damage fail closed without truncation or new writes', () async {
    final io = MemoryIO();
    final store = JournalCorrelationStore(io, maxBytes: 8192);
    await store.save(record());
    final valid = Uint8List.fromList(io.bytes);
    for (
      var size = CorrelationJournal.initialBytes.length + 1;
      size < valid.length;
      size++
    ) {
      io.bytes = Uint8List.fromList(valid.sublist(0, size));
      final before = Uint8List.fromList(io.bytes);
      await expectLater(
        store.read('profile-A', 'https://control.example'),
        problem(CorrelationStoreProblem.corrupt),
      );
      await expectLater(
        store.save(record()),
        problem(CorrelationStoreProblem.corrupt),
      );
      expect(io.bytes, before);
    }
    io.bytes = Uint8List.fromList(valid)..[20] ^= 1;
    await expectLater(
      store.read('profile-A', 'https://control.example'),
      problem(CorrelationStoreProblem.corrupt),
    );
    expect(io.writes, 1);
  });

  test(
    'different profile/origin records coexist; bounded file refuses growth',
    () async {
      final io = MemoryIO();
      final store = JournalCorrelationStore(io, maxBytes: 8192);
      for (var i = 0; i < 20; i++) {
        await store.save(record(profile: 'profile-$i'));
      }
      expect(
        (await store.read('profile-0', 'https://control.example'))!.requestId,
        record().requestId,
      );
      var full = false;
      for (var i = 20; i < 200; i++) {
        try {
          await store.save(record(profile: 'profile-$i'));
        } on CorrelationStoreFailure catch (error) {
          expect(error.problem, CorrelationStoreProblem.full);
          full = true;
          break;
        }
      }
      expect(full, true);
      expect(io.bytes.length, lessThanOrEqualTo(8192));
      expect(
        await store.read('profile-0', 'https://control.example'),
        isNotNull,
      );
    },
  );

  test('busy fails immediately, close awaits outstanding flush and rejects new work', () async {
    final io = MemoryIO()..pendingFlush = Completer<void>();
    final store = JournalCorrelationStore(io, maxBytes: 8192);
    final save = store.save(record());
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      store.read('profile-A', 'https://control.example'),
      problem(CorrelationStoreProblem.busy),
    );
    final closing = store.close();
    await expectLater(
      store.save(record()),
      problem(CorrelationStoreProblem.closed),
    );
    expect(io.closed, false);
    io.pendingFlush!.complete();
    await save;
    await closing;
    expect(io.closed, true);
    await store.close();
  });

  test('invalid correlation cannot enter the journal', () async {
    final io = MemoryIO();
    final store = JournalCorrelationStore(io, maxBytes: 8192);
    for (final invalid in [
      record(origin: 'http://control.example'),
      record(uuid: 'not-a-uuid'),
      record(profile: ''),
    ]) {
      await expectLater(
        store.save(invalid),
        problem(CorrelationStoreProblem.corrupt),
      );
    }
    expect(io.writes, 0);
    expect(io.flushes, 0);
  });
}
