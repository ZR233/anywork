part of 'studio_demo_api.dart';

// A controlled story declaration, not an atom classifier. Only IDs and member
// heads live here; bodies and completion originals remain in _DemoHistory.
final class _DemoDisplayScript {
  _DemoDisplayScript(this.id, this.memberIds, {required this.work, this.turnId})
    : startedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final String id;
  final List<String> memberIds;
  final bool work;
  final String? turnId;
  bool sealed = false;
  int? blockOrder;
  final int startedAt;
  int? finishedAt;
}

bool _sameDisplayAtomIdentity(ChatAtom previous, ChatAtom next) =>
    previous.id == next.id &&
    previous.source == next.source &&
    previous.sourceOrder == next.sourceOrder;

bool _sameDisplayBodyIdentity(
  DisplayBlockBody previous,
  DisplayBlockBody next,
) => switch (previous) {
  WorkDisplayBlock(:final members) =>
    next is WorkDisplayBlock && next.members == members,
  SingleDisplayBlock(:final record) =>
    next is SingleDisplayBlock &&
        _sameDisplayAtomIdentity(record.atom, next.record.atom) &&
        switch (record.contentSource) {
          CompletedOriginal(:final completionId) =>
            switch (next.record.contentSource) {
              CompletedOriginal(completionId: final nextId) =>
                completionId == nextId,
              _ => false,
            },
          _ => true,
        },
};

const _demoDisplayIdentityFailure = StudioFailure(
  code: StudioFailureCode.conflict,
  message: 'An explicit Demo display fixture cannot change its block or member identity',
  retryable: false,
  correlationId: 'demo-display-identity-conflict',
);

