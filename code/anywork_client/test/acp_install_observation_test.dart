import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/acp_port_fixture.dart';

/// `acpInstall` 是共享资产的独立版本域：首帧基线（含 revision 0）是唯一加载入口，
/// 之后按自己的 revision 单调收敛。总量缺失时保留 null，不合成百分比；就绪不是
/// 下载完成，也不是账号已保存或已认证。
void main() {
  test('the install baseline arrives before any progress fact', () async {
    final fixture = AcpPortFixture();
    final repository = fixture.install;
    addTearDown(() async {
      final report = await repository.close();
      expect(report.unresolved, isEmpty);
      expect(fixture.budget.usage, isEmpty);
    });

    var ready = false;
    final synchronizing = repository.synchronize().then((_) => ready = true);
    final feed = await fixture.port.installFeedOpened(0);
    expect(ready, isFalse);
    expect(
      repository.state.value.canonical,
      isNull,
      reason: 'an unloaded install domain publishes no empty snapshot',
    );
    expect(
      repository.state.value.stateOf(AcpProvider.antigravity),
      isA<AcpInstallIdleState>(),
    );

    await feed.listened;
    await feed.acknowledged(feed.sendBaseline(AcpInstallSnapshot.empty));
    await synchronizing;

    expect(ready, isTrue);
    expect(repository.state.value.projection.header?.revision, 0);
    expect(repository.state.value.canonical, AcpInstallSnapshot.empty);
    expect(
      repository.state.value.stateOf(AcpProvider.antigravity).isReady,
      isFalse,
      reason: 'no entry is not an installed server',
    );
    expect(repository.state.value.readyServer(AcpProvider.antigravity), isNull);
  });

  test(
    'missing download totals stay null instead of a synthesized percentage',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.install;
      addTearDown(() async {
        final report = await repository.close();
        expect(report.unresolved, isEmpty);
        expect(fixture.budget.usage, isEmpty);
      });
      final feed = await establishAcpInstall(fixture);

      await feed.publishChanged(
        acpInstallSnapshot(
          revision: 2,
          state: AcpInstallState.downloading(
            operationId: 'op-install',
            release: acpRelease(),
            progress: const AcpInstallProgress(
              completedBytes: 512,
              totalBytes: null,
              bytesPerSecond: null,
            ),
            retryCount: 2,
          ),
        ),
        baseRevision: 1,
      );

      final state = repository.state.value.stateOf(AcpProvider.antigravity);
      expect(state, isA<AcpInstallDownloading>());
      expect(state.isBusy, isTrue);
      expect(state.isReady, isFalse);
      expect(state.progress?.completedBytes, 512);
      expect(
        state.progress?.totalBytes,
        isNull,
        reason: 'an unknown transfer length is not invented',
      );
      expect(
        state.progress?.fraction,
        isNull,
        reason: 'indeterminate progress is presented as indeterminate',
      );
      expect(state.progress?.effectiveBytesPerSecond, isNull);
      expect(state.retryCount, 2);
      expect(state.release?.version, '1.4.1');
      expect(
        state.release?.hasPublisherChecksum,
        isFalse,
        reason: 'the 1.4.1 manifest carries no publisher checksum',
      );

      // A later stage reports real bytes for a known total.
      await feed.publishChanged(
        acpInstallSnapshot(
          revision: 3,
          state: AcpInstallState.verifying(
            operationId: 'op-install',
            release: acpRelease(),
            progress: const AcpInstallProgress(
              completedBytes: 50,
              totalBytes: 100,
              bytesPerSecond: 0,
            ),
          ),
        ),
        baseRevision: 2,
      );
      final verifying = repository.state.value.stateOf(AcpProvider.antigravity);
      expect(verifying, isA<AcpInstallVerifying>());
      expect(verifying.progress?.fraction, 0.5);
      expect(
        verifying.progress?.effectiveBytesPerSecond,
        isNull,
        reason: 'a zero sample is not a transfer rate',
      );
      expect(verifying.retryCount, 0);
    },
  );

  test('a ready row reports the installation identity, not a login', () async {
    final fixture = AcpPortFixture();
    final repository = fixture.install;
    addTearDown(() async {
      final report = await repository.close();
      expect(report.unresolved, isEmpty);
      expect(fixture.budget.usage, isEmpty);
    });
    final feed = await establishAcpInstall(fixture);

    await feed.publishChanged(
      acpInstallSnapshot(
        revision: 2,
        state: AcpInstallState.ready(
          operationId: 'op-install',
          server: AcpInstalledServer(
            installationId: 'install-1',
            release: acpRelease(),
            program: '/managed/agy_acp_server.par',
            readyAt: 100,
            reused: true,
          ),
        ),
      ),
      baseRevision: 1,
    );

    final state = repository.state.value.stateOf(AcpProvider.antigravity);
    expect(state, isA<AcpInstallReady>());
    expect(state.isReady, isTrue);
    expect(state.isSettled, isTrue);
    expect(state.server?.installationId, 'install-1');
    expect(state.server?.reused, isTrue);
    expect(state.server?.readyAt, 100);
    expect(
      repository.state.value.readyServer(AcpProvider.antigravity)?.program,
      '/managed/agy_acp_server.par',
    );

    // Closing is a non-terminal safety state, never a finished preparation.
    await feed.publishChanged(
      acpInstallSnapshot(
        revision: 3,
        state: const AcpInstallState.closing(
          operationId: 'op-install',
          failure: AcpInstallFailure(
            code: AcpInstallFailureCode.resourceClose,
            stage: AcpInstallStage.close,
            message: 'The prepared files are not joined yet.',
            retryable: true,
          ),
        ),
      ),
      baseRevision: 2,
    );
    final closing = repository.state.value.stateOf(AcpProvider.antigravity);
    expect(closing, isA<AcpInstallClosing>());
    expect(closing.isBusy, isTrue);
    expect(closing.isSettled, isFalse);
    expect(closing.isReady, isFalse);
    expect(closing.failure?.code, AcpInstallFailureCode.resourceClose);
  });

  test('the install projection keeps its own watermark and never fails the auth one', () async {
    final fixture = AcpPortFixture();
    addTearDown(() async {
      final auth = await fixture.auth.close();
      expect(auth.unresolved, isEmpty);
      final install = await fixture.install.close();
      expect(install.unresolved, hasLength(1));
      expect(install.unresolved.single.owner, 'acp-install:feed');
    });

    // Two domains, two watermarks: authentication at 5 while installation is 1.
    final authFeed = await establishAcpAuth(fixture, revision: 5);
    final installFeed = await establishAcpInstall(fixture);
    expect(fixture.auth.state.value.canonical?.revision, 5);
    expect(fixture.install.state.value.canonical?.revision, 1);

    installFeed.sendChanged(
      acpInstallSnapshot(
        revision: 4,
        state: const AcpInstallState.resolving(operationId: 'op-install'),
      ),
      baseRevision: 0,
    );
    final failed = await fixture.install.state.waitFor(
      (value) => value.projection.sync.phase == ResourceSyncPhase.failed,
    );
    expect(failed.projection.sync.error?.code, StudioFailureCode.protocol);
    expect(failed.canonical?.revision, 1);
    expect(
      failed.stateOf(AcpProvider.antigravity),
      isA<AcpInstallIdleState>(),
      reason: 'the rejected preparation never becomes canonical',
    );

    expect(
      fixture.auth.state.value.projection.sync.phase,
      ResourceSyncPhase.ready,
      reason: 'the authentication projection is independent of this failure',
    );
    expect(fixture.auth.state.value.canonical?.revision, 5);
    expect(authFeed.feed.closeCalls, 0);

    // The authentication topic still accepts its own next fact.
    await authFeed.publishChanged(
      acpAuthSnapshot(
        revision: 6,
        state: const AcpAuthState.verified(checkedAt: 60, server: null),
      ),
      baseRevision: 5,
    );
    expect(fixture.auth.state.value.canonical?.revision, 6);
  });
}
