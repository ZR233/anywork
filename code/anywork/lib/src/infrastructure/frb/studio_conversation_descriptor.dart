part of 'studio_api.dart';

frb_timeline_types.BridgeTimelineMembersRef _timelineMembersToFrb(
  TimelineMembersRef value,
) => frb_timeline_types.BridgeTimelineMembersRef(
  databaseId: value.databaseId,
  projectionVersion: value.projectionVersion,
  projectionGeneration: value.projectionGeneration,
  itemId: value.itemId,
);

TimelineItem _timelineItemFromFrb(
  frb_timeline_types.BridgeTimelineItem value,
) => TimelineItem(
  id: value.id,
  kind: TimelineItemKind.values.byName(value.kind.name),
  source: _chatSourceFromFrb(value.source),
  atomKind: value.atomKind == null
      ? null
      : ChatAtomKind.values.byName(value.atomKind!.name),
  delivery: ChatDeliveryKind.values.byName(value.delivery.name),
  outcome: value.outcome == null
      ? null
      : ChatTerminalOutcome.values.byName(value.outcome!.name),
  textChannel: value.textChannel == null
      ? null
      : ThreadTextChannel.values.byName(value.textChannel!.name),
  turnId: value.turnId,
  startedAt: value.startedAt == null
      ? null
      : _exactSignedTimelineInt(value.startedAt!),
  finishedAt: value.finishedAt == null
      ? null
      : _exactSignedTimelineInt(value.finishedAt!),
  summary: value.summary == null
      ? null
      : TimelineGroupSummary(
          latestThinkingSummary: value.summary!.latestThinkingSummary,
          memberCount: value.summary!.memberCount,
          activeCount: value.summary!.activeCount,
          failedCount: value.summary!.failedCount,
          cancelledCount: value.summary!.cancelledCount,
          categories: [
            for (final count in value.summary!.categories)
              TimelineCategoryCount(
                category: TimelineCategory.values.byName(count.category.name),
                count: count.count,
              ),
          ],
          startedAt: value.summary!.startedAt == null
              ? null
              : _exactSignedTimelineInt(value.summary!.startedAt!),
          finishedAt: value.summary!.finishedAt == null
              ? null
              : _exactSignedTimelineInt(value.summary!.finishedAt!),
        ),
  members: value.members == null
      ? null
      : TimelineMembersRef(
          databaseId: value.members!.databaseId,
          projectionVersion: value.members!.projectionVersion,
          projectionGeneration: value.members!.projectionGeneration,
          itemId: value.members!.itemId,
        ),
  contents: [
    for (final content in value.contents)
      ChatAtomContent(
        role: ChatContentRole.values.byName(content.role.name),
        reference: _contentRefFromFrb(content.reference),
      ),
  ],
  payload: value.payload == null ? null : _payloadFromFrb(value.payload!),
  contentItemId: value.contentItemId,
  position: value.position == null
      ? null
      : _exactTimelineInt(value.position!, 'item position'),
  admissionClosed: value.admissionClosed,
);

frb_chat_types.BridgeReadDemand _readDemandToFrb(ReadDemand value) =>
    frb_chat_types.BridgeReadDemand(
      maxItems: value.maxItems,
      maxBytes: value.maxBytes,
    );

ChatBatch _chatBatchFromFrb(frb_chat_types.BridgeChatBatch value) => ChatBatch(
  placement: switch (value.placement) {
    frb_chat_types.BridgeChatPlacement.set_ => ChatPlacement.set,
    frb_chat_types.BridgeChatPlacement.prepend => ChatPlacement.prepend,
    frb_chat_types.BridgeChatPlacement.append => ChatPlacement.append,
    frb_chat_types.BridgeChatPlacement.update => ChatPlacement.update,
  },
  entries: value.entries.map(_chatEntryFromFrb).toList(),
  before: value.before,
  current: value.current == null ? null : _currentFromFrb(value.current!),
);

ChatSourceId _chatSourceFromFrb(frb_chat_types.BridgeChatSourceId value) =>
    switch (value) {
      frb_chat_types.BridgeChatSourceId_ForegroundTurn(:final turnId) =>
        ForegroundTurnChatSource(turnId: turnId),
      frb_chat_types.BridgeChatSourceId_Input(:final inputId) =>
        InputChatSource(inputId: inputId),
      frb_chat_types.BridgeChatSourceId_BackgroundResult(:final messageId) =>
        BackgroundResultChatSource(messageId: messageId),
      frb_chat_types.BridgeChatSourceId_Operation(:final operationId) =>
        OperationChatSource(operationId: operationId),
      frb_chat_types.BridgeChatSourceId_Receipt(:final receiptId) =>
        ReceiptChatSource(receiptId: receiptId),
    };
