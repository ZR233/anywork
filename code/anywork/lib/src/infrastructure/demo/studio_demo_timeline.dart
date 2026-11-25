part of 'studio_demo_api.dart';

// A controlled story declaration, not an atom classifier. Only IDs and member
// heads live here; bodies and completion originals remain in _DemoHistory.
final class _DemoDisplayScript {
  _DemoDisplayScript(this.id, this.memberIds, {required this.work, this.turnId})
    : startedAtMillis = DateTime.now().millisecondsSinceEpoch;
  final String id;
  final List<String> memberIds;
  final bool work;
  final String? turnId;
  bool sealed = false;
  int? blockOrder;
  final int startedAtMillis;
  int? finishedAtMillis;
}

extension _DemoDisplayHistory on _DemoHistory {
  DisplayBlockRef displayRef(String id) => DisplayBlockRef(
    blockId: id,
    cut: HistoryCut('demo-cut:$epoch'),
    anchorSeq: 0,
    headSeq: 0,
  );

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
  }

  void updateDisplayMember(String itemId) {
    final id = displayMembership[itemId];
    if (id == null) return; // Explicitly hidden from this controlled story.
    final script = displayScripts[id]!;
    if (script.sealed) return;
    final entry = byId[itemId];
    final atom = entry?.message ?? activeAtoms[itemId];
    if (atom == null) return;
    script.blockOrder ??= ++historyLastOrder;
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
            : CompletedOriginal(completionId: entry.message.id),
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
        startedAtMillis: script.startedAtMillis,
        finishedAtMillis: script.sealed ? script.finishedAtMillis : null,
      ),
      executionPresent: false,
      memberCount: script.memberIds.length,
      unfinishedCount: script.memberIds
          .where((id) => activeAtoms.containsKey(id))
          .length,
      groupClosed: script.sealed,
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
    script.finishedAtMillis = DateTime.now().millisecondsSinceEpoch;
    script.sealed = true;
    displayBlocks.add(
      DisplayBlock(
        id: id,
        blockOrder: script.blockOrder!,
        body: scriptBody(script),
      ),
    );
    displayBlocks.sort((a, b) => a.blockOrder.compareTo(b.blockOrder));
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
}
