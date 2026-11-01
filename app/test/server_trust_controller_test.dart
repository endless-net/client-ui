import 'dart:async';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/client/call_failure.dart';
import 'package:endlessnet_client_ui/enrollment/server_trust_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;

import 'enrollment_controller_test.dart' as fixture;

api.GetServerIdentityResponse announcement({
  String profile = 'profile-A',
  String key = 'announced-key',
  String id = 'announcement-A',
  bool trusted = false,
}) => api.GetServerIdentityResponse(
  metadata: fixture.metadata(),
  identity: api.ServerIdentity(
    profileId: profile,
    controlOrigin: 'https://control.example',
    trustedKeyId: trusted ? key : 'previous-key',
    announcedKeyId: key,
    announcementId: id,
    changed: !trusted,
  ),
);

class TrustClient extends fixture.FakeClient {
  int reads = 0;
  int trusts = 0;
  api.Access access = api.Access.ACCESS_ADMINISTRATOR;
  api.GetServerIdentityResponse identity = announcement();
  api.TrustServerIdentityRequest? confirmed;
  api.GetServerIdentityRequest? readRequest;
  bool persist = true;
  bool lostTrust = false;
  ClientCallFailure? trustFailure;
  ClientCallFailure? readFailure;
  Completer<api.GetServerIdentityResponse>? pendingRead;
  Completer<void>? pendingTrust;
  @override
  Future<api.RuntimeInfo> runtimeInfo(Duration timeout) async =>
      (await super.runtimeInfo(timeout))..callerAccess = access;
  @override
  Future<api.GetServerIdentityResponse> serverIdentity(
    api.GetServerIdentityRequest request,
    Duration timeout,
  ) async {
    reads++;
    readRequest = request;
    if (pendingRead != null) return pendingRead!.future;
    if (readFailure != null) throw readFailure!;
    return identity;
  }

  @override
  Future<api.ChangeResult> trustIdentity(
    api.TrustServerIdentityRequest request,
    Duration timeout,
  ) async {
    trusts++;
    confirmed = api.TrustServerIdentityRequest.fromBuffer(
      request.writeToBuffer(),
    );
    await pendingTrust?.future;
    if (trustFailure != null) throw trustFailure!;
    if (persist) {
      identity =
          api.GetServerIdentityResponse.fromBuffer(identity.writeToBuffer())
            ..identity.trustedKeyId = request.confirmedKeyId
            ..identity.changed = false
            ..metadata.revision += 1;
    }
    if (lostTrust) {
      throw ClientCallFailure.fromGrpc(
        const grpc.GrpcError.unavailable('raw-secret'),
        16384,
      );
    }
    return api.ChangeResult(changed: true);
  }
}

ServerTrustController trustController(TrustClient client) =>
    ServerTrustController(
      client: client,
      expectedContractSha256: 'a' * 64,
      callTimeout: const Duration(seconds: 1),
    );

