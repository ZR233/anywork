part of 'studio_demo_api.dart';

final class _DemoDisplayScript {
  const _DemoDisplayScript(this.memberIds, {required this.work, this.turnId});

  final List<String> memberIds;
  final bool work;
  final String? turnId;
}

final class _DemoSealedBlock {
  const _DemoSealedBlock({
    required this.id,
    required this.members,
    required this.work,
    required this.status,
  });

  final String id;
  final List<({int seq, _DemoItem item})> members;
  final bool work;
  final WorkGroupStatus status;

  int get firstSeq => members.first.seq;
  int get lastSeq => members.last.seq;
}

extension _DemoDisplayHistory on _DemoHistory {
  void declareDisplay(
    String id,
    List<String> memberIds, {
    required bool work,
    String? turnId,
  }) {
    if (displayScripts.containsKey(id) ||
        displayBlocks.any((b) => b.id == id)) {
      throw _demoQueryFailure('Duplicate display story');
    }
    if (memberIds.isEmpty ||
        (!work && memberIds.length != 1) ||
        memberIds.any(displayMembership.containsKey)) {
      throw _demoQueryFailure('Invalid display story membership');
    }
    displayScripts[id] = _DemoDisplayScript(
      List.unmodifiable(memberIds),
      work: work,
      turnId: turnId,
    );
    for (final member in memberIds) {
      displayMembership[member] = id;
    }
  }

  void sealDisplay(
    String id, {
    WorkGroupStatus status = WorkGroupStatus.completed,
  }) {
    final script = displayScripts.remove(id)!;
    final members = [
      for (final memberId in script.memberIds)
        if (completed[memberId] case final item?)
          (seq: itemSequences[memberId]!, item: item),
    ];
    if (members.isEmpty) return;
    members.sort((a, b) => a.seq.compareTo(b.seq));
    displayBlocks.add(
      _DemoSealedBlock(
        id: id,
        members: List.unmodifiable(members),
        work: script.work,
        status: status,
      ),
    );
  }

  void finishDisplayTurn(String turnId, StudioTurnState state) {
    final status = switch (state) {
      FailedStudioTurnState() => WorkGroupStatus.failed,
      CancelledStudioTurnState() => WorkGroupStatus.cancelled,
      _ => WorkGroupStatus.completed,
    };
    final unfinished = [
      for (final entry in displayScripts.entries)
        if (entry.value.turnId == turnId) entry.key,
    ];
    for (final id in unfinished) {
      sealDisplay(id, status: status);
    }
  }
}

final class DemoConversationFeedHandle
    extends _DemoPortProxy<_DemoConversationFeedResource>
    implements ConversationFeedHandle {
  DemoConversationFeedHandle._(super.entry, this._resource);

  final _DemoConversationFeedResource _resource;

  @override
  String get threadId => _resource.threadId;
  @override
  LiveStatusSnapshot get liveStatusSnapshot => _resource.liveStatus;
  @override
  SessionMetaSnapshot get sessionMetaSnapshot => _resource.sessionMeta;
  @override
  Stream<ConversationFeedEvent> get events => _resource.events;

  @override
  Future<TimelinePatch> loadOlder({
    required String cursor,
    int limit = 50,
  }) async => _resource.loadOlder(cursor, limit);

  @override
  Future<List<WorkGroupMember>> loadWorkGroupMembers({
    int? afterSeq,
    int? beforeSeq,
  }) async => _resource.loadMembers(afterSeq, beforeSeq);

  @override
  Future<BodyWindow> readBodyWindow({
    required BodyRef reference,
    required int offset,
    required int maxBytes,
  }) async => _resource.readBody(reference, offset, maxBytes);

  @override
  Future<SessionDetailWindow> readSessionDetail({
    required SessionDetailKind kind,
    required int offset,
    required int maxBytes,
  }) async => _resource.readSessionDetail(kind, offset, maxBytes);

  @override
  Future<TimelinePatch> resetToLatest({int limit = 50}) async =>
      _resource.reset(limit);
}

