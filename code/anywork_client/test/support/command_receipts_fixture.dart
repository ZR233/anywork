import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'conversation_fixture.dart';
import 'drafts_native_fixture.dart' show DraftCalls;
import 'timeline_transport.dart';

const receiptEpoch = 'native-runtime-one';
const receiptConflict = StudioFailure(
  code: StudioFailureCode.conflict,
  message: 'route changed at its owner',
  retryable: true,
  correlationId: 'route-conflict',
);

ResourceStamp receiptStamp(String key, int revision) => ResourceStamp(
  resourceKey: key,
  ownerEpoch: receiptEpoch,
  revision: revision,
);
CommitReceipt commandReceipt(
  OperationId id,
  List<ResourceStamp> targets, {
  CommitDisposition disposition = CommitDisposition.applied,
  EffectPoint effect = EffectPoint.immediate,
  bool identity = false,
  bool? effective,
}) => CommitReceipt(
  operationId: id,
  disposition: disposition,
  targets: targets,
  effect: effect,
  effective: effective ?? effect == EffectPoint.immediate,
  durable: false,
  requiresIdentityObservation: identity,
);

final class ReceiptModeCall {
  ReceiptModeCall(this.id, this.threadId, this.mode);
  final OperationId id;
  final String threadId;
  final String mode;
  final reply = Completer<CommitReceipt>();
}

final class ReceiptRouteCall {
  ReceiptRouteCall(
    this.id,
    this.threadId,
    this.account,
    this.model,
    this.effort,
    this.routeRevision,
    this.settingsRevision,
  );
  final OperationId id;
  final String threadId;
  final String account;
  final String model;
  final String? effort;
  final int routeRevision;
  final int settingsRevision;
  final reply = Completer<ThreadModelRouteCommandReply>();
}

final class ReceiptCompactCall {
  ReceiptCompactCall(this.id, this.threadId);
  final OperationId id;
  final String threadId;
  final reply = Completer<void>();
}

final class ReceiptInteractionCall {
  ReceiptInteractionCall(this.id, this.interactionId, this.resolution);
  final OperationId id;
  final String interactionId;
  final InteractionResolutionCommand resolution;
  final reply = Completer<InteractionCommandReply>();
}

/// External command results only. The real Session freezes commands, allocates
/// tickets, serializes lanes and joins canonical evidence independently.
final class ReceiptCommands extends UnscriptedConversationCommands {
  final modes = DraftCalls<ReceiptModeCall>();
  final routes = DraftCalls<ReceiptRouteCall>();
  final compactions = DraftCalls<ReceiptCompactCall>();
  final interactions = DraftCalls<ReceiptInteractionCall>();
  @override
  Future<InteractionCommandReply> respondInteraction(
    String threadId,
    String interactionId, {
    required OperationId operationId,
    required int expectedInteractionRevision,
    required InteractionResolutionCommand resolution,
  }) {
    expect((threadId, expectedInteractionRevision), ('thread', 1));
    final call = ReceiptInteractionCall(operationId, interactionId, resolution);
    interactions.add(call);
    return call.reply.future;
  }

  @override
  Future<void> compactThread(
    String threadId, {
    required OperationId operationId,
  }) {
    final call = ReceiptCompactCall(operationId, threadId);
    compactions.add(call);
    return call.reply.future;
  }

  @override
  Future<CommitReceipt> setThreadMode(
    String threadId,
    String mode, {
    required OperationId operationId,
  }) {
    final call = ReceiptModeCall(operationId, threadId, mode);
    modes.add(call);
    return call.reply.future;
  }

  @override
  Future<ThreadModelRouteCommandReply> setThreadModelRoute(
    String threadId, {
    required OperationId operationId,
    required String accountId,
    required String modelId,
    required String? effort,
    required int expectedModelRouteRevision,
    required int expectedSettingsRevision,
  }) {
    final call = ReceiptRouteCall(
      operationId,
      threadId,
      accountId,
      modelId,
      effort,
      expectedModelRouteRevision,
      expectedSettingsRevision,
    );
    routes.add(call);
    return call.reply.future;
  }
}

ThreadFacetStamp receiptOrigin(ThreadFacet facet, int revision) =>
    ThreadFacetStamp(
      runtimeEpoch: receiptEpoch,
      incarnation: 1,
      facet: facet,
      revision: revision,
    );
