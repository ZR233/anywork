import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart';

import 'conversation_current_owner.dart';

/// One display-lease-owned complete member result, stable across live/history.
/// ReadDemand limits each transport batch, not the accepted group size.
final class DisplayMemberController extends ChangeNotifier {
  DisplayMemberController({
    required this.reference,
    required this.demand,
    required this.open,
  }) {
    _restart();
  }
  final DisplayBlockRef reference;
  final ReadDemand demand;
  final Future<DisplayMembers> Function(DisplayBlockRef, ReadDemand) open;
  List<DisplayMemberHead> _entries = const [];
  List<DisplayMemberHead> get entries => _entries;
  int? revision;
  bool sealed = false;
  bool get hasSnapshot => revision != null;
  Object? _error;
  Object? cleanupError;
  Object? get error => cleanupError ?? _error;
  bool loading = true;
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
      if (entry.record.contentSource is! CurrentAtom) continue;
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

  void _restart() {
    if (_retired) return;
    _qualification = Object();
    final qualification = _qualification;
    _closeHandle();
    _error = null;
    loading = true;
    notifyListeners();
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
      final handle = await open(reference, demand);
      if (!_eligible(qualification)) {
        _close(handle);
        return;
      }
      _handle = handle;
      final pending = <DisplayMemberHead>[];
      final keys = <String>{};
      int? pendingRevision;
      bool? pendingSealed;
      // Continuity belongs to this qualified reader, not the retained UI cut.
      // Keep skipped live results here too while awaiting a sealed snapshot.
      int? observedRevision;
      List<DisplayMemberHead>? observedEntries;
      bool completedSealed = false;
      while (_eligible(qualification)) {
        final batch = await handle.next();
        if (!_eligible(qualification)) return;
        if (batch == null) {
          if (pendingRevision != null || !completedSealed || awaitingSealed) {
            throw const ConversationContinuityError(
              'Incomplete display member result',
            );
          }
          loading = false;
          _closeHandle();
          return;
        }
        if (completedSealed) {
          throw const ConversationContinuityError(
            'Display member data after sealed result',
          );
        }
        if (batch.block != reference ||
            batch.offset != pending.length ||
            (pendingRevision != null &&
                (pendingRevision != batch.revision ||
                    pendingSealed != batch.sealed)) ||
            (!batch.complete && batch.entries.isEmpty)) {
          throw const ConversationContinuityError(
            'Inconsistent display member batch',
          );
        }
        pendingRevision ??= batch.revision;
        pendingSealed ??= batch.sealed;
        for (final entry in batch.entries) {
          if (!keys.add(entry.memberKey) ||
              (pending.isNotEmpty &&
                  pending.last.memberOrder >= entry.memberOrder)) {
            throw const ConversationContinuityError(
              'Invalid display member order or key',
            );
          }
          pending.add(entry);
        }
        if (!batch.complete) continue;
        final next = List<DisplayMemberHead>.unmodifiable(pending);
        final firstResult = observedRevision == null;
        final previousRevision = observedRevision ?? revision;
        final previousEntries = observedEntries ?? entries;
        final previousSealed = firstResult ? sealed : completedSealed;
        if (previousRevision != null &&
            (batch.revision < previousRevision ||
                (previousSealed && !batch.sealed) ||
                (batch.revision == previousRevision &&
                    ((!firstResult && (previousSealed || !batch.sealed)) ||
                        next.length != previousEntries.length ||
                        !Iterable<int>.generate(next.length).every(
                          (i) => _sameMember(previousEntries[i], next[i]),
                        ))))) {
          throw const ConversationContinuityError(
            'Display member revision did not advance',
          );
        }
        observedRevision = batch.revision;
        observedEntries = next;
        completedSealed = batch.sealed;
        pending.clear();
        keys.clear();
        pendingRevision = null;
        pendingSealed = null;
        if (_requiresSealed && !batch.sealed) continue;
        final structural =
            loading ||
            _error != null ||
            sealed != batch.sealed ||
            !listEquals(
              entries.map((e) => e.memberKey).toList(),
              next.map((e) => e.memberKey).toList(),
            );
        _entries = next;
        revision = batch.revision;
        sealed = batch.sealed;
        _retireDisclosures(keep: next.map((e) => e.memberKey).toSet());
        loading = false;
        _error = null;
        // Register accepted state before callbacks: listeners may synchronously
        // retire the lease. Never publish another row after that revocation.
        for (final entry in next) {
          if (!_eligible(qualification)) return;
          final row = _rows.putIfAbsent(
            entry.memberKey,
            () => ValueNotifier(null),
          );
          if (!_sameMember(row.value, entry)) row.value = entry;
        }
        if (!_eligible(qualification)) return;
        final acceptedKeys = next.map((e) => e.memberKey).toSet();
        for (final key in _rows.keys.toList()) {
          if (!acceptedKeys.contains(key)) {
            _rows[key]!.value = null;
          }
        }
        if (structural) notifyListeners();
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
    revision = null;
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
      CurrentAtom() => 'current',
      FrozenObservation(:final capturedAt, :final available) => (
        'frozen',
        capturedAt,
        available,
      ),
      CompletedOriginal(:final completionId) => ('completed', completionId),
    },
    atom.id,
    atom.completionItemId,
    atom.completionSeq,
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