final class _DemoConversationFeedResource implements ClientResource {
  _DemoConversationFeedResource(
    this._transport,
    this._history,
    ThreadWorkspace workspace,
    int initialLimit,
    this.resourceId,
  ) : threadId = workspace.thread.id {
    liveStatus = _liveSnapshot(workspace);
    _plan = workspace.runtime.plan;
    sessionMeta = _sessionSnapshot(workspace);
    reset(initialLimit);
    _events.add(ConversationLiveStatus(snapshot: liveStatus));
    _events.add(ConversationSessionMeta(snapshot: sessionMeta));
    _history.changes.add(_changed);
    _history.retiring.add(requestClose);
  }

  final DemoStudioTransport _transport;
  final _DemoHistory _history;
  final String threadId;
  @override
  final ClientResourceId resourceId;

  final _events = StreamController<ConversationFeedEvent>();
  late final Stream<ConversationFeedEvent> events = _events.stream.takeWhile(
    (_) => !_closed,
  );
  late LiveStatusSnapshot liveStatus;
  late SessionMetaSnapshot sessionMeta;
  PlanRuntimeView? _plan;
  final String _cursorPrefix = 'demo-feed:${newStudioCorrelationId()}:';
  int _publishedCount = 0;
  int _timelineRevision = 0;
  bool _closed = false;
  void Function()? _retire;

  void bind(ClientAcquisition<_DemoConversationFeedResource> entry) {
    if (_closed) {
      entry.requestClose();
      throw const ClientResourceClosed();
    }
    _history.retiring.remove(requestClose);
    _retire = entry.requestClose;
    _history.retiring.add(_retire!);
    _events.onCancel = entry.requestClose;
  }

  void _checkOpen() {
    if (_closed) throw _conversationClosedFailure;
  }

  SessionDetailWindow readSessionDetail(
    SessionDetailKind kind,
    int offset,
    int maxBytes,
  ) {
    _checkOpen();
    if (offset < 0 || maxBytes < 0) {
      throw _demoQueryFailure('Invalid Demo session detail window');
    }
    final snapshot = sessionMeta;
    final window = _DemoDetailWindowSink(offset, maxBytes.clamp(1, 64 * 1024));
    JsonUtf8Encoder().startChunkedConversion(window)
      ..add(_demoSessionDetail(snapshot, kind, plan: _plan))
      ..close();
    return SessionDetailWindow(
      ownerEpoch: snapshot.ownerEpoch,
      revision: snapshot.revision,
      offset: offset,
      totalBytes: window.totalBytes,
      bytes: window.bytes.takeBytes(),
    );
  }

  String? _cursor(int start) => start == 0 ? null : '$_cursorPrefix$start';

  Iterable<TimelineItem> _items(int start, int end) =>
      _history.displayBlocks.getRange(start, end).map(_history.timelineItem);

  TimelinePatch reset(int limit) {
    _checkOpen();
    final end = _history.displayBlocks.length;
    final start = (end - limit.clamp(1, 512)).clamp(0, end);
    _publishedCount = end;
    final patch = TimelineReset(
      items: _items(start, end),
      hasMoreOlder: start != 0,
      olderCursor: _cursor(start),
      revision: ++_timelineRevision,
    );
    _events.add(ConversationTimeline(patch: patch));
    return patch;
  }

  TimelinePatch loadOlder(String cursor, int limit) {
    _checkOpen();
    final end = cursor.startsWith(_cursorPrefix)
        ? int.tryParse(cursor.substring(_cursorPrefix.length))
        : null;
    if (end == null || end < 1 || end > _publishedCount) {
      throw _demoQueryFailure('Invalid Demo timeline cursor');
    }
    final start = (end - limit.clamp(1, 512)).clamp(0, end);
    return TimelinePrependOlder(
      items: _items(start, end),
      hasMoreOlder: start != 0,
      olderCursor: _cursor(start),
    );
  }

  List<WorkGroupMember> loadMembers(int? afterSeq, int? beforeSeq) {
    _checkOpen();
    return List.unmodifiable([
      for (final block in _history.displayBlocks)
        if (block.work)
          for (final member in block.members)
            if ((afterSeq == null || member.seq > afterSeq) &&
                (beforeSeq == null || member.seq < beforeSeq))
              _history.workMember(member.item, member.seq),
    ]);
  }

