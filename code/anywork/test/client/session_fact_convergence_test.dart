import 'package:anywork/src/features/conversation/presentation/model_route_presentation.dart';
import 'package:anywork/src/features/conversation/view_models/conversation_view_model.dart';
import 'package:anywork/src/features/conversation/view_models/thread_status_view_model.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/selector_command_reply.dart';
import 'support/selector_conversation_port.dart';
import 'support/selector_environment.dart';

/// Real Repository -> generated VM adapters. Native replies and canonical
/// publications are independently gated so command-time refresh or optimistic
/// state cannot hide a missing typed directory/configuration publication.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const threadId = 'thread-main';
  late SelectorEnvironment env;
  late ProviderSubscription<Object?> conversationHold, statusHold;
  late void Function() endRouteDemand;

  ConversationModelRouteProps props() => env.container.read(threadStatusViewModelProvider(threadId).notifier)
    .modelRouteProps(env.container.read(conversationViewModelProvider(threadId)).requireValue.metadata);
  ThreadModelRoute route() => props().route!;
  ConversationSession session() => env.conversations.active.value!;

  setUp(() async {
    env = SelectorEnvironment();
    await env.establish();
    await env.selectThread(threadId);
    conversationHold = env.container.listen(conversationViewModelProvider(threadId), (_, _) {});
    statusHold = env.container.listen(threadStatusViewModelProvider(threadId), (_, _) {});
    await env.container.read(conversationViewModelProvider(threadId).future);
    await env.container.read(threadStatusViewModelProvider(threadId).future);
    endRouteDemand = env.container.read(threadStatusViewModelProvider(threadId).notifier).beginModelRouteDemand();
    await env.container.read(threadStatusViewModelProvider(threadId).notifier).loadModelRoute();
  });
  tearDown(() async {
    endRouteDemand();
    conversationHold.close(); statusHold.close();
    await env.close();
  });

  test('任务模式由目录增量交付，运行时 route 由 Configuration facet 交付', () async {
    final before = env.container.read(conversationViewModelProvider(threadId)).requireValue.thread!;
    expect(before.mode, ThreadModeId.simple);
    final routeRevisionBefore = route().revision;
    final metadata = env.workspace.thread(threadId);
    addTearDown(metadata.close);
    await waitLatest(metadata.state, (value) => value.value is ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>);
    final directoryRevisionBefore = metadata.state.value.projection.stamp!.revision;
    final ticket = session().setThreadMode(origin: session().configuration.value.stamp!, mode: ThreadModeId.task.id);
    final call = await env.commands.modes.at(0);
    expect(call.mode, ThreadModeId.task.id);
    expect(route().revision, routeRevisionBefore);
    expect(env.container.read(conversationViewModelProvider(threadId)).requireValue.thread!.mode, ThreadModeId.simple,
      reason: '命令发出不能提前改写目录 mode');
    call.reply.complete(CommitReceipt(operationId: call.operationId, disposition: CommitDisposition.applied,
      targets: [const ResourceStamp(resourceKey: 'thread-mode:thread-main', ownerEpoch: 'selector-native', revision: 2),
        const ResourceStamp(resourceKey: 'thread-directory', ownerEpoch: 'selector-native', revision: 8)],
      effect: EffectPoint.nextTurn, requiresIdentityObservation: true));
    final next = route().copyWith(revision: routeRevisionBefore + 1);
    await env.conversationPort.publishRoute(next, modeBindingRevision: 2);
    await env.directory.publishThread(before.copyWith(mode: ThreadModeId.task));
    await waitLatest(metadata.state, (value) => value.value is ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef> &&
      (value.value as ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>).current.value.mode == ThreadModeId.task);
    expect(await ticket.result, isA<CommittedCommandResult<CommitReceipt>>());
    await env.container.read(threadStatusViewModelProvider(threadId).notifier).loadModelRoute();
    expect(metadata.state.value.projection.stamp!.revision, greaterThan(directoryRevisionBefore),
      reason: 'mode 是 typed directory 事实，必须推进自己的水位');
    expect(route().revision, routeRevisionBefore + 1,
      reason: '路由来自 Configuration facet，不能依赖命令后聚合重新读取');
    expect(env.container.read(conversationViewModelProvider(threadId)).requireValue.thread!.mode, ThreadModeId.task);
    expect(env.conversationPort.reads.last.origin, session().configuration.value.stamp);
  });

  test('思考强度经 Configuration facet 与原版本 typed read 收敛，响应不能充当 canonical', () async {
    final canonical = route();
    expect(canonical, isNotNull);
    final catalog = env.models.state.value.accounts as CurrentCollectionMirror<AccountCatalogEntry>;
    final model = catalog.window.rows.values.whereType<ReadyReadValue<AccountCatalogEntry, ProductEntityRef>>()
      .firstWhere((row) => row.current.value.accountId == canonical.accountId).current.value.effectiveModels
      .firstWhere((model) => model.modelId == canonical.modelId);
    expect(model, isNotNull);
    final target = model.reasoning!.candidates.where((effort) => effort != canonical.effort).firstOrNull;
    expect(target, isNotNull);
    final expected = canonical.copyWith(effort: target, revision: canonical.revision + 1);
    final writer = env.container.read(threadStatusViewModelProvider(threadId).notifier)
      .captureModelRouteWriter(env.container.read(conversationViewModelProvider(threadId)).requireValue.metadata)!;
    final ticket = writer(ModelSelection(model: AccountModelKey(accountId: canonical.accountId, modelId: canonical.modelId), effort: target));
    final call = await env.commands.routes.at(0);
    expect((call.routeRevision, call.settingsRevision), (canonical.revision, 1));
    call.reply.complete(selectorRouteReply(call, expected, saved: true, settingsRevision: 2));
    await waitLatest(ticket.state, (value) => value.receipt != null);
    expect(route(), canonical, reason: '响应没有原 facet/read 身份，不能被乐观提升为 canonical');
    expect(ticket.state.value.isPending, isTrue);
    env.configurationPort.routes[2] = ModelSelection(model: call.selection.model, effort: target);
    await env.configurationPort.base.publishSettings(2);
    await env.conversationPort.publishRoute(expected);
    expect(await ticket.result, isA<CommittedCommandResult<ThreadModelRouteCommandReply>>());
    await env.container.read(threadStatusViewModelProvider(threadId).notifier).loadModelRoute();
    await env.configuration.loadModeRoutes();
    expect(session().configuration.value.value?.modelRoute?.revision, canonical.revision + 1);
    expect(route().effort, target, reason: 'selector 必须消费真实 typed 原版本详情');
    expect(route().revision, canonical.revision + 1);
    expect(ticket.state.value.isPending, isFalse);
    expect(route().effort, expected.effort, reason: 'pending 清除后 canonical 不得回落');
    final settings = env.configuration.state.value.modeRoutes as ReadyReadValue<List<ModeModelRoute>, ConfigurationReadRef>;
    expect(settings.current.value.single.effort, target, reason: '配置是独立 owner，由自身 feed/read 收敛');
    expect(env.conversationPort.reads.last.origin.runtimeEpoch, 'selector-native');
    expect(env.conversationPort.reads.last.origin.incarnation, 1);
    expect(env.conversationPort.reads.last.origin.revision, session().configuration.value.stamp!.revision);
  });

  test('facet 水位门：重复/更低/缺口/跨原身份不覆盖 canonical，连续事实才应用', () async {
    // The deleted helper silently dropped malformed notifications. The typed
    // protocol is stricter: fail the original feed, preserve its last-known
    // fact and require an explicit fresh baseline. Exercise the real Session.
    for (final scenario in ['duplicate', 'lower', 'next', 'gap', 'base', 'epoch', 'incarnation']) {
      final opening = env.conversationPort.facets.execution.last;
      await opening.feed.acknowledged(1);
      opening.feed.emit(ThreadExecutionFrame.data(deliverySequence: 2,
        event: ThreadExecutionEvent.change(stamp: selectorFacet(ThreadFacet.execution, 4), baseRevision: 1,
          value: const ThreadExecutionChange(status: ThreadStatus.idle, turns: null, interactions: null,
            activity: ActivityReplacement.unchanged(), storage: StorageReplacement.unchanged()))));
      await opening.feed.acknowledged(2);
      final watermark = session().execution.value;
      expect(watermark.stamp!.revision, 4);
      final stamp = selectorFacet(ThreadFacet.execution, switch (scenario) {'duplicate' => 4, 'lower' => 3, _ => 5},
        runtime: scenario == 'epoch' ? 'replacement-native' : 'selector-native', incarnation: scenario == 'incarnation' ? 2 : 1);
      opening.feed.emit(ThreadExecutionFrame.data(deliverySequence: scenario == 'gap' ? 4 : 3,
        event: ThreadExecutionEvent.change(stamp: stamp, baseRevision: scenario == 'base' ? 3 : 4,
          value: const ThreadExecutionChange(status: ThreadStatus.running, turns: null, interactions: null,
            activity: ActivityReplacement.unchanged(), storage: StorageReplacement.unchanged()))));
      if (scenario == 'next') {
        await opening.feed.acknowledged(3);
        expect(session().execution.value.stamp, selectorFacet(ThreadFacet.execution, 5));
        expect(session().execution.value.value!.status, ThreadStatus.running);
      } else {
        final failed = await waitLatest(session().execution, (value) => value.sync.phase == FacetSyncPhase.failed);
        expect(failed.sync.error!.code, StudioFailureCode.protocol, reason: scenario);
        expect(failed.stamp, watermark.stamp, reason: '$scenario 不得覆盖新事实');
        expect(failed.value, watermark.value, reason: '$scenario 不得就地拼接');
        expect(opening.feed.acknowledgements, [1, 2], reason: '坏帧不得伪造数据 ACK');
      }
      await session().retry(ThreadFacet.execution);
      await waitLatest(session().execution, (value) => value.sync.phase == FacetSyncPhase.ready && value.stamp!.revision == 1);
    }
  });
}
