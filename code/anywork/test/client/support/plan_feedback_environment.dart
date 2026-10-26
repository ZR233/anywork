import 'dart:async';

import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/features/conversation/state/editor_keys.dart';
import 'package:anywork/src/infrastructure/frb/demo/demo_timeline_content.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../anywork_client/test/support/conversation_fixture.dart';
import '../../../../anywork_client/test/support/profile_native_pin.dart';
import 'conversation_workspace_fixture.dart';

const planTestMarkdown =
    '# Delivery Blueprint\n\n## Steps\n\n1. Keep it readable.';
const planTestRuntime = 'plan-feedback-native';

InteractionEditorKey planTestKey(String threadId, {String suffix = ''}) =>
    InteractionEditorKey(
      threadId: threadId,
      runtimeEpoch: planTestRuntime,
      sourceGeneration: 1,
      incarnation: 1,
      interactionId: 'interaction-plan$suffix',
      revision: 1,
    );

/// All state, operation evidence and editing belong to the production owners.
/// This fixture supplies only native facets, pinned materials and dispatch gates.
final class PlanFeedbackEnvironment {
  PlanFeedbackEnvironment(String threadId) {
    native = PlanFeedbackPort(threadId);
    commands = PlanFeedbackCommands(native);
    operations = OperationRegistry(clientId: 'plan-feedback', budget: budget);
    final assembly = createConversationRepository(
      port: native,
      context: FixtureConversationContext(),
      commands: commands,
      timeline: DemoTimelineContent(seedDemoConversations: false),
      budget: budget,
      operations: operations,
      agentDirectory: () => workspaceOwner.workspace.agents,
    );
    conversations = assembly.repository;
    demand = assembly.demand;
    workspaceOwner = ConversationWorkspaceFixture(
      budget: budget,
      operations: operations,
      archive: assembly.archive,
    );
    container = ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(conversations),
      ],
    );
  }
  final budget = ResourceBudget();
  late final ConversationWorkspaceFixture workspaceOwner;
  late final PlanFeedbackPort native;
  late final PlanFeedbackCommands commands;
  late final OperationRegistry operations;
  late final ConversationRepository conversations;
  late final ConversationDemand demand;
  late final ProviderContainer container;
  Future<void> establish() async {
    demand.select(
      threadId: native.threadId,
      needsOpen: false,
      selectionGeneration: 1,
    );
    final opening = await native.base.executionOpened(0);
    await opening.feed.listened.future;
    opening.feed.emit(
      ThreadExecutionFrame.data(
        deliverySequence: 1,
        event: ThreadExecutionEvent.baseline(
          identity: ThreadFeedIdentity(
            feedId: opening.feed.feedId,
            runtimeEpoch: planTestRuntime,
            incarnation: 1,
            facet: ThreadFacet.execution,
            mode: opening.mode,
          ),
          stamp: native.origin,
          value: ThreadExecutionBaseline(
            status: ThreadStatus.waitingInteraction,
            execution: null,
            continuation: null,
            activeTurn: null,
            recentTerminalTurn: null,
            interactions: native.index,
            activity: null,
            storage: null,
          ),
        ),
      ),
    );
    await opening.feed.acknowledged(1);
  }

  Future<void> publish(InteractionEditorKey key) async {
    final old = native.entry;
    native.add(key);
    final prior = native.sequence++;
    final opening = native.base.execution.single;
    opening.feed.emit(
      ThreadExecutionFrame.data(
        deliverySequence: native.sequence,
        event: ThreadExecutionEvent.change(
          stamp: native.origin,
          baseRevision: prior,
          value: ThreadExecutionChange(
            status: null,
            turns: null,
            interactions: InteractionDelta(
              baseIndexRevision: prior,
              index: native.index,
              upserted: [native.brief],
              removedEntries: [old],
              terminalFacts: const [],
            ),
            activity: const ActivityReplacement.unchanged(),
            storage: const StorageReplacement.unchanged(),
          ),
        ),
      ),
    );
    await opening.feed.acknowledged(native.sequence);
  }

  Future<void> close() async {
    await workspaceOwner.close();
    if (!native.terminalProof.isCompleted) native.terminalProof.complete();
    container.dispose();
    // 该 close() 在 pumpClientFuture 的受保护异步区间内运行，
    // 受 TestAsyncUtils 保护的 expect 会触发 Guarded function conflict；
    // 这里改用同步断言，语义不变。
    // 直接断言未解决清单：失败时能读出具体 owner，而不是只有一个 false。
    expectSync(
      (await conversations.close(
            deadline: DateTime.now().add(const Duration(seconds: 3)),
          )).unresolved
          .map(
            (item) => (
              item.owner,
              item.issues
                  .map(
                    (issue) => (
                      issue.diagnostic.stage,
                      issue.diagnostic.code,
                      issue.diagnostic.message,
                      issue.diagnostic.correlationId,
                      issue.recovery,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
      isEmpty,
    );
    operations.seal();
    expectSync(budget.usage, isEmpty);
  }
}

final class PlanFeedbackPort implements ConversationObservationPort {
  PlanFeedbackPort(this.threadId) {
    add(planTestKey(threadId));
  }
  final String threadId;
  final base = FixtureConversationPort();
  final terminalProof = Completer<void>();
  final keys = <int, InteractionEditorKey>{};
  final resolutions = <String, UserInputResolutionCommand>{};
  int entry = 0;
  int sequence = 1;
  void add(InteractionEditorKey key) {
    keys[++entry] = key;
  }

  InteractionIndexHeader get index => InteractionIndexHeader(
    reference: InteractionIndexRef(entry: 10, revision: sequence),
    total: 1,
    pending: 1,
  );
  ThreadFacetStamp get origin => ThreadFacetStamp(
    runtimeEpoch: planTestRuntime,
    incarnation: 1,
    facet: ThreadFacet.execution,
    revision: sequence,
  );
  InteractionBrief get brief => InteractionBrief(
    reference: InteractionReadRef(entry: entry, revision: 1),
    revision: 1,
    kind: InteractionKind.userInput,
    status: InteractionStatus.pending,
    createdAt: 1,
    updatedAt: 1,
  );
  ReadScopeIdentity scope(String id, int revision) => ReadScopeIdentity(
    scopeId: id,
    runtimeEpoch: planTestRuntime,
    incarnation: 1,
    sourceRevision: revision,
  );
  @override
  Future<FeedConnection<ThreadExecutionFrame>> openThreadExecution(
    String id, {
    required ThreadObservationMode mode,
  }) => base.openThreadExecution(id, mode: mode);
  @override
  Future<FeedConnection<ThreadAuthoringFrame>> openThreadAuthoring(
    String id, {
    required ThreadObservationMode mode,
  }) => base.openThreadAuthoring(id, mode: mode);
  @override
  Future<FeedConnection<ThreadConfigurationFrame>> openThreadConfiguration(
    String id, {
    required ThreadObservationMode mode,
  }) => base.openThreadConfiguration(id, mode: mode);
  @override
  Future<FeedConnection<ThreadMetricsFrame>> openThreadMetrics(
    String id, {
    required ThreadObservationMode mode,
  }) => base.openThreadMetrics(id, mode: mode);
  @override
  Future<FeedConnection<ThreadContextFrame>> openThreadContext(
    String id, {
    required ThreadObservationMode mode,
  }) => base.openThreadContext(id, mode: mode);
  @override
  Future<InteractionIndexReadConnection> openInteractionIndexRead(
    String id,
    InteractionIndexRef reference, {
    required ThreadFacetStamp origin,
  }) async => _PlanIndexPin(this, reference);
  @override
  Future<InteractionReadRef> resolveInteractionReadRef(
    String id,
    String interactionId, {
    required int revision,
    required ThreadFacetStamp origin,
  }) async => InteractionReadRef(
    entry: keys.entries
        .firstWhere((item) => item.value.interactionId == interactionId)
        .key,
    revision: revision,
  );
  @override
  Future<InteractionReadConnection> openInteractionRead(
    String id,
    InteractionReadRef reference, {
    required ThreadFacetStamp origin,
  }) async => _PlanInteractionPin(this, reference);
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted Plan native capability: ${invocation.memberName}',
  );
}

final class _PlanIndexPin extends ProfileNativePin
    implements InteractionIndexReadConnection {
  _PlanIndexPin(this.native, this.reference)
    : brief = native.brief,
      super('plan-index-${reference.revision}');
  final PlanFeedbackPort native;
  final InteractionIndexRef reference;
  final InteractionBrief brief;
  ReadScopeIdentity get scope => native.scope(id, reference.revision);
  @override
  Future<InteractionIndexReadHeader> header() async =>
      InteractionIndexReadHeader(scope: scope, total: 1, pending: 1);
  @override
  Future<InteractionBriefPage> entries({
    int offset = 0,
    int limit = 32,
  }) async => InteractionBriefPage(
    scope: scope,
    offset: offset,
    total: 1,
    items: [brief],
    nextOffset: null,
  );
}

final class _PlanInteractionPin extends ProfileNativePin
    implements InteractionReadConnection {
  _PlanInteractionPin(this.native, this.reference)
    : super('plan-read-${reference.entry}-${reference.revision}');
  final PlanFeedbackPort native;
  final InteractionReadRef reference;
  InteractionEditorKey get key => native.keys[reference.entry]!;
  ReadScopeIdentity get scope => native.scope(id, reference.revision);
  @override
  // 终态读取在命令被受理之后才发生（D1 的 observe 步骤），因此这里直接返回
  // 真实 revision：阻塞它只会让“已受理但未观察”的命令永远无法结算，关闭时
  // 遗留一次伪未解决。
  Future<InteractionReadHeader> header() async {
    return InteractionReadHeader(
      scope: scope,
      interactionId: ReadText.inline(text: key.interactionId),
      threadId: ReadText.inline(text: key.threadId),
      turnId: ReadText.inline(text: 'turn-${key.interactionId}'),
      itemId: null,
      toolId: null,
      agentPath: null,
      revision: reference.revision,
      purpose: const InteractionPurposeRead.planConfirmation(
        expectedRevision: 1,
        operationId: ReadText.inline(text: 'plan-operation'),
        argumentHash: ReadText.inline(text: 'arguments'),
        planHash: ReadText.inline(text: 'plan-hash'),
      ),
      continuation: null,
      createdAt: 1,
      updatedAt: reference.revision,
      content: const InteractionContentRead.userInput(questionCount: 1),
      state: reference.revision == 1
          ? const InteractionStateRead.pending(
              operationId: ReadText.inline(text: 'plan-operation'),
            )
          : const InteractionStateRead.userInputResolved(
              operationId: ReadText.inline(text: 'plan-operation'),
              resolvedAt: 2,
              answerEntryCount: 1,
            ),
    );
  }

  @override
  Future<QuestionPage> questions({int offset = 0, int limit = 32}) async =>
      QuestionPage(
        scope: scope,
        offset: offset,
        total: 1,
        nextOffset: null,
        items: const [
          QuestionReadItem(
            index: 0,
            id: ReadText.inline(text: agentSessionPlanConfirmationQuestionId),
            header: ReadText.inline(text: 'Implementation plan'),
            question: ReadText.inline(text: planTestMarkdown),
            isOther: false,
            isSecret: false,
            optionsCount: 0,
          ),
        ],
      );
  @override
  Future<AnswerEntryPage> answerEntries({
    int offset = 0,
    int limit = 32,
  }) async => AnswerEntryPage(
    scope: scope,
    offset: offset,
    total: 1,
    nextOffset: null,
    items: [
      AnswerEntryReadItem(
        index: 0,
        questionId: const ReadText.inline(
          text: agentSessionPlanConfirmationQuestionId,
        ),
        answerCount: native
            .resolutions[key.interactionId]!
            .answers
            .single
            .answers
            .length,
      ),
    ],
  );
  @override
  Future<AnswerValuePage> answerValues(
    int index, {
    int offset = 0,
    int limit = 32,
  }) async {
    final values =
        native.resolutions[key.interactionId]!.answers.single.answers;
    return AnswerValuePage(
      scope: scope,
      offset: offset,
      total: values.length,
      nextOffset: null,
      items: [
        for (var i = 0; i < values.length; i++)
          AnswerValueReadItem(
            index: i,
            value: ReadText.inline(text: values[i]),
          ),
      ],
    );
  }
}

final class PlanFeedbackCommands extends UnscriptedConversationCommands {
  PlanFeedbackCommands(this.native);
  final PlanFeedbackPort native;
  int respondCalls = 0;
  StudioFailure? failure;
  Completer<void>? gate;
  @override
  Future<InteractionCommandReply> respondInteraction(
    String threadId,
    String interactionId, {
    required OperationId operationId,
    required int expectedInteractionRevision,
    required InteractionResolutionCommand resolution,
  }) async {
    respondCalls++;
    final originalFailure = failure;
    final originalGate = gate;
    await originalGate?.future;
    if (originalFailure != null) {
      throw CommandDispatchFailure.rejected(failure: originalFailure);
    }
    final answers = (resolution as UserInputResolutionCommand).answers;
    native.resolutions[interactionId] = resolution;
    return InteractionCommandReply(
      interaction: InteractionSnapshot(
        interactionId: interactionId,
        scope: InteractionScope(
          threadId: threadId,
          turnId: 'turn-$interactionId',
          itemId: null,
          toolId: null,
          agentPath: null,
        ),
        revision: 2,
        content: InteractionSnapshotContent.userInput(
          questions: [
            InteractionQuestion(
              id: agentSessionPlanConfirmationQuestionId,
              header: 'Implementation plan',
              question: planTestMarkdown,
              isOther: false,
              isSecret: false,
              options: const [],
            ),
          ],
          state: UserInputInteractionState.resolved(
            operationId: 'plan-operation',
            resolvedAt: 2,
            answers: answers,
          ),
        ),
        createdAt: 1,
        updatedAt: 2,
      ),
      receipt: CommitReceipt(
        operationId: operationId,
        disposition: CommitDisposition.applied,
        targets: [
          ResourceStamp(
            resourceKey: 'interaction:$interactionId',
            ownerEpoch: planTestRuntime,
            revision: 2,
          ),
        ],
        effect: EffectPoint.immediate,
        requiresIdentityObservation: true,
      ),
    );
  }
}