  BodyWindow readBody(BodyRef reference, int offset, int maxBytes) {
    _checkOpen();
    if (reference.databaseId != _history.epoch) throw _demoMissing();
    final stored = _history.completed[reference.ownerEventId]?.textFor(
      reference.bodyKey,
    );
    if (stored == null ||
        reference.bodyId !=
            _demoBodyId(reference.ownerEventId, reference.bodyKey)) {
      throw _demoMissing();
    }
    final bytes = utf8.encode(stored);
    if (offset < 0 ||
        offset > bytes.length ||
        maxBytes < 0 ||
        reference.byteLength != bytes.length) {
      throw _demoQueryFailure('Invalid Demo body window');
    }
    final end = (offset + maxBytes.clamp(1, 64 * 1024)).clamp(
      offset,
      bytes.length,
    );
    final window = bytes.sublist(offset, end);
    String? text;
    try {
      text = utf8.decode(window);
    } on FormatException {
      // The range can split a UTF-8 character. Preserve the original bytes.
    }
    return BodyWindow(
      offset: offset,
      text: text,
      bytesBase64: text == null ? base64Encode(window) : null,
      totalBytes: bytes.length,
      eof: end == bytes.length,
    );
  }

  void _changed(ThreadWorkspace workspace) {
    if (_closed) return;
    final end = _history.displayBlocks.length;
    if (end > _publishedCount) {
      final patch = TimelineAppend(items: _items(_publishedCount, end));
      _publishedCount = end;
      _events.add(ConversationTimeline(patch: patch));
      for (final item in patch.items) {
        if (item case TimelineUserMessage(:final id, inputId: final inputId?)) {
          _events.add(ConversationInputPresented(inputId: inputId, itemId: id));
        }
      }
    }
    final live = _liveSnapshot(workspace, previous: liveStatus);
    if (live != liveStatus) {
      liveStatus = live;
      _events.add(ConversationLiveStatus(snapshot: live));
    }
    _plan = workspace.runtime.plan;
    final meta = _sessionSnapshot(workspace);
    if (meta != sessionMeta) {
      sessionMeta = meta;
      _events.add(ConversationSessionMeta(snapshot: meta));
    }
  }

  SessionMetaSnapshot _sessionSnapshot(ThreadWorkspace workspace) =>
      _demoSessionMeta(
        workspace,
        _history.epoch,
        _transport._demoThreadMcp(threadId),
      );

