import 'dart:math';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/lifecycle.dart' show ClientResourceClosed;

import '../state/timeline_display_models.dart';
import '../state/work_group_event_folder.dart';

/// Reads and folds one fixed History WorkRange, with bounded call backfills.
///
/// The caller owns the borrowed scope; closing members only stops this demand.
final class HistoryWorkRangeMembers implements DisplayMembers {
  HistoryWorkRangeMembers._(this.scope, this.reference, this.demand);

  static Future<HistoryWorkRangeMembers> open(
    HistoryReadScope scope, {
    required DisplayBlockRef reference,
    required ReadDemand demand,
  }) async {
    if (reference.blockId.isEmpty || !scope.isActive) {
      throw const StaleConversationScope();
    }
    return HistoryWorkRangeMembers._(scope, reference, demand);
  }

  final HistoryReadScope scope;
  final DisplayBlockRef reference;
  final ReadDemand demand;
  List<DisplayMemberHead>? _folded;
  int _offset = 0;
  bool _done = false;
  bool _closed = false;

  @override
  Future<DisplayMemberBatch?> next() async {
    if (_closed || !scope.isActive || _done) {
      return null;
    }
    var folded = _folded;
    if (folded == null) {
      final rangeEvents = await _loadAllRangeEvents();
      if (_closed || !scope.isActive) return null;
      final backfilledByCall = <String, List<HistoryEventRecord>>{};
      final attemptedBackfills = <String>{};
      var result = WorkGroupEventFolder.fold(
        rangeEvents: rangeEvents,
        backfilledCallEvents: backfilledByCall,
        attemptedCallBackfills: attemptedBackfills,
      );
      if (result.missingCallIds.isNotEmpty) {
        var added = false;
        for (final callId in result.missingCallIds) {
          attemptedBackfills.add(callId);
          final fetched = await _loadCallEvents(callId);
          if (_closed || !scope.isActive) return null;
          if (fetched.isNotEmpty) {
            backfilledByCall[callId] = fetched;
            added = true;
          }
        }
        if (added) {
          result = WorkGroupEventFolder.fold(
            rangeEvents: rangeEvents,
            backfilledCallEvents: backfilledByCall,
            attemptedCallBackfills: attemptedBackfills,
          );
        }
      }
      folded = _folded = result.entries;
    }

    if (folded.isEmpty) {
      _done = true;
      return DisplayMemberBatch(
        block: reference,
        offset: _offset,
        complete: true,
        entries: const [],
      );
    }
    final limit = demand.maxItems > 0 ? demand.maxItems : 1;
    final start = _offset;
    final end = min(start + limit, folded.length);
    final entries = folded.sublist(start, end);
    _offset = end;
    _done = end >= folded.length;
    return DisplayMemberBatch(
      block: reference,
      offset: start,
      complete: _done,
      entries: entries,
    );
  }

  Future<List<HistoryEventRecord>> _loadAllRangeEvents() async {
    final collected = <HistoryEventRecord>[];
    final seenEventIds = <String>{};
    final seenCursors = <String>{};
    String? cursor;
    while (true) {
      if (_closed) return collected;
      if (!scope.isActive) throw const StaleConversationScope();
      final previousCursor = cursor;
      final page = await scope.workRangePage(
        afterSeq: reference.afterSeq,
        beforeSeq: reference.beforeSeq,
        cut: reference.cut,
        cursor: cursor,
        demand: HistoryDemand(
          maxRows: demand.maxItems,
          maxBytes: demand.maxBytes,
        ),
      );
      if (page.cut != reference.cut ||
          page.afterSeq != reference.afterSeq ||
          page.beforeSeq != reference.beforeSeq) {
        throw const ConversationContinuityError(
          'History work range page changed its fixed cut or bounds',
        );
      }
      if (page.next?.isEmpty ?? false) {
        throw const ConversationContinuityError(
          'History work range page returned an empty cursor',
        );
      }
      if (page.next != null &&
          (page.next == previousCursor ||
              !seenCursors.add(page.next!) ||
              page.events.isEmpty)) {
        throw const ConversationContinuityError(
          'History work range page made no bounded cursor progress',
        );
      }
      // workRangePage returns raw work events in ascending seq order.
      for (final event in page.events) {
        if (event.eventId.isEmpty) {
          throw const ConversationContinuityError(
            'History work range returned an empty event identity',
          );
        }
        if (seenEventIds.add(event.eventId)) {
          collected.add(event);
        }
      }
      cursor = page.next;
      if (cursor == null) return collected;
    }
  }

  Future<List<HistoryEventRecord>> _loadCallEvents(String callId) async {
    final collected = <HistoryEventRecord>[];
    final seenEventIds = <String>{};
    final seenCursors = <String>{};
    String? cursor;
    try {
      while (true) {
        if (_closed) return collected;
        if (!scope.isActive) throw const StaleConversationScope();
        final page = await scope.eventsPage(
          query: CallHistoryEvents(callId),
          cut: reference.cut,
          cursor: cursor,
          demand: HistoryDemand(
            maxRows: demand.maxItems,
            maxBytes: demand.maxBytes,
          ),
        );
        if (page.cut != reference.cut) return collected;
        for (final event in page.entries) {
          if (event.eventId.isNotEmpty && seenEventIds.add(event.eventId)) {
            collected.add(event);
          }
        }
        final next = page.next;
        if (next == null || next.isEmpty || !seenCursors.add(next)) {
          return collected;
        }
        if (page.entries.isEmpty) return collected;
        cursor = next;
      }
    } on StaleConversationScope {
      rethrow;
    } on ClientResourceClosed {
      rethrow;
    } catch (_) {
      // Single missing/failed call backfill falls back gracefully to in-range events.
      return collected;
    }
  }

  @override
  void requestClose() {
    _closed = true;
  }

  @override
  Future<void> close() async {
    requestClose();
  }
}
