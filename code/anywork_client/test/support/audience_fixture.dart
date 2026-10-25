import 'dart:async';

import 'package:anywork_client/studio_client.dart';

const audienceTarget = BotAudienceTarget(
  botId: 'bot',
  botName: '机器人',
  chatId: 'chat',
  chatName: '讨论 群',
  kind: BotConversationKind.group,
);
BotAuthorizationRef authorization(int generation, int revision) =>
    BotAuthorizationRef(
      id: BotAuthorizationId(
        botId: 'bot',
        chatId: 'chat',
        generation: generation,
      ),
      revision: revision,
    );

ThreadAudience knownAudience({
  int generation = 1,
  int controlRevision = 1,
  int summaryVersion = 1,
  String phase = 'active',
}) {
  final ref = authorization(generation, controlRevision);
  final started = BotStartedAuthorization(
    authorization: ref,
    bindingRevision: 3,
    start: const BotAudienceStart(
      commitSequence: 8,
      excludedTurnId: 'started-before-cut',
    ),
  );
  return ThreadAudienceKnown(
    audience: BotThreadAudience(
      target: audienceTarget,
      binding: BotThreadBindingPositionCurrent(
        cas: BotSyncCas(
          bindingRevision: 3,
          authorizationHead: BotAuthorizationHeadPresent(authorization: ref),
        ),
        sync: switch (phase) {
          'active' => BotCurrentSyncActive(authorization: started),
          'paused' => BotCurrentSyncPaused(authorization: started),
          'pending' => BotCurrentSyncPendingStart(
            pending: BotPendingAuthorization(
              authorization: ref,
              operationId: 'pending-enable',
            ),
          ),
          'closed' => const BotCurrentSyncClosed(),
          'upgrade' => const BotCurrentSyncRequiresUpgrade(),
          _ => throw ArgumentError(phase),
        },
      ),
      latestClosed: phase == 'closed'
          ? BotClosedAuthorization(
              authorization: ref,
              bindingRevision: 3,
              start: BotClosedStartSaved(start: started.start),
              reason: BotAudienceCloseReason.localClose,
              closedAt: 1234,
            )
          : null,
      hasOlderClosed: false,
      delivery: BotDeliverySummary(
        version: summaryVersion,
        pendingItems: 2,
        unknownOperations: 1,
        incompleteItems: 1,
        countsCapped: false,
      ),
      legacyFinal: const BotLegacyFinalSummary(
        unfinishedChains: 0,
        unknownOperations: 0,
        needsAttention: false,
        countsCapped: false,
      ),
    ),
  );
}

ThreadWorkspace audienceWorkspace(
  ThreadAudience audience, {
  int revision = 1,
}) => ThreadWorkspace(
  thread: StudioThread(
    id: 'thread',
    projectId: 'project',
    title: 'Thread',
    mode: ThreadModeId.simple,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    updatedAt: DateTime.utc(2026),
    workspacePath: '/workspace',
  ),
  revision: revision,
  audience: audience,
  interactions: const [],
  runtime: const ThreadRuntimeView(
    modelId: '',
    contextTokens: 0,
    contextWindow: 1,
    totalTokens: 0,
    costLabel: '',
    activeSkills: [],
    activeMcpServers: [],
    activeLspServers: [],
  ),
);

AnyworkClient audienceClient(
  StudioTransport transport, {
  ResourceBudget? budget,
}) {
  final client = AnyworkClient(
    transport: transport,
    clientId: 'test-audience',
    budget: budget,
  );
  client.applyBootstrap(
    StudioBootstrap(
      ownerEpoch: 'host-epoch',
      projectDirectory: ProjectDirectoryState(),
      threadDirectory: const ThreadDirectoryWindow(),
      agentDirectory: AgentDirectoryState(),
      settingsState: SettingsStateSnapshot(revision: 1),
      recoveryState: RecoveryStateSnapshot(revision: 1),
      mcpState: McpStateSnapshot(revision: 1),
      lspState: LspStateSnapshot(revision: 1),
      skillsByProject: const {},
      threadModeCatalog: const ThreadModeCatalogView(),
      accountUsageState: AccountUsageStateSnapshot(revision: 1),
      modelPerformance: const ModelPerformanceSnapshotView(),
      updaterState: DisabledUpdaterStateSnapshot(
        revision: 1,
        updatedAt: DateTime.utc(2026),
      ),
      persistenceState: const PersistenceStateSnapshot.ready(),
    ),
  );
  return client;
}