  LiveStatusSnapshot _liveSnapshot(
    ThreadWorkspace workspace, {
    LiveStatusSnapshot? previous,
  }) {
    final pending = _transport._pendingItemsOf(threadId);
    final activity = workspace.activity;
    final startedAt = workspace.activeTurn?.updatedAt.millisecondsSinceEpoch;
    final text = pending
        .where((item) => item.content.kind == _DemoContentKind.text)
        .lastOrNull;
    final reasoning = pending
        .where((item) => item.content.kind == _DemoContentKind.thinking)
        .lastOrNull;
    final phase =
        _history.reconnecting ??
        switch ((text, activity?.kind, workspace.activeTurn)) {
          (_, ThreadActivityKind.stopping, _) => LiveStatusStopping(
            startedAtMs: startedAt,
          ),
          (final item?, _, _) => LiveStatusStreamingText(
            attemptId: item.turnId ?? item.id,
            itemId: item.id,
            text: item.textFor('body') ?? '',
            startedAtMs: item.updatedAt.millisecondsSinceEpoch,
          ),
          (_, ThreadActivityKind.compacting, _) => LiveStatusCompacting(
            manual: workspace.activeTurn == null,
            startedAtMs: startedAt,
          ),
          (_, _, null) => const LiveStatusIdle(),
          _ => LiveStatusWorking(
            items: [
              for (final item in pending)
                if (item.content.invocation case final invocation?)
                  WorkGroupToolCall(
                    id: item.id,
                    seq: 0,
                    callId: invocation.toolCallId,
                    turnId: item.turnId,
                    toolName: invocation.name,
                    presentationContract: invocation.presentationContract,
                    status: 'running',
                    summary: activity?.summary ?? invocation.name,
                    payloadJson: _history._toolPayload(item),
                    bodies: _history._toolBodies(item),
                    startedAtMs: item.updatedAt.millisecondsSinceEpoch,
                  ),
            ],
            reasoningPreview:
                reasoning?.textFor('part.summaryText.0') ??
                activity?.thinkingSummary,
            startedAtMs: startedAt,
          ),
        };
    final attentions = [
      for (final interaction in workspace.interactions)
        LiveAttention(
          id: interaction.id,
          kind: interaction.kind.name,
          summary: interaction.title,
        ),
    ];
    final next = LiveStatusSnapshot(
      revision: previous?.revision ?? 0,
      phase: phase,
      attentions: attentions,
      suppressedByInteraction: attentions.isNotEmpty,
    );
    if (previous == null || next == previous) return next;
    return LiveStatusSnapshot(
      revision: previous.revision + 1,
      phase: phase,
      attentions: attentions,
      suppressedByInteraction: attentions.isNotEmpty,
    );
  }

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    _history.changes.remove(_changed);
    _history.retiring.remove(_retire ?? requestClose);
    // Dart's done Future requires a listening, unpaused consumer. The source
    // is already detached, so the resource join does not depend on that consumer.
    unawaited(_events.close());
  }

  @override
  Future<void> close() async => requestClose();

  @override
  Future<void> retryClose() => close();
}

