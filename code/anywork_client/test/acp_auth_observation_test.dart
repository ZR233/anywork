import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/acp_port_fixture.dart';

/// `acpAuth` 是独立版本域：首帧基线（含 revision 0）是唯一加载入口，之后按
/// owner/revision 单调收敛。基线与每条变更都携带完整快照，所以这些用例全部通过
/// `AcpAuthRepository` 的公开观察面判定收敛结果，而不是断言 fake 自己的字段。
void main() {
  test(
    'the first canonical frame is the baseline, including revision zero',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.auth;
      addTearDown(() async {
        final report = await repository.close();
        expect(report.unresolved, isEmpty);
        expect(fixture.budget.usage, isEmpty);
      });

      var ready = false;
      final synchronizing = repository.synchronize().then((_) => ready = true);
      final feed = await fixture.port.authFeedOpened(0);

      expect(ready, isFalse, reason: 'ready waits for the native baseline');
      expect(
        repository.state.value.projection.sync.phase,
        ResourceSyncPhase.connecting,
      );
      expect(
        repository.state.value.canonical,
        isNull,
        reason:
            'an unloaded domain must not publish a fabricated empty snapshot',
      );
      expect(
        repository.state.value.stateOf(
          acpTestAccountId,
          connectionRevision: acpTestConnectionRevision,
        ),
        isA<AcpAuthUnchecked>(),
      );

      await feed.listened;
      expect(ready, isFalse, reason: 'connecting alone is not a baseline');
      await feed.acknowledged(feed.sendBaseline(AcpAuthSnapshot.empty));
      await synchronizing;

      expect(ready, isTrue);
      expect(
        repository.state.value.projection.sync.phase,
        ResourceSyncPhase.ready,
      );
      expect(repository.state.value.canonical, AcpAuthSnapshot.empty);
      expect(repository.state.value.projection.header?.revision, 0);

      final lease = repository.observe();
      expect(lease.latest.value, repository.state.value);
      expect(repository.state.observerCount, 1);
      lease.release();
      expect(
        repository.state.observerCount,
        0,
        reason: 'a lease owns only its own observation',
      );
    },
  );

  test(
    'a named canonical read is bounded evidence and never rewrites the mirror',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.auth;
      addTearDown(() async {
        final report = await repository.close();
        expect(report.unresolved, isEmpty);
        expect(fixture.budget.usage, isEmpty);
      });

      final reading = repository.readCanonical();
      expect(fixture.port.authReads, hasLength(1));
      fixture.port.answerAuthRead(
        0,
        acpAuthSnapshot(revision: 5, state: const AcpAuthState.unchecked()),
      );
      expect((await reading).revision, 5);

      expect(fixture.port.authFeeds, isEmpty, reason: 'a read opens no feed');
      expect(repository.state.value.canonical, isNull);
      expect(
        repository.state.value.projection.sync.phase,
        ResourceSyncPhase.idle,
      );
    },
  );

  test('a malformed canonical read fails as a protocol error instead of loading it', () async {
    final fixture = AcpPortFixture();
    final repository = fixture.auth;
    addTearDown(() async {
      final report = await repository.close();
      expect(report.unresolved, isEmpty);
    });

    final negative = repository.readCanonical();
    fixture.port.answerAuthRead(
      0,
      const AcpAuthSnapshot(revision: -1, updatedAt: 0, accounts: []),
    );
    await expectLater(
      negative,
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.protocol,
        ),
      ),
    );

    final duplicated = repository.readCanonical();
    fixture.port.answerAuthRead(
      1,
      AcpAuthSnapshot(
        revision: 1,
        updatedAt: 1,
        accounts: [
          const AcpAuthAccount(
            accountId: acpTestAccountId,
            connectionRevision: 1,
            state: AcpAuthState.unchecked(),
          ),
          const AcpAuthAccount(
            accountId: acpTestAccountId,
            connectionRevision: 2,
            state: AcpAuthState.unchecked(),
          ),
        ],
      ),
    );
    await expectLater(
      duplicated,
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.protocol,
        ),
      ),
    );
    expect(repository.state.value.canonical, isNull);
  });

  test(
    'the template catalog is validated before it is handed to the caller',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.auth;
      addTearDown(() async {
        final report = await repository.close();
        expect(report.unresolved, isEmpty);
      });

      final reading = repository.readCatalog();
      fixture.port.answerCatalogRead(
        0,
        AcpAccountCatalog(templates: [acpTemplate(), acpTemplate()]),
      );
      await expectLater(
        reading,
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.protocol,
          ),
        ),
      );

      final usable = repository.readCatalog();
      fixture.port.answerCatalogRead(
        1,
        AcpAccountCatalog(templates: [acpTemplate()]),
      );
      final catalog = await usable;
      expect(
        catalog.template(AcpProvider.antigravity)?.supportedVersion,
        '1.4.1',
      );
      expect(
        catalog.template(AcpProvider.antigravity)?.prefersAutomaticInstall,
        isTrue,
      );
    },
  );

  test('a change that does not name the current watermark fails instead of jumping', () async {
    final fixture = AcpPortFixture();
    final repository = fixture.auth;
    addTearDown(() async {
      final report = await repository.close();
      expect(
        report.unresolved.single.owner,
        'acp-auth:feed',
        reason: 'a rejected delivery keeps its real cleanup responsibility',
      );
    });

    final synchronizing = repository.synchronize();
    final feed = await fixture.port.authFeedOpened(0);
    await feed.publishBaseline(
      acpAuthSnapshot(revision: 1, state: const AcpAuthState.unchecked()),
    );
    await synchronizing;

    // The publisher claims to replace revision 0 while the mirror is at 1.
    feed.sendChanged(
      acpAuthSnapshot(
        revision: 3,
        state: const AcpAuthState.verified(checkedAt: 30, server: null),
      ),
      baseRevision: 0,
    );

    final failed = await repository.state.waitFor(
      (value) => value.projection.sync.phase == ResourceSyncPhase.failed,
    );
    expect(failed.projection.sync.error?.code, StudioFailureCode.protocol);
    expect(failed.projection.sync.retryExhausted, isFalse);
    expect(
      failed.canonical?.revision,
      1,
      reason: 'a gap is not permission to adopt the newer snapshot',
    );
    expect(
      failed.stateOf(
        acpTestAccountId,
        connectionRevision: acpTestConnectionRevision,
      ),
      isA<AcpAuthUnchecked>(),
      reason: 'a login result that arrived over a gap is never published',
    );
  });

  test(
    'one owner revision cannot carry a second value, even after a resubscribe',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.auth;
      addTearDown(() async {
        final report = await repository.close();
        expect(report.unresolved, hasLength(1));
        expect(report.unresolved.single.owner, 'acp-auth:feed');
      });

      final synchronizing = repository.synchronize();
      final first = await fixture.port.authFeedOpened(0);
      await first.publishBaseline(
        acpAuthSnapshot(revision: 2, state: const AcpAuthState.unchecked()),
      );
      await synchronizing;

      // The runtime owner restarts its feed with a new incarnation but keeps
      // the owner epoch and the domain revision it already published.
      fixture.port.authFeedOrigin = const ProductReadOrigin(
        ownerEpoch: 'acp-auth-native',
        incarnation: 2,
      );
      first.sendResyncRequired();
      final second = await fixture.port.authFeedOpened(1);
      await second.listened;
      second.sendBaseline(
        acpAuthSnapshot(
          revision: 2,
          state: const AcpAuthState.verified(checkedAt: 99, server: null),
        ),
      );

      final failed = await repository.state.waitFor(
        (value) => value.projection.sync.phase == ResourceSyncPhase.failed,
      );
      expect(failed.projection.sync.error?.code, StudioFailureCode.protocol);
      expect(failed.canonical?.revision, 2);
      expect(
        failed.stateOf(
          acpTestAccountId,
          connectionRevision: acpTestConnectionRevision,
        ),
        isA<AcpAuthUnchecked>(),
        reason: 'the second value of revision 2 is a protocol violation',
      );
    },
  );

  test(
    'a late or duplicated delivery cannot move the watermark backwards',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.auth;
      addTearDown(() async {
        final report = await repository.close();
        expect(report.unresolved, hasLength(1));
        expect(report.unresolved.single.owner, 'acp-auth:feed');
      });

      final synchronizing = repository.synchronize();
      final feed = await fixture.port.authFeedOpened(0);
      await feed.publishBaseline(
        acpAuthSnapshot(revision: 2, state: const AcpAuthState.unchecked()),
      );
      await synchronizing;

      await feed.publishChanged(
        acpAuthSnapshot(
          revision: 3,
          state: const AcpAuthState.checking(operationId: 'op-current'),
        ),
        baseRevision: 2,
      );
      expect(repository.state.value.canonical?.revision, 3);

      // The publisher repeats a revision the mirror already consumed.
      feed.sendChanged(
        acpAuthSnapshot(
          revision: 3,
          state: const AcpAuthState.verified(checkedAt: 31, server: null),
        ),
        baseRevision: 2,
      );

      final failed = await repository.state.waitFor(
        (value) => value.projection.sync.phase == ResourceSyncPhase.failed,
      );
      expect(failed.projection.sync.error?.code, StudioFailureCode.protocol);
      expect(failed.canonical?.revision, 3);
      expect(
        failed
            .stateOf(
              acpTestAccountId,
              connectionRevision: acpTestConnectionRevision,
            )
            .operationId,
        'op-current',
        reason: 'the already consumed observation is retained',
      );
    },
  );

  test('retrySync replaces the subscription without replaying accepted commands', () async {
    final fixture = AcpPortFixture();
    final repository = fixture.auth;
    addTearDown(() async {
      final report = await repository.close();
      expect(report.unresolved, isEmpty);
      expect(fixture.budget.usage, isEmpty);
    });
    final first = await establishAcpAuth(fixture, revision: 2);

    // The native owner replaced the source: same owner epoch, new incarnation.
    fixture.port.authFeedOrigin = const ProductReadOrigin(
      ownerEpoch: 'acp-auth-native',
      incarnation: 2,
    );
    final resyncing = repository.retrySync();
    final second = await fixture.port.authFeedOpened(1);
    await second.publishBaseline(
      acpAuthSnapshot(revision: 2, state: const AcpAuthState.unchecked()),
    );
    await resyncing;

    expect(
      repository.state.value.projection.sync.phase,
      ResourceSyncPhase.ready,
    );
    expect(repository.state.value.projection.stamp?.incarnation, 2);
    expect(
      first.feed.requestCloseCalls,
      greaterThan(0),
      reason: 'the replaced subscription is closed, not left running',
    );
    expect(
      fixture.port.authStarts,
      isEmpty,
      reason: 'a resubscribe never replays an accepted command',
    );
    expect(fixture.port.authFeeds, hasLength(2));
  });

  test(
    'a replaced owner feed recovers instead of failing the domain',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.auth;
      addTearDown(() async {
        final report = await repository.close();
        expect(report.unresolved, isEmpty);
        expect(fixture.budget.usage, isEmpty);
      });
      final first = await establishAcpAuth(fixture, revision: 1);

      fixture.port.authFeedOrigin = const ProductReadOrigin(
        ownerEpoch: 'acp-auth-native',
        incarnation: 3,
      );
      first.sendOwnerReplaced();
      final second = await fixture.port.authFeedOpened(1);
      await second.publishBaseline(
        acpAuthSnapshot(
          revision: 3,
          state: const AcpAuthState.verified(checkedAt: 33, server: null),
        ),
      );

      final ready = await repository.state.waitFor(
        (value) =>
            value.projection.sync.phase == ResourceSyncPhase.ready &&
            value.projection.stamp?.incarnation == 3,
      );
      expect(
        ready.projection.sync.error,
        isNull,
        reason: 'an owner replacement is a reconnect, not a failure',
      );
      expect(ready.canonical?.revision, 3);
      expect(
        ready.stateOf(
          acpTestAccountId,
          connectionRevision: acpTestConnectionRevision,
        ),
        isA<AcpAuthVerified>(),
      );
    },
  );
}

AcpAccountTemplate acpTemplate() => const AcpAccountTemplate(
  provider: AcpProvider.antigravity,
  displayName: 'Antigravity',
  description: 'Managed official server',
  iconKey: '',
  supportedVersion: '1.4.1',
  installUrl: 'https://antigravity.invalid/install',
  termsUrl: '',
  automaticInstall: AcpInstallAvailability.available(target: 'linux-x86_64'),
);
