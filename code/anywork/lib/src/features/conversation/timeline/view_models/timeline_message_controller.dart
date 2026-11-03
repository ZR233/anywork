import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:math' as math;

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_encoding.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../state/chat_item_presentation.dart';
import '../state/timeline_display_unit.dart';
import '../state/timeline_image_resources.dart';

/// Sole presentation reducer inside the existing serial feed admission. The
/// controller owns committed units; this owner retains only uncommitted units
/// and their bounded member props. It never reads a body or waits for layout.
final class TimelineMessageController implements ConversationBatchConsumer {
  TimelineMessageController(
    this.controller, {
    required this.generation,
    required this.imageResources,
    this.displayDemand,
    this.groupForeground = true,
    this.onUnitCreated,
    this.onUnitRetired,
  });
  final InMemoryChatController controller;
  final int generation;
  final TimelineImageResources imageResources;
  final ReadDemand? displayDemand;
  final bool groupForeground;
  final void Function(TimelineDisplayUnit unit)? onUnitCreated;
  final void Function(TimelineDisplayUnit unit)? onUnitRetired;
  final ValueNotifier<List<TimelineDisplayUnit>> live = ValueNotifier(const []);
  final ValueNotifier<bool> hasUnmaterialized = ValueNotifier(false);
  final List<TimelineDisplayUnit> _pending = [];
  final Map<ChatSourceId, _CompletionInterval> _blockedRanges = {};
  _CompletionInterval? _ordinaryRange;
  bool get hasRecoveryDemand => _ordinaryRange != null;

  /// One scalar interval per genuinely blocked source, plus one ordinary demand.
  /// The opaque identity invalidates a prior fixed-cut read when bounds expand.
  (Object, int, int)? get recoveryRange {
    final range = _ordinaryRange ?? _blockedRanges.values.firstOrNull;
    return range == null ? null : (range, range.lower, range.upper);
  }

  (int, int) get retainedCompletedBudget {
    final atoms = _pending
        .expand((unit) => unit.members)
        .where((atom) => atom.lifecycle is TerminalChatAtom)
        .toSet();
    return (
      atoms.length,
      atoms.fold(0, (bytes, atom) => bytes + _encodedCompletedPropsBytes(atom)),
    );
  }

  final Map<ChatSourceId, ChatSourceState> _sources = {};
  int _serial = 0;
  int _observedWindow = 1;
  bool _disposed = false;
  bool _setting = false;
  // One ordinary Main cursor chain; no per-member history index. EOF covers the
  // old query prefix, whereas Append is reliable continuous admission.
  bool _historyEof = false;
  Object _historyRange = Object();
  bool _receivingStream = false;
  bool _completeAdmission = false;
  int? _completionCeiling;
  int _mainCeiling = 0;
  Object? _admissionRange;
  TimelineExpansionIntent? _detailIntent;
  List<ChatAtom> _pageFacts = const [];
  int get length => controller.messages.length;
  int get _window => displayDemand?.maxItems ?? _observedWindow;

  TimelineUnitKind _kind(ChatAtom atom) => !groupForeground
      ? atom.kind == ChatAtomKind.text || atom.kind == ChatAtomKind.input
            ? TimelineUnitKind.text
            : TimelineUnitKind.receipt
      : switch (atom.kind) {
          ChatAtomKind.input || ChatAtomKind.text => TimelineUnitKind.text,
          ChatAtomKind.reasoning ||
          ChatAtomKind.toolCall ||
          ChatAtomKind.fileChange ||
          ChatAtomKind.skill ||
          ChatAtomKind.unknown
              when atom.source is ForegroundTurnChatSource &&
                  atom.delivery != ChatDeliveryKind.independent =>
            TimelineUnitKind.work,
          _ => TimelineUnitKind.receipt,
        };

