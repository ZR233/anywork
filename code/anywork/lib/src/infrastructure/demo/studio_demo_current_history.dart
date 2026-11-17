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
  @override
  final String threadId;
  final _DemoHistory _history;
  final _DemoReadSource reader;
  bool _closed = false;

  @override
  OpenHistory get metadata => OpenHistory(
    readerId: 'demo-history:${_history.epoch}',
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
      entries: _historyEntries(page.blocks),
      next: page.before,
    );
  }

  @override
  Future<HistoryGroupPage> groupPage({
    required String groupId,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) async {
    _checkOpen();
    final block = _history.displayBlocks
        .where((value) => value.id == groupId)
        .firstOrNull;
    if (block == null) throw _demoMissing();
    final body = block.body;
    if (body is! WorkDisplayBlock) throw _demoMissing();
    final heads =
        _history.displayHeads[body.members] ?? const <DisplayMemberHead>[];
    final start = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    final selected = heads.skip(start).take(demand.maxRows).toList();
    final next = start + selected.length < heads.length
        ? '${start + selected.length}'
        : null;
    return HistoryGroupPage(
      cut: cut ?? body.members.cut,
      groupId: groupId,
      members: [
        for (final head in selected)
          HistoryTimelineEntry(
            rowKey: head.memberKey,
            anchorSeq: head.memberOrder,
            headSeq: head.memberOrder,
            head: MemberHistoryRow(_historyEntityHead(head.record)),
          ),
      ],
      next: next,
    );
  }

  @override
  Future<HistoryTimelinePage> turnsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) async {
    _checkOpen();
    final turn = _api._demoWorkspace(threadId).lastTurn;
    return HistoryTimelinePage(
      cut: cut ?? _cut(),
      entries: [
        if (turn != null)
          HistoryTimelineEntry(
            rowKey: 'turn:${turn.turnId}',
            anchorSeq: turn.revision,
            headSeq: turn.revision,
            head: TurnHistoryRow(
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
        HistoryEventDetail(
          header: HistoryEventHeader(
            seq: item.order,
            eventId: item.message.id,
            kind: 'entity_ended',
            runId: null,
            attemptId: item.message.attemptId,
            entityId: item.message.id,
            turnId: item.message.turnId,
            source: item.message.source,
            recordedAt: 0,
          ),
          head: SingleHistoryRow(
            _historyEntityHead(
              DisplayRecord(
                atom: item.message,
                contentSource: CompletedOriginal(completionId: item.message.id),
              ),
            ),
          ),
        ),
    ];
    final filtered = switch (query) {
      EntityHistoryEvents(:final entityId) =>
        all.where((event) => event.header.entityId == entityId).toList(),
      TurnHistoryEvents(:final turnId) =>
        all.where((event) => event.header.turnId == turnId).toList(),
      SourceHistoryEvents(:final source) =>
        all.where((event) => event.header.source == source).toList(),
      CallHistoryEvents(:final callId) =>
        all
            .where(
              (event) => switch (event.head) {
                SingleHistoryRow(:final head) => head.tool?.callId == callId,
                _ => false,
              },
            )
            .toList(),
      MessageHistoryEvents(:final messageId) =>
        all.where((event) => event.header.messageId == messageId).toList(),
      AttemptHistoryEvents(:final runId, :final attemptId) =>
        all
            .where(
              (event) =>
                  event.header.runId == runId &&
                  event.header.attemptId == attemptId,
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
  Future<HistoryEventDetail> readEvent({
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
  Future<HistoryTimelinePage> costsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) async => HistoryTimelinePage(cut: cut ?? _cut(), entries: const []);

  @override
  Future<HistoryCut> waitChanged(HistoryCut after) async {
    _checkOpen();
    final afterFrontier = _cutFrontier(after);
    final completer = Completer<void>();
    void wake() {
      if (_history.displayHead > afterFrontier && !completer.isCompleted) {
        completer.complete();
      }
    }

    _history.changes.add(wake);
    wake();
    try {
      await completer.future;
      _checkOpen();
      return _cut();
    } finally {
      _history.changes.remove(wake);
    }
  }

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
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

  List<HistoryTimelineEntry> _historyEntries(List<DisplayBlock> blocks) => [
    for (final block in blocks)
      HistoryTimelineEntry(
        rowKey: block.id,
        anchorSeq: block.blockOrder,
        headSeq: block.blockOrder,
        head: switch (block.body) {
          WorkDisplayBlock(
            :final timing,
            :final members,
            :final executionPresent,
            :final memberCount,
            :final unfinishedCount,
            :final groupClosed,
            :final summary,
          ) =>
            WorkHistoryRow(
              HistoryWorkHead(
                groupId: members.blockId,
                runId: null,
                startedAt: timing.startedAt,
                boundaryAt: timing.finishedAt,
                closed: groupClosed,
                memberCount: memberCount,
                unfinishedCount: unfinishedCount,
                executionPresent: executionPresent,
                summary: summary,
              ),
            ),
          SingleDisplayBlock(:final record, :final visibility) =>
            SingleHistoryRow(
              _historyEntityHead(record, visibility: visibility),
            ),
        },
      ),
  ];

  HistoryEntityHead _historyEntityHead(
    DisplayRecord record, {
    HistorySingleVisibility? visibility,
  }) {
    final atom = record.atom;
    return HistoryEntityHead(
      entityId: atom.id,
      runId: null,
      attemptId: atom.attemptId,
      source: atom.source,
      kind: atom.kind,
      delivery: atom.delivery,
      state: switch (atom.lifecycle) {
        ActiveChatAtom(:final status) => HistoryEntityState(
          kind: HistoryEntityStateKind.knownActive,
          activeStatus: status,
        ),
        TerminalChatAtom(:final outcome) => HistoryEntityState(
          kind: HistoryEntityStateKind.knownTerminal,
          outcome: outcome,
        ),
      },
      startedAt: atom.startedAt,
      finishedAt: atom.finishedAt,
      textChannel: atom.textChannel,
      tool: atom.tool,
      wait: null,
      contentPresent: atom.contentPresent,
      singleVisibility: visibility,
      observation: switch (record.contentSource) {
        FrozenObservation(:final capturedAt) => HistoryObservation(
          kind: HistoryObservationKind.boundary,
          capturedAt: capturedAt,
        ),
        CompletedOriginal() || CurrentAtomSource() => const HistoryObservation(
          kind: HistoryObservationKind.original,
        ),
      },
      detailEventId: atom.id,
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
  @override
  final String threadId;
  final _DemoHistory _history;
  final _DemoReadSource reader;
  final Map<CurrentContentRef, ContentRef> _content = {};
  bool _closed = false;

  @override
  OpenCurrent get metadata => OpenCurrent(
    readerId: 'demo-current:${_history.epoch}',
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
    workspace = workspace.copyWith(
      interactions: const [],
      runtime: runtime.copyWith(
        activeSkills: skills == null ? runtime.activeSkills : const [],
        activeMcpServers: mcp == null ? runtime.activeMcpServers : const [],
        activeLspServers: lsp == null ? runtime.activeLspServers : const [],
        deferred: deferred,
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
    final plan = workspace.runtime.plan;
    final interactions = workspace.interactions.isEmpty
        ? null
        : CurrentCollectionRef(
            ownerId: _history.epoch,
            collection: 'interactions',
            revision: _history.interactionRevision,
          );
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
                kind: switch (activity.kind) {
                  ThreadActivityKind.preparing =>
                    ConversationActivityKind.preparing,
                  ThreadActivityKind.compacting =>
                    ConversationActivityKind.compacting,
                  ThreadActivityKind.waitingApi ||
                  ThreadActivityKind.thinking =>
                    ConversationActivityKind.thinking,
                  ThreadActivityKind.responding =>
                    ConversationActivityKind.responding,
                  ThreadActivityKind.planning =>
                    ConversationActivityKind.planning,
                  ThreadActivityKind.runningTool =>
                    ConversationActivityKind.runningTool,
                  ThreadActivityKind.awaitingApproval =>
                    ConversationActivityKind.awaitingApproval,
                  ThreadActivityKind.awaitingInput =>
                    ConversationActivityKind.awaitingInput,
                  ThreadActivityKind.stopping =>
                    ConversationActivityKind.stopping,
                },
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
        plan: plan == null
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
              ),
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
    return _DemoCurrentWatch(this);
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
    return Future.value(_DemoCurrentBodyWatch(this, reference, range));
  }

  @override
  void requestClose() {
    _closed = true;
    reader.requestClose();
  }

  @override
  Future<void> close() async {
    requestClose();
    await reader.close();
  }
}

final class _DemoCurrentWatch implements CurrentWatch {
  _DemoCurrentWatch(this.reader) {
    _output = StreamController(onListen: _start, onCancel: requestClose);
  }

  final _DemoCurrentReader reader;
  late final StreamController<CurrentFrame> _output;
  var _revision = -1;
  bool _closed = false;

  void _publish({required bool reset}) {
    if (_closed) return;
    final view = reader._snapshot();
    if (!reset && view.revision.revision == _revision) return;
    _revision = view.revision.revision;
    _output.add(
      reset
          ? ResetCurrentFrame(view)
          : ProjectionCurrentFrame(
              revision: view.revision,
              projection: view.projection,
            ),
    );
  }

  void _start() {
    reader._history.changes.add(_changed);
    _publish(reset: true);
  }

  void _changed() => _publish(reset: false);

  @override
  Stream<CurrentFrame> get frames => _output.stream;

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    reader._history.changes.remove(_changed);
    unawaited(_output.close());
  }

  @override
  Future<void> close() async {
    requestClose();
    await _output.done;
  }
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

  void _start() {
    reader._history.changes.add(_wake);
    _wake();
  }

  void _wake() {
    if (_closed) return;
    unawaited(() async {
      try {
        final window = await reader.readBody(
          reference: reference,
          range: range,
        );
        final stamp =
            '${window.generation}:${window.availableThrough}:${window.sealed}';
        if (stamp == _last) return;
        _last = stamp;
        _output.add(window);
        if (window.sealed) requestClose();
      } catch (error, stack) {
        if (!_closed) {
          _output.addError(error, stack);
          requestClose();
        }
      }
    }());
  }

  @override
  Stream<ContentWindow> get windows => _output.stream;

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    reader._history.changes.remove(_wake);
    unawaited(_output.close());
  }

  @override
  Future<void> close() async {
    requestClose();
    await _output.done;
  }
}