extension _DemoDisplayHistory on _DemoHistory {
  DisplayBlockRef displayRef(String id) =>
      DisplayBlockRef(databaseId: epoch, blockId: id);

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
      id,
      List.unmodifiable(memberIds),
      work: work,
      turnId: turnId,
    );
    if (work) displayCurrentWorkId = id;
    for (final member in memberIds) {
      displayMembership[member] = id;
      updateDisplayMember(member);
    }
    displayRevision++;
    displayLayoutRevision++;
  }

  void updateDisplayMember(String itemId) {
    final id = displayMembership[itemId];
    if (id == null) return; // Explicitly hidden from this controlled story.
    final script = displayScripts[id]!;
    if (script.sealed) return;
    final entry = completed[itemId];
    final atom = entry?.atom ?? activeAtoms[itemId];
    if (atom == null) return;
    script.blockOrder ??= ++displayLastOrder;
    final heads = displayHeads.putIfAbsent(displayRef(id), () => []);
    final order = script.memberIds.indexOf(itemId) + 1;
    final index = heads.indexWhere((h) => h.memberKey == itemId);
    final start = index < 0 ? null : heads[index].record.startFact;
    final head = DisplayMemberHead(
      memberKey: itemId,
      memberOrder: order,
      record: DisplayRecord(
        atom: atom,
        startFact:
            start ??
            switch (atom.lifecycle) {
              ActiveChatAtom(:final started) => started,
              TerminalChatAtom() => null,
            },
        endFact: switch (atom.lifecycle) {
          TerminalChatAtom(:final ended) => ended,
          ActiveChatAtom() => null,
        },
        contentSource: entry == null
            ? const CurrentAtom()
            : CompletedOriginal(completionId: entry.recordId),
      ),
    );
    if (index >= 0 && identical(heads[index].record.atom, atom)) return;
    if (index < 0) {
      heads.add(head);
      heads.sort((a, b) => a.memberOrder.compareTo(b.memberOrder));
    } else {
      heads[index] = head;
    }
    displayMemberRevisions.update(id, (v) => v + 1, ifAbsent: () => 1);
    displayRevision++;
    displayLayoutRevision++;
  }

  DisplayBlockBody scriptBody(_DemoDisplayScript script) {
    final heads = displayHeads[displayRef(script.id)] ?? const [];
    if (!script.work) {
      final head = heads.single;
      return SingleDisplayBlock(
        visibility: SingleVisibility.content,
        record: head.record,
      );
    }
    return WorkDisplayBlock(
      members: displayRef(script.id),
      timing: WorkTiming(
        startedAt: script.startedAt,
        finishedAt: script.sealed ? script.finishedAt : null,
      ),
    );
  }

  DisplayRecord freezeDisplayRecord(String blockId, DisplayMemberHead head) {
    final record = head.record;
    if (record.contentSource is! CurrentAtom) return record;
    final owner = DisplayObservationContentOwner(
      blockId: blockId,
      memberKey: head.memberKey,
    );
    final snapshot = bodies.putIfAbsent(
      jsonEncode(['display-observation', blockId, head.memberKey]),
      () => {},
    );
    ContentRef capture(String key, _DemoBody body) {
      snapshot[key] = body.frozen();
      return ContentRef(
        databaseId: epoch,
        target: BodyContentTarget(owner: owner, key: key),
      );
    }

    ContentRef captureRef(ContentRef reference) {
      final target = reference.target;
      final body = switch (target) {
        ItemPayloadTarget(:final itemId) => payloads[itemId],
        BodyContentTarget(owner: ItemContentOwner(:final itemId), :final key) =>
          bodies[itemId]?[key],
        BodyContentTarget(
          owner: CurrentContentOwner(:final domain, :final id),
          :final key,
        ) =>
          currentBodies[(domain, id, key)],
        BodyContentTarget(
          owner: DisplayObservationContentOwner(
            :final blockId,
            :final memberKey,
          ),
          :final key,
        ) =>
          bodies[jsonEncode(['display-observation', blockId, memberKey])]?[key],
      };
      if (body == null || reference.databaseId != epoch) {
        throw StateError('Explicit Demo snapshot content is missing');
      }
      return capture(
        jsonEncode(['content', contentRefToJson(reference)]),
        body,
      );
    }

    final payload = switch (record.atom.payload) {
      InlinePayload(:final bytes) => DeferredPayload(
        reference: capture('payload', _DemoBody()..append(bytes)),
        byteLength: bytes.length,
      ),
      DeferredPayload(:final reference, :final byteLength) => DeferredPayload(
        reference: captureRef(reference),
        byteLength: byteLength,
      ),
      null => null,
    };
    return DisplayRecord(
      atom: _demoCopy(
        record.atom,
        payload: payload,
        contents: [
          for (final content in record.atom.contents)
            ChatAtomContent(
              role: content.role,
              reference: captureRef(content.reference),
            ),
        ],
        frozen: true,
      ),
      startFact: record.startFact,
      endFact: record.endFact,
      contentSource: const FrozenObservation(available: true),
    );
  }

  void advanceDisplayFrontier() {
    var frontier = displayLastOrder;
    for (final script in displayScripts.values) {
      if (!script.sealed &&
          script.blockOrder != null &&
          script.blockOrder! - 1 < frontier) {
        frontier = script.blockOrder! - 1;
      }
    }
    for (final block in displayLiveSeed?.blocks ?? <LiveDisplayBlock>[]) {
      if (block.state == DisplayBlockState.open &&
          !displayBlocks.any((saved) => saved.id == block.id) &&
          block.blockOrder - 1 < frontier) {
        frontier = block.blockOrder - 1;
      }
    }
    if (frontier < displayReadyFrontier) {
      throw _demoQueryFailure('Display ready frontier regressed');
    }
    displayReadyFrontier = frontier;
  }

  void sealDisplay(String id) {
    final script = displayScripts[id]!;
    if (script.sealed) return;
    final heads = displayHeads[displayRef(id)] ?? const [];
    if (heads.isEmpty) {
      throw StateError('An explicit Demo boundary requires a nonempty block');
    }
    for (var i = 0; i < heads.length; i++) {
      final head = heads[i];
      heads[i] = DisplayMemberHead(
        memberKey: head.memberKey,
        memberOrder: head.memberOrder,
        record: freezeDisplayRecord(id, head),
      );
    }
    script.finishedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    script.sealed = true;
    displayBlocks.add(
      DisplayBlock(
        id: id,
        blockOrder: script.blockOrder!,
        body: scriptBody(script),
      ),
    );
    displayBlocks.sort((a, b) => a.blockOrder.compareTo(b.blockOrder));
    advanceDisplayFrontier();
    if (displayCurrentWorkId == id) displayCurrentWorkId = null;
    displayRevision++;
    displayLayoutRevision++;
    displayMemberRevisions.update(id, (v) => v + 1, ifAbsent: () => 1);
  }

  void finishDisplayTurn(String turnId, ChatTerminalOutcome outcome) {
    for (final script in displayScripts.values) {
      if (script.turnId != turnId || script.sealed) continue;
      final heads = displayHeads[displayRef(script.id)];
      if (heads == null || heads.isEmpty) continue;
      for (var i = 0; i < heads.length; i++) {
        final head = heads[i];
        if (head.record.atom.lifecycle case ActiveChatAtom(:final started)) {
          if (outcome == ChatTerminalOutcome.completed) {
            throw StateError('Successful story left an unfinished member');
          }
          final ended = _fact();
          heads[i] = DisplayMemberHead(
            memberKey: head.memberKey,
            memberOrder: head.memberOrder,
            record: DisplayRecord(
              atom: _demoCopy(
                head.record.atom,
                lifecycle: TerminalChatAtom(
                  started: started,
                  ended: ended,
                  outcome: outcome,
                ),
              ),
              startFact: head.record.startFact,
              endFact: ended,
              contentSource: const CurrentAtom(),
            ),
          );
          for (final body in bodies[head.memberKey]?.values ?? <_DemoBody>[]) {
            body.sealed = true;
          }
        }
      }
      sealDisplay(script.id);
    }
  }

  void installDisplay({
    required List<DisplayBlock> blocks,
    TailSnapshot? live,
    Map<DisplayBlockRef, List<DisplayMemberHead>>? members,
  }) {
    final summaryOnly =
        blocks.isEmpty &&
        (members == null || members.isEmpty) &&
        live != null &&
        displayLiveSeed != null &&
        _demoSameTailLayout(displayLiveSeed!, live);
    var through = displayHead;
    final ids = {for (final block in displayBlocks) block.id};
    final existingBodies = {
      for (final block in liveBlocks()) block.id: block.body,
    };
    final existingOrders = {
      for (final block in liveBlocks()) block.id: block.blockOrder,
    };
    void validateIdentity(String id, DisplayBlockBody body, int order) {
      final previousOrder = existingOrders[id];
      if (previousOrder != null && previousOrder != order) {
        throw _demoDisplayIdentityFailure;
      }
      final script = displayScripts[id];
      if (script != null &&
          (script.work != (body is WorkDisplayBlock) ||
              (body is SingleDisplayBlock &&
                  body.record.atom.id != script.memberIds.single))) {
        throw _demoDisplayIdentityFailure;
      }
      final previous = existingBodies[id];
      if (previous != null && !_sameDisplayBodyIdentity(previous, body)) {
        throw _demoDisplayIdentityFailure;
      }
    }

    for (final block in blocks) {
      if (block.blockOrder <= through || !ids.add(block.id)) {
        throw _demoQueryFailure('Duplicate or unordered display fixture');
      }
      validateIdentity(block.id, block.body, block.blockOrder);
      if (block.body case WorkDisplayBlock(:final members)) {
        if (members.databaseId != epoch || members.blockId != block.id) {
          throw _demoStale();
        }
      }
      through = block.blockOrder;
    }
    if (live != null &&
        (live.readyFrontier != through ||
            live.blocks.any((block) => ids.contains(block.id)))) {
      throw _demoQueryFailure('Invalid display live/history cut');
    }
    var liveOrder = 0;
    final liveIds = <String>{};
    for (final block in live?.blocks ?? <LiveDisplayBlock>[]) {
      if (block.id.isEmpty ||
          !liveIds.add(block.id) ||
          block.blockOrder <= liveOrder ||
          block.blockOrder <= through) {
        throw _demoQueryFailure('Invalid explicit live display order');
      }
      validateIdentity(block.id, block.body, block.blockOrder);
      if (block.body case WorkDisplayBlock(:final members)) {
        if (members.databaseId != epoch || members.blockId != block.id) {
          throw _demoStale();
        }
      }
      liveOrder = block.blockOrder;
    }
    for (final entry
        in (members ?? const <DisplayBlockRef, List<DisplayMemberHead>>{})
            .entries) {
      if (entry.key.databaseId != epoch) throw _demoStale();
      if (displayBlocks.any((block) => block.id == entry.key.blockId)) {
        throw _demoQueryFailure('Sealed display members cannot be replaced');
      }
      var order = 0;
      final keys = <String>{};
      for (final head in entry.value) {
        if (head.memberOrder <= order || !keys.add(head.memberKey)) {
          throw _demoQueryFailure('Invalid explicit display member order');
        }
        order = head.memberOrder;
      }
      for (final previous in displayHeads[entry.key] ?? <DisplayMemberHead>[]) {
        final next = entry.value
            .where((head) => head.memberKey == previous.memberKey)
            .firstOrNull;
        if (next == null ||
            next.memberOrder != previous.memberOrder ||
            !_sameDisplayAtomIdentity(previous.record.atom, next.record.atom)) {
          throw _demoDisplayIdentityFailure;
        }
      }
    }
    // Sealing changes the page even if every existing member was already
    // terminal and the caller correctly omits an unchanged member fixture.
    final changedMemberBlocks = <String>{
      for (final block in blocks)
        if (block.body is WorkDisplayBlock) block.id,
      for (final reference in members?.keys ?? <DisplayBlockRef>[])
        reference.blockId,
    };
    displayBlocks.addAll(blocks);
    displayBlocks.sort((a, b) => a.blockOrder.compareTo(b.blockOrder));
    displayReadyFrontier = through;
    for (final block in blocks) {
      if (block.blockOrder > displayLastOrder) {
        displayLastOrder = block.blockOrder;
      }
    }
    for (final block in live?.blocks ?? <LiveDisplayBlock>[]) {
      if (block.blockOrder > displayLastOrder) {
        displayLastOrder = block.blockOrder;
      }
    }
    if (blocks.any((block) => block.id == displayCurrentWorkId)) {
      displayCurrentWorkId = null;
    }
    if (live != null) {
      displayLiveSeed = live;
      displayCurrentWorkId = live.currentWorkId;
    }
    for (final entry
        in (members ?? const <DisplayBlockRef, List<DisplayMemberHead>>{})
            .entries) {
      displayHeads[entry.key] = List.of(entry.value);
    }
    for (final id in changedMemberBlocks) {
      displayMemberRevisions.update(id, (v) => v + 1, ifAbsent: () => 1);
    }
    if (blocks.isNotEmpty || live != null) {
      displayRevision++;
      if (!summaryOnly) displayLayoutRevision++;
    }
  }

  List<LiveDisplayBlock> liveBlocks() => [
    ...?displayLiveSeed?.blocks.where(
      (b) => !displayBlocks.any((s) => s.id == b.id),
    ),
    for (final block in displayBlocks.where(
      (block) => block.blockOrder > displayHead,
    ))
      LiveDisplayBlock(
        id: block.id,
        blockOrder: block.blockOrder,
        body: block.body,
        state: DisplayBlockState.sealed,
      ),
    for (final script in displayScripts.values)
      if (!script.sealed &&
          (displayHeads[displayRef(script.id)]?.isNotEmpty ?? false))
        LiveDisplayBlock(
          id: script.id,
          source: script.turnId == null
              ? null
              : ForegroundTurnChatSource(turnId: script.turnId!),
          blockOrder: script.blockOrder!,
          hasUnfinishedMembers:
              (displayHeads[displayRef(script.id)] ??
                      const <DisplayMemberHead>[])
                  .any(
                    (member) => member.record.atom.lifecycle is ActiveChatAtom,
                  ),
          body: scriptBody(script),
          state: DisplayBlockState.open,
        ),
  ]..sort((a, b) => a.blockOrder.compareTo(b.blockOrder));
}

