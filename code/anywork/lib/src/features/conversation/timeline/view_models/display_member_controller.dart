import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart';

import '../state/timeline_current_projection.dart';
import '../state/timeline_display_unit.dart';
import 'conversation_current_owner.dart';

/// One display-lease-owned complete member result, stable across live/history.
/// ReadDemand limits each transport batch, not the accepted group size.
final class DisplayMemberController extends ChangeNotifier {
  DisplayMemberController({
    required this.reference,
    required bool groupClosed,
    required this.demand,
    required this.open,
    bool readHistory = true,
  }) : _groupClosed = groupClosed,
       loading = readHistory {
    _requiresSealed = groupClosed;
    if (readHistory) _restart();
  }
  DisplayBlockRef reference;
  bool _groupClosed;
  final ReadDemand demand;
  final Future<DisplayMembers> Function(DisplayBlockRef, ReadDemand, bool) open;
  List<DisplayMemberHead> _entries = const [];
  List<DisplayMemberHead> _history = const [];
  List<CurrentAtom> _liveAtoms = const [];
  Map<String, CurrentAtom> _currentById = const {};
  Map<String, CurrentAtom> _currentByCall = const {};
  CurrentAtomSnapshot? _current;
  List<DisplayMemberHead> get entries => _entries;
  bool sealed = false;
  bool hasSnapshot = false;
  Object? _error;
  Object? cleanupError;
  Object? get error => cleanupError ?? _error;
  bool loading;
  bool _retired = false;
  bool _requiresSealed = false;
  Object _qualification = Object();
  DisplayMembers? _handle;
  final Set<DisplayMembers> _closing = {};
  final Set<Future<void>> _pulls = {};
  final Map<String, TimelineMemberDisclosure> _disclosures = {};
  final Map<String, ValueNotifier<DisplayMemberHead?>> _rows = {};
  Future<void> _joins = Future.value();

  bool get isActive => !_retired;
  bool get awaitingSealed => _requiresSealed && !sealed;
  ValueListenable<DisplayMemberHead?> member(String key) =>
      _rows.putIfAbsent(key, () => ValueNotifier(null));
  void rebase(DisplayBlockRef next, {required bool groupClosed}) {
    if (_retired || reference == next && _groupClosed == groupClosed) {
      return;
    }
    final sameOpenGroup =
        !_groupClosed && !groupClosed && reference.blockId == next.blockId;
    reference = next;
    _groupClosed = groupClosed;
    _requiresSealed = groupClosed;
    hasSnapshot = false;
    sealed = false;
    if (!sameOpenGroup) {
      final expanded = {
        for (final entry in _disclosures.entries)
          entry.key: entry.value.expanded,
      };
      _retireDisclosures();
      for (final entry in expanded.entries) {
        _disclosures[entry.key] = TimelineMemberDisclosure()
          ..expanded = entry.value;
      }
    }
    _restart(notify: !sameOpenGroup);
  }

  /// Apply Current values to the accepted History cut without reopening it.
  void updateLive({
    required List<CurrentAtom> atoms,
    required CurrentAtomSnapshot? current,
  }) {
    if (_retired ||
        _groupClosed ||
        identical(current, _current) && listEquals(atoms, _liveAtoms)) {
      return;
    }
    _liveAtoms = atoms;
    _current = current;
    _currentById = {
      for (final atom in current?.currentAtoms ?? const <CurrentAtom>[])
        if (atom.contents.isNotEmpty) atom.id: atom,
    };
    _currentByCall = {
      for (final atom in _currentById.values)
        if (atom.tool?.callId case final callId?) callId: atom,
    };
    _publishRows(_qualification);
  }

  TimelineMemberDisclosure disclosure(String memberKey) =>
      _disclosures.putIfAbsent(memberKey, TimelineMemberDisclosure.new);

  /// Revoke CurrentAtom body scopes synchronously, before any closing animation
  /// or the independently transported sealed snapshot finishes.
  void requireSealed() {
    if (_retired || _requiresSealed) return;
    _requiresSealed = true;
    if (sealed) return;
    loading = true;
    for (final entry in entries) {
      if (entry.record.contentSource is! CurrentAtomSource) continue;
      final previous = _disclosures[entry.memberKey];
      if (previous == null) continue;
      previous.retire();
      _disclosures[entry.memberKey] = TimelineMemberDisclosure()
        ..expanded = previous.expanded;
    }
    notifyListeners();
  }

  void _retireDisclosures({Set<String> keep = const {}}) {
    for (final key in _disclosures.keys.toList()) {
      if (!keep.contains(key)) _disclosures.remove(key)!.retire();
    }
  }

