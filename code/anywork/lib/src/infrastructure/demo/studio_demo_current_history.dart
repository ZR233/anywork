part of 'studio_demo_api.dart';

final class _DemoHistoryReader implements HistoryReader {
  _DemoHistoryReader(this._api, this.threadId, this._history)
    : reader = _DemoReadSource(
        _api,
        threadId,
        _history,
        const ChatScope.conversation(),
      ) {
    _api._ownedHistoryReaders.add(reader);
  }

  final DemoStudioTransport _api;
  final String _readerId = newStudioCorrelationId();
  @override
  final String threadId;
  final _DemoHistory _history;
  final _DemoReadSource reader;
  final Set<Completer<void>> _waiters = {};
  bool _closed = false;

  @override
  OpenHistory get metadata => OpenHistory(
    readerId: 'demo-history:$_readerId',
    historyProtocolVersion: historyProtocolVersion,
  );

  void _checkOpen() {
    if (_closed || _api._runtimeExiting) throw _conversationClosedFailure;
  }

  HistoryCut _cut() => HistoryCut('demo-cut:${_history.displayHead}');

  int _cutFrontier(HistoryCut cut) {
    const prefix = 'demo-cut:';
    final raw = cut.token.startsWith(prefix)
        ? cut.token.substring(prefix.length)
        : null;
    final frontier = raw == null ? null : int.tryParse(raw);
    if (frontier == null || frontier < 0 || frontier > _history.displayHead) {
      throw _demoStale();
    }
    return frontier;
  }

  @override
  Future<HistoryCut> capture() async {
    _checkOpen();
    return _cut();
  }