Object _displayRecordJson(DisplayRecord record) => {
  'atom': chatAtomToJson(record.atom),
  'startFact': record.startFact == null
      ? null
      : {
          'effectSeq': record.startFact!.effectSeq,
          'suborder': record.startFact!.suborder,
        },
  'endFact': record.endFact == null
      ? null
      : {
          'effectSeq': record.endFact!.effectSeq,
          'suborder': record.endFact!.suborder,
        },
  'contentSource': switch (record.contentSource) {
    CurrentAtom() => {'kind': 'currentAtom'},
    FrozenObservation(:final capturedAt, :final available) => {
      'kind': 'frozenObservation',
      'capturedAt': capturedAt,
      'available': available,
    },
    CompletedOriginal(:final completionId) => {
      'kind': 'completedOriginal',
      'completionId': completionId,
    },
  },
};

Object _displayBodyJson(DisplayBlockBody body) => switch (body) {
  SingleDisplayBlock(:final record, :final visibility) => {
    'kind': 'single',
    'record': _displayRecordJson(record),
    'visibility': visibility.name,
  },
  WorkDisplayBlock(:final timing, :final members) => {
    'kind': 'work',
    'members': {'databaseId': members.databaseId, 'blockId': members.blockId},
    'timing': {'startedAt': timing.startedAt, 'finishedAt': timing.finishedAt},
  },
};
Map<String, Object?> _liveJson(TailSnapshot live) => {
  'revision': live.revision,
  'layoutRevision': live.layoutRevision,
  'readyFrontier': live.readyFrontier,
  'executionPresent': live.executionPresent,
  'currentWorkId': live.currentWorkId,
  'older': live.older,
  'blocks': [
    for (final b in live.blocks)
      {
        'id': b.id,
        'blockOrder': b.blockOrder,
        if (b.source != null) 'source': chatSourceIdToJson(b.source!),
        'body': _displayBodyJson(b.body),
        'state': b.state.name,
        'hasUnfinishedMembers': b.hasUnfinishedMembers,
        'thinkingSummary': b.thinkingSummary,
      },
  ],
};