ThreadConfigurationValue receiptConfiguration(
  int revision, {
  int? route,
  int? mode,
  int settings = 1,
}) => ThreadConfigurationValue(
  details: ThreadConfigurationReadRef(entry: 1, revision: revision),
  sources: ConfigProjectionStamp(
    settingsRevision: settings,
    modelCatalogRevision: 1,
    closing: false,
  ),
  modeRevision: 1,
  modeBindingRevision: mode ?? revision,
  modelRoute: ModelRouteBrief(
    revision: route ?? revision,
    available: true,
    hasUnavailableReason: false,
  ),
  activeSkillCount: 0,
  activeMcp: ThreadCapabilitySupport.unsupported,
  activeLsp: ThreadCapabilitySupport.unsupported,
  mcpHealth: ThreadCapabilitySupport.unsupported,
);

final class ReceiptFixture {
  ReceiptFixture() : commands = ReceiptCommands() {
    owner = ConversationFixture(commands: commands);
    owner.facets.configurationOpen = (threadId, reference, origin) async {
      expect(threadId, 'thread');
      return ReceiptConfigurationPin(
        configurationMaterials[reference.revision]!,
      );
    };
  }
  final ReceiptCommands commands;
  late final ConversationFixture owner;
  late ConversationSession session;
  late FacetOpen<ThreadConfigurationFrame> configuration;
  late FacetOpen<ThreadContextFrame> context;
  int sequence = 0;
  int revision = 0;
  final configurationMaterials = <int, ThreadConfigurationReadHeader>{};
  final interactionProofs = <String, Completer<void>>{};
  final interactionReads = <String, Completer<void>>{};
  final interactionEntries = <String, int>{};
  void scriptInteraction(String id) {
    interactionEntries[id] = interactionEntries.length + 1;
    interactionProofs[id] = Completer<void>();
    interactionReads[id] = Completer<void>();
    owner.facets.interactionResolve =
        (threadId, interactionId, revision, origin) async {
          expect(threadId, 'thread');
          final entry = interactionEntries[interactionId]!;
          if (revision == 2) {
            if (!interactionReads[interactionId]!.isCompleted)
              interactionReads[interactionId]!.complete();
            await interactionProofs[interactionId]!.future;
          }
          return InteractionReadRef(entry: entry, revision: revision);
        };
    owner.facets.interactionOpen = (threadId, reference, origin) async {
      final id = interactionEntries.entries
          .singleWhere((entry) => entry.value == reference.entry)
          .key;
      return ReceiptInteractionPin(id, reference.revision, origin);
    };
  }

  Future<void> establish() async {
    session = owner.select('thread');
    configuration = await owner.facets.configurationOpened(0);
    await configuration.feed.listened.future;
    final opening = await owner.timeline.opened(0);
    opening.result.complete(TestTimelineConnection(initial: baseline(300)));
    await session.timeline.ready;
    await publishConfiguration(1);
    context = owner.facets.context.single;
    await context.feed.listened.future;
    context.feed.emit(
      ThreadContextFrame.data(
        deliverySequence: 1,
        event: ThreadContextEvent.baseline(
          identity: ThreadFeedIdentity(
            feedId: context.feed.feedId,
            runtimeEpoch: receiptEpoch,
            incarnation: 1,
            facet: ThreadFacet.context,
            mode: context.mode,
          ),
          stamp: receiptOrigin(ThreadFacet.context, 1),
          value: const ThreadContextValue(
            usage: null,
            liveContext: null,
            currentPolicy: null,
            details: ContextReadRef(entry: 1, revision: 1),
          ),
        ),
      ),
    );
    await context.feed.acknowledged(1);
  }

  Future<void> publishConfiguration(
    int next, {
    int? route,
    int? mode,
    int settings = 1,
    String model = 'alpha',
  }) async {
    revision = next;
    final first = sequence == 0;
    final value = receiptConfiguration(
      next,
      route: route,
      mode: mode,
      settings: settings,
    );
    final stamp = receiptOrigin(ThreadFacet.configuration, next);
    configurationMaterials[next] = ThreadConfigurationReadHeader(
      scope: ReadScopeIdentity(
        scopeId: 'native-configuration-$next',
        runtimeEpoch: receiptEpoch,
        incarnation: 1,
        sourceRevision: next,
      ),
      route: ModelRouteReadValue(
        botId: null,
        accountId: const ReadText.inline(text: 'account'),
        modelId: ReadText.inline(text: model),
        effort: const ReadText.inline(text: 'medium'),
        revision: route ?? next,
        available: true,
        unavailableReason: null,
      ),
      activeSkillCount: 0,
    );
    configuration.feed.emit(
      ThreadConfigurationFrame.data(
        deliverySequence: ++sequence,
        event: first
            ? ThreadConfigurationEvent.baseline(
                identity: ThreadFeedIdentity(
                  feedId: configuration.feed.feedId,
                  runtimeEpoch: receiptEpoch,
                  incarnation: 1,
                  facet: ThreadFacet.configuration,
                  mode: configuration.mode,
                ),
                stamp: stamp,
                value: value,
              )
            : ThreadConfigurationEvent.replace(stamp: stamp, value: value),
      ),
    );
    await configuration.feed.acknowledged(sequence);
  }