  @override
  Future<void> applyBatch(
    ChatBatch batch, {
    TimelineExpansionIntent? windowIntent,
    Object? windowRange,
  }) async {
    _checkActive();
    final atoms = batch.entries
        .whereType<ChatAtomEntry>()
        .map((entry) => entry.atom)
        .toList();
    // Reject mismatched annotations before mutating a Set or any display.
    for (final atom in [...atoms, ...?batch.current?.atoms]) {
      if (atom.sourceState case final state? when state.source != atom.source) {
        throw StateError(
          'Atom ${atom.id} has lifecycle evidence for a different source',
        );
      }
    }
    if (windowIntent != null && windowIntent.current == null) {
      throw const StaleConversationScope();
    }
    final localWindow = windowIntent != null || windowRange != null;
    _setting = !localWindow && batch.placement == ChatPlacement.set;
    final resolvingPrefix =
        !localWindow &&
        !_historyEof &&
        batch.placement == ChatPlacement.prepend &&
        batch.before == null;
    try {
      if (_setting) {
        _pending.clear();
        _sources.clear();
        _blockedRanges.clear();
        _ordinaryRange = null;
        _mainCeiling = 0;
        _historyRange = Object();
        _historyEof = batch.before == null;
      }
      if (!localWindow &&
          batch.placement == ChatPlacement.prepend &&
          batch.before == null) {
        _historyEof = true;
      }
      _detailIntent = windowIntent;
      if (!localWindow && batch.placement != ChatPlacement.append) {
        for (final atom in atoms) {
          _mainCeiling = math.max(_mainCeiling, atom.completionSeq ?? 0);
        }
      }
      _completionCeiling = !localWindow
          ? _mainCeiling
          : windowIntent?.completionAnchor ??
                windowIntent?.current?.completionThrough ??
                (windowRange is _CompletionInterval ? windowRange.upper : null);
      _completeAdmission = !localWindow
          ? batch.placement != ChatPlacement.append && _historyEof
          : batch.before == null;
      _admissionRange =
          windowIntent?.ordinaryRange ?? windowRange ?? _historyRange;
      _receivingStream = batch.placement == ChatPlacement.append;
      _pageFacts = [...atoms, ...?batch.current?.atoms];
      _observedWindow = math.max(
        _observedWindow,
        math.max(atoms.length, batch.current?.atoms.length ?? 0),
      );
      _rememberBatchSources(batch, atoms);
      // Current is unfinished fact, not an alternate completed-tail collection.
      // Admit all current starts before terminal facts, preserving overlap and
      // allowing a late reasoning terminal to release an already completed text.
      for (final atom in batch.current?.atoms ?? const <ChatAtom>[]) {
        await _admit(atom, batch);
      }
      for (final atom in atoms) {
        await _admit(atom, batch);
      }
      if (resolvingPrefix || localWindow && batch.before == null) {
        await _resolveCoveredPrefix(_admissionRange!, seed: windowIntent);
      }
      if (windowIntent != null) await _refreshDetail(windowIntent, atoms);
      _closeFromFacts();
      await _commitPrefix(older: batch.placement == ChatPlacement.prepend);
      _checkActive();
      _enforceCompletedBudget(preferred: localWindow ? atoms : const []);
      _releaseUnblockedRanges();
      // Preserve cross-source admission slots; only order facts within their
      // source. Mixing source-order and completion-order in one comparator is
      // non-transitive when parts finish in reverse order.
      for (final source in _pending.map((unit) => unit.source).toSet()) {
        final indices = [
          for (var i = 0; i < _pending.length; i++)
            if (_pending[i].source == source) i,
        ];
        final units = indices.map((index) => _pending[index]).toList()
          ..sort(_order);
        for (var i = 0; i < indices.length; i++) {
          _pending[indices[i]] = units[i];
        }
      }
      live.value = List.unmodifiable(_pending);
      hasUnmaterialized.value =
          _ordinaryRange != null || _blockedRanges.isNotEmpty;
      _pruneSources();
      developer.Timeline.instantSync(
        'conversation.applied',
        arguments: {
          'generation': generation,
          'placement': batch.placement.name,
          'acceptedEntries': batch.entries.length,
          'controllerMessages': length,
          'liveUnits': _pending.length,
        },
      );
    } finally {
      _setting = false;
      _receivingStream = false;
      _pageFacts = const [];
      _detailIntent = null;
      _admissionRange = null;
      _completeAdmission = false;
      _completionCeiling = null;
    }
  }

  void _rememberSource(ChatSourceState state) {
    final previous = _sources[state.source];
    if (previous?.lifecycle is EndedChatSource &&
        state.lifecycle is! EndedChatSource) {
      return;
    }
    if (previous?.lifecycle is ActiveChatSource &&
        state.lifecycle is UnknownChatSource) {
      return;
    }
    _sources[state.source] = state;
  }

  void _rememberBatchSources(ChatBatch batch, List<ChatAtom> atoms) {
    for (final entry in batch.entries.whereType<ChatSourceEntry>()) {
      _rememberSource(entry.state);
    }
    for (final state in batch.current?.sources ?? const <ChatSourceState>[]) {
      _rememberSource(state);
    }
    for (final atom in [...atoms, ...?batch.current?.atoms]) {
      if (atom.sourceState case final state?) _rememberSource(state);
    }
  }

  void _pruneSources() {
    final activeSources = _pending.map((unit) => unit.source).toSet();
    activeSources.addAll(_blockedRanges.keys);
    _sources.removeWhere((source, _) => !activeSources.contains(source));
  }