bool _demoSameTailLayout(TailSnapshot before, TailSnapshot after) {
  Map<String, Object?> layout(TailSnapshot value) {
    final result = _liveJson(value)
      ..remove('revision')
      ..remove('layoutRevision');
    result['blocks'] = [
      for (final entry in result['blocks'] as List)
        if ((entry as Map)['id'] == value.currentWorkId)
          (Map<String, Object?>.from(entry)..remove('thinkingSummary'))
        else
          entry,
    ];
    return result;
  }

  return jsonEncode(layout(before)) == jsonEncode(layout(after));
}

extension _DemoPresentationQueries on _DemoReader {
  DisplayBlockBody fitDisplay(DisplayBlockBody body) => switch (body) {
    SingleDisplayBlock(:final record, :final visibility) => SingleDisplayBlock(
      visibility: visibility,
      record: DisplayRecord(
        atom: fit(record.atom, 0),
        startFact: record.startFact,
        endFact: record.endFact,
        contentSource: record.contentSource,
      ),
    ),
    WorkDisplayBlock() => body,
  };

  TailSnapshot livePage(ReadDemand demand, {String? before}) {
    _demoDemand(demand);
    final history = _history;
    final revision = history.displayRevision;
    final layout = history.displayLayoutRevision;
    final blocks = history.liveBlocks();
    final end = before == null
        ? blocks.length
        : boundary(before, 'display-live', layout);
    final selected = <LiveDisplayBlock>[];
    String? older;
    TailSnapshot page() => TailSnapshot(
      currentWorkId: history.displayCurrentWorkId,
      revision: revision,
      layoutRevision: layout,
      readyFrontier: history.displayHead,
      executionPresent:
          history.displayLiveSeed?.executionPresent ??
          (_api._demoWorkspace(threadId).runtime.execution != null),
      blocks: selected,
      older: older,
    );
    for (var i = end - 1; i >= 0; i--) {
      final b = blocks[i];
      final candidate = LiveDisplayBlock(
        id: b.id,
        blockOrder: b.blockOrder,
        source: b.source,
        body: fitDisplay(b.body),
        state: b.state,
        hasUnfinishedMembers: b.hasUnfinishedMembers,
        thinkingSummary: b.thinkingSummary,
      );
      final next = i > 0 ? cursor('display-live', layout, i) : null;
      final trial = TailSnapshot(
        currentWorkId: history.displayCurrentWorkId,
        revision: revision,
        layoutRevision: layout,
        readyFrontier: history.displayHead,
        executionPresent: page().executionPresent,
        blocks: [candidate, ...selected],
        older: next,
      );
      if (_demoEncoded(_liveJson(trial)) > demand.maxBytes) {
        if (selected.isEmpty) {
          throw _demoQueryFailure(
            'InvalidDemand: live display envelope does not fit',
          );
        }
        break;
      }
      selected.insert(0, candidate);
      older = next;
      if (selected.length == demand.maxItems) break;
    }
    final result = page();
    if (before == null &&
        result.currentWorkId != null &&
        !result.blocks.any(
          (block) =>
              block.id == result.currentWorkId &&
              block.state == DisplayBlockState.open &&
              block.body is WorkDisplayBlock,
        )) {
      throw _demoQueryFailure(
        'InvalidDemand: current Work head does not fit the latest window',
      );
    }
    if (_demoEncoded(_liveJson(result)) > demand.maxBytes) {
      throw _demoQueryFailure(
        'InvalidDemand: live display envelope does not fit',
      );
    }
    return result;
  }

