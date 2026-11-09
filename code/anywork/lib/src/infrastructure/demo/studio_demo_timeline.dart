part of 'studio_demo_api.dart';

// A controlled story declaration, not an atom classifier. Only IDs and member
// heads live here; bodies and completion originals remain in _DemoHistory.
final class _DemoDisplayScript {
  _DemoDisplayScript(
    this.id,
    this.memberIds, {
    required this.work,
    this.turnId,
  });
  final String id;
  final List<String> memberIds;
  final bool work;
  final String? turnId;
  bool sealed = false;
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
  SingleDisplayBlock(:final atom, :final completionId) =>
    next is SingleDisplayBlock &&
        _sameDisplayAtomIdentity(atom, next.atom) &&
        (completionId == null || completionId == next.completionId),
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
    for (final member in memberIds) {
      displayMembership[member] = id;
      updateDisplayMember(member);
    }
    displayRevision++;
  }

  void updateDisplayMember(String itemId) {
    final id = displayMembership[itemId];
    if (id == null) return; // Explicitly hidden from this controlled story.
    final script = displayScripts[id]!;
    if (script.sealed) return;
    final entry = completed[itemId];
    final atom = entry?.atom ?? activeAtoms[itemId];
    if (atom == null) return;
    final heads = displayHeads.putIfAbsent(displayRef(id), () => []);
    final order = script.memberIds.indexOf(itemId) + 1;
    final head = DisplayMemberHead(
      memberKey: itemId,
      memberOrder: order,
      atom: atom,
      completionId: entry?.recordId,
    );
    final index = heads.indexWhere((h) => h.memberKey == itemId);
    if (index >= 0 && identical(heads[index].atom, atom)) return;
    if (index < 0) {
      heads.add(head);
      heads.sort((a, b) => a.memberOrder.compareTo(b.memberOrder));
    } else {
      heads[index] = head;
    }
    displayMemberRevisions.update(id, (v) => v + 1, ifAbsent: () => 1);
    displayRevision++;
  }

  DisplayBlockBody scriptBody(_DemoDisplayScript script) {
    final heads = displayHeads[displayRef(script.id)] ?? const [];
    if (!script.work) {
      final head = heads.single;
      return SingleDisplayBlock(
        atom: head.atom,
        completionId: head.completionId,
      );
    }
    var terminal = 0,
        running = 0,
        waiting = 0,
        failed = 0,
        cancelled = 0,
        transferred = 0;
    for (final head in heads) {
      switch (head.atom.lifecycle) {
        case TerminalChatAtom(:final outcome):
          terminal++;
          if (outcome == ChatTerminalOutcome.failed) failed++;
          if (outcome == ChatTerminalOutcome.cancelled) cancelled++;
          if (outcome == ChatTerminalOutcome.transferred) transferred++;
        case ActiveChatAtom(:final status):
          if (status == ChatActiveStatus.waiting) {
            waiting++;
          } else {
            running++;
          }
      }
    }
    return WorkDisplayBlock(
      members: displayRef(script.id),
      summary: WorkSummary(
        total: heads.length,
        terminal: terminal,
        running: running,
        waiting: waiting,
        failed: failed,
        cancelled: cancelled,
        transferred: transferred,
      ),
    );
  }

  void sealDisplay(String id) {
    final script = displayScripts[id]!;
    if (script.sealed) return;
    final heads = displayHeads[displayRef(id)] ?? const [];
    if (heads.isEmpty ||
        heads.any((h) => h.atom.lifecycle is! TerminalChatAtom)) {
      throw StateError(
        'A scripted display block seals only at its terminal boundary',
      );
    }
    displayBlocks.add(
      DisplayBlock(
        id: id,
        historyPos: displayHead + 1,
        body: scriptBody(script),
      ),
    );
    script.sealed = true;
    displayRevision++;
    displayMemberRevisions.update(id, (v) => v + 1, ifAbsent: () => 1);
  }

  void finishDisplayTurn(String turnId, ChatTerminalOutcome outcome) {
    for (final script in displayScripts.values) {
      if (script.turnId != turnId || script.sealed) continue;
      final heads = displayHeads[displayRef(script.id)];
      if (heads == null || heads.isEmpty) continue;
      for (var i = 0; i < heads.length; i++) {
        final head = heads[i];
        if (head.atom.lifecycle case ActiveChatAtom(:final started)) {
          if (outcome == ChatTerminalOutcome.completed) {
            throw StateError('Successful story left an unfinished member');
          }
          heads[i] = DisplayMemberHead(
            memberKey: head.memberKey,
            memberOrder: head.memberOrder,
            atom: _demoCopy(
              head.atom,
              lifecycle: TerminalChatAtom(
                started: started,
                ended: _fact(),
                outcome: outcome,
              ),
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
    LiveDisplayWindow? live,
    Map<DisplayBlockRef, List<DisplayMemberHead>>? members,
  }) {
    var through = displayHead;
    final ids = {for (final block in displayBlocks) block.id};
    final existingBodies = {
      for (final block in liveBlocks()) block.id: block.body,
    };
    void validateIdentity(String id, DisplayBlockBody body) {
      final script = displayScripts[id];
      if (script != null &&
          (script.work != (body is WorkDisplayBlock) ||
              (body is SingleDisplayBlock &&
                  body.atom.id != script.memberIds.single))) {
        throw _demoDisplayIdentityFailure;
      }
      final previous = existingBodies[id];
      if (previous != null && !_sameDisplayBodyIdentity(previous, body)) {
        throw _demoDisplayIdentityFailure;
      }
    }

    for (final block in blocks) {
      if (block.historyPos <= through || !ids.add(block.id)) {
        throw _demoQueryFailure('Duplicate or unordered display fixture');
      }
      validateIdentity(block.id, block.body);
      if (block.body case WorkDisplayBlock(:final members)) {
        if (members.databaseId != epoch || members.blockId != block.id) {
          throw _demoStale();
        }
      }
      through = block.historyPos;
    }
    if (live != null &&
        (live.historyThrough != through ||
            live.blocks.any((block) => ids.contains(block.id)))) {
      throw _demoQueryFailure('Invalid display live/history cut');
    }
    var liveOrder = 0;
    final liveIds = <String>{};
    for (final block in live?.blocks ?? <LiveDisplayBlock>[]) {
      if (block.id.isEmpty ||
          !liveIds.add(block.id) ||
          block.blockOrder <= liveOrder) {
        throw _demoQueryFailure('Invalid explicit live display order');
      }
      validateIdentity(block.id, block.body);
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
            !_sameDisplayAtomIdentity(previous.atom, next.atom)) {
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
    if (live != null) displayLiveSeed = live;
    for (final entry
        in (members ?? const <DisplayBlockRef, List<DisplayMemberHead>>{})
            .entries) {
      displayHeads[entry.key] = List.of(entry.value);
    }
    for (final id in changedMemberBlocks) {
      displayMemberRevisions.update(id, (v) => v + 1, ifAbsent: () => 1);
    }
    if (blocks.isNotEmpty || live != null) displayRevision++;
  }

  List<LiveDisplayBlock> liveBlocks() => [
    ...?displayLiveSeed?.blocks.where(
      (b) => !displayBlocks.any((s) => s.id == b.id),
    ),
    for (final script in displayScripts.values)
      if (!script.sealed &&
          (displayHeads[displayRef(script.id)]?.isNotEmpty ?? false))
        LiveDisplayBlock(
          id: script.id,
          blockOrder:
              (displayLiveSeed?.blocks.lastOrNull?.blockOrder ?? 0) +
              displayScripts.keys.toList().indexOf(script.id) +
              1,
          body: scriptBody(script),
          closing: false,
        ),
  ];
}

Object _displayBodyJson(DisplayBlockBody body) => switch (body) {
  SingleDisplayBlock(:final atom, :final completionId) => {
    'kind': 'single',
    'atom': chatAtomToJson(atom),
    'completionId': completionId,
  },
  WorkDisplayBlock(:final summary, :final members) => {
    'kind': 'work',
    'members': {'databaseId': members.databaseId, 'blockId': members.blockId},
    'summary': {
      'total': summary.total,
      'terminal': summary.terminal,
      'running': summary.running,
      'waiting': summary.waiting,
      'failed': summary.failed,
      'cancelled': summary.cancelled,
      'transferred': summary.transferred,
      'startedAt': summary.startedAt,
      'finishedAt': summary.finishedAt,
      'durationMs': summary.durationMs,
      if (summary.createdAt != null) 'createdAt': summary.createdAt,
      if (summary.elapsedMs != null) 'elapsedMs': summary.elapsedMs,
      'thinkingSummary': summary.thinkingSummary,
      'thinkingContent': summary.thinkingContent == null
          ? null
          : contentRefToJson(summary.thinkingContent!),
    },
  },
};
Object _liveJson(LiveDisplayWindow live) => {
  'revision': live.revision,
  'historyThrough': live.historyThrough,
  'executionPresent': live.executionPresent,
  'older': live.older,
  'blocks': [
    for (final b in live.blocks)
      {
        'id': b.id,
        'blockOrder': b.blockOrder,
        'body': _displayBodyJson(b.body),
        'closing': b.closing,
      },
  ],
};
int _timelineBytes(TimelineBatch batch) => _demoEncoded({
  'presentationVersion': batch.presentationVersion,
  'placement': batch.placement.name,
  'before': batch.before,
  'fromPos': batch.fromPos,
  'throughPos': batch.throughPos,
  'live': batch.live == null ? null : _liveJson(batch.live!),
  'blocks': [
    for (final b in batch.blocks)
      {
        'id': b.id,
        'historyPos': b.historyPos,
        'body': _displayBodyJson(b.body),
      },
  ],
});

extension _DemoTimelineReader on _DemoReader {
  DisplayBlockBody fitDisplay(DisplayBlockBody body) => switch (body) {
    SingleDisplayBlock(:final atom, :final completionId) => SingleDisplayBlock(
      atom: fit(atom, 0),
      completionId: completionId,
    ),
    WorkDisplayBlock() => body,
  };

  LiveDisplayWindow livePage(ReadDemand demand, {String? before}) {
    _demoDemand(demand);
    final history = _history;
    final revision = history.displayRevision;
    final blocks = history.liveBlocks();
    final end = before == null
        ? blocks.length
        : boundary(before, 'display-live', revision);
    final selected = <LiveDisplayBlock>[];
    String? older;
    LiveDisplayWindow page() => LiveDisplayWindow(
      revision: revision,
      historyThrough: history.displayHead,
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
        body: fitDisplay(b.body),
        closing: b.closing,
      );
      final next = i > 0 ? cursor('display-live', revision, i) : null;
      final trial = LiveDisplayWindow(
        revision: revision,
        historyThrough: history.displayHead,
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
    if (_demoEncoded(_liveJson(result)) > demand.maxBytes) {
      throw _demoQueryFailure(
        'InvalidDemand: live display envelope does not fit',
      );
    }
    return result;
  }

  TimelineBatch timelinePage(
    ReadDemand demand, {
    String? before,
    bool initial = false,
  }) {
    _demoDemand(demand);
    final h0 = before == null
        ? _history.displayHead
        : boundary('h0:$before', 'display-h0', 0);
    final end = before == null
        ? h0 + 1
        : boundary(before, 'display-history', h0);
    final records = _history.displayBlocks
        .where((b) => b.historyPos < end)
        .toList();
    DisplayBlock fitted(DisplayBlock b) => DisplayBlock(
      id: b.id,
      historyPos: b.historyPos,
      body: fitDisplay(b.body),
    );
    String? historyCursor(int index) {
      if (index == 0) return null;
      final token = cursor('display-history', h0, records[index].historyPos);
      _cursors['h0:$token'] = ('display-h0', 0, h0);
      return token;
    }

    // Reserve the actual newest history envelope before allocating live's
    // bounded suffix. Both surfaces share the caller's byte budget.
    final reserved = TimelineBatch(
      presentationVersion: presentationVersion,
      placement: ChatPlacement.set,
      blocks: records.isEmpty ? [] : [fitted(records.last)],
      before: records.isEmpty ? null : historyCursor(records.length - 1),
      throughPos: h0,
    );
    final live = initial
        ? livePage(
            ReadDemand(
              maxItems: demand.maxItems,
              maxBytes: demand.maxBytes - _timelineBytes(reserved) + 4,
            ),
          )
        : null;
    final selected = <DisplayBlock>[];
    String? next;
    TimelineBatch batch() => TimelineBatch(
      presentationVersion: presentationVersion,
      placement: before == null ? ChatPlacement.set : ChatPlacement.prepend,
      blocks: selected,
      before: next,
      throughPos: h0,
      live: live,
    );
    for (var i = records.length - 1; i >= 0; i--) {
      final candidate = fitted(records[i]);
      final token = historyCursor(i);
      final trial = TimelineBatch(
        presentationVersion: presentationVersion,
        placement: batch().placement,
        blocks: [candidate, ...selected],
        before: token,
        throughPos: h0,
        live: live,
      );
      if (_timelineBytes(trial) > demand.maxBytes) {
        if (selected.isEmpty) {
          throw _demoQueryFailure(
            'InvalidDemand: display envelope does not fit',
          );
        }
        break;
      }
      selected.insert(0, candidate);
      next = token;
      if (selected.length == demand.maxItems) break;
    }
    if (_timelineBytes(batch()) > demand.maxBytes) {
      throw _demoQueryFailure('InvalidDemand: timeline envelope does not fit');
    }
    return batch();
  }

  LiveDisplayWindow timelineTarget(ReadDemand demand) {
    final through = _history.displayHead;
    final empty = TimelineBatch(
      presentationVersion: presentationVersion,
      placement: ChatPlacement.append,
      blocks: [],
      fromPos: through,
      throughPos: through,
    );
    return livePage(
      ReadDemand(
        maxItems: demand.maxItems,
        maxBytes: demand.maxBytes - _timelineBytes(empty) + 4,
      ),
    );
  }

  TimelineBatch timelineAppend(
    ReadDemand demand,
    int from,
    LiveDisplayWindow target,
  ) {
    final records = _history.displayBlocks.where(
      (b) => b.historyPos > from && b.historyPos <= target.historyThrough,
    );
    final selected = <DisplayBlock>[];
    var through = from;
    for (final b in records) {
      final candidate = DisplayBlock(
        id: b.id,
        historyPos: b.historyPos,
        body: fitDisplay(b.body),
      );
      final trial = TimelineBatch(
        presentationVersion: presentationVersion,
        placement: ChatPlacement.append,
        blocks: [...selected, candidate],
        fromPos: from,
        throughPos: b.historyPos,
      );
      if (selected.length == demand.maxItems ||
          _timelineBytes(trial) > demand.maxBytes) {
        if (selected.isEmpty) {
          throw _demoQueryFailure(
            'InvalidDemand: display envelope does not fit',
          );
        }
        break;
      }
      selected.add(candidate);
      through = b.historyPos;
    }
    // A partial append carries no live replacement: it cannot retire an ID
    // before the matching sealed block reaches the consumer.
    LiveDisplayWindow? live;
    if (through == target.historyThrough) {
      final combined = TimelineBatch(
        presentationVersion: presentationVersion,
        placement: ChatPlacement.append,
        blocks: selected,
        fromPos: from,
        throughPos: through,
        live: target,
      );
      if (_timelineBytes(combined) <= demand.maxBytes) {
        live = target;
      } else if (selected.isEmpty) {
        throw _demoQueryFailure(
          'InvalidDemand: timeline envelope does not fit',
        );
      }
    }
    return TimelineBatch(
      presentationVersion: presentationVersion,
      placement: ChatPlacement.append,
      blocks: selected,
      fromPos: from,
      throughPos: through,
      live: live,
    );
  }
}

final class _DemoTimelineFeed extends _DemoConversationFeed
    implements TimelineFeed {
  _DemoTimelineFeed(
    DemoStudioTransport api,
    String threadId,
    _DemoHistory history,
    ReadDemand demand,
  ) : super(
        api,
        threadId,
        history,
        const MainChatScope(),
        demand,
        timeline: true,
      );

  @override
  Future<TimelineBatch> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) => reader._read(() => reader.timelinePage(demand, before: before));
  @override
  Future<LiveDisplayWindow> loadLiveOlder({
    required String before,
    required ReadDemand demand,
  }) => reader._read(() => reader.livePage(demand, before: before));
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
    if (reference.databaseId != _history.epoch) throw _demoStale();
    final known =
        _history.displayBlocks.any(
          (b) => b.id == reference.blockId && b.body is WorkDisplayBlock,
        ) ||
        _history.liveBlocks().any(
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
                'atom': chatAtomToJson(e.atom),
                'completionId': e.completionId,
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
        atom: reader.fit(h.atom, 0),
        completionId: h.completionId,
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