  ChatSourceLifecycle? _rememberedLifecycle(TimelineDisplayUnit unit) {
    final lifecycle = _sources[unit.source]?.lifecycle;
    if (unit.sourceLifecycle is EndedChatSource ||
        unit.sourceLifecycle is ActiveChatSource &&
            lifecycle is UnknownChatSource) {
      return unit.sourceLifecycle;
    }
    return lifecycle ?? unit.sourceLifecycle;
  }

  List<TimelineDisplayUnit> get _history => [
    for (final message in _setting ? const <Message>[] : controller.messages)
      if (message.metadata?[timelineDisplayUnitKey]
          case final TimelineDisplayUnit unit)
        unit,
  ];
  int _order(TimelineDisplayUnit a, TimelineDisplayUnit b) {
    if (a.source == b.source && a.source is ForegroundTurnChatSource) {
      // A Turn reserves its stable source position before model parts exist.
      // Its terminal receipt closes that source, not the position of its start.
      final aTerminal = a.members.any(
        (atom) => atom.kind == ChatAtomKind.turnReceipt,
      );
      final bTerminal = b.members.any(
        (atom) => atom.kind == ChatAtomKind.turnReceipt,
      );
      if (aTerminal != bTerminal) return aTerminal ? 1 : -1;
    }
    if (a.source == b.source && a.firstOrder != null && b.firstOrder != null) {
      return a.firstOrder!.compareTo(b.firstOrder!);
    }
    return (a.completionThrough ?? 0).compareTo(b.completionThrough ?? 0);
  }

  bool _contains(TimelineDisplayUnit unit, ChatAtom atom) =>
      unit.source == atom.source &&
      (unit.members.any((member) => member.id == atom.id) ||
          (atom.sourceOrder != null &&
              unit.firstOrder != null &&
              unit.lastOrder != null &&
              atom.sourceOrder! >= unit.firstOrder! &&
              atom.sourceOrder! <= unit.lastOrder!));
  bool _adjacent(
    TimelineDisplayUnit unit,
    ChatAtom atom, {
    bool completeRange = false,
    Iterable<ChatAtom>? facts,
    Iterable<TimelineDisplayUnit>? units,
  }) =>
      unit.source == atom.source &&
      unit.kind == TimelineUnitKind.work &&
      _kind(atom) == TimelineUnitKind.work &&
      atom.sourceOrder != null &&
      unit.firstOrder != null &&
      unit.lastOrder != null &&
      (unit.lowerSeparator == null ||
          atom.sourceOrder! > unit.lowerSeparator!) &&
      (unit.upperSeparator == null ||
          atom.sourceOrder! < unit.upperSeparator!) &&
      (completeRange ||
          _completeAdmission &&
              (_completionCeiling == null ||
                  (unit.completionThrough ?? 0) <= _completionCeiling! &&
                      (atom.completionSeq ?? 0) <= _completionCeiling!) ||
          _receivingStream &&
              unit.streamConnected &&
              atom.sourceOrder! > unit.lastOrder!) &&
      !(facts ?? _pageFacts).any(
        (other) =>
            other.source == atom.source &&
            _kind(other) != TimelineUnitKind.work &&
            other.sourceOrder != null &&
            other.sourceOrder! >
                math.min(unit.firstOrder!, atom.sourceOrder!) &&
            other.sourceOrder! < math.max(unit.lastOrder!, atom.sourceOrder!),
      ) &&
      !(units ?? [..._pending, ..._history]).any(
        (other) =>
            other.source == atom.source &&
            other.kind != TimelineUnitKind.work &&
            other.firstOrder != null &&
            other.firstOrder! > math.min(unit.firstOrder!, atom.sourceOrder!) &&
            other.firstOrder! < math.max(unit.lastOrder!, atom.sourceOrder!),
      );

  Future<void> _admit(ChatAtom atom, ChatBatch batch) async {
    final all = [..._pending, ..._history];
    var matches = all.where((unit) => _contains(unit, atom)).toList();
    if (matches.isEmpty) {
      matches = all.where((unit) => _adjacent(unit, atom)).toList();
    }
    matches.sort(
      (a, b) => identical(a.expansion, _detailIntent)
          ? -1
          : identical(b.expansion, _detailIntent)
          ? 1
          : 0,
    );
    if (matches.isEmpty) {
      final kind = _kind(atom);
      final unit = TimelineDisplayUnit(
        id: kind == TimelineUnitKind.work
            ? 'work:$generation:${++_serial}'
            : atom.id,
        source: atom.source,
        kind: kind,
        members: const [],
        live: true,
        closedForAdmission: kind != TimelineUnitKind.work,
        memberCount: 0,
        activeCount: 0,
        failedCount: 0,
        stoppedCount: 0,
        olderCursor: batch.placement == ChatPlacement.append
            ? null
            : batch.before,
        streamConnected:
            _receivingStream ||
            _completeAdmission ||
            atom.lifecycle is ActiveChatAtom,
        incompleteRange: !_receivingStream && !_completeAdmission
            ? _admissionRange
            : null,
      );
      onUnitCreated?.call(unit);
      final next = _withAtom(unit, atom);
      next.expansion.current = next;
      _pending.add(next);
      return;
    }
    // A member update never rekeys its existing live/history object.
    final previous = matches.first;
    var next = _withAtom(previous, atom);
    if (identical(next, previous) && matches.length == 1) return;
    for (final other in matches.skip(1)) {
      if (other.kind != TimelineUnitKind.work ||
          previous.kind != TimelineUnitKind.work) {
        continue;
      }
      next = _merge(next, other);
      final removed = _pending.any((unit) => unit.id == other.id);
      final message = other.expansion.committedMessage;
      _retireUnit(other);
      _pending.removeWhere((unit) => unit.id == other.id);
      if (!removed) {
        await controller.removeMessage(message!, animated: false);
      }
    }
    final pendingIndex = _pending.indexWhere((unit) => unit.id == previous.id);
    if (pendingIndex >= 0) {
      _pending[pendingIndex] = next;
      next.expansion.current = next;
    } else {
      await _replaceHistory(previous, next);
    }
  }