  TimelinePage timelinePage(ReadDemand demand, {String? before}) {
    _demoDemand(demand);
    final ceiling = before == null
        ? _history.displayHead
        : boundary('h0:$before', 'display-h0', 0);
    final end = before == null
        ? ceiling + 1
        : boundary(before, 'display-history', ceiling);
    final records = _history.displayBlocks
        .where((b) => b.blockOrder < end && b.blockOrder <= ceiling)
        .toList();
    final selected = <DisplayBlock>[];
    String? next;
    TimelinePage page() => TimelinePage(
      presentationVersion: presentationVersion,
      databaseId: _history.epoch,
      ceiling: ceiling,
      blocks: selected,
      before: next,
    );
    for (var i = records.length - 1; i >= 0; i--) {
      final b = records[i];
      final candidate = DisplayBlock(
        id: b.id,
        blockOrder: b.blockOrder,
        body: fitDisplay(b.body),
      );
      final token = i > 0
          ? cursor('display-history', ceiling, b.blockOrder)
          : null;
      if (token != null) _cursors['h0:$token'] = ('display-h0', 0, ceiling);
      final trial = TimelinePage(
        presentationVersion: presentationVersion,
        databaseId: _history.epoch,
        ceiling: ceiling,
        blocks: [candidate, ...selected],
        before: token,
      );
      if (_pageBytes(trial) > demand.maxBytes) {
        if (selected.isEmpty) throw _demoQueryFailure('InvalidDemand');
        break;
      }
      selected.insert(0, candidate);
      next = token;
      if (selected.length == demand.maxItems) break;
    }
    if (_pageBytes(page()) > demand.maxBytes) {
      throw _demoQueryFailure('InvalidDemand');
    }
    return page();
  }
}

final class _DemoTimelineReader implements TimelineReader {
  _DemoTimelineReader(
    this._api,
    String threadId,
    _DemoHistory history,
    this._demand,
  ) : reader = _DemoReader(_api, threadId, history, const MainChatScope()),
      metadata = OpenTimeline(
        readerId: newStudioCorrelationId(),
        presentationVersion: presentationVersion,
        readerProtocolVersion: timelineReaderProtocolVersion,
        initialCursor: ViewCursor(newStudioCorrelationId()),
      ) {
    _demoDemand(_demand);
    _confirmed = metadata.initialCursor;
    _api._ownedHistoryReaders.add(reader);
    history.changes.add(_changed);
  }
  final DemoStudioTransport _api;
  @override
  final _DemoReader reader;
  @override
  final OpenTimeline metadata;
  final ReadDemand _demand;
  late ViewCursor _confirmed;
  ViewUpdate? _pending;
  TailSnapshot? _tail;
  TailSnapshot? _pendingTail;
  TailSnapshot? _target;
  int? _through;
  bool _closed = false;
  bool _reading = false;
  Completer<void>? _changedWait;
  Future<void>? _active;

  void _changed() {
    final waiter = _changedWait;
    _changedWait = null;
    waiter?.complete();
  }