SessionMetaSnapshot _demoSessionMeta(
  ThreadWorkspace workspace,
  String ownerEpoch,
  ThreadMcpStateSnapshot mcp,
) {
  final thread = workspace.thread;
  final runtime = workspace.runtime;
  final planHead = runtime.plan?.copyWith(document: null);
  final liveUsage = runtime.liveUsage;
  final diagnostics = runtime.usageDiagnostics;
  final cache = runtime.cacheUsage;
  final updatedAt = _demoSeconds(thread.updatedAt);
  final runtimeUsage = ConversationRuntimeUsage(
    diagnostics: diagnostics,
    hasIncompleteUsage: runtime.hasIncompleteUsage,
    modelId: runtime.modelId,
    contextWindow: runtime.contextWindow == 0 ? null : runtime.contextWindow,
    maxContextWindow: runtime.maxContextWindow,
    autoCompactLimit: runtime.autoCompactLimit,
    latestContextTokens: runtime.contextTokens,
    promptTokens: runtime.promptTokens,
    completionTokens: runtime.completionTokens,
    cachedPromptTokens: runtime.cachedPromptTokens,
    cacheWriteTokens: runtime.cacheWriteTokens,
    reasoningTokens: runtime.reasoningTokens,
    inferenceCount: runtime.inferenceCount,
    totalTokens: runtime.totalTokens,
    cacheUsage: cache,
    estimatedCosts: runtime.estimatedCosts,
    estimatedCacheSavings: runtime.estimatedCacheSavings,
    hasUnpricedUsage: runtime.hasUnpricedUsage,
    promptGeneration: runtime.promptGeneration,
    promptCachePolicy: runtime.promptCachePolicy,
    prefixChangedReason: ConversationPromptPrefixChangedReason.values
        .asNameMap()[runtime.prefixChangedReason],
    updatedAt: updatedAt,
  );
  return SessionMetaSnapshot(
    threadId: thread.id,
    status: switch ((workspace.activeTurn?.state, workspace.activity?.kind)) {
      (
        _,
        ThreadActivityKind.awaitingApproval || ThreadActivityKind.awaitingInput,
      ) =>
        ThreadStatusView.waitingInteraction,
      (_, ThreadActivityKind.stopping) => ThreadStatusView.cancelling,
      (QueuedStudioTurnState(), _) => ThreadStatusView.queued,
      (RunningStudioTurnState(), _) => ThreadStatusView.running,
      _ => thread.status,
    },
    title: thread.title,
    parentThreadId: thread.parentThreadId,
    rootThreadId: thread.rootThreadId.isEmpty ? thread.id : thread.rootThreadId,
    ownerEpoch: ownerEpoch,
    revision: workspace.revision,
    activeTurn: workspace.activeTurn,
    lastTurn: workspace.lastTurn,
    activity: workspace.activity,
    usage: SessionUsageSummary(
      appliedSequence: workspace.revision,
      binding: runtime.modelId.isEmpty
          ? null
          : SessionModelUsageBinding(
              model: runtime.modelId,
              contextWindow: runtime.contextWindow,
              maxContextWindow: runtime.maxContextWindow,
              autoCompactLimit: runtime.autoCompactLimit,
            ),
      totals: SessionUsageTotals(
        inferenceCount: runtime.inferenceCount,
        promptTokens: runtime.promptTokens,
        completionTokens: runtime.completionTokens,
        cachedPromptTokens: runtime.cachedPromptTokens,
        cacheWriteTokens: runtime.cacheWriteTokens,
        reasoningTokens: runtime.reasoningTokens,
        totalTokens: runtime.totalTokens,
      ),
      cache: SessionUsageCache(
        inputTokens: cache.inputTokens,
        readTokens: cache.cacheReadTokens,
        sampleCount: cache.sampleCount,
        incomplete: cache.hasIncompleteUsage,
      ),
      context: SessionUsageContext(
        tokens: runtime.contextTokens,
        latestCall: diagnostics.latestCall,
      ),
      throughput: SessionUsageThroughput(
        turnId: liveUsage?.turnId ?? workspace.lastTurn?.turnId ?? '',
        completionTokens:
            liveUsage?.completionTokens ?? runtime.turnCompletionTokens,
        responseMillis: liveUsage?.responseMillis ?? runtime.turnResponseMillis,
      ),
      diagnostics: SessionUsageDiagnostics(
        incompleteCalls: diagnostics.incompleteCalls,
        missingCalls: diagnostics.missingCalls,
        partialCalls: diagnostics.partialCalls,
        invalidCalls: diagnostics.invalidCalls,
        overflowCalls: diagnostics.overflowCalls,
        byOutcome: diagnostics.byOutcome,
        byPurpose: diagnostics.byPurpose,
        otherPurposeCalls: diagnostics.otherPurposeCalls,
        byIssue: diagnostics.byIssue,
        recentGaps: diagnostics.recentGaps,
        legacyUnknown: diagnostics.legacyUnknown,
        legacyIncomplete: runtime.hasIncompleteUsage,
        countsOverflowed: diagnostics.countsOverflowed,
      ),
      pricing: SessionUsagePricing(
        incomplete: runtime.hasUnpricedUsage,
        estimatedCosts: runtime.estimatedCosts,
        estimatedCacheSavings: runtime.estimatedCacheSavings,
      ),
    ),
    contextMetrics: runtimeUsage,
    modelRoute: workspace.modelRoute,
    runtime: ConversationRuntimeSnapshot(
      threadId: thread.id,
      deferred: runtime.deferred,
      usage: runtimeUsage,
      liveUsage: liveUsage,
      turnCompletionTokens: runtime.turnCompletionTokens,
      turnResponseMillis: runtime.turnResponseMillis,
      todo: workspace.todo,
      activeSkills: runtime.activeSkills,
      activeMcpServers: runtime.activeMcpServers,
      activeLspServers: runtime.activeLspServers,
      mcpHealth: ConversationMcpHealthSnapshot(
        generation: mcp.generation,
        servers: [
          for (final server in mcp.servers)
            ConversationMcpAvailabilityDescriptor(
              server: ConversationMcpServerDescriptor(
                id: server.id,
                source: server.builtIn ? 'builtIn' : 'user',
                transport: server.transport,
                endpoint: server.endpointSummary,
                builtIn: server.builtIn,
              ),
              availability: server.lifecycle.name,
              message: server.message,
              lastCheckedAt: server.lastCheckedAt,
              toolCount: server.toolCount,
            ),
        ],
      ),
      workflow: runtime.workflow,
      plan: planHead,
      execution: runtime.execution,
      continuation: runtime.continuation,
      updatedAt: updatedAt,
    ),
    storageState: workspace.storage,
    interactions: workspace.interactions,
    pendingInteractionCount: workspace.interactions.length,
    plan: planHead,
    mode: thread.mode,
    executionPresent: runtime.execution != null,
  );
}