  Future<void> _resolveCoveredPrefix(
    Object range, {
    TimelineExpansionIntent? seed,
  }) async {
    // EOF removes precisely the original cursor chain's unknown prefix. Only
    // weld work runs formerly separated by that unknown range; keep every
    // unrelated row and every real structural separator in place.
    final observed = [..._pending, ..._history];
    final affected = observed.where(
      (unit) =>
          identical(unit.incompleteRange, range) ||
          identical(unit.expansion, seed),
    );
    for (final source in affected.map((unit) => unit.source).toSet()) {
      final local = affected.where((unit) => unit.source == source).toList();
      if (local.any(
        (unit) => unit.firstOrder == null || unit.lastOrder == null,
      )) {
        continue;
      }
      final low = local.map((unit) => unit.firstOrder!).reduce(math.min);
      final high = local.map((unit) => unit.lastOrder!).reduce(math.max);
      // Every loaded structural barrier participates, even if it completed
      // above this window's cut. The cut limits merge eligibility, not evidence.
      final ordered = observed
          .where(
            (unit) =>
                unit.source == source &&
                unit.firstOrder != null &&
                unit.lastOrder != null &&
                unit.lastOrder! >= low &&
                unit.firstOrder! <= high,
          )
          .toList();
      if (ordered.any((unit) => unit.firstOrder == null)) continue;
      ordered.sort((a, b) => a.firstOrder!.compareTo(b.firstOrder!));
      for (var index = 0; index + 1 < ordered.length;) {
        final left = ordered[index], right = ordered[index + 1];
        if (left.kind != TimelineUnitKind.work ||
            right.kind != TimelineUnitKind.work ||
            (_completionCeiling != null &&
                ((left.completionThrough ?? 0) > _completionCeiling! ||
                    (right.completionThrough ?? 0) > _completionCeiling!)) ||
            (left.upperSeparator != null &&
                right.firstOrder! >= left.upperSeparator!) ||
            (right.lowerSeparator != null &&
                left.lastOrder! <= right.lowerSeparator!)) {
          index++;
          continue;
        }
        if (!identical(left.incompleteRange, range) &&
            !identical(right.incompleteRange, range) &&
            !identical(left.expansion, seed) &&
            !identical(right.expansion, seed)) {
          index++;
          continue;
        }
        final retained = identical(right.expansion, seed)
            ? right
            : left.expansion.committedMessage != null
            ? left
            : right;
        final removed = identical(retained, left) ? right : left;
        final next = _merge(retained, removed);
        final message = removed.expansion.committedMessage;
        _retireUnit(removed);
        _pending.removeWhere((unit) => unit.id == removed.id);
        if (message != null) {
          await controller.removeMessage(message, animated: false);
        }
        final pending = _pending.indexWhere((unit) => unit.id == retained.id);
        if (pending >= 0) {
          _pending[pending] = next;
          retained.expansion.current = next;
        } else {
          await _replaceHistory(retained, next);
        }
        ordered[index] = next;
        ordered.removeAt(index + 1);
      }
    }
  }