  TailSnapshot _captureTail(ReadDemand demand, {String? before}) =>
      reader.livePage(demand, before: before);
  TailSnapshot _mainTail(
    ViewCursor after, {
    required bool initial,
    String? before,
  }) {
    var tail = _captureTail(_demand);
    while (true) {
      final response = _response(
        after,
        HistoryDelta(
          placement: initial ? HistoryPlacement.set : HistoryPlacement.append,
          fromOrder: initial ? null : tail.readyFrontier,
          throughOrder: tail.readyFrontier,
          blocks: const [],
          before: before,
        ),
        ReplaceTail(snapshot: tail),
      );
      if (_fits(response)) return tail;
      if (tail.blocks.isEmpty || tail.blocks.first.id == tail.currentWorkId) {
        throw _demoQueryFailure('InvalidDemand');
      }
      final blocks = tail.blocks.skip(1).toList();
      final index = blocks.isEmpty
          ? reader._history.liveBlocks().length
          : reader._history.liveBlocks().indexWhere(
              (b) => b.id == blocks.first.id,
            );
      final older = reader.cursor('display-live', tail.layoutRevision, index);
      tail = TailSnapshot(
        revision: tail.revision,
        layoutRevision: tail.layoutRevision,
        readyFrontier: tail.readyFrontier,
        executionPresent: tail.executionPresent,
        currentWorkId: tail.currentWorkId,
        blocks: blocks,
        older: older,
      );
    }
  }

  @override
  Future<ViewUpdate> next({required ViewCursor after}) {
    if (_closed) return Future.error(_conversationClosedFailure);
    if (_reading) return Future.error(_demoQueryFailure('ConcurrentNext'));
    _reading = true;
    final done = Completer<void>();
    _active = done.future;
    return _next(after).whenComplete(() {
      _reading = false;
      done.complete();
    });
  }

  ViewUpdate _response(
    ViewCursor after,
    HistoryDelta history,
    TailUpdate tail,
  ) => ViewUpdate(
    presentationVersion: presentationVersion,
    readerProtocolVersion: timelineReaderProtocolVersion,
    after: after,
    next: ViewCursor(newStudioCorrelationId()),
    history: history,
    tail: tail,
  );
  bool _fits(ViewUpdate response) =>
      response.history.blocks.length +
              (response.tail is ReplaceTail
                  ? (response.tail as ReplaceTail).snapshot.blocks.length
                  : 0) <=
          _demand.maxItems &&
      _viewBytes(response) <= _demand.maxBytes;
  Future<ViewUpdate> _next(ViewCursor after) async {
    final pending = _pending;
    if (pending != null) {
      if (after == pending.after) return pending;
      if (after != pending.next) throw _demoQueryFailure('StaleViewCursor');
      _confirmed = pending.next;
      _through = pending.history.throughOrder;
      _tail = _pendingTail;
      _pending = null;
    }
    if (after != _confirmed) throw _demoQueryFailure('StaleViewCursor');
    while (!_closed) {
      final history = reader._history;
      final through = _through;
      if (through == null) {
        final page = reader.timelinePage(_demand);
        final zeroBefore = history.displayHead == 0
            ? null
            : reader.cursor(
                'display-history',
                history.displayHead,
                history.displayHead + 1,
              );
        if (zeroBefore != null) {
          reader._cursors['h0:$zeroBefore'] = (
            'display-h0',
            0,
            history.displayHead,
          );
        }
        final tail = _mainTail(after, initial: true, before: zeroBefore);
        var heads = page.blocks;
        var before = page.before;
        while (true) {
          final response = _response(
            after,
            HistoryDelta(
              placement: HistoryPlacement.set,
              throughOrder: history.displayHead,
              blocks: heads,
              before: before,
            ),
            ReplaceTail(snapshot: tail),
          );
          if (_fits(response)) {
            _pendingTail = tail;
            return _pending = response;
          }
          if (heads.isEmpty) throw _demoQueryFailure('InvalidDemand');
          heads = heads.skip(1).toList();
          final boundary = heads.isEmpty
              ? history.displayHead + 1
              : heads.first.blockOrder;
          before = reader.cursor(
            'display-history',
            history.displayHead,
            boundary,
          );
          reader._cursors['h0:$before'] = (
            'display-h0',
            0,
            history.displayHead,
          );
        }
      }
      final previousTail = _tail;
      if (_target == null &&
          previousTail != null &&
          previousTail.layoutRevision == history.displayLayoutRevision &&
          previousTail.readyFrontier == history.displayHead &&
          previousTail.revision != history.displayRevision) {
        final work = history.displayLiveSeed?.blocks
            .where((block) => block.id == previousTail.currentWorkId)
            .firstOrNull;
        final summary = work?.thinkingSummary;
        final status = _response(
          after,
          HistoryDelta(
            placement: HistoryPlacement.append,
            fromOrder: through,
            throughOrder: through,
            blocks: const [],
          ),
          TailStatus(
            baseLayoutRevision: previousTail.layoutRevision,
            revision: history.displayRevision,
            currentWorkId: previousTail.currentWorkId,
            thinkingSummary: summary,
          ),
        );
        if (!_fits(status)) throw _demoQueryFailure('InvalidDemand');
        _pendingTail = TailSnapshot(
          revision: history.displayRevision,
          layoutRevision: previousTail.layoutRevision,
          readyFrontier: previousTail.readyFrontier,
          executionPresent: previousTail.executionPresent,
          currentWorkId: previousTail.currentWorkId,
          older: previousTail.older,
          blocks: [
            for (final block in previousTail.blocks)
              if (block.id != previousTail.currentWorkId)
                block
              else
                LiveDisplayBlock(
                  id: block.id,
                  blockOrder: block.blockOrder,
                  source: block.source,
                  body: block.body,
                  state: block.state,
                  hasUnfinishedMembers: block.hasUnfinishedMembers,
                  thinkingSummary: summary,
                ),
          ],
        );
        return _pending = status;
      }
      if (_target == null &&
          (_tail?.layoutRevision != history.displayLayoutRevision ||
              _tail?.readyFrontier != history.displayHead)) {
        _target = _mainTail(after, initial: false);
      }
      final target = _target;
      if (target != null) {
        final records = history.displayBlocks
            .where(
              (b) =>
                  b.blockOrder > through &&
                  b.blockOrder <= target.readyFrontier,
            )
            .take(_demand.maxItems)
            .toList();
        final selected = <DisplayBlock>[];
        var checked = through;
        for (final b in records) {
          final head = DisplayBlock(
            id: b.id,
            blockOrder: b.blockOrder,
            body: reader.fitDisplay(b.body),
          );
          final trial = _response(
            after,
            HistoryDelta(
              placement: HistoryPlacement.append,
              fromOrder: through,
              throughOrder: b.blockOrder,
              blocks: [...selected, head],
            ),
            const KeepTail(),
          );
          if (!_fits(trial)) break;
          selected.add(head);
          checked = b.blockOrder;
        }
        if (records.isNotEmpty && selected.isEmpty) {
          throw _demoQueryFailure('InvalidDemand');
        }
        if (records.length < _demand.maxItems &&
            selected.length == records.length) {
          checked = target.readyFrontier;
        }
        TailUpdate tail = checked == target.readyFrontier
            ? ReplaceTail(snapshot: target)
            : const KeepTail();
        var response = _response(
          after,
          HistoryDelta(
            placement: HistoryPlacement.append,
            fromOrder: through,
            throughOrder: checked,
            blocks: selected,
          ),
          tail,
        );
        if (!_fits(response) && tail is ReplaceTail && selected.isNotEmpty) {
          tail = const KeepTail();
          response = ViewUpdate(
            presentationVersion: response.presentationVersion,
            readerProtocolVersion: response.readerProtocolVersion,
            after: response.after,
            next: response.next,
            history: response.history,
            tail: tail,
          );
        }
        if (!_fits(response)) throw _demoQueryFailure('InvalidDemand');
        if (tail is ReplaceTail) {
          _pendingTail = target;
          _target = null;
        } else {
          final ids = selected.map((b) => b.id).toSet();
          final previous = _tail!;
          _pendingTail = TailSnapshot(
            revision: previous.revision,
            layoutRevision: previous.layoutRevision,
            readyFrontier: previous.readyFrontier,
            executionPresent: previous.executionPresent,
            currentWorkId: ids.contains(previous.currentWorkId)
                ? null
                : previous.currentWorkId,
            blocks: previous.blocks.where((b) => !ids.contains(b.id)).toList(),
            older: previous.older,
          );
        }
        return _pending = response;
      }
      final wait = _changedWait ??= Completer<void>();
      await wait.future;
    }
    throw _conversationClosedFailure;
  }