String _demoBodyId(String owner, String key) => jsonEncode([owner, key]);

extension _DemoFeedProjection on _DemoHistory {
  BodyRef _bodyRef(_DemoItem item, String key, String role) {
    final text = item.content.fields[key]!;
    final length = utf8.encode(text).length;
    return BodyRef(
      databaseId: epoch,
      bodyId: _demoBodyId(item.id, key),
      ownerEventId: item.id,
      bodyKey: key,
      role: role,
      byteLength: length,
      mediaType: 'text/plain',
      inlineText: length <= 4096 ? text : null,
    );
  }

  Iterable<BodyRef> _toolBodies(_DemoItem item) sync* {
    for (final key in item.content.fields.keys) {
      yield _bodyRef(
        item,
        key,
        key == 'tool.arguments' ? 'tool_arguments' : 'tool_output',
      );
    }
  }

  String _toolPayload(_DemoItem item) => jsonEncode({
    'contract': 'anywork.event/1',
    'type': 'tool',
    'data': item.content.descriptor!['data'],
    'bodies': [
      for (final ref in _toolBodies(item))
        {
          'key': ref.bodyKey,
          'role': ref.role,
          'byteLength': ref.byteLength,
          'mediaType': ref.mediaType,
          if (ref.inlineText != null) 'inlineText': ref.inlineText,
        },
    ],
  });

  TimelineItem timelineItem(_DemoSealedBlock block) {
    if (block.work) {
      final names = [
        for (final member in block.members)
          if (member.item.content.invocation case final invocation?)
            invocation.name,
      ];
      return TimelineWorkGroup(
        id: 'work:${block.firstSeq}',
        firstSeq: block.firstSeq,
        lastSeq: block.lastSeq,
        afterBoundarySeq: block.firstSeq == 1 ? null : block.firstSeq - 1,
        beforeBoundarySeq: block.lastSeq + 1,
        memberCount: block.members.length,
        summary: names.isEmpty ? 'Reasoning' : names.join(', '),
        status: block.status,
        startedAtMs: block.members.first.item.updatedAt.millisecondsSinceEpoch,
        finishedAtMs: block.members.last.item.updatedAt.millisecondsSinceEpoch,
      );
    }
    final (:seq, :item) = block.members.single;
    final id = 'msg:$seq';
    final occurredAt = item.updatedAt.millisecondsSinceEpoch;
    final data = _demoItemData(item);
    return switch (item.content.descriptor!['type']) {
      'text'
          when item.content.textChannel == ThreadTextChannel.user ||
              item.content.textChannel == ThreadTextChannel.parentAgent =>
        TimelineUserMessage(
          id: id,
          seq: seq,
          turnId: item.turnId,
          inputId: item.id,
          channel: item.content.textChannel!.name,
          text: item.textFor('body')!,
          attachments: data['attachments'] as List<Object?>,
          occurredAtMs: occurredAt,
        ),
      'text' => _assistantText(id, seq, item, occurredAt),
      'plan' => _planResolution(id, seq, item, data, occurredAt),
      'tool' => TimelineStandaloneTool(
        id: id,
        seq: seq,
        turnId: item.turnId,
        callId: (data['invocation'] as Map)['toolCallId'] as String,
        toolName: (data['invocation'] as Map)['name'] as String,
        presentationContract:
            (data['invocation'] as Map)['presentationContract'] as String?,
        state: _demoItemOutcome(data, 'state'),
        summary: (data['invocation'] as Map)['name'] as String,
        payloadJson: _toolPayload(item),
        bodies: _toolBodies(item),
        occurredAtMs: occurredAt,
      ),
      'turn' => TimelineTurnOutcome(
        id: id,
        seq: seq,
        turnId: item.turnId,
        inputId: data['inputId'] as String?,
        outcome: _demoItemOutcome(data, 'outcome'),
        turnFailure: StudioTurnFailureView.fromJson(
          (data['outcome'] as Map)['data']['failure'],
        ),
        occurredAtMs: occurredAt,
      ),
      'connection' => TimelineConnectionNotice(
        id: id,
        seq: seq,
        turnId: item.turnId,
        scope: 'model',
        state: 'reconnecting',
        transport: 'http',
        attempt: data['attempt'] as int,
        maxAttempts: data['maxAttempts'] as int,
        recoverable: true,
        reason: data['message'] as String,
        occurredAtMs: occurredAt,
      ),
      final type => TimelineFallback(
        id: id,
        seq: seq,
        eventId: item.id,
        eventKind: '$type',
        reason: 'Unsupported Demo item',
        occurredAtMs: occurredAt,
      ),
    };
  }