  Future<void> _refreshDetail(
    TimelineExpansionIntent intent,
    List<ChatAtom> atoms,
  ) async {
    final original = intent.current;
    if (original == null) throw const StaleConversationScope();
    // Every returned atom has already entered the sole reducer. A detail only
    // borrows members whose run is now established; other fragments stay in
    // the same controller, even when this ordinary window is still non-EOF.
    final selected = atoms
        .where(
          (atom) => _contains(original, atom) && _kind(atom) == original.kind,
        )
        .toList();
    var lower = original.lowerSeparator;
    var upper = original.upperSeparator;
    for (final atom in atoms) {
      if (atom.source != original.source ||
          _kind(atom) == TimelineUnitKind.work ||
          atom.sourceOrder == null) {
        continue;
      }
      if (original.firstOrder != null &&
          atom.sourceOrder! < original.firstOrder!) {
        lower = math.max(lower ?? atom.sourceOrder!, atom.sourceOrder!);
      }
      if (original.lastOrder != null &&
          atom.sourceOrder! > original.lastOrder!) {
        upper = math.min(upper ?? atom.sourceOrder!, atom.sourceOrder!);
      }
    }
    if (selected.isEmpty &&
        lower == original.lowerSeparator &&
        upper == original.upperSeparator) {
      return;
    }
    final active = original.members.where(
      (atom) => atom.lifecycle is ActiveChatAtom,
    );
    final anchor = original.lastCompletion;
    final members = [
      ...active,
      if (anchor != null && !active.any((part) => part.id == anchor.id)) anchor,
      ...selected.where(
        (atom) =>
            atom.id != anchor?.id && !active.any((part) => part.id == atom.id),
      ),
    ]..sort((a, b) => (a.sourceOrder ?? 0).compareTo(b.sourceOrder ?? 0));
    final next = original.copy(
      members: selected.isEmpty ? original.members : members,
      lowerSeparator: lower,
      upperSeparator: upper,
    );
    final index = _pending.indexWhere((value) => value.id == next.id);
    if (index >= 0) {
      _pending[index] = next;
      intent.current = next;
      live.value = List.unmodifiable(_pending);
    } else {
      await _replaceHistory(original, next);
    }
  }