  @override
  Future<TimelinePage> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) => reader._read(() {
    return reader.timelinePage(demand, before: before);
  });
  @override
  Future<TailSnapshot> loadLiveOlder({
    required String before,
    required ReadDemand demand,
  }) => reader._read(() => _captureTail(demand, before: before));
  @override
  void requestClose() {
    _closed = true;
    reader.requestClose();
    _changed();
  }

  @override
  Future<void> close() async {
    requestClose();
    await _active;
    await reader.close();
    reader._history.changes.remove(_changed);
    _pending = null;
    _tail = null;
    _target = null;
    _api._ownedTimelineReaders.remove(this);
  }

  @override
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  }) => reader._read(() {
    _demoDemand(demand);
    if (window case BeforeDisplayMembers(:final memberOrder)
        when memberOrder < 1) {
      throw _demoQueryFailure('Invalid display member boundary');
    }
    if (reference.databaseId != reader._history.epoch) throw _demoStale();
    final known =
        reader._history.displayBlocks.any(
          (b) => b.id == reference.blockId && b.body is WorkDisplayBlock,
        ) ||
        reader._history.liveBlocks().any(
          (b) => b.id == reference.blockId && b.body is WorkDisplayBlock,
        );
    if (!known) throw _demoMissing();
    final members = _DemoDisplayMembers(reader, reference, window, demand);
    reader._displayReads.add(members);
    return members;
  });
}