  TimelineAssistantText _assistantText(
    String id,
    int seq,
    _DemoItem item,
    int occurredAt,
  ) {
    final body = _bodyRef(item, 'body', 'body');
    final data = _demoItemData(item);
    final channel = item.content.textChannel!;
    final outcome = _demoItemOutcome(data, 'outcome');
    return TimelineAssistantText(
      id: id,
      seq: seq,
      turnId: item.turnId,
      attemptId: item.turnId,
      channel: channel == ThreadTextChannel.finalAnswer
          ? 'final'
          : channel.name,
      text: body.inlineText ?? '',
      bodyRef: body,
      isFinalTurnDelivery:
          channel == ThreadTextChannel.finalAnswer && outcome == 'completed',
      outcome: outcome,
      occurredAtMs: occurredAt,
    );
  }

  TimelinePlanResolution _planResolution(
    String id,
    int seq,
    _DemoItem item,
    Map<String, Object?> data,
    int occurredAt,
  ) {
    final document = _bodyRef(item, 'plan.document', 'body');
    return TimelinePlanResolution(
      id: id,
      seq: seq,
      turnId: item.turnId,
      decision: data['decision'] as String,
      document: document.inlineText,
      documentRef: document,
      feedback: item.textFor('plan.feedback'),
      occurredAtMs: occurredAt,
    );
  }

  WorkGroupMember workMember(_DemoItem item, int seq) {
    final data = _demoItemData(item);
    final occurredAt = item.updatedAt.millisecondsSinceEpoch;
    if (item.content.invocation case final invocation?) {
      return WorkGroupToolCall(
        id: 'call:${invocation.toolCallId}',
        seq: seq,
        callId: invocation.toolCallId,
        toolName: invocation.name,
        presentationContract: invocation.presentationContract,
        status: _demoItemOutcome(data, 'state'),
        summary: invocation.name,
        arguments: _bodyRef(
          item,
          'tool.arguments',
          'tool_arguments',
        ).inlineText,
        resultPreview: item.textFor('tool.result') == null
            ? null
            : _bodyRef(item, 'tool.result', 'tool_output').inlineText,
        payloadJson: _toolPayload(item),
        bodies: _toolBodies(item),
        finishedAtMs: occurredAt,
      );
    }
    final summary = item.textFor('part.summaryText.0') ?? '';
    final body = item.textFor('part.reasoningText.0') != null
        ? _bodyRef(item, 'part.reasoningText.0', 'body')
        : item.textFor('part.summaryText.0') != null
        ? _bodyRef(item, 'part.summaryText.0', 'reasoning_summary')
        : null;
    return WorkGroupReasoning(
      id: item.id,
      seq: seq,
      text: body?.inlineText ?? '',
      summary: summary,
      bodyRef: body,
      outcome: _demoItemOutcome(data, 'outcome'),
      finishedAtMs: occurredAt,
    );
  }
}

String _demoItemOutcome(Map<String, Object?> data, String key) =>
    (data[key] as Map<String, Object?>)['kind'] as String;

Map<String, Object?> _demoItemData(_DemoItem item) =>
    item.content.descriptor!['data'] as Map<String, Object?>;