ChatFactPosition _chatPositionFromFrb(
  frb_chat_types.BridgeChatFactPosition value,
) => ChatFactPosition(
  effectSeq: _exactTimelineInt(value.effectSeq, 'effect sequence'),
  suborder: value.suborder,
);
ChatEntry _chatEntryFromFrb(frb_chat_types.BridgeChatEntry value) =>
    switch (value) {
      frb_chat_types.BridgeChatEntry_Item(:final field0) => ItemChatEntry(
        _timelineItemFromFrb(field0),
      ),
      frb_chat_types.BridgeChatEntry_Atom(:final field0) => ChatAtomEntry(
        _chatAtomFromFrb(field0),
      ),
      frb_chat_types.BridgeChatEntry_Source(:final field0) => ChatSourceEntry(
        _chatSourceStateFromFrb(field0),
      ),
    };
ChatSourceState _chatSourceStateFromFrb(
  frb_chat_types.BridgeChatSourceState value,
) => ChatSourceState(
  source: _chatSourceFromFrb(value.source),
  lifecycle: switch (value.lifecycle) {
    frb_chat_types.BridgeChatSourceLifecycle_Unknown() =>
      const UnknownChatSource(),
    frb_chat_types.BridgeChatSourceLifecycle_Active() =>
      const ActiveChatSource(),
    frb_chat_types.BridgeChatSourceLifecycle_Ended(:final outcome) =>
      EndedChatSource(outcome: ChatTerminalOutcome.values.byName(outcome.name)),
  },
  started: value.started == null ? null : _chatPositionFromFrb(value.started!),
  ended: value.ended == null ? null : _chatPositionFromFrb(value.ended!),
);
ChatAtom _chatAtomFromFrb(frb_chat_types.BridgeChatAtom value) => ChatAtom(
  id: value.id,
  completionItemId: value.completionItemId,
  completionSeq: _exactNullableTimelineInt(
    value.completionSeq,
    'completion sequence',
  ),
  source: _chatSourceFromFrb(value.source),
  sourceState: value.sourceState == null
      ? null
      : _chatSourceStateFromFrb(value.sourceState!),
  sourceOrder: _exactNullableTimelineInt(value.sourceOrder, 'source order'),
  kind: ChatAtomKind.values.byName(value.kind.name),
  delivery: ChatDeliveryKind.values.byName(value.delivery.name),
  lifecycle: switch (value.lifecycle) {
    frb_chat_types.BridgeChatAtomLifecycle_Active(
      :final started,
      :final status,
    ) =>
      ActiveChatAtom(
        started: started == null ? null : _chatPositionFromFrb(started),
        status: ChatActiveStatus.values.byName(status.name),
      ),
    frb_chat_types.BridgeChatAtomLifecycle_Terminal(
      :final started,
      :final ended,
      :final outcome,
    ) =>
      TerminalChatAtom(
        started: started == null ? null : _chatPositionFromFrb(started),
        ended: ended == null ? null : _chatPositionFromFrb(ended),
        outcome: ChatTerminalOutcome.values.byName(outcome.name),
      ),
  },
  turnId: value.turnId,
  attemptId: value.attemptId,
  tool: value.tool == null
      ? null
      : ChatToolIdentity(callId: value.tool!.callId, name: value.tool!.name),
  wait: value.wait == null ? null : _waitFromFrb(value.wait!),
  textChannel: value.textChannel == null
      ? null
      : ThreadTextChannel.values.byName(value.textChannel!.name),
  contentPresent: value.contentPresent,
  startedAt: value.startedAt == null
      ? null
      : _exactSignedTimelineInt(value.startedAt!),
  finishedAt: value.finishedAt == null
      ? null
      : _exactSignedTimelineInt(value.finishedAt!),
  contents: [
    for (final content in value.contents)
      ChatAtomContent(
        role: ChatContentRole.values.byName(content.role.name),
        reference: _contentRefFromFrb(content.reference),
      ),
  ],
  payload: value.payload == null ? null : _payloadFromFrb(value.payload!),
);