final class _DemoDisplayMembers implements DisplayMembers {
  _DemoDisplayMembers(this.reader, this.reference, this.window, this.demand) {
    reader._history.changes.add(_changed);
  }
  final _DemoReader reader;
  final DisplayBlockRef reference;
  final DisplayMemberWindow window;
  final ReadDemand demand;
  bool _closed = false, _reading = false, _sealedDelivered = false;
  int? _revision;
  Completer<void>? _wake;
  Future<DisplayMemberPage?>? _pending;
  int get revision =>
      reader._history.displayMemberRevisions[reference.blockId] ?? 0;
  void _changed() {
    if (_revision != revision && !(_wake?.isCompleted ?? true)) {
      _wake!.complete();
    }
  }

  @override
  Future<DisplayMemberPage?> next() {
    if (_reading) {
      return Future.error(_demoQueryFailure('Concurrent member next'));
    }
    _reading = true;
    final result = _next();
    _pending = result;
    return result.whenComplete(() {
      _reading = false;
      _pending = null;
    });
  }

  Future<DisplayMemberPage?> _next() async {
    while (!_closed && !_sealedDelivered && _revision == revision) {
      _wake = Completer<void>();
      await _wake!.future;
    }
    if (_closed || _sealedDelivered) return null;
    final history = reader._history;
    final sealed = history.displayBlocks.any((b) => b.id == reference.blockId);
    final all = history.displayHeads[reference] ?? const [];
    final end = switch (window) {
      LatestDisplayMembers() => null,
      BeforeDisplayMembers(:final memberOrder) => memberOrder,
    };
    final records = all
        .where((h) => end == null || h.memberOrder < end)
        .toList();
    final selected = <DisplayMemberHead>[];
    int? before;
    int pageBytes(List<DisplayMemberHead> entries, int? before) =>
        _demoEncoded({
          'block': {
            'databaseId': reference.databaseId,
            'blockId': reference.blockId,
          },
          'revision': revision,
          'sealed': sealed,
          'before': before,
          'entries': [
            for (final e in entries)
              {
                'memberKey': e.memberKey,
                'memberOrder': e.memberOrder,
                'record': _displayRecordJson(e.record),
              },
          ],
        });
    if (pageBytes([], null) > demand.maxBytes) {
      throw _demoQueryFailure('InvalidDemand: member envelope does not fit');
    }
    for (var i = records.length - 1; i >= 0; i--) {
      final h = records[i];
      final candidate = DisplayMemberHead(
        memberKey: h.memberKey,
        memberOrder: h.memberOrder,
        record: DisplayRecord(
          atom: reader.fit(h.record.atom, 0),
          startFact: h.record.startFact,
          endFact: h.record.endFact,
          contentSource: h.record.contentSource,
        ),
      );
      final trial = [candidate, ...selected];
      final size = pageBytes(trial, i > 0 ? h.memberOrder : null);
      if (size > demand.maxBytes) {
        if (selected.isEmpty) {
          throw _demoQueryFailure(
            'InvalidDemand: member envelope does not fit',
          );
        }
        break;
      }
      selected.insert(0, candidate);
      before = i > 0 ? h.memberOrder : null;
      if (selected.length == demand.maxItems) break;
    }
    _revision = revision;
    _sealedDelivered = sealed;
    return DisplayMemberPage(
      block: reference,
      revision: revision,
      sealed: sealed,
      entries: selected,
      before: before,
    );
  }

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    reader._history.changes.remove(_changed);
    if (!(_wake?.isCompleted ?? true)) _wake!.complete();
  }

  @override
  Future<void> close() async {
    requestClose();
    await _pending;
    reader._displayReads.remove(this);
  }
}

int _viewBytes(ViewUpdate value) => _demoEncoded({
  'presentationVersion': value.presentationVersion,
  'readerProtocolVersion': value.readerProtocolVersion,
  'after': value.after.value,
  'next': value.next.value,
  'history': {
    'placement': value.history.placement.name,
    'fromOrder': value.history.fromOrder,
    'throughOrder': value.history.throughOrder,
    'blocks': [
      for (final b in value.history.blocks)
        {
          'id': b.id,
          'blockOrder': b.blockOrder,
          'body': _displayBodyJson(b.body),
        },
    ],
    'before': value.history.before,
  },
  'tail': switch (value.tail) {
    KeepTail() => {'kind': 'keep'},
    ReplaceTail(:final snapshot) => {
      'kind': 'replace',
      'snapshot': _liveJson(snapshot),
    },
    TailStatus(
      :final baseLayoutRevision,
      :final revision,
      :final currentWorkId,
      :final thinkingSummary,
    ) =>
      {
        'kind': 'status',
        'baseLayoutRevision': baseLayoutRevision,
        'revision': revision,
        'currentWorkId': currentWorkId,
        'thinkingSummary': thinkingSummary,
      },
  },
});

int _pageBytes(TimelinePage page) => _demoEncoded({
  'presentationVersion': page.presentationVersion,
  'databaseId': page.databaseId,
  'ceiling': page.ceiling,
  'blocks': [
    for (final b in page.blocks)
      {
        'id': b.id,
        'blockOrder': b.blockOrder,
        'body': _displayBodyJson(b.body),
      },
  ],
  'before': page.before,
});
