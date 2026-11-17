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
            ? const CurrentAtomSource()
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
        visibility: HistorySingleVisibility.content,
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
    if (record.contentSource is! CurrentAtomSource) return record;
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
              contentSource: const CurrentAtomSource(),
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
    CurrentRunSnapshot? live,
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
    CurrentAtomSource() => {'kind': 'currentAtom'},
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
Map<String, Object?> _liveJson(CurrentRunSnapshot live) => {
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

bool _demoSameTailLayout(CurrentRunSnapshot before, CurrentRunSnapshot after) {
  Map<String, Object?> layout(CurrentRunSnapshot value) {
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

  CurrentRunSnapshot livePage(ReadDemand demand, {String? before}) {
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
    CurrentRunSnapshot page() => CurrentRunSnapshot(
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
      final trial = CurrentRunSnapshot(
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

  ({List<DisplayBlock> blocks, String? before}) historyPage(
    ReadDemand demand, {
    String? before,
  }) {
    _demoDemand(demand);
    final ceiling = before == null
        ? _history.displayHead
        : boundary('h0:$before', 'display-h0', 0);
    final end = before == null
        ? ceiling + 1
        : boundary(before, 'display-history', ceiling);
    final records = _history.displayBlocks
        .where((block) => block.blockOrder < end && block.blockOrder <= ceiling)
        .toList();
    final selected = <DisplayBlock>[];
    String? next;
    ({List<DisplayBlock> blocks, String? before}) page() =>
        (blocks: selected, before: next);
    int encoded(({List<DisplayBlock> blocks, String? before}) value) =>
        _demoEncoded({
          'blocks': [
            for (final block in value.blocks)
              {
                'id': block.id,
                'blockOrder': block.blockOrder,
                'body': _displayBodyJson(block.body),
              },
          ],
          'before': value.before,
        });
    if (encoded(page()) > demand.maxBytes)
      throw _demoQueryFailure('InvalidDemand');
    for (var i = records.length - 1; i >= 0; i--) {
      final block = records[i];
      final candidate = DisplayBlock(
        id: block.id,
        blockOrder: block.blockOrder,
        body: fitDisplay(block.body),
      );
      final token = i > 0
          ? cursor('display-history', ceiling, block.blockOrder)
          : null;
      if (token != null) _cursors['h0:$token'] = ('display-h0', 0, ceiling);
      final trial = (blocks: [candidate, ...selected], before: token);
      if (encoded(trial) > demand.maxBytes) {
        if (selected.isEmpty) throw _demoQueryFailure('InvalidDemand');
        break;
      }
      selected.insert(0, candidate);
      next = token;
      if (selected.length == demand.maxItems) break;
    }
    return page();
  }
}