  @override
  Future<HistoryTimelinePage> timelinePage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) async {
    _checkOpen();
    final page = reader.historyPage(
      ReadDemand(maxItems: demand.maxRows, maxBytes: demand.maxBytes),
      before: cursor,
      ceiling: cut == null ? null : _cutFrontier(cut),
    );
    return HistoryTimelinePage(
      cut: cut ?? _cut(),
      items: _historyItems(page.blocks),
      next: page.before,
    );
  }

  @override
  Future<HistoryWorkRangePage> workRangePage({
    int? afterSeq,
    int? beforeSeq,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) async {
    _checkOpen();
    WorkDisplayBlock? work;
    int? blockOrder;
    for (final candidate in _history.displayBlocks) {
      final body = candidate.body;
      if (body is! WorkDisplayBlock) continue;
      final candidateBefore =
          body.members.beforeSeq ??
          (body.groupClosed ? candidate.blockOrder + 1 : null);
      if (body.members.afterSeq == afterSeq && candidateBefore == beforeSeq) {
        work = body;
        blockOrder = candidate.blockOrder;
        break;
      }
      if (afterSeq == null && beforeSeq == null && candidate.blockOrder >= 0) {
        work ??= body;
        blockOrder ??= candidate.blockOrder;
      }
    }
    if (work == null || blockOrder == null) {
      throw _demoMissing();
    }
    final heads =
        _history.displayHeads[work.members] ?? const <DisplayMemberHead>[];
    final start = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    final selected = heads.skip(start).take(demand.maxRows).toList();
    final next = start + selected.length < heads.length
        ? '${start + selected.length}'
        : null;
    return HistoryWorkRangePage(
      cut: cut ?? work.members.cut,
      afterSeq: afterSeq,
      beforeSeq: beforeSeq,
      events: [
        for (final head in selected)
          _eventRecordFromRecord(
            head.record,
            seq: head.memberOrder,
            rowKey: head.memberKey,
            timelineRole: HistoryTimelineRole.work,
          ),
      ],
      next: next,
    );
  }

  @override
  Future<HistoryBusinessPage> turnsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) async {
    _checkOpen();
    final turn = _api._demoWorkspace(threadId).lastTurn;
    return HistoryBusinessPage(
      cut: cut ?? _cut(),
      entries: [
        if (turn != null)
          HistoryBusinessRowEntry(
            rowKey: 'turn:${turn.turnId}',
            anchorSeq: turn.revision,
            headSeq: turn.revision,
            head: TurnHistoryBusinessRow(
              HistoryTurnHead(
                turnId: turn.turnId,
                inputId: turn.inputId,
                runId: null,
                state: switch (turn.state) {
                  QueuedStudioTurnState() => HistoryTurnState.queued,
                  RunningStudioTurnState() => HistoryTurnState.running,
                  CompletedStudioTurnState() => HistoryTurnState.completed,
                  CancelledStudioTurnState() => HistoryTurnState.cancelled,
                  FailedStudioTurnState() => HistoryTurnState.failed,
                  BudgetLimitedStudioTurnState() =>
                    HistoryTurnState.budgetLimited,
                },
                phase: switch (turn.state) {
                  RunningStudioTurnState(:final activity) =>
                    CurrentTurnPhase.values.byName(activity.name),
                  _ => null,
                },
                contextDisposition: HistoryContextDisposition.active,
                queuedAt: switch (turn.state) {
                  QueuedStudioTurnState(:final queuedAt) => queuedAt,
                  _ => null,
                },
                startedAt: switch (turn.state) {
                  RunningStudioTurnState(:final startedAt) => startedAt,
                  CompletedStudioTurnState(:final startedAt) => startedAt,
                  CancelledStudioTurnState(:final startedAt) => startedAt,
                  FailedStudioTurnState(:final startedAt) => startedAt,
                  BudgetLimitedStudioTurnState(:final startedAt) => startedAt,
                  QueuedStudioTurnState() => null,
                },
                finishedAt: switch (turn.state) {
                  CompletedStudioTurnState(:final completedAt) => completedAt,
                  CancelledStudioTurnState(:final completedAt) => completedAt,
                  FailedStudioTurnState(:final completedAt) => completedAt,
                  BudgetLimitedStudioTurnState(:final completedAt) =>
                    completedAt,
                  QueuedStudioTurnState() || RunningStudioTurnState() => null,
                },
                updatedAt: turn.updatedAt.millisecondsSinceEpoch ~/ 1000,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Future<HistoryEventsPage> eventsPage({
    required HistoryEventsQuery query,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) async {
    _checkOpen();
    final all = [
      for (final item in _history.items)
        _eventRecordFromRecord(
          DisplayRecord(
            atom: item.message,
            contentSource: CompletedOriginal(completionId: item.message.id),
          ),
          seq: item.order,
          rowKey: 'single:${item.message.id}',
          timelineRole: HistoryTimelineRole.divider,
        ),
    ];
    final filtered = switch (query) {
      EntityHistoryEvents(:final entityId) =>
        all.where((event) => event.entityId == entityId).toList(),
      TurnHistoryEvents(:final turnId) =>
        all.where((event) => event.turnId == turnId).toList(),
      SourceHistoryEvents(:final source) =>
        all.where((event) => event.source == source).toList(),
      CallHistoryEvents(:final callId) =>
        all.where((event) => event.callId == callId).toList(),
      MessageHistoryEvents(:final messageId) =>
        all.where((event) => event.messageId == messageId).toList(),
      AttemptHistoryEvents(:final runId, :final attemptId) =>
        all
            .where(
              (event) => event.runId == runId && event.attemptId == attemptId,
            )
            .toList(),
      AllHistoryEvents() ||
      OriginalsHistoryEvents() ||
      TextOriginalHistoryEvents() => all,
    };
    final start = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    final selected = filtered.skip(start).take(demand.maxRows).toList();
    return HistoryEventsPage(
      cut: cut ?? _cut(),
      entries: selected,
      next: start + selected.length < filtered.length
          ? '${start + selected.length}'
          : null,
    );
  }

  @override
  Future<HistoryEventRecord> readEvent({
    required String eventId,
    required HistoryDemand demand,
  }) async {
    _checkOpen();
    return (await eventsPage(
          query: EntityHistoryEvents(eventId),
          demand: demand,
        )).entries.firstOrNull ??
        (throw _demoMissing());
  }

  @override
  Future<HistoryBodyPage> listBodies({
    required String eventId,
    String? cursor,
    required HistoryDemand demand,
  }) async {
    _checkOpen();
    final bodies = <HistoryBodyEntry>[];
    var ordinal = 0;
    for (final entry in (_history.bodies[eventId] ?? const {}).entries) {
      bodies.add(
        HistoryBodyEntry(
          ordinal: ordinal++,
          bodyKey: entry.key,
          role: const HistoryBodyRole(HistoryBodyRoleKind.body),
          reference: _historyBodyRef(eventId, entry.key, entry.value.length),
          mediaType: 'text/plain; charset=utf-8',
        ),
      );
    }
    final payload = _history.payloads[eventId];
    if (payload != null) {
      bodies.insert(
        0,
        HistoryBodyEntry(
          ordinal: 0,
          bodyKey: 'canonical_payload',
          role: const HistoryBodyRole(HistoryBodyRoleKind.canonicalPayload),
          reference: _historyBodyRef(
            eventId,
            'canonical_payload',
            payload.length,
          ),
        ),
      );
    }
    final start = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    final selected = bodies.skip(start).take(demand.maxRows).toList();
    return HistoryBodyPage(
      ownerEventId: eventId,
      entries: selected,
      next: start + selected.length < bodies.length
          ? '${start + selected.length}'
          : null,
    );
  }

  @override
  Future<HistoryBodyWindow> readBody({
    required HistoryEventBodyRef reference,
    required int offset,
    required int maxBytes,
  }) async {
    _checkOpen();
    final body = reference.bodyKey == 'canonical_payload'
        ? _history.payloads[reference.ownerEventId]
        : _history.bodies[reference.ownerEventId]?[reference.bodyKey];
    if (body == null) throw _demoMissing();
    return HistoryBodyWindow(
      offset: offset,
      bytes: body.range(offset, maxBytes),
      totalLength: body.length,
      mediaType: 'text/plain; charset=utf-8',
    );
  }

  @override
  Future<HistoryAccounting?> accounting({HistoryCut? cut}) async => null;

  @override
  Future<HistoryBusinessPage> costsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) async => HistoryBusinessPage(cut: cut ?? _cut(), entries: const []);

  @override
  Future<HistoryCut> waitChanged(HistoryCut after) async {
    _checkOpen();
    final afterFrontier = _cutFrontier(after);
    final completer = Completer<void>();
    void wake(_DemoChange _) {
      if (_history.displayHead > afterFrontier && !completer.isCompleted) {
        completer.complete();
      }
    }

    _waiters.add(completer);
    _history.changes.add(wake);
    wake(const _DemoChange(null));
    try {
      await completer.future;
      _checkOpen();
      return _cut();
    } finally {
      _waiters.remove(completer);
      _history.changes.remove(wake);
    }
  }

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    for (final waiter in _waiters.toList()) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _waiters.clear();
    reader.requestClose();
  }

  @override
  Future<void> close() async {
    requestClose();
    await reader.close();
  }

  HistoryEventBodyRef _historyBodyRef(String owner, String key, int length) =>
      HistoryEventBodyRef(
        databaseId: _history.epoch,
        ownerEventId: owner,
        bodyKey: key,
        bodyId: 'demo:$owner:$key',
        byteStart: 0,
        byteLength: length,
      );

  List<HistoryTimelineItem> _historyItems(List<DisplayBlock> blocks) => [
    for (final block in blocks)
      switch (block.body) {
        WorkDisplayBlock(
          :final timing,
          :final members,
          :final memberCount,
          :final groupClosed,
        ) =>
          WorkRangeTimelineItem(
            HistoryWorkRange(
              rangeId: members.blockId,
              afterSeq: members.afterSeq,
              beforeSeq:
                  members.beforeSeq ??
                  (groupClosed ? block.blockOrder + 1 : null),
              firstSeq: block.blockOrder,
              lastSeq: members.headSeq,
              startedAt: timing.startedAtMillis,
              endedAt: timing.finishedAtMillis,
              runId: members.runId,
              eventCount: memberCount > 0 ? memberCount : 1,
            ),
          ),
        SingleDisplayBlock(:final record, :final visibility) =>
          DividerTimelineItem(
            _eventRecordFromRecord(
              record,
              seq: block.blockOrder,
              rowKey: block.id,
              timelineRole: HistoryTimelineRole.divider,
              visibility: visibility,
            ),
          ),
      },
  ];

  HistoryEventRecord _eventRecordFromRecord(
    DisplayRecord record, {
    required int seq,
    required String rowKey,
    required HistoryTimelineRole timelineRole,
    HistorySingleVisibility? visibility,
  }) {
    final atom = record.atom;
    final startedAt = atom.startedAt;
    final finishedAt = atom.finishedAt;
    final payloadBody = _history.payloads[atom.id];
    Map<String, Object?>? payloadMap;
    if (payloadBody != null) {
      try {
        final decoded = jsonDecode(
          utf8.decode(payloadBody.range(0, payloadBody.length)),
        );
        if (decoded is Map<String, Object?>) payloadMap = decoded;
      } on FormatException {
        // Non-UTF-8 or non-JSON demo payload falls back to atom metadata below.
        payloadMap = null;
      }
    }

    final itemBodies = _history.bodies[atom.id];
    final bodiesJson = <Map<String, Object?>>[];
    if (itemBodies != null && itemBodies.isNotEmpty) {
      for (final entry in itemBodies.entries) {
        final bytes = entry.value.range(0, entry.value.length);
        final ref = _historyBodyRef(atom.id, entry.key, bytes.length);
        String? inlineText;
        if (bytes.length <= 16384) {
          try {
            inlineText = utf8.decode(bytes);
          } on FormatException {
            inlineText = null;
          }
        }
        bodiesJson.add({
          'key': entry.key,
          'role': switch (entry.key) {
            'tool.arguments' => 'toolArguments',
            'tool.result' => 'toolOutput',
            _ when entry.key.startsWith('part.summaryText.') =>
              'reasoningSummary',
            'tool.output-artifacts' => 'attachment',
            _ => 'body',
          },
          'byteLength': bytes.length,
          'inlineText': ?inlineText,
          if (inlineText == null)
            'reference': {
              'databaseId': ref.databaseId,
              'ownerEventId': ref.ownerEventId,
              'bodyKey': ref.bodyKey,
              'bodyId': ref.bodyId,
              'byteStart': ref.byteStart,
              'byteLength': ref.byteLength,
            },
        });
      }
    } else if (payloadMap?['bodies'] case final List<Object?> declared) {
      for (final item in declared) {
        if (item is Map<String, Object?>) bodiesJson.add(item);
      }
    }

    final itemType =
        payloadMap?['type'] as String? ??
        switch (atom.kind) {
          ChatAtomKind.input || ChatAtomKind.text => 'text',
          ChatAtomKind.reasoning => 'thinking',
          ChatAtomKind.toolCall => 'tool',
          ChatAtomKind.plan => 'plan',
          ChatAtomKind.turnReceipt => 'turn',
          ChatAtomKind.skill => 'skill',
          ChatAtomKind.fileChange => 'file',
          ChatAtomKind.agent => 'agent',
          ChatAtomKind.inference => 'inference',
          ChatAtomKind.compaction => 'contextCompaction',
          _ => 'raw',
        };
    final kind = switch (atom.kind) {
      ChatAtomKind.input => 'input_accepted',
      ChatAtomKind.toolCall => switch (atom.lifecycle) {
        ActiveChatAtom() => 'tool_called',
        TerminalChatAtom() => 'tool_completed',
      },
      ChatAtomKind.reasoning => 'thinking_completed',
      _ => 'text_completed',
    };
    final envelope = <String, Object?>{
      'contract': 'anywork.event/1',
      'type': itemType,
      'meta': {
        'entityId': atom.id,
        'entityKind': atom.kind.name,
        'delivery': atom.delivery.name,
        'state': switch (atom.lifecycle) {
          ActiveChatAtom(:final status) => {
            'kind': 'knownActive',
            'status': status.name,
          },
          TerminalChatAtom(:final outcome) => {
            'kind': 'knownTerminal',
            'outcome': outcome.name,
          },
        },
        if (startedAt != null)
          'startedAt': startedAt * Duration.millisecondsPerSecond,
        if (finishedAt != null)
          'finishedAt': finishedAt * Duration.millisecondsPerSecond,
        if (atom.textChannel != null) 'textChannel': atom.textChannel!.name,
        if (visibility != null) 'singleVisibility': visibility.name,
        if (atom.contentPresent != null) 'contentPresent': atom.contentPresent,
        if (atom.tool != null)
          'tool': {'callId': atom.tool!.callId, 'name': atom.tool!.name},
      },
      'data': payloadMap?['data'] ?? <String, Object?>{},
      'bodies': bodiesJson,
      if (record.contentSource case FrozenObservation(:final capturedAt)
          when capturedAt != null)
        'capturedAt': capturedAt,
    };

    return HistoryEventRecord(
      seq: seq,
      eventId: atom.id,
      kind: kind,
      timelineRole: timelineRole,
      occurredAt: startedAt == null
          ? null
          : startedAt * Duration.millisecondsPerSecond,
      recordedAt: seq,
      runId: record.runId,
      turnId: atom.turnId,
      attemptId: atom.attemptId,
      callId: record.callId ?? atom.tool?.callId,
      entityId: atom.id,
      toolName: atom.tool?.name,
      source: atom.source,
      rowKey: rowKey,
      payloadSchema: 'anywork.event/1',
      payloadJson: jsonEncode(envelope),
    );
  }
}

final class _DemoCurrentReader implements CurrentReader {
  _DemoCurrentReader(this._api, this.threadId, this._history)
    : reader = _DemoReadSource(
        _api,
        threadId,
        _history,
        const ChatScope.conversation(),
      ) {
    _api._ownedHistoryReaders.add(reader);
  }

  final DemoStudioTransport _api;
  final String _readerId = newStudioCorrelationId();
  @override
  final String threadId;
  final _DemoHistory _history;
  final _DemoReadSource reader;
  final Map<CurrentContentRef, ContentRef> _content = {};
  final Set<_DemoCurrentWatch> _watches = {};
  final Set<_DemoCurrentBodyWatch> _bodyWatches = {};
  Future<void>? _closing;
  bool _closed = false;

  @override
  OpenCurrent get metadata => OpenCurrent(
    readerId: 'demo-current:$_readerId',
    currentProtocolVersion: currentProtocolVersion,
    currentOwnerId: _history.epoch,
  );

  CurrentRevision get _revision =>
      CurrentRevision(ownerId: _history.epoch, revision: _history.revision);

  void _checkOpen() {
    if (_closed || _api._runtimeExiting) throw _conversationClosedFailure;
  }

  @override
  CurrentView get initialView => _snapshot();

  CurrentView _snapshot() {
    var workspace = _api._demoWorkspace(threadId);
    _history.prepareCurrent(workspace);
    final deferred = <CurrentStateField>[];
    final collections = <CurrentCollectionRef>[];
    CurrentCollectionRef? deferCollection(String name, List<Object?> values) {
      if (_demoEncoded(values) <= 2048) return null;
      final signature = jsonEncode(values);
      if (_history._stateCollectionSignatures[name] != signature) {
        _history._stateCollectionSignatures[name] = signature;
        _history.stateCollectionVersions[name] =
            (_history.stateCollectionVersions[name] ?? 0) + 1;
        _history.stateCollections[name] = List.unmodifiable(values);
      }
      final reference = CurrentCollectionRef(
        ownerId: _history.epoch,
        collection: 'state:runtime:$name',
        revision: _history.stateCollectionVersions[name]!,
      );
      deferred.add(
        CollectionCurrentStateField(
          field: name,
          reference: reference,
          count: values.length,
        ),
      );
      collections.add(reference);
      return reference;
    }

    final runtime = workspace.runtime;
    final skills = deferCollection(
      'activeSkills',
      runtime.activeSkills.cast<Object?>(),
    );
    final mcp = deferCollection(
      'activeMcpServers',
      runtime.activeMcpServers.cast<Object?>(),
    );
    final lsp = deferCollection(
      'activeLspServers',
      runtime.activeLspServers.cast<Object?>(),
    );
    final interactions = workspace.interactions.isEmpty
        ? null
        : CurrentCollectionRef(
            ownerId: _history.epoch,
            collection: 'interactions',
            revision: _history.interactionRevision,
          );
    final boundedPlan = runtime.plan?.document == null
        ? runtime.plan
        : runtime.plan!.copyWith(document: null);
    final plan = runtime.plan;
    final planHead = plan == null
        ? null
        : CurrentPlanHead(
            revision: plan.revision,
            phase: plan.state,
            document: plan.document == null
                ? null
                : CurrentContentRef(
                    ownerId: _history.epoch,
                    domain: 'plan',
                    entityId: threadId,
                    contentKey: 'plan.document',
                    generation: '${plan.revision}',
                  ),
          );
    final references = ThreadBusinessRefs(
      plan: planHead,
      interactions: interactions,
    );
    workspace = workspace.copyWith(
      interactions: const [],
      businessRefs: references,
      runtime: runtime.copyWith(
        activeSkills: skills == null ? runtime.activeSkills : const [],
        activeMcpServers: mcp == null ? runtime.activeMcpServers : const [],
        activeLspServers: lsp == null ? runtime.activeLspServers : const [],
        deferred: deferred,
        plan: boundedPlan,
      ),
    );
    final atoms = [
      for (final atom in _history.activeAtoms.values)
        CurrentAtom(
          id: atom.id,
          source: atom.source,
          sourceState: atom.sourceState,
          sourceOrder: atom.sourceOrder,
          kind: atom.kind,
          delivery: atom.delivery,
          lifecycle: atom.lifecycle,
          turnId: atom.turnId,
          attemptId: atom.attemptId,
          tool: atom.tool,
          wait: atom.wait,
          textChannel: atom.textChannel,
          startedAt: atom.startedAt,
          finishedAt: atom.finishedAt,
          contentPresent: atom.contentPresent,
          contents: [
            for (final content in atom.contents)
              CurrentAtomContent(
                role: content.role,
                reference: _currentRef(atom.id, content.reference),
              ),
          ],
        ),
    ];
    final activity = workspace.activity;
    return CurrentView(
      revision: _revision,
      state: ThreadSnapshotFrame(
        workspace: workspace,
        schemaVersion: threadSchemaVersion,
      ),
      projection: CurrentProjection(
        logicalStatus: workspace.thread.status,
        executionPresent: workspace.runtime.execution != null,
        active: activity == null
            ? null
            : CurrentActivityHead(
                id: activity.identity,
                kind: activity.kind,
                summary: activity.summary,
                thinkingSummary: activity.thinkingSummary,
                thinkingSeconds: activity.thinkingSeconds,
                toolCount: activity.tools.count,
                backgroundToolCount: activity.tools.background,
                latestTool: activity.tools.latestStarted == null
                    ? null
                    : CurrentToolHead(
                        callId: activity.tools.latestStarted!.callId,
                        name: activity.tools.latestStarted!.name,
                        state: activity.tools.latestStarted!.state,
                      ),
              ),
        activeTurn: switch (workspace.activeTurn?.state) {
          RunningStudioTurnState(:final activity) => CurrentTurnHead(
            id: workspace.activeTurn!.turnId,
            phase: CurrentTurnPhase.values.byName(activity.name),
          ),
          _ => null,
        },
        sources: _history.sourceStates.values.toList(),
        atoms: atoms,
        plan: planHead,
        interactions: interactions,
        previews: const [],
        collections: [...collections, ?interactions],
      ),
    );
  }

  CurrentContentRef _currentRef(String atomId, ContentRef reference) {
    final value = CurrentContentRef(
      ownerId: _history.epoch,
      domain: 'content',
      entityId: atomId,
      contentKey: switch (reference.target) {
        ItemPayloadTarget() => 'payload',
        BodyContentTarget(:final key) => key,
      },
      generation: '${_revision.revision}',
    );
    _content[value] = reference;
    return value;
  }

  @override
  Future<CurrentView> snapshot(ReadDemand demand) async {
    _checkOpen();
    return _snapshot();
  }

  @override
  Future<CurrentWatch> watch({
    CurrentRevision? after,
    required ReadDemand demand,
  }) async {
    _checkOpen();
    final watch = _DemoCurrentWatch(this);
    _watches.add(watch);
    return watch;
  }

  @override
  Future<CurrentCollectionPage> pageCollection({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) async {
    _checkOpen();
    if (reference.ownerId == _history.epoch &&
        reference.collection.startsWith('state:runtime:')) {
      final name = reference.collection.substring('state:runtime:'.length);
      final values = _history.stateCollections[name];
      if (values == null ||
          _history.stateCollectionVersions[name] != reference.revision) {
        throw _demoStale();
      }
      final start = continuation == null ? 0 : int.tryParse(continuation) ?? 0;
      final entries = <CurrentCollectionEntry>[];
      var next = start;
      while (next < values.length && entries.length < demand.maxItems) {
        final ordinal = next++;
        final bytes = utf8.encode(jsonEncode(values[ordinal]));
        CurrentPayloadData payload = InlineCurrentPayload(bytes: bytes);
        var entry = CurrentCollectionEntry(
          id: '$ordinal',
          position: ordinal,
          payload: payload,
        );
        int encoded(CurrentCollectionEntry value) => _demoEncoded({
          'revision': reference.revision,
          'entries': [
            {
              'id': value.id,
              'position': value.position,
              'payload': switch (value.payload) {
                InlineCurrentPayload(:final bytes) => {
                  'kind': 'inline',
                  'bytes': bytes,
                },
                DeferredCurrentPayload(:final byteLength) => {
                  'kind': 'deferred',
                  'byteLength': byteLength,
                },
              },
            },
          ],
          'continuation': next < values.length ? '$next' : null,
        });
        if (encoded(entry) > demand.maxBytes) {
          payload = DeferredCurrentPayload(
            reference: CurrentContentRef(
              ownerId: _history.epoch,
              domain: 'collection:${reference.collection}',
              entityId: '$ordinal',
              contentKey: 'entry',
              generation: '${reference.revision}',
            ),
            byteLength: bytes.length,
          );
          entry = CurrentCollectionEntry(
            id: '$ordinal',
            position: ordinal,
            payload: payload,
          );
          if (entries.isEmpty && encoded(entry) > demand.maxBytes) {
            throw _demoQueryFailure(
              'InvalidDemand: State collection entry does not fit',
            );
          }
        }
        entries.add(entry);
      }
      return CurrentCollectionPage(
        revision: reference.revision,
        entries: entries,
        continuation: next < values.length ? '$next' : null,
      );
    }
    if (reference.ownerId != _history.epoch ||
        reference.collection != 'interactions' ||
        reference.revision != _history.interactionRevision) {
      throw _demoStale();
    }
    final rows = _api._demoWorkspace(threadId).interactions.toList()
      ..sort(
        (a, b) => _history.positions[('interaction', a.id)]!.compareTo(
          _history.positions[('interaction', b.id)]!,
        ),
      );
    final start = continuation == null ? 0 : int.tryParse(continuation) ?? 0;
    final selected = rows.skip(start).take(demand.maxItems).toList();
    final entries = <CurrentCollectionEntry>[];
    for (final row in selected) {
      final bytes = utf8.encode(
        jsonEncode({
          'interactionId': row.id,
          'scope': {'threadId': row.threadId, 'turnId': row.turnId},
          'revision': row.revision,
          'kind': row.kind.name,
          'title': row.title,
          'body': row.body,
        }),
      );
      final position = _history.positions[('interaction', row.id)]!;
      entries.add(
        CurrentCollectionEntry(
          id: row.id,
          position: position,
          payload: InlineCurrentPayload(bytes: bytes),
        ),
      );
    }
    return CurrentCollectionPage(
      revision: reference.revision,
      entries: entries,
      continuation: start + selected.length < rows.length
          ? '${start + selected.length}'
          : null,
    );
  }

  @override
  Future<ContentWindow> readBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) async {
    _checkOpen();
    if (reference.ownerId != _history.epoch) throw _demoStale();
    final _DemoBody? body;
    if (reference.domain == 'plan') {
      final plan = _api._demoWorkspace(threadId).runtime.plan;
      if (plan == null || '${plan.revision}' != reference.generation) {
        throw _demoStale();
      }
      body = _history.planDocument;
    } else if (reference.domain.startsWith('collection:')) {
      final collection = reference.domain.substring('collection:'.length);
      if (collection.startsWith('state:runtime:')) {
        final name = collection.substring('state:runtime:'.length);
        final ordinal = int.tryParse(reference.entityId);
        final values = _history.stateCollections[name];
        final version = _history.stateCollectionVersions[name];
        if (ordinal == null ||
            values == null ||
            ordinal < 0 ||
            ordinal >= values.length ||
            reference.contentKey != 'entry' ||
            reference.generation != '$version') {
          throw _demoStale();
        }
        body = _DemoBody()
          ..append(utf8.encode(jsonEncode(values[ordinal])))
          ..sealed = true;
        return ContentWindow(
          offset: range.offset,
          bytes: body.range(range.offset, range.maxBytes),
          generation: reference.generation,
          availableThrough: body.length,
          sealed: true,
        );
      }
      final key = (collection, reference.entityId, reference.contentKey);
      body = _history.currentBodies.putIfAbsent(key, () {
        final row = _api
            ._demoWorkspace(threadId)
            .interactions
            .where((value) => value.id == reference.entityId)
            .firstOrNull;
        if (row == null) throw _demoMissing();
        return _DemoBody()
          ..append(
            utf8.encode(
              jsonEncode({
                'interactionId': row.id,
                'revision': row.revision,
                'kind': row.kind.name,
                'title': row.title,
                'body': row.body,
              }),
            ),
          )
          ..sealed = true;
      });
    } else {
      final old = _content[reference];
      if (old == null) throw _demoStale();
      body = reader._body(old);
    }
    if (body == null) throw _demoMissing();
    return ContentWindow(
      offset: range.offset,
      bytes: body.range(range.offset, range.maxBytes),
      generation: reference.generation,
      availableThrough: body.length,
      sealed: true,
    );
  }

  @override
  Future<CurrentBodyWatch> watchBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) {
    _checkOpen();
    final watch = _DemoCurrentBodyWatch(this, reference, range);
    _bodyWatches.add(watch);
    return Future.value(watch);
  }

  void _watchClosed(_DemoCurrentWatch watch) {
    _watches.remove(watch);
  }

  void _bodyWatchClosed(_DemoCurrentBodyWatch watch) {
    _bodyWatches.remove(watch);
  }

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    for (final watch in _watches.toList()) {
      watch.requestClose();
    }
    for (final watch in _bodyWatches.toList()) {
      watch.requestClose();
    }
    reader.requestClose();
  }

  @override
  Future<void> close() => _closing ??= () async {
    final watches = _watches.toList();
    final bodyWatches = _bodyWatches.toList();
    requestClose();
    Object? error;
    StackTrace? stackTrace;
    void remember(Object failure, StackTrace stack) {
      error ??= failure;
      stackTrace ??= stack;
    }

    for (final watch in watches) {
      try {
        await watch.close();
      } catch (failure, stack) {
        remember(failure, stack);
      }
    }
    for (final watch in bodyWatches) {
      try {
        await watch.close();
      } catch (failure, stack) {
        remember(failure, stack);
      }
    }
    try {
      await reader.close();
    } catch (failure, stack) {
      remember(failure, stack);
    }
    if (error case final failure?) {
      Error.throwWithStackTrace(failure, stackTrace!);
    }
  }();
}

final class _DemoCurrentWatch implements CurrentWatch {
  _DemoCurrentWatch(this.reader) {
    _output = StreamController(onListen: _start, onCancel: requestClose);
  }

  final _DemoCurrentReader reader;
  late final StreamController<CurrentFrame> _output;
  var _revision = -1;
  bool _closed = false;
  Future<void>? _closing;

  void _publish(_DemoChange change, {required bool reset}) {
    if (_closed) return;
    final view = reader._snapshot();
    if (!reset && view.revision.revision == _revision) return;
    _revision = view.revision.revision;
    final frame = reset ? ResetCurrentFrame(view) : _frame(view, change);
    if (!_output.isClosed) _output.add(frame);
    if (!reset && change.update != null && !_output.isClosed) {
      // State notifications and query metadata are separate consumers of the
      // same Current cut. Timeline observes Projection, while the SDK applies
      // the typed State notification.
      _output.add(
        ProjectionCurrentFrame(
          revision: view.revision,
          projection: view.projection,
        ),
      );
    }
  }

  void _start() {
    if (_closed) return;
    reader._history.changes.add(_changed);
    _publish(const _DemoChange(null), reset: true);
  }

  void _changed(_DemoChange change) => _publish(change, reset: false);

  CurrentFrame _frame(CurrentView view, _DemoChange change) {
    final update = change.update;
    if (update == null) {
      return ProjectionCurrentFrame(
        revision: view.revision,
        projection: view.projection,
      );
    }
    final state = view.state.workspace;
    return NotificationCurrentFrame(
      revision: view.revision,
      notification: ThreadNotificationFrame(
        threadId: reader.threadId,
        revision: state.revision,
        baseRevision: state.revision - 1,
        update: switch (update) {
          ThreadTurnUpdate(:final turn) => ThreadTurnUpdate(turn),
          ThreadActivityUpdate(:final activity) => ThreadActivityUpdate(
            activity: activity,
          ),
          ThreadInteractionUpdate(:final interaction, :final pending) =>
            ThreadInteractionUpdate(interaction: interaction, pending: pending),
          ThreadRuntimeUpdate() => ThreadRuntimeUpdate(
            runtime: state.runtime,
            todo: state.todo,
            modelRoute: state.modelRoute,
          ),
          ThreadStorageUpdate(:final storage) => ThreadStorageUpdate(
            storage: storage,
          ),
          ThreadBusinessRefsUpdate() => ThreadBusinessRefsUpdate(
            references: state.businessRefs,
          ),
        },
      ),
    );
  }

  @override
  Stream<CurrentFrame> get frames => _output.stream;

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    reader._history.changes.remove(_changed);
    if (!_output.isClosed) unawaited(_output.close());
  }

  @override
  Future<void> close() => _closing ??= Future<void>.sync(() {
    requestClose();
    reader._watchClosed(this);
  });
}

final class _DemoCurrentBodyWatch implements CurrentBodyWatch {
  _DemoCurrentBodyWatch(this.reader, this.reference, this.range) {
    _output = StreamController(onListen: _start, onCancel: requestClose);
  }

  final _DemoCurrentReader reader;
  final CurrentContentRef reference;
  final ContentRange range;
  late final StreamController<ContentWindow> _output;
  bool _closed = false;
  String? _last;
  final Set<Future<void>> _reads = {};
  Future<void>? _closing;

  void _start() {
    if (_closed) return;
    reader._history.changes.add(_wake);
    _wake(const _DemoChange(null));
  }

  void _wake(_DemoChange _) {
    if (_closed) return;
    late final Future<void> read;
    read = () async {
      try {
        final window = await reader.readBody(
          reference: reference,
          range: range,
        );
        if (_closed) return;
        final stamp =
            '${window.generation}:${window.availableThrough}:${window.sealed}';
        if (stamp == _last) return;
        _last = stamp;
        if (!_output.isClosed) _output.add(window);
        if (window.sealed) requestClose();
      } catch (error, stack) {
        if (!_closed) {
          if (!_output.isClosed) _output.addError(error, stack);
          requestClose();
        }
      }
    }();
    _reads.add(read);
    unawaited(
      read.whenComplete(() {
        _reads.remove(read);
      }),
    );
  }

  @override
  Stream<ContentWindow> get windows => _output.stream;

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    reader._history.changes.remove(_wake);
    if (!_output.isClosed) unawaited(_output.close());
  }

  @override
  Future<void> close() => _closing ??= () async {
    requestClose();
    while (_reads.isNotEmpty) {
      await Future.wait(_reads.toList());
    }
    reader._bodyWatchClosed(this);
  }();
}