  void _restart({bool notify = true}) {
    if (_retired) return;
    _qualification = Object();
    final qualification = _qualification;
    _closeHandle();
    final hadError = _error != null;
    _error = null;
    loading = true;
    if (notify || hadError) notifyListeners();
    final pull = _pull(qualification);
    _pulls.add(pull);
    unawaited(pull.whenComplete(() => _pulls.remove(pull)));
  }

  Future<void> retry() async {
    await _joins;
    if (_retired) return;
    for (final handle in List.of(_closing)) {
      _closing.remove(handle);
      _close(handle);
    }
    _restart();
  }

  bool _eligible(Object qualification) =>
      !_retired && identical(_qualification, qualification);

  Future<void> _pull(Object qualification) async {
    try {
      await _joins;
      if (!_eligible(qualification)) return;
      if (_closing.isNotEmpty) {
        throw cleanupError ?? StateError('Member reader still closing');
      }
      final cut = reference;
      final closedGroup = _groupClosed;
      final handle = await open(cut, demand, closedGroup);
      if (!_eligible(qualification)) {
        _close(handle);
        return;
      }
      _handle = handle;
      final pending = <DisplayMemberHead>[];
      final keys = <String>{};
      final orders = <int>{};
      while (_eligible(qualification)) {
        final batch = await handle.next();
        if (!_eligible(qualification)) return;
        if (batch == null) {
          throw const ConversationContinuityError(
            'Incomplete History group result',
          );
        }
        if (batch.block != cut ||
            batch.offset != pending.length ||
            batch.entries.length > demand.maxItems ||
            (!batch.complete && batch.entries.isEmpty)) {
          throw const ConversationContinuityError(
            'Inconsistent History group batch',
          );
        }
        for (final entry in batch.entries) {
          if (entry.memberKey.isEmpty ||
              !keys.add(entry.memberKey) ||
              !orders.add(entry.memberOrder)) {
            throw const ConversationContinuityError(
              'Invalid History member identity or order',
            );
          }
          pending.add(entry);
        }
        if (!batch.complete) continue;
        // Transport pages are newest first; owner indices define display order.
        pending.sort(
          (left, right) => left.memberOrder.compareTo(right.memberOrder),
        );
        _history = pending;
        hasSnapshot = true;
        final statusChanged = closedGroup && (loading || !sealed);
        sealed = closedGroup;
        loading = false;
        _error = null;
        _closeHandle();
        _publishRows(qualification, statusChanged: statusChanged);
        return;
      }
    } catch (failure) {
      if (_eligible(qualification)) {
        _error = failure;
        loading = false;
        _closeHandle();
        notifyListeners();
      }
    }
  }

  void _publishRows(Object qualification, {bool statusChanged = false}) {
    final ownerId = _current?.ownerId;
    final next = <DisplayMemberHead>[
      for (final entry in _history)
        if (_groupClosed || ownerId == null || _currentById.isEmpty)
          entry
        else
          DisplayMemberHead(
            memberKey: entry.memberKey,
            memberOrder: entry.memberOrder,
            record: TimelineCurrentProjection.overlayRecord(
              entry.record,
              current: _currentById,
              currentByCall: _currentByCall,
              ownerId: ownerId,
              fallbackRunId: reference.runId,
            ),
          ),
    ];
    if (!_groupClosed && _liveAtoms.isNotEmpty) {
      final representedIds = {for (final entry in next) entry.record.atom.id};
      final representedCalls = {
        for (final entry in next)
          entry.record.callId ?? entry.record.atom.tool?.callId,
      };
      final representedKeys = {for (final entry in next) entry.memberKey};
      for (final atom in _liveAtoms) {
        final callId = atom.tool?.callId;
        final key = callId == null ? 'entity:${atom.id}' : 'call:$callId';
        if (representedIds.contains(atom.id) ||
            (callId != null && representedCalls.contains(callId)) ||
            !representedKeys.add(key)) {
          continue;
        }
        next.add(
          DisplayMemberHead(
            memberKey: key,
            memberOrder: next.isEmpty ? 0 : next.last.memberOrder + 1,
            record: DisplayRecord(
              atom: TimelineCurrentProjection.toChatAtom(atom),
              contentSource: const CurrentAtomSource(),
              currentContents: atom.contents,
            ),
          ),
        );
      }
    }

    final structural = !listEquals(
      [for (final entry in entries) entry.memberKey],
      [for (final entry in next) entry.memberKey],
    );
    final keys = {for (final entry in next) entry.memberKey};
    // Publish the complete accepted rows before any synchronous callbacks.
    _entries = List.unmodifiable(next);
    _retireDisclosures(keep: keys);
    for (final entry in next) {
      if (!_eligible(qualification)) return;
      final row = _rows.putIfAbsent(entry.memberKey, () => ValueNotifier(null));
      if (!_sameMember(row.value, entry)) row.value = entry;
    }
    for (final key in _rows.keys.toList()) {
      if (!_eligible(qualification)) return;
      if (!keys.contains(key)) _rows[key]!.value = null;
    }
    if (_eligible(qualification) && (structural || statusChanged)) {
      notifyListeners();
    }
  }