void main() {
  test('local snapshot invalidates cached trust and fences a stale re-read across bind', () async {
    final client = TrustClient()..identity = announcement(trusted: true);
    final c = trustController(client);
    addTearDown(c.dispose);
    c.observeLocalState(
      fixture.profile(),
      fixture.metadata(),
      reasonKey: '',
      available: true,
    );
    await c.bind(fixture.profile());
    expect(c.trusted, isTrue);
    final newer = fixture.metadata()..revision += 1;
    c.observeLocalState(
      fixture.profile(),
      newer,
      reasonKey: 'client.server_identity.changed',
      available: true,
    );
    expect(c.observation, isNull);
    expect(c.trusted, isFalse);
    await c.bind(fixture.profile());
    expect(
      c.observation,
      isNull,
    ); // Producer reply predates the local snapshot.
    client.identity = announcement()..metadata.revision = newer.revision;
    await c.bind(fixture.profile());
    expect(c.canConfirm, isTrue);
    c.observeLocalState(
      fixture.profile(),
      newer,
      reasonKey: 'client.server_identity.changed',
      available: true,
    );
    expect(
      c.canConfirm,
      isTrue,
    ); // Repeated notifications are not new evidence.
    expect(client.trusts, 0);
  });

  test(
    'local profile origin or instance change fences old dialog and late reads',
    () async {
      for (final change in ['profile', 'origin', 'instance']) {
        final client = TrustClient();
        final c = trustController(client);
        await c.bind(fixture.profile());
        final old = c.observation!;
        client.pendingRead = Completer<api.GetServerIdentityResponse>();
        final read = c.refresh();
        final profile = fixture.profile(
          change == 'profile' ? 'profile-B' : 'profile-A',
        );
        if (change == 'origin') profile.controlOrigin = 'https://other.example';
        final meta = fixture.metadata();
        if (change == 'instance') meta.instanceId = 'instance-B';
        c.observeLocalState(profile, meta, reasonKey: '', available: true);
        client.pendingRead!.complete(announcement());
        await read;
        expect(c.observation, isNull);
        expect(await c.confirm(old), isFalse);
        expect(client.trusts, 0);
        c.dispose();
      }
    },
  );

  test('a newly unavailable local state invalidates trust; unknown in-flight confirmation never auto retries', () async {
    final client = TrustClient()..pendingTrust = Completer<void>();
    final c = trustController(client);
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    final confirming = c.confirm(c.observation!);
    c.observeLocalState(
      fixture.profile(),
      fixture.metadata(),
      reasonKey: 'ui.client_unavailable',
      available: false,
    );
    client.pendingTrust!.complete();
    expect(await confirming, isFalse);
    expect(c.unknownOutcome, isTrue);
    expect(c.observation, isNull);
    expect(client.trusts, 1);
    expect(client.reads, 1);
  });
  test(
    'contract mismatch cannot read or confirm a server announcement',
    () async {
      final client = TrustClient()..digest = 'b' * 64;
      final c = trustController(client);
      addTearDown(c.dispose);
      await c.bind(fixture.profile());
      expect(c.state, ServerTrustState.mismatch);
      expect(c.canRefresh, false);
      expect(c.canConfirm, false);
      expect(client.reads, 0);
      expect(client.trusts, 0);
    },
  );
  test('read never trusts automatically and OWNER cannot issue privileged UI confirmation', () async {
    final client = TrustClient()..access = api.Access.ACCESS_OWNER;
    final c = trustController(client);
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    expect(client.readRequest!.profile.profileId, 'profile-A');
    expect(c.observation!.identity.announcedKeyId, 'announced-key');
    expect(c.canConfirm, false);
    expect(c.administratorAvailable, false);
    await c.confirm(c.observation!);
    expect(client.trusts, 0);
    expect(client.enrolls, 0);
  });

  test('confirmation carries exact displayed fields/revision and requires current re-read', () async {
    final client = TrustClient();
    final c = trustController(client);
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    expect(client.trusts, 0);
    final displayed = c.observation!;
    expect(await c.confirm(displayed), true);
    expect(client.confirmed!.confirmedControlOrigin, 'https://control.example');
    expect(client.confirmed!.confirmedKeyId, displayed.identity.announcedKeyId);
    expect(
      client.confirmed!.confirmedAnnouncementId,
      displayed.identity.announcementId,
    );
    expect(
      client.confirmed!.mutation.expectedRevision.toStringUnsigned(),
      '9007199254740993',
    );
    expect(client.confirmed!.mutation.expectedInstanceId, 'instance-A');
    expect(client.reads, 2);
    expect(c.trusted, true);
    expect(c.canConfirm, false);
    expect(client.enrolls, 0);
  });

  test(
    'changed=true acknowledgement without matching current trust is unknown',
    () async {
      final client = TrustClient()..persist = false;
      final c = trustController(client);
      addTearDown(c.dispose);
      await c.bind(fixture.profile());
      expect(await c.confirm(c.observation!), false);
      expect(c.trusted, false);
      expect(c.unknownOutcome, true);
      expect(c.canConfirm, false);
      expect(client.trusts, 1);
    },
  );

  test('lost trust reply reads current state manually without automatic mutation retry', () async {
    final client = TrustClient()..lostTrust = true;
    final c = trustController(client);
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    final old = c.observation!;
    expect(await c.confirm(old), false);
    expect(c.unknownOutcome, true);
    expect(c.canConfirm, false);
    expect(client.reads, 1);
    expect(await c.confirm(old), false);
    await c.refresh();
    expect(c.trusted, true);
    expect(c.unknownOutcome, false);
    expect(client.trusts, 1);
    expect(client.reads, 2);
    expect(client.enrolls, 0);
  });

  test(
    'mutated observation and rotated announcement invalidate old confirmation',
    () async {
      final client = TrustClient();
      final c = trustController(client);
      addTearDown(c.dispose);
      await c.bind(fixture.profile());
      final old = c.observation!;
      final modified = c.observation!
        ..identity.controlOrigin = 'https://evil.example';
      expect(await c.confirm(modified), false);
      expect(client.trusts, 0);
      expect(c.canConfirm, false);
      client.identity = announcement(id: 'announcement-B');
      await c.refresh();
      expect(await c.confirm(old), false);
      expect(client.trusts, 0);
      await c.refresh();
      expect(await c.confirm(c.observation!), true);
      expect(client.confirmed!.confirmedAnnouncementId, 'announcement-B');
    },
  );

  test('foreign origin/profile/instance or rollback never creates confirmable observation', () async {
    for (final kind in ['origin', 'profile', 'instance', 'rollback']) {
      final client = TrustClient();
      final c = trustController(client);
      await c.bind(fixture.profile());
      switch (kind) {
        case 'origin':
          client.identity.identity.controlOrigin = 'https://evil.example';
        case 'profile':
          client.identity.identity.profileId = 'foreign';
        case 'instance':
          client.identity.metadata.instanceId = 'foreign';
        case 'rollback':
          client.identity.metadata.revision -= 1;
      }
      await c.refresh();
      expect(c.observation, isNull, reason: kind);
      expect(c.canConfirm, false);
      expect(c.trusted, false);
      expect(client.trusts, 0);
      c.dispose();
    }
  });

  test('late old profile read and in-flight duplicate confirm cannot mutate new binding', () async {
    final client = TrustClient()
      ..pendingRead = Completer<api.GetServerIdentityResponse>();
    final c = trustController(client);
    final oldRead = c.bind(fixture.profile());
    await Future<void>.delayed(Duration.zero);
    final pending = client.pendingRead!;
    client.pendingRead = null;
    client.identity = announcement(profile: 'profile-B');
    await c.bind(fixture.profile('profile-B'));
    pending.complete(announcement());
    await oldRead;
    expect(c.observation!.identity.profileId, 'profile-B');
    client.pendingTrust = Completer<void>();
    final displayed = c.observation!;
    final trusting = c.confirm(displayed);
    await Future<void>.delayed(Duration.zero);
    expect(await c.confirm(displayed), false);
    expect(client.trusts, 1);
    c.dispose();
    client.pendingTrust!.complete();
    expect(await trusting, false);
  });

  test(
    'failed post-ack read remains unknown even if read permission was revoked',
    () async {
      final client = TrustClient();
      final c = trustController(client);
      addTearDown(c.dispose);
      await c.bind(fixture.profile());
      client.readFailure = ClientCallFailure.fromGrpc(
        const grpc.GrpcError.permissionDenied('raw-secret'),
        16384,
      );
      expect(await c.confirm(c.observation!), false);
      expect(c.unknownOutcome, true);
      expect(c.trusted, false);
      expect(c.reasonKey, 'ui.server_identity.trust_unknown');
      expect(client.trusts, 1);
    },
  );
}