  Future<void> close() async {
    final closing = owner.repository.close();
    for (final opening in owner.timeline.requests) {
      if (!opening.result.isCompleted)
        opening.result.complete(TestTimelineConnection(initial: baseline(1)));
    }
    for (final call in commands.compactions.values) {
      if (!call.reply.isCompleted)
        call.reply.completeError(
          const CommandDispatchFailure.rejected(failure: receiptConflict),
        );
    }
    for (final call in commands.modes.values) {
      if (!call.reply.isCompleted)
        call.reply.completeError(
          const CommandDispatchFailure.rejected(failure: receiptConflict),
        );
    }
    for (final call in commands.routes.values) {
      if (!call.reply.isCompleted)
        call.reply.completeError(
          const CommandDispatchFailure.rejected(failure: receiptConflict),
        );
    }
    for (final proof in interactionProofs.values) {
      if (!proof.isCompleted) proof.complete();
    }
    for (final call in commands.interactions.values) {
      if (!call.reply.isCompleted)
        call.reply.completeError(
          const CommandDispatchFailure.rejected(failure: receiptConflict),
        );
    }
    expect((await closing).complete, isTrue);
    expect(owner.budget.usage, isEmpty);
  }
}

final class ReceiptConfigurationPin
    implements ThreadConfigurationReadConnection {
  ReceiptConfigurationPin(this.value);
  final ThreadConfigurationReadHeader value;
  @override
  Future<ThreadConfigurationReadHeader> header() async => value;
  @override
  void requestClose() {}
  @override
  Future<FeedCloseReport> close() async => FeedCloseReport(
    feedId: value.scope.scopeId,
    outcome: const FeedCloseOutcome.clean(),
  );
  @override
  Future<FeedCloseReport> retryClose() => close();
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted configuration body ${invocation.memberName}',
  );
}

final class ReceiptInteractionPin implements InteractionReadConnection {
  ReceiptInteractionPin(this.id, this.revision, this.origin);
  final String id;
  final int revision;
  final ThreadFacetStamp origin;
  @override
  Future<InteractionReadHeader> header() async => InteractionReadHeader(
    scope: ReadScopeIdentity(
      scopeId: 'native-$id-$revision',
      runtimeEpoch: origin.runtimeEpoch,
      incarnation: origin.incarnation,
      sourceRevision: revision,
    ),
    interactionId: ReadText.inline(text: id),
    threadId: const ReadText.inline(text: 'thread'),
    turnId: const ReadText.inline(text: 'turn'),
    itemId: null,
    toolId: null,
    agentPath: null,
    revision: revision,
    purpose: const InteractionPurposeRead.general(),
    continuation: null,
    createdAt: 1,
    updatedAt: revision,
    content: const InteractionContentRead.userInput(questionCount: 0),
    state: revision == 1
        ? const InteractionStateRead.pending(
            operationId: ReadText.inline(text: 'native-input'),
          )
        : const InteractionStateRead.userInputResolved(
            operationId: ReadText.inline(text: 'native-input'),
            resolvedAt: 2,
            answerEntryCount: 1,
          ),
  );
  @override
  void requestClose() {}
  @override
  Future<FeedCloseReport> close() async => FeedCloseReport(
    feedId: 'native-$id-$revision',
    outcome: const FeedCloseOutcome.clean(),
  );
  @override
  Future<FeedCloseReport> retryClose() => close();
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted interaction body ${invocation.memberName}',
  );
}

InteractionCommandReply receiptInteractionReply(ReceiptInteractionCall call) =>
    InteractionCommandReply(
      interaction: InteractionSnapshot(
        interactionId: call.interactionId,
        scope: const InteractionScope(
          threadId: 'thread',
          turnId: 'turn',
          itemId: null,
          toolId: null,
          agentPath: null,
        ),
        revision: 2,
        content: InteractionSnapshotContent.userInput(
          questions: const [],
          state: UserInputInteractionState.resolved(
            operationId: 'native-input',
            resolvedAt: 2,
            answers: (call.resolution as UserInputResolutionCommand).answers,
          ),
        ),
        createdAt: 1,
        updatedAt: 2,
      ),
      receipt: commandReceipt(call.id, [
        receiptStamp('interaction:${call.interactionId}', 2),
      ], identity: true),
    );

