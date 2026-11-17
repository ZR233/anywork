import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart';

import 'conversation_current_owner.dart';
import '../state/timeline_display_unit.dart';

/// One display-lease-owned bounded member demand, stable across live/history.
final class DisplayMemberController extends ChangeNotifier {
  DisplayMemberController({
    required this.reference,
    required this.demand,
    required this.open,
  }) {
    select(const LatestDisplayMembers());
  }
  final DisplayBlockRef reference;
  final ReadDemand demand;
  final Future<DisplayMembers> Function(
    DisplayBlockRef,
    DisplayMemberWindow,
    ReadDemand,
  )
  open;
  DisplayMemberWindow window = const LatestDisplayMembers();
  DisplayMemberPage? page;
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
  final List<DisplayMemberWindow> _newer = [];
  int? _seekAfter;
  Future<void> _joins = Future.value();

  bool get isActive => !_retired;
  bool get awaitingSealed => _requiresSealed && page?.sealed != true;
  bool get hasNewer => _newer.isNotEmpty;
  ValueListenable<DisplayMemberHead?> member(String key) =>
      _rows.putIfAbsent(key, () => ValueNotifier(null));

  // Only window descriptors are retained, never previous mutable pages. Each
  // accepted result is one backend cut, including the overlapping anchor row.
  void older() {
    final current = page;
    if (loading || current == null || !current.hasOlder) return;
    if (window is LatestDisplayMembers) {
      _newer.add(window);
      _newer.add(
        BeforeDisplayMembers(memberOrder: current.entries.last.memberOrder + 1),
      );
    } else {
      _newer.add(window);
    }
    _select(
      BeforeDisplayMembers(
        memberOrder:
            current.entries.first.memberOrder +
            (current.entries.length > 1 ? 1 : 0),
      ),
    );
  }

  void newer() {
    if (loading || _newer.isEmpty) return;
    _seekAfter = page?.entries.lastOrNull?.memberOrder;
    _select(_newer.removeLast());
  }

  void holdLatest() {
    final current = page;
    if (loading ||
        window is! LatestDisplayMembers ||
        current == null ||
        current.entries.isEmpty) {
      return;
    }
    _newer.add(window);
    _select(
      BeforeDisplayMembers(memberOrder: current.entries.last.memberOrder + 1),
    );
  }

  TimelineMemberDisclosure disclosure(String memberKey) =>
      _disclosures.putIfAbsent(memberKey, TimelineMemberDisclosure.new);

  /// The accepted block head revoked mutable rows before this independent
  /// member observation delivered its sealed cut. Keep only disclosure intent.
  void requireSealed() {
    if (_retired || _requiresSealed) return;
    _requiresSealed = true;
    if (page?.sealed == true) return;
    loading = true;
    for (final entry in page?.entries ?? const <DisplayMemberHead>[]) {
      if (entry.record.contentSource is! CurrentAtomSource) continue;
      final key = entry.memberKey;
      final previous = _disclosures[key];
      if (previous == null) continue;
      previous.retire();
      _disclosures[key] = TimelineMemberDisclosure()
        ..expanded = previous.expanded;
    }
  }

  void _retireDisclosures({Set<String> keep = const {}}) {
    for (final key in _disclosures.keys.toList()) {
      if (keep.contains(key)) continue;
      _disclosures.remove(key)!.retire();
    }
  }

  void select(DisplayMemberWindow next) {
    _newer.clear();
    _seekAfter = null;
    _select(next);
  }

  void _select(DisplayMemberWindow next) {
    if (_retired) return;
    _qualification = Object();
    final qualification = _qualification;
    _closeHandle();
    window = next;
    // Keep the current bounded page visible until its replacement is accepted.
    // It is never merged with the new page, even when their revisions differ.
    _error = null;
    loading = true;
    notifyListeners();
    final pull = _pull(qualification, next);
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
    _select(window);
  }

  bool _eligible(Object qualification) =>
      !_retired && identical(_qualification, qualification);

  Future<void> _pull(Object qualification, DisplayMemberWindow selected) async {
    DisplayMembers? handle;
    try {
      await _joins;
      if (!_eligible(qualification)) return;
      if (_closing.isNotEmpty) {
        throw cleanupError ?? StateError('Member window still closing');
      }
      handle = await open(reference, selected, demand);
      if (!_eligible(qualification)) {
        _close(handle);
        return;
      }
      _handle = handle;
      while (_eligible(qualification)) {
        final value = await handle.next();
        if (!_eligible(qualification)) return;
        if (value == null) {
          if (awaitingSealed) {
            throw const ConversationContinuityError(
              'Sealed display member snapshot is unavailable',
            );
          }
          final changed = loading;
          loading = false;
          _closeHandle();
          if (changed) notifyListeners();
          return;
        }
        if (_requiresSealed && !value.sealed) continue;
        final seek = _seekAfter;
        if (seek != null &&
            value.entries.isNotEmpty &&
            value.entries.first.memberOrder > seek &&
            value.before != null) {
          // New members may have filled more than one Latest window while the
          // user was reading. Discover only cursor descriptors on the way back
          // to the reading boundary; never publish a page that skips the gap.
          _newer.add(selected);
          _select(
            BeforeDisplayMembers(
              memberOrder:
                  value.entries.first.memberOrder +
                  (value.entries.length > 1 ? 1 : 0),
            ),
          );
          return;
        }
        _seekAfter = null;
        final previous = page;
        final structural =
            loading ||
            _error != null ||
            previous?.sealed != value.sealed ||
            previous?.before != value.before ||
            !listEquals(
              previous?.entries.map((e) => e.memberKey).toList(),
              value.entries.map((e) => e.memberKey).toList(),
            );
        page = value;
        _retireDisclosures(
          keep: value.entries.map((entry) => entry.memberKey).toSet(),
        );
        loading = false;
        _error = null;
        for (final entry in value.entries) {
          final row = _rows.putIfAbsent(
            entry.memberKey,
            () => ValueNotifier(null),
          );
          if (!_sameMember(row.value, entry)) row.value = entry;
        }
        final keys = value.entries.map((entry) => entry.memberKey).toSet();
        for (final key in _rows.keys.toList()) {
          if (!keys.contains(key)) _rows.remove(key)!.dispose();
        }
        if (structural) notifyListeners();
        // Sealed is still one real page. Consume the explicit EOF next, rather
        // than synthesizing another page or leaving a useless history watch.
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
        if (!_retired) {
          notifyListeners();
        }
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
    page = null;
    _newer.clear();
    _seekAfter = null;
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
      CurrentAtomSource() => 'current',
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