  void _close(DisplayMembers handle) {
    if (!_closing.add(handle)) return;
    try {
      handle.requestClose();
    } catch (failure) {
      cleanupError = failure;
    }
    _joins = _joins.then((_) async {
      try {
        await handle.close();
        _closing.remove(handle);
        if (_closing.isEmpty && cleanupError != null) {
          cleanupError = null;
          if (!_retired) notifyListeners();
        }
      } catch (failure) {
        cleanupError = failure;
        if (!_retired) notifyListeners();
      }
    });
  }

  void _closeHandle() {
    final handle = _handle;
    _handle = null;
    if (handle != null) _close(handle);
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    _qualification = Object();
    _closeHandle();
    _entries = const [];
    _history = const [];
    _liveAtoms = const [];
    _currentById = const {};
    _currentByCall = const {};
    _current = null;
    hasSnapshot = false;
    sealed = false;
    for (final row in _rows.values) {
      row.dispose();
    }
    _rows.clear();
    _retireDisclosures();
  }

  Future<void> close() async {
    retire();
    while (_pulls.isNotEmpty) {
      await Future.wait(List.of(_pulls));
    }
    await _joins;
  }
}

bool _sameMember(DisplayMemberHead? a, DisplayMemberHead b) =>
    a != null &&
    a.memberKey == b.memberKey &&
    a.memberOrder == b.memberOrder &&
    _recordValue(a.record) == _recordValue(b.record) &&
    _samePayload(a.record.atom.payload, b.record.atom.payload) &&
    listEquals(
      a.record.currentContents.map((c) => (c.role, c.reference)).toList(),
      b.record.currentContents.map((c) => (c.role, c.reference)).toList(),
    ) &&
    listEquals(
      a.record.atom.contents.map((c) => (c.role, c.reference)).toList(),
      b.record.atom.contents.map((c) => (c.role, c.reference)).toList(),
    );

Object? _fact(ChatFactPosition? value) =>
    value == null ? null : (value.effectSeq, value.suborder);

Object _lifecycle(ChatAtomLifecycle value) => switch (value) {
  ActiveChatAtom(:final started, :final status) => (_fact(started), status),
  TerminalChatAtom(:final started, :final ended, :final outcome) => (
    _fact(started),
    _fact(ended),
    outcome,
  ),
};

Object? _sourceState(ChatSourceState? value) => value == null
    ? null
    : (
        value.source,
        switch (value.lifecycle) {
          UnknownChatSource() => 'unknown',
          ActiveChatSource() => 'active',
          EndedChatSource(:final outcome) => outcome,
        },
        _fact(value.started),
        _fact(value.ended),
      );

Object _recordValue(DisplayRecord record) {
  final atom = record.atom;
  return (
    _fact(record.startFact),
    _fact(record.endFact),
    switch (record.contentSource) {
      CurrentAtomSource() => 'current',
      FrozenObservation(:final capturedAt, :final available) => (
        'frozen',
        capturedAt,
        available,
      ),
      CompletedOriginal(:final completionId) => ('completed', completionId),
    },
    atom.id,
    record.historyEventId,
    record.historyDetailEventId,
    record.runId,
    record.isTerminalHistory,
    record.isFrozenHistory,
    record.callId,
    record.predecodedPresentation?.raw,
    record.predecodedPresentation?.compatibility,
    atom.source,
    _sourceState(atom.sourceState),
    atom.sourceOrder,
    atom.kind,
    atom.delivery,
    _lifecycle(atom.lifecycle),
    atom.turnId,
    atom.attemptId,
    (atom.tool?.callId, atom.tool?.name),
    atom.wait,
    atom.textChannel,
    atom.contentPresent,
    atom.startedAt,
    atom.finishedAt,
  );
}

bool _samePayload(PayloadData? a, PayloadData? b) => switch ((a, b)) {
  (null, null) => true,
  (InlinePayload(:final bytes), InlinePayload(bytes: final other)) =>
    listEquals(bytes, other),
  (
    DeferredPayload(:final reference, :final byteLength),
    DeferredPayload(reference: final other, byteLength: final length),
  ) =>
    reference == other && byteLength == length,
  _ => false,
};