PayloadData _payloadFromFrb(frb_chat_types.BridgePayloadData value) =>
    switch (value) {
      frb_chat_types.BridgePayloadData_Inline(:final bytes) => InlinePayload(
        bytes: bytes,
      ),
      frb_chat_types.BridgePayloadData_Deferred(
        :final reference,
        :final byteLength,
      ) =>
        DeferredPayload(
          reference: _contentRefFromFrb(reference),
          byteLength: _exactTimelineInt(byteLength, 'payload bytes'),
        ),
    };

ContentRef _contentRefFromFrb(frb_chat_types.BridgeContentRef value) =>
    ContentRef(
      databaseId: value.databaseId,
      target: switch (value.target) {
        frb_chat_types.BridgeContentTarget_ItemPayload(:final itemId) =>
          ItemPayloadTarget(itemId: itemId),
        frb_chat_types.BridgeContentTarget_Body(:final owner, :final key) =>
          BodyContentTarget(
            key: key,
            owner: switch (owner) {
              frb_chat_types.BridgeContentOwner_Item(:final itemId) =>
                ItemContentOwner(itemId: itemId),
              frb_chat_types.BridgeContentOwner_Current(
                :final domain,
                :final id,
                :final revision,
              ) =>
                CurrentContentOwner(
                  domain: domain,
                  id: id,
                  revision: _exactTimelineInt(revision, 'content revision'),
                ),
            },
          ),
      },
    );

frb_chat_types.BridgeContentRef _contentRefToFrb(ContentRef value) =>
    frb_chat_types.BridgeContentRef(
      databaseId: value.databaseId,
      target: switch (value.target) {
        ItemPayloadTarget(:final itemId) =>
          frb_chat_types.BridgeContentTarget.itemPayload(itemId: itemId),
        BodyContentTarget(:final owner, :final key) =>
          frb_chat_types.BridgeContentTarget.body(
            key: key,
            owner: switch (owner) {
              ItemContentOwner(:final itemId) =>
                frb_chat_types.BridgeContentOwner.item(itemId: itemId),
              CurrentContentOwner(:final domain, :final id, :final revision) =>
                frb_chat_types.BridgeContentOwner.current(
                  domain: domain,
                  id: id,
                  revision: BigInt.from(revision),
                ),
            },
          ),
      },
    );

CurrentCollectionRef _collectionFromFrb(
  frb_chat_types.BridgeCurrentCollectionRef value,
) => CurrentCollectionRef(
  databaseId: value.databaseId,
  collection: value.collection,
  revision: _exactTimelineInt(value.revision, 'collection revision'),
);

frb_chat_types.BridgeCurrentCollectionRef _collectionToFrb(
  CurrentCollectionRef value,
) => frb_chat_types.BridgeCurrentCollectionRef(
  databaseId: value.databaseId,
  collection: value.collection,
  revision: BigInt.from(value.revision),
);

CurrentProjection _currentFromFrb(
  frb_chat_types.BridgeCurrentProjection value,
) => CurrentProjection(
  sourceEffectSeq: _exactTimelineInt(value.sourceEffectSeq, 'source effect'),
  logicalStatus: ThreadStatusView.values.byName(value.logicalStatus.name),
  executionPresent: value.executionPresent,
  sources: value.sources.map(_chatSourceStateFromFrb).toList(),
  items: value.items.map(_timelineItemFromFrb).toList(),
  atoms: value.atoms.map(_chatAtomFromFrb).toList(),
  active: value.active == null ? null : _currentActivityFromFrb(value.active!),
  activeTurn: value.activeTurn == null
      ? null
      : CurrentTurnHead(
          id: value.activeTurn!.id,
          phase: StudioTurnActivity.values.byName(value.activeTurn!.phase.name),
        ),
  plan: value.plan == null
      ? null
      : CurrentPlanHead(
          revision: _exactTimelineInt(value.plan!.revision, 'plan revision'),
          phase: PlanRuntimePhase.values.byName(value.plan!.phase.name),
          document: value.plan!.document == null
              ? null
              : _contentRefFromFrb(value.plan!.document!),
        ),
  interactions: value.interactions == null
      ? null
      : _collectionFromFrb(value.interactions!),
  previews: value.previews
      .map(
        (preview) => CurrentContentPreview(
          id: preview.id,
          role: CurrentContentRole.values.byName(preview.role.name),
          textChannel: preview.textChannel == null
              ? null
              : ThreadTextChannel.values.byName(preview.textChannel!.name),
          text: preview.text,
          reference: _contentRefFromFrb(preview.reference),
        ),
      )
      .toList(),
  collections: value.collections.map(_collectionFromFrb).toList(),
);