ThreadModelRouteCommandReply receiptRouteReply(
  ReceiptRouteCall call,
  int revision, {
  int settings = 2,
  CommitDisposition disposition = CommitDisposition.applied,
}) => ThreadModelRouteCommandReply(
  runtime: ThreadRuntimeSnapshot(
    threadId: call.threadId,
    modelRoute: ThreadModelRoute(
      botId: null,
      accountId: call.account,
      modelId: call.model,
      effort: call.effort,
      revision: revision,
      available: true,
      unavailableReason: null,
    ),
    usage: ThreadRuntimeUsage(
      hasIncompleteUsage: false,
      modelId: call.model,
      contextWindow: 100,
      maxContextWindow: 100,
      autoCompactLimit: null,
      latestContextTokens: 0,
      promptTokens: 0,
      completionTokens: 0,
      cachedPromptTokens: 0,
      cacheWriteTokens: 0,
      reasoningTokens: 0,
      inferenceCount: 0,
      totalTokens: 0,
      cacheUsage: const CacheUsageSummary(
        inputTokens: 0,
        cacheReadTokens: 0,
        hitRate: null,
        hasIncompleteUsage: false,
      ),
      estimatedCosts: const [],
      estimatedCacheSavings: const [],
      hasUnpricedUsage: false,
      promptGeneration: null,
      promptCachePolicy: null,
      prefixChangedReason: null,
      updatedAt: 1,
    ),
    liveUsage: null,
    turnCompletionTokens: 0,
    turnResponseMillis: 0,
    todo: null,
    activeSkills: const [],
    activeMcpServers: const [],
    activeLspServers: const [],
    progress: null,
    mcpHealth: null,
    workflow: null,
    plan: null,
    updatedAt: 1,
  ),
  settings: ThreadSettingsSnapshot(
    config: ThreadSettingsConfigSnapshot(
      revision: settings,
      updatedAt: 1,
      settings: ThreadSettingsValue(
        defaultAccountId: 'account',
        accounts: const [],
        modeModelRoutes: const [],
        roles: const [],
        permissionMode: 'requestApproval',
        instructions: InstructionsSettings(
          baseOverride: '',
          developer: '',
          user: '',
          projectDocMaxBytes: 0,
          projectDocFallbackFilenames: const [],
        ),
        skills: SkillsSettings(
          enabled: false,
          autoLearn: false,
          systemEnabled: false,
          projectDir: '',
          userDir: '',
          externalDirs: const [],
          disabled: const [],
          autoLearnMinToolCalls: 0,
        ),
        mcpServers: const [],
        general: GeneralSettings(
          followActiveTurn: false,
          compactTimeline: false,
          sidebarWidth: null,
          pinnedThreadIds: const [],
          pinnedProjectIds: const [],
        ),
        delegation: const DelegationSettings(
          mode: DelegationMode.profile,
          preference: DelegationPreference.balanced,
        ),
        webSearch: ThreadWebSearchSettings(
          configuration: WebSearchConfiguration(
            configuredMode: 'disabled',
            contextSize: null,
            allowedDomains: const [],
            country: null,
            region: null,
            city: null,
            timezone: null,
          ),
          effective: const EffectiveWebSearch(
            effectiveMode: 'disabled',
            availability: 'unavailable',
            accountId: null,
            modelId: null,
          ),
        ),
        deepseekWebSearch: const ThreadDeepSeekSearchSettings(
          configuration: DeepSeekSearchConfiguration(
            configuredEnabled: false,
            configuredFetchEnabled: false,
          ),
          effective: EffectiveDeepSeekSearch(
            effectiveEnabled: false,
            effectiveFetchEnabled: false,
            availability: 'unavailable',
            accountId: null,
          ),
        ),
      ),
    ),
    catalog: ThreadSettingsCatalogSnapshot(
      revision: 1,
      updatedAt: 1,
      accounts: const [],
    ),
  ),
  modeDefaultSaved: true,
  warning: null,
  receipt: commandReceipt(
    call.id,
    [
      receiptStamp('thread-route:thread', revision),
      receiptStamp('settings', settings),
    ],
    effect: EffectPoint.nextTurn,
    disposition: disposition,
  ),
);
