part of 'studio_api.dart';

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
  },
  messages: value.messages
      .map(
        (item) =>
            ChatMessage(id: item.id, payload: _payloadFromFrb(item.payload)),
      )
      .toList(),
  before: value.before,
  current: value.current == null ? null : _currentFromFrb(value.current!),
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
  active: value.active == null ? null : _currentActivityFromFrb(value.active!),
  activeTurn: value.activeTurn == null
      ? null
      : CurrentTurnHead(
          id: value.activeTurn!.id,
          phase: StudioTurnActivity.values.byName(value.activeTurn!.phase.name),
          childrenParentId: value.activeTurn!.childrenParentId,
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