CurrentActivityHead _currentActivityFromFrb(
  frb_chat_types.BridgeCurrentActivityHead value,
) => CurrentActivityHead(
  id: value.id,
  kind: ThreadActivityKind.values.byName(value.kind.name),
  summary: value.summary,
  thinkingSummary: value.thinkingSummary,
  thinkingSeconds: _exactNullableTimelineInt(
    value.thinkingSeconds,
    'thinking seconds',
  ),
  toolCount: value.toolCount,
  backgroundToolCount: value.backgroundToolCount,
  latestTool: value.latestTool == null
      ? null
      : CurrentToolHead(
          callId: value.latestTool!.callId,
          name: value.latestTool!.name,
          state: _activityToolStateFromFrb(value.latestTool!.state),
        ),
);

ContentWindow _contentWindowFromFrb(frb_chat_types.BridgeContentWindow value) =>
    ContentWindow(
      offset: _exactTimelineInt(value.offset, 'content offset'),
      bytes: value.bytes,
      generation: value.generation,
      availableThrough: _exactTimelineInt(
        value.availableThrough,
        'available bytes',
      ),
      sealed: value.sealed,
    );

/// No separately opened native reader. All operations use the facade's captured
/// lease, independently of events/ACK and its producer receive lock.
final class _FrbConversationReader implements ConversationReader {
  _FrbConversationReader(this._feed);
  final FrbConversationFeed _feed;
  @override
  String get threadId => _feed.threadId;
  void _checkOpen() {
    if (_feed._admissionsClosed) throw _conversationClosedFailure;
  }

  @override
  Future<ChatBatch> loadOlder({
    required String before,
    required ReadDemand demand,
  }) async {
    _checkOpen();
    return FrbStudioTransport._bridgeCall(
      () async => _chatBatchFromFrb(
        await _feed._native.loadOlder(
          before: before,
          demand: _readDemandToFrb(demand),
        ),
      ),
    );
  }

  @override
  Future<ContentManifestPage> listContents({
    required String itemId,
    String? continuation,
    required ReadDemand demand,
  }) async {
    _checkOpen();
    return FrbStudioTransport._bridgeCall(() async {
      final value = await _feed._native.listContents(
        itemId: itemId,
        continuation: continuation,
        demand: _readDemandToFrb(demand),
      );
      return ContentManifestPage(
        continuation: value.continuation,
        entries: value.entries
            .map(
              (entry) => ContentManifestEntry(
                key: entry.key,
                payload: entry.payload,
                reference: _contentRefFromFrb(entry.reference),
              ),
            )
            .toList(),
      );
    });
  }

  frb_chat_types.BridgeContentRange _range(ContentRange range) =>
      frb_chat_types.BridgeContentRange(
        offset: BigInt.from(range.offset),
        maxBytes: range.maxBytes,
      );
  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) async {
    _checkOpen();
    return FrbStudioTransport._bridgeCall(
      () async => _contentWindowFromFrb(
        await _feed._native.readContent(
          reference: _contentRefToFrb(reference),
          range: _range(range),
        ),
      ),
    );
  }

  @override
  ConversationContentWatch watchContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    _checkOpen();
    return _FrbContentWatch(_feed, reference, range);
  }

  @override
  Future<CurrentCollectionPage> pageCurrent({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) async {
    _checkOpen();
    return FrbStudioTransport._bridgeCall(() async {
      final value = await _feed._native.pageCurrent(
        reference: _collectionToFrb(reference),
        continuation: continuation,
        demand: _readDemandToFrb(demand),
      );
      return CurrentCollectionPage(
        revision: _exactTimelineInt(value.revision, 'current revision'),
        entries: value.entries
            .map(
              (entry) => CurrentCollectionEntry(
                id: entry.id,
                position: _exactSignedTimelineInt(entry.position),
                payload: _payloadFromFrb(entry.payload),
              ),
            )
            .toList(),
        continuation: value.continuation,
      );
    });
  }

  @override
  void requestClose() => _feed.requestClose();
  @override
  Future<void> close() => _feed.close();
}