  TimelineDisplayUnit _withAtom(TimelineDisplayUnit unit, ChatAtom atom) {
    final previous = unit.members
        .where((member) => member.id == atom.id)
        .firstOrNull;
    final covered = previous == null && _contains(unit, atom);
    if (previous?.lifecycle is TerminalChatAtom) return unit;
    if (covered) {
      if (_detailIntent == null && _admissionRange == _historyRange) {
        return unit;
      }
      return unit.copy(
        members: [...unit.members, atom]
          ..sort((a, b) => (a.sourceOrder ?? 0).compareTo(b.sourceOrder ?? 0)),
      );
    }
    final isNew = previous == null;
    final terminal = atom.lifecycle is TerminalChatAtom;
    final active =
        unit.activeCount +
        (isNew && !terminal ? 1 : 0) -
        (!isNew && terminal && previous.lifecycle is ActiveChatAtom ? 1 : 0);
    final members = [
      for (final member in unit.members)
        if (member.id != atom.id) member,
      atom,
    ];
    members.sort(
      (a, b) => (a.sourceOrder ?? a.completionSeq ?? 0).compareTo(
        b.sourceOrder ?? b.completionSeq ?? 0,
      ),
    );
    final terminals = members
        .where((member) => member.lifecycle is TerminalChatAtom)
        .toList();
    final tail =
        unit.expansion.committedMessage == null || terminals.length <= _window
        ? terminals
        : terminals.sublist(terminals.length - _window);
    final retained =
        [
          ...members.where((member) => member.lifecycle is ActiveChatAtom),
          ...tail,
        ]..sort(
          (a, b) => (a.sourceOrder ?? a.completionSeq ?? 0).compareTo(
            b.sourceOrder ?? b.completionSeq ?? 0,
          ),
        );
    final order = atom.sourceOrder;
    final outcome = switch (atom.lifecycle) {
      TerminalChatAtom(:final outcome) => outcome,
      ActiveChatAtom() => null,
    };
    final categories = Map<TimelineProcessKind, int>.of(unit.categories);
    if (isNew) {
      categories.update(
        timelineProcessKind(atom),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return unit.copy(
      categories: categories,
      members: retained,
      memberCount: unit.memberCount + (isNew ? 1 : 0),
      activeCount: active,
      failedCount:
          unit.failedCount + (outcome == ChatTerminalOutcome.failed ? 1 : 0),
      stoppedCount:
          unit.stoppedCount +
          (outcome == ChatTerminalOutcome.cancelled ? 1 : 0),
      firstOrder: order == null
          ? null
          : unit.firstOrder == null
          ? order
          : math.min(order, unit.firstOrder!),
      lastOrder: order == null
          ? null
          : unit.lastOrder == null
          ? order
          : math.max(order, unit.lastOrder!),
      completionThrough: atom.completionSeq == null
          ? null
          : math.max(unit.completionThrough ?? 0, atom.completionSeq!),
      startedAt: atom.startedAt == null
          ? null
          : unit.startedAt == null
          ? atom.startedAt
          : math.min(atom.startedAt!, unit.startedAt!),
      finishedAt: atom.finishedAt == null
          ? null
          : math.max(unit.finishedAt ?? atom.finishedAt!, atom.finishedAt!),
    );
  }

  TimelineDisplayUnit _merge(TimelineDisplayUnit a, TimelineDisplayUnit b) {
    final categories = Map<TimelineProcessKind, int>.of(a.categories);
    for (final category in b.categories.entries) {
      categories.update(
        category.key,
        (count) => count + category.value,
        ifAbsent: () => category.value,
      );
    }
    final members = [...a.members, ...b.members]
      ..sort((a, b) => (a.sourceOrder ?? 0).compareTo(b.sourceOrder ?? 0));
    final active = members
        .where((member) => member.lifecycle is ActiveChatAtom)
        .toList();
    final terminal = members
        .where((member) => member.lifecycle is TerminalChatAtom)
        .toList();
    final retained = [
      ...active,
      ...terminal.skip(
        a.expansion.committedMessage == null
            ? 0
            : math.max(0, terminal.length - _window),
      ),
    ]..sort((a, b) => (a.sourceOrder ?? 0).compareTo(b.sourceOrder ?? 0));
    return a.copy(
      categories: categories,
      members: retained,
      memberCount: a.memberCount + b.memberCount,
      activeCount: a.activeCount + b.activeCount,
      failedCount: a.failedCount + b.failedCount,
      stoppedCount: a.stoppedCount + b.stoppedCount,
      closedForAdmission: a.closedForAdmission || b.closedForAdmission,
      firstOrder: math.min(a.firstOrder!, b.firstOrder!),
      lastOrder: math.max(a.lastOrder!, b.lastOrder!),
      completionThrough: math.max(
        a.completionThrough ?? 0,
        b.completionThrough ?? 0,
      ),
      startedAt: a.startedAt == null
          ? b.startedAt
          : b.startedAt == null
          ? a.startedAt
          : math.min(a.startedAt!, b.startedAt!),
      finishedAt: a.finishedAt == null
          ? b.finishedAt
          : b.finishedAt == null
          ? a.finishedAt
          : math.max(a.finishedAt!, b.finishedAt!),
    );
  }

  void _closeFromFacts() {
    final all = [..._pending, ..._history];
    for (var i = 0; i < _pending.length; i++) {
      final unit = _pending[i];
      final knownEnd = _history
          .where(
            (other) =>
                other.source == unit.source &&
                other.sourceLifecycle is EndedChatSource,
          )
          .firstOrNull;
      final ended =
          _sources[unit.source]?.lifecycle is EndedChatSource ||
          knownEnd != null;
      final successor = all.any(
        (other) =>
            other.source == unit.source &&
            other.kind != TimelineUnitKind.work &&
            other.firstOrder != null &&
            unit.lastOrder != null &&
            other.firstOrder! > unit.lastOrder!,
      );
      var lower = unit.lowerSeparator;
      var upper = unit.upperSeparator;
      for (final other in all) {
        if (other.source != unit.source ||
            other.kind == TimelineUnitKind.work ||
            other.firstOrder == null ||
            unit.firstOrder == null ||
            unit.lastOrder == null) {
          continue;
        }
        if (other.firstOrder! < unit.firstOrder!) {
          lower = lower == null
              ? other.firstOrder
              : math.max(lower, other.firstOrder!);
        }
        if (other.firstOrder! > unit.lastOrder!) {
          upper = upper == null
              ? other.firstOrder
              : math.min(upper, other.firstOrder!);
        }
      }
      _pending[i] = unit.copy(
        closedForAdmission: unit.closedForAdmission || ended || successor,
        sourceLifecycle:
            knownEnd?.sourceLifecycle ?? _rememberedLifecycle(unit),
        lowerSeparator: lower,
        upperSeparator: upper,
      );
      _pending[i].expansion.current = _pending[i];
    }
  }

  Future<void> _commitPrefix({required bool older}) async {
    final ready = <TimelineDisplayUnit>[];
    while (_pending.isNotEmpty) {
      final eligible =
          _pending.where((unit) {
            if (!unit.ready) return false;
            if (unit.source is! ForegroundTurnChatSource) return true;
            return !_pending.any(
              (prior) =>
                  prior.id != unit.id &&
                  prior.source == unit.source &&
                  _order(prior, unit) < 0,
            );
          }).toList()..sort((a, b) {
            final order = (a.completionThrough ?? 0).compareTo(
              b.completionThrough ?? 0,
            );
            return order == 0
                ? _pending.indexOf(a).compareTo(_pending.indexOf(b))
                : order;
          });
      if (eligible.isEmpty) break;
      final unit = eligible.first;
      _pending.removeWhere((pending) => pending.id == unit.id);
      ready.add(unit.copy(live: false));
    }
    if (_setting) {
      await controller.setMessages(
        ready.map(_message).toList(),
        animated: false,
      );
      return;
    }
    // Coalesce only actually contiguous insertions, preserving Flyer's batch
    // operations and old row identity without rebuilding loaded history.
    final run = <TimelineDisplayUnit>[];
    int? runIndex;
    Future<void> flush() async {
      if (run.isEmpty) return;
      await controller.insertAllMessages(
        run.map(_message).toList(),
        index: runIndex!,
        animated: false,
      );
      run.clear();
    }

    for (final unit in ready) {
      var index = _insertionIndex(
        unit,
        unknownPrependIndex: older && unit.completionThrough == null ? 0 : null,
      );
      if (run.isNotEmpty && index != runIndex) {
        await flush();
        index = _insertionIndex(
          unit,
          unknownPrependIndex: older && unit.completionThrough == null
              ? 0
              : null,
        );
      }
      if (run.isEmpty) runIndex = index;
      run.add(unit);
    }
    await flush();
  }

  Message _message(TimelineDisplayUnit unit, {bool bounded = true}) {
    final active = unit.members.where(
      (atom) => atom.lifecycle is ActiveChatAtom,
    );
    final terminal = unit.members
        .where((atom) => atom.lifecycle is TerminalChatAtom)
        .toList();
    if (bounded && terminal.length > _window) {
      unit = unit.copy(
        members: [...active, ...terminal.skip(terminal.length - _window)],
      );
    }
    final atom = unit.members.firstOrNull;
    final presentation =
        unit.kind == TimelineUnitKind.work ||
            atom == null ||
            atom.payload == null
        ? ChatItemPresentation.forUnit(unit)
        : ChatItemPresentation.decode(atom);
    final message = Message.custom(
      id: unit.id,
      authorId: presentation.authorId,
      createdAt: presentation.createdAt,
      metadata: {
        chatItemPresentationKey: presentation,
        timelineDisplayUnitKey: unit,
      },
    );
    unit.expansion
      ..current = unit
      ..committedMessage = message;
    return message;
  }

  Future<void> _replaceHistory(
    TimelineDisplayUnit old,
    TimelineDisplayUnit next,
  ) async {
    final previous = old.expansion.committedMessage!;
    await controller.updateMessage(previous, _message(next, bounded: false));
  }

  int _insertionIndex(TimelineDisplayUnit unit, {int? unknownPrependIndex}) {
    final history = _history;
    var lower = 0;
    var upper = history.length;
    final same = history.where((other) => other.source == unit.source).toList();
    for (final other in same) {
      final position = history.indexOf(other);
      if (_order(other, unit) < 0) {
        lower = math.max(lower, position + 1);
      } else {
        upper = math.min(upper, position);
      }
    }
    final later = history
        .where(
          (other) =>
              (other.completionThrough ?? 0) > (unit.completionThrough ?? 0),
        )
        .firstOrNull;
    final suggested =
        unknownPrependIndex ??
        (later == null ? history.length : history.indexOf(later));
    return suggested.clamp(lower, upper);
  }

  void _checkActive() {
    if (_disposed) throw StateError('Timeline display is retired');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final unit in _pending) {
      _retireUnit(unit);
    }
    _pending.clear();
    _sources.clear();
    _blockedRanges.clear();
    _ordinaryRange = null;
    live.dispose();
    hasUnmaterialized.dispose();
  }

  void _retireUnit(TimelineDisplayUnit unit) {
    final intent = unit.expansion;
    // Revoke inherited body tokens before owner callbacks or controller removal
    // can reenter an old mounted subtree. retire() owns the one body retirement.
    intent.retire();
    onUnitRetired?.call(unit);
    intent
      ..current = null
      ..committedMessage = null
      ..readBody = null
      ..retireBody = null
      ..readEarlier = null
      ..onVisibilityChanged = null
      ..registerDisplay = null
      ..isDisplayActive = (() => false)
      ..expanded = null
      ..before = null
      ..error = null;
    intent.changed();
  }

  void _rememberMissing(ChatAtom atom) {
    final seq = atom.completionSeq;
    if (seq == null) {
      throw StateError('Completed atom has no observed completion position');
    }
    final blocked = _sourceBlocks(atom.source, atom.sourceOrder);
    if (blocked) {
      _blockedRanges[atom.source] = _CompletionInterval.include(
        _blockedRanges[atom.source],
        seq,
        sourceOrder: atom.sourceOrder,
      );
    } else {
      _ordinaryRange = _CompletionInterval.include(_ordinaryRange, seq);
    }
  }

  void _releaseUnblockedRanges() {
    for (final source in _blockedRanges.keys.toList()) {
      if (_sourceBlocks(source, _blockedRanges[source]!.highestOrder)) continue;
      final range = _blockedRanges.remove(source)!;
      _ordinaryRange = _CompletionInterval.merge(_ordinaryRange, range);
    }
  }

  bool _sourceBlocks(ChatSourceId source, int? throughOrder) => _pending.any(
    (unit) =>
        unit.source == source &&
        !unit.ready &&
        (throughOrder == null ||
            unit.firstOrder == null ||
            unit.firstOrder! <= throughOrder),
  );

  /// Called by the original lease only after its page was serially admitted.
  /// No IDs, DTOs or per-page cursor history survive range completion.
  void finishRecovery(Object identity) {
    if (identical(_ordinaryRange, identity)) _ordinaryRange = null;
    _blockedRanges.removeWhere(
      (source, range) =>
          identical(range, identity) &&
          !_sourceBlocks(source, range.highestOrder),
    );
    hasUnmaterialized.value =
        _ordinaryRange != null || _blockedRanges.isNotEmpty;
  }

  void _enforceCompletedBudget({required List<ChatAtom> preferred}) {
    final completed = _pending
        .expand((unit) => unit.members)
        .where((atom) => atom.lifecycle is TerminalChatAtom)
        .toSet()
        .toList();
    final wanted = preferred.map((atom) => atom.id).toSet();
    completed.sort((a, b) {
      final priority =
          (wanted.contains(b.id) ? 1 : 0) - (wanted.contains(a.id) ? 1 : 0);
      return priority != 0
          ? priority
          : (b.completionSeq ?? 0).compareTo(a.completionSeq ?? 0);
    });
    final retained = <ChatAtom>{};
    var bytes = 0;
    for (final atom in completed) {
      final size = _encodedCompletedPropsBytes(atom);
      if (retained.length < _window &&
          bytes + size <= (displayDemand?.maxBytes ?? 262144)) {
        retained.add(atom);
        bytes += size;
      } else {
        _rememberMissing(atom);
      }
    }
    final missingSources = <ChatSourceId>{};
    for (var i = _pending.length - 1; i >= 0; i--) {
      final unit = _pending[i];
      final members = unit.members
          .where(
            (atom) =>
                atom.lifecycle is ActiveChatAtom || retained.contains(atom),
          )
          .toList();
      if (members.length == unit.members.length) continue;
      if (members.isEmpty) {
        missingSources.add(unit.source);
        _pending.removeAt(i);
        _retireUnit(unit);
        continue;
      }
      // One surviving proven run may keep its scalar loaded summary. No
      // member/segment skeleton survives when the whole object leaves demand.
      final next = unit.copy(members: members);
      _pending[i] = next;
      next.expansion.current = next;
    }
    for (var i = 0; i < _pending.length; i++) {
      if (!missingSources.contains(_pending[i].source)) continue;
      final next = _pending[i].copy(streamConnected: false);
      _pending[i] = next;
      next.expansion.current = next;
    }
  }
}

final class _CompletionInterval {
  _CompletionInterval(this.lower, this.upper, [this.highestOrder]);
  final int lower;
  final int upper;
  final int? highestOrder;
  static _CompletionInterval include(
    _CompletionInterval? old,
    int seq, {
    int? sourceOrder,
  }) {
    final order = old == null
        ? sourceOrder
        : old.highestOrder == null || sourceOrder == null
        ? null
        : math.max(old.highestOrder!, sourceOrder);
    return old != null &&
            seq >= old.lower &&
            seq <= old.upper &&
            old.highestOrder == order
        ? old
        : _CompletionInterval(
            math.min(old?.lower ?? seq, seq),
            math.max(old?.upper ?? seq, seq),
            order,
          );
  }

  static _CompletionInterval merge(
    _CompletionInterval? a,
    _CompletionInterval b,
  ) => include(include(a, b.lower), b.upper);
}

// Wire accounting belongs to the SDK's canonical entry encoder. Also reserve
// the actual encoded values retained by the existing decoded UI presentation;
// these values are not a wire DTO, persistence format or alternate atom schema.
int _encodedCompletedPropsBytes(ChatAtom atom) {
  final entryBytes = chatAtomEntryEncodedLength(atom);
  if (atom.payload == null) return entryBytes;
  final presentation = ChatItemPresentation.decode(atom);
  return entryBytes +
      utf8
          .encode(
            jsonEncode([
              presentation.id,
              presentation.compatibility.name,
              presentation.type,
              presentation.data,
              presentation.raw,
              if (presentation.reference case final reference?)
                contentRefToJson(reference),
              presentation.byteLength,
              presentation.authorId,
              presentation.createdAt?.toIso8601String(),
              presentation.presentationContract,
              presentation.diagnostic,
              for (final body in presentation.bodies)
                [
                  body.key,
                  body.byteLength,
                  body.inline,
                  if (body.reference case final reference?)
                    contentRefToJson(reference),
                ],
            ]),
          )
          .length;
}