final class AudienceReadCall {
  AudienceReadCall(this.request);
  final ReadThreadAudienceItemsRequest request;
  final result = Completer<ReadThreadAudienceItemsReply>();
  void complete({
    int revision = 1,
    int? controlRevision,
    int summaryVersion = 1,
    int deliveryVersion = 1,
    BotAuthorizationPhase phase = BotAuthorizationPhase.active,
  }) {
    result.complete(
      ReadThreadAudienceItemsReply(
        threadId: request.threadId,
        authorization: request.authorization,
        result: BotAudienceItemsReadItems(
          authorization: BotAuthorizationRef(
            id: request.authorization,
            revision: controlRevision ?? 1,
          ),
          phase: phase,
          summaryVersion: summaryVersion,
          deliveryVersion: deliveryVersion,
          items: [
            for (final id in request.itemIds)
              BotAudienceItemStatus(
                itemId: id,
                canonical: BotAudienceCanonicalItemPresent(
                  revision: revision,
                  saved: true,
                  eligibility: const BotItemEligibilityText(
                    channel: BotPublicTextChannel.finalAnswer,
                  ),
                ),
                delivery: const BotItemDeliveryNotProjected(),
              ),
          ],
        ),
      ),
    );
  }
}

final class SyncCall {
  SyncCall(this.request);
  final ChangeBotThreadSyncRequest request;
  final result = Completer<ChangeBotThreadSyncReply>();
  void complete(
    ThreadAudience audience, {
    bool pending = false,
    bool effective = true,
  }) {
    final ref = audience.queryAuthorization!;
    result.complete(
      ChangeBotThreadSyncReply(
        threadId: request.threadId,
        audience: audience,
        state: pending
            ? BotThreadSyncCommandStatePendingStart(authorization: ref.id)
            : const BotThreadSyncCommandStateSettled(),
        receipt: StudioCommandReceipt(
          operationId: OperationId(request.operationId),
          disposition: CommitDisposition.applied,
          targets: [
            ResourceStamp(
              resourceKey:
                  'bot-audience:${request.threadId}:${ref.id.generation}',
              ownerEpoch: 'host-epoch',
              revision: ref.revision,
            ),
          ],
          effect: EffectPoint.immediate,
          effective: effective,
          durable: true,
        ),
      ),
    );
  }
}

final class AudienceTransport extends StudioTransport {
  final List<AudienceReadCall> reads = [];
  final List<SyncCall> controls = [];
  final List<ReadThreadClosedAuthorizationsRequest> history = [];
  Completer<AudienceReadCall>? _nextRead;
  Completer<SyncCall>? _nextControl;
  final List<AudienceReadCall> _unconsumedReads = [];
  final List<SyncCall> _unconsumedControls = [];
  Future<AudienceReadCall> nextRead() => _unconsumedReads.isNotEmpty
      ? Future.value(_unconsumedReads.removeAt(0))
      : (_nextRead ??= Completer<AudienceReadCall>()).future;
  Future<SyncCall> nextControl() => _unconsumedControls.isNotEmpty
      ? Future.value(_unconsumedControls.removeAt(0))
      : (_nextControl ??= Completer<SyncCall>()).future;
  @override
  Future<ReadThreadAudienceItemsReply> readThreadAudienceItems(
    ReadThreadAudienceItemsRequest request,
  ) {
    final call = AudienceReadCall(request);
    reads.add(call);
    if (_nextRead case final ready?) {
      _nextRead = null;
      ready.complete(call);
    } else {
      _unconsumedReads.add(call);
    }
    return call.result.future;
  }

  @override
  Future<ChangeBotThreadSyncReply> changeBotThreadSync(
    ChangeBotThreadSyncRequest request,
  ) {
    final call = SyncCall(request);
    controls.add(call);
    if (_nextControl case final ready?) {
      _nextControl = null;
      ready.complete(call);
    } else {
      _unconsumedControls.add(call);
    }
    return call.result.future;
  }

  @override
  Future<ReadThreadClosedAuthorizationsReply> readThreadClosedAuthorizations(
    ReadThreadClosedAuthorizationsRequest request,
  ) async {
    history.add(request);
    return ReadThreadClosedAuthorizationsReply(
      threadId: request.threadId,
      result: ThreadClosedAuthorizationsReadPage(
        page: ThreadClosedAuthorizationPage(
          target: audienceTarget,
          authorizations: [
            BotClosedAuthorization(
              authorization: authorization(1, 2),
              bindingRevision: 3,
              start: const BotClosedStartNeverActivated(),
              reason: BotAudienceCloseReason.startFailed,
              closedAt: 1,
            ),
          ],
          nextCursor: request.cursor == null
              ? 'opaque:not/a/timeline/cursor'
              : null,
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused test capability ${invocation.memberName}');
}
