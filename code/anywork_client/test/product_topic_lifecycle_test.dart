import 'dart:async';

import 'package:anywork_client/bots_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/bots_fixture.dart';

/// 产品主题（`ProductTopic`）的多路复用通道已由分层重构移除：每个领域
/// Repository 现在自己拥有唯一 feed，`ResourceLifetime`/`ProductFeedOwner`
/// 提供取消 ACK 门、预算保留与 cleanup join。本文件锁定同一批不变量，
/// 只是宿主从共享 topic registry 换成真实领域 owner。
const _retryIssue = FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'native-read',
    code: 'readJoinPending',
    message: 'The original native join needs an explicit retry.',
    retryable: true,
    correlationId: 'topic-native-read',
  ),
  recovery: CleanupRecovery.retryClose,
);

void main() {
  test('scoped demand installs the canonical source before the first native callback', () async {
    final environment = BotsEnvironment(clientId: 'scoped');
    addTearDown(environment.close);
    // Unknown is not an invented empty business value.
    expect(environment.repository.state.value.snapshot, isNull);
    expect(environment.repository.state.value.projection.stamp, isNull);
    expect(environment.feedCount, 0);

    final ready = environment.repository.synchronize();
    final feed = await environment.feedAt(0);
    await feed.listened.future;
    // The owned source exists before any native delivery arrives.
    expect(
      environment.repository.state.value.projection.sync.phase,
      ResourceSyncPhase.connecting,
    );
    expect(environment.repository.state.value.snapshot, isNull);
    expect(environment.used(ResourceKind.observer), 1);
    expect(environment.used(ResourceKind.readModel), 1);

    environment.publishBaseline(revision: 1, bots: [botsFixtureBot()]);
    await feed.acknowledged(1);
    await ready;
    expect(environment.bot('bot-1').id, 'bot-1');
    // A second demand joins the same subscription instead of opening another.
    await environment.repository.synchronize();
    expect(environment.feedCount, 1);

    final report = await environment.close();
    expect(report.complete, isTrue);
    expect(environment.budget.usage, isEmpty);
  });

  test(
    'replacement subscription opens only after the original real cancel ACK',
    () async {
      final environment = BotsEnvironment(clientId: 'restart');
      addTearDown(environment.close);
      await environment.establish(revision: 1, bots: [botsFixtureBot()]);
      final original = environment.feed!;
      original.closeReceipt = Completer<FeedCloseReport>();

      final restarting = environment.repository.retrySync();
      await original.cancellationStarted.future;
      // The original native owner is still joining: no parallel subscription.
      expect(environment.feedCount, 1);
      // Exactly one original native close is in flight; the restart intent and
      // the owner cleanup request the same close idempotently.
      expect(original.requestCloseCalls, greaterThanOrEqualTo(1));
      expect(original.closeReceipt!.isCompleted, isFalse);
      expect(
        environment.repository.state.value.projection.sync.phase,
        ResourceSyncPhase.reconnecting,
      );
      // Last-known canonical material is retained during the join.
      expect(environment.repository.state.value.snapshot!.value.revision, 1);

      original.closeReceipt!.complete(
        FeedCloseReport(
          feedId: original.feedId,
          outcome: const FeedCloseOutcome.clean(),
        ),
      );
      final replacement = await environment.feedAt(1);
      await replacement.listened.future;
      expect(environment.feedCount, 2);
      // A replacement subscription starts from its own baseline delivery.
      environment.publishBaseline(
        revision: 2,
        bots: [botsFixtureBot(configRevision: 2)],
      );
      await replacement.acknowledged(1);
      // The restart resolves only after its replacement source is really ready.
      await restarting;
      expect(environment.repository.state.value.snapshot!.value.revision, 2);
      // Exactly one replacement native feed handle is owned; the retired one
      // has already been joined and released.
      expect(environment.used(ResourceKind.readModel), 1);
    },
  );

  test(
    'cancel failure retains the same owner and blocks a second subscription',
    () async {
      final environment = BotsEnvironment(clientId: 'cancel-failure');
      addTearDown(environment.close);
      await environment.establish(revision: 1, bots: [botsFixtureBot()]);
      final original = environment.feed!;
      original.closeReceipt = Completer<FeedCloseReport>();

      final restarting = environment.repository.retrySync();
      await original.cancellationStarted.future;
      original.closeReceipt!.complete(
        FeedCloseReport(
          feedId: original.feedId,
          outcome: FeedCloseOutcome.unresolved(issues: [_retryIssue]),
        ),
      );
      await expectLater(
        restarting,
        throwsA(
          isA<StudioFailure>().having(
            (StudioFailure failure) => failure.code,
            'code',
            StudioFailureCode.busy,
          ),
        ),
      );
      // The unresolved native owner keeps its real permit and blocks a
      // replacement subscription.
      expect(environment.feedCount, 1);
      expect(environment.used(ResourceKind.readModel), 1);
      expect(
        environment.repository.state.value.projection.sync.phase,
        ResourceSyncPhase.failed,
      );

      original.closeReceipt = null;
      original.outcome = const FeedCloseOutcome.clean();
      final retried = environment.repository.retrySync();
      final replacement = await environment.feedAt(1);
      await replacement.listened.future;
      expect(environment.feedCount, 2);
      environment.publishBaseline(
        revision: 3,
        bots: [botsFixtureBot(configRevision: 3)],
      );
      await replacement.acknowledged(1);
      await retried;
      expect(environment.repository.state.value.snapshot!.value.revision, 3);
      expect(environment.used(ResourceKind.readModel), 1);
    },
  );

  test(
    'budget exhaustion preserves the already active canonical source',
    () async {
      final capacity = ResourceBudget(
        capacities: {ResourceKind.observer: 1, ResourceKind.readModel: 1},
      );
      final established = BotsEnvironment(
        clientId: 'budget-taken',
        budget: capacity,
      );
      addTearDown(established.close);
      // The first owner of this shared budget took the only feed permits.
      final ready = established.repository.synchronize();
      final feed = await established.feedAt(0);
      await feed.listened.future;
      established.publishBaseline(revision: 1, bots: [botsFixtureBot()]);
      await feed.acknowledged(1);
      await ready;

      // A second resident source cannot subscribe from the exhausted budget.
      final refused = BotsEnvironment(
        clientId: 'budget-refused',
        budget: capacity,
      );
      addTearDown(refused.close);
      expect(
        () => refused.repository.synchronize(),
        throwsA(isA<StudioFailure>()),
      );
      expect(refused.feedCount, 0);
      // The active canonical source keeps reducing after the refused demand.
      established.publishChange(
        baseRevision: 1,
        revision: 4,
        bots: [botsFixtureBot(configRevision: 4)],
      );
      await feed.acknowledged(2);
      expect(established.repository.state.value.snapshot!.value.revision, 4);
      final report = await established.close();
      expect(report.complete, isTrue);
      expect(capacity.usage, isEmpty);
    },
  );

  test(
    'close reports unresolved native cleanup and retry retains its permit',
    () async {
      final environment = BotsEnvironment(clientId: 'close-unresolved');
      addTearDown(environment.close);
      await environment.establish(revision: 1, bots: [botsFixtureBot()]);
      final feed = environment.feed!;
      feed.outcome = FeedCloseOutcome.unresolved(issues: [_retryIssue]);

      final report = await environment.close();
      expect(report.complete, isFalse);
      expect(report.unresolved.single.owner, 'bots:feed');
      // A pending native cleanup keeps its real permit; nothing is dropped.
      expect(environment.used(ResourceKind.readModel), 1);

      feed.outcome = const FeedCloseOutcome.clean();
      final retried = await environment.repository.retryCleanup();
      expect(retried.complete, isTrue);
      expect(environment.budget.usage, isEmpty);
    },
  );

  test(
    'restarting one source joins only itself while another keeps reducing',
    () async {
      final restarting = BotsEnvironment(clientId: 'join-a');
      final steady = BotsEnvironment(clientId: 'join-b');
      addTearDown(steady.close);
      addTearDown(restarting.close);
      await restarting.establish(revision: 1, bots: [botsFixtureBot()]);
      await steady.establish(revision: 1, bots: [botsFixtureBot()]);
      final held = restarting.feed!;
      held.closeReceipt = Completer<FeedCloseReport>();

      final pending = restarting.repository.retrySync();
      await held.cancellationStarted.future;
      steady.publishChange(
        baseRevision: 1,
        revision: 4,
        bots: [botsFixtureBot(configRevision: 4)],
      );
      await steady.feed!.acknowledged(1);
      expect(steady.repository.state.value.snapshot!.value.revision, 4);
      // The join is scoped to one source: the steady owner is untouched.
      expect(steady.feed!.requestCloseCalls, 0);
      expect(steady.feedCount, 1);
      expect(restarting.feedCount, 1);

      held.closeReceipt!.complete(
        FeedCloseReport(
          feedId: held.feedId,
          outcome: const FeedCloseOutcome.clean(),
        ),
      );
      final replacement = await restarting.feedAt(1);
      await replacement.listened.future;
      restarting.publishBaseline(
        revision: 2,
        bots: [botsFixtureBot(configRevision: 2)],
      );
      await replacement.acknowledged(1);
      await pending;
      expect(restarting.repository.state.value.snapshot!.value.revision, 2);
      expect(steady.repository.state.value.snapshot!.value.revision, 4);
      expect(steady.feed!.requestCloseCalls, 0);
    },
  );

  test('repeated exit shares the first deadline and keeps pending cancel owned', () async {
    final environment = BotsEnvironment(clientId: 'repeated-exit');
    addTearDown(environment.close);
    await environment.establish(revision: 1, bots: [botsFixtureBot()]);
    final feed = environment.feed!;
    feed.closeReceipt = Completer<FeedCloseReport>();

    final closing = environment.close(deadline: DateTime.utc(2000));
    final report = await closing;
    expect(report.complete, isFalse);
    // A second exit cannot restart cleanup or extend the original deadline.
    final second = await environment.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 100)),
    );
    expect(second.complete, isFalse);
    expect(feed.closeCalls + feed.retryCloseCalls, 1);
    await feed.cancellationStarted.future;
    // A sealed source neither publishes nor releases its pending native cancel.
    expect(environment.repository.state.value.snapshot!.value.revision, 1);
    expect(environment.used(ResourceKind.readModel), 1);

    feed.closeReceipt!.complete(
      FeedCloseReport(
        feedId: feed.feedId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    feed.outcome = const FeedCloseOutcome.clean();
    final retried = await environment.repository.retryCleanup();
    expect(retried.complete, isTrue);
    expect(environment.budget.usage, isEmpty);
  });

  test(
    'the assembly owns the resident bots source across unrelated scope demand',
    () async {
      final environment = BotsEnvironment(clientId: 'resident');
      addTearDown(environment.close);
      await environment.establish(revision: 2, bots: [botsFixtureBot()]);
      final feed = environment.feed!;
      // The Client-side assembly — not a visible page scope — owns the source.
      expect(environment.feedCount, 1);
      expect(feed.requestCloseCalls, 0);

      // A settings round trip adds and removes only its own scope demand.
      final scope = environment.repository.conversations('bot-1');
      final opening = await environment.port.conversationOpened(0);
      final connection = ScriptedConversationConnection(
        'bot-1',
        declaredBotId: 'bot-1',
      );
      connection.onPage = (request) async => BotConversationPage(
        botId: 'bot-1',
        conversations: const [],
        nextCursor: null,
      );
      opening.reply.complete(connection);
      await scope.page();
      final scopeReport = await scope.close();
      expect(scopeReport.complete, isTrue);
      expect(environment.feedCount, 1);
      expect(feed.requestCloseCalls, 0);

      // Typed increments keep flowing into the canonical owner.
      environment.publishChange(baseRevision: 2, revision: 3, bots: const []);
      await feed.acknowledged(1);
      expect(environment.repository.state.value.snapshot!.value.revision, 3);
      expect(environment.repository.state.value.snapshot!.value.bots, isEmpty);

      // Real close cancels the resident source exactly once.
      final report = await environment.close();
      expect(report.complete, isTrue);
      // requestClose is idempotent; the native join happens exactly once.
      expect(feed.requestCloseCalls, greaterThanOrEqualTo(1));
      expect(feed.closeCalls + feed.retryCloseCalls, 1);
      expect(environment.budget.usage, isEmpty);
    },
  );
}
