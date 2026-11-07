import 'dart:async';

import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads through the production Main lease and original SDK query scopes.
/// Only test counters and one bounded member page/body window are retained.
final class TimelineOutputConsumption {
  TimelineOutputConsumption({
    required this.lease,
    required this.session,
    required this.conversations,
    required this.turnId,
    required this.executionId,
  }) : _attempt = lease.content.currentAttemptId,
       _scope = lease.content.openScope(generation: lease.generation);

  final TimelineDisplayLease lease;
  final ConversationSession session;
  final ConversationRepository conversations;
  final String turnId;
  final String executionId;
  final AttemptId? _attempt;
  final ConversationQueryScope _scope;
  final _clock = Stopwatch()..start();
  final _outputs = <String>{};
  int _bytes = 0;
  int _reads = 0;
  int _rangeReads = 0;
  int _watchWindows = 0;
  int _runningReads = 0;
  int _runningBytes = 0;
  int _memberScopes = 0;
  int _memberPages = 0;
  int _sealedEnds = 0;
  int _peakWindowBytes = 0;
  bool _watchEnded = false;

  Future<T> _within<T>(Future<T> operation) {
    final remaining = const Duration(minutes: 6) - _clock.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('Original timeline consumption deadline');
    }
    return operation.timeout(remaining);
  }

  bool get _running {
    final execution = session.state.runtime?.execution;
    final turn = session.state.activeTurn;
    return execution?.id == executionId &&
        execution?.turnId == turnId &&
        execution?.phase == AgentExecutionPhase.running &&
        turn?.turnId == turnId &&
        turn?.state.isBusy == true;
  }

  void _checkOriginal() {
    expectSync(lease.isMounted, isTrue);
    expectSync(lease.isRetired, isFalse);
    expectSync(lease.threadId, session.threadId);
    expectSync(lease.content.currentAttemptId, _attempt);
    expectSync(lease.content.state.value, isA<ChatReady<bool>>());
    expectSync(_scope.isActive, isTrue);
  }

  void _acceptBytes(List<int> bytes, int offset, bool wasRunning) {
    for (var index = 0; index < bytes.length; index += 1) {
      expectSync(bytes[index], (offset + index).isEven ? 32 : 97);
    }
    _bytes += bytes.length;
    if (bytes.isNotEmpty && wasRunning && _running) {
      _runningReads += 1;
      _runningBytes += bytes.length;
    }
  }

  Future<void> _readFrozen(
    ConversationQueryScope scope,
    String owner,
    List<ChatAtomContent> contents,
  ) async {
    expectSync(
      _outputs.add(owner),
      isTrue,
      reason: 'one original output identity',
    );
    final reference = contents.single.reference;
    final target = reference.target as BodyContentTarget;
    expectSync((target.owner as ItemContentOwner).itemId, owner);
    _checkOriginal();
    final wasRunning = _running;
    final window = await _within(
      scope.readContent(
        reference: reference,
        range: const ContentRange(offset: 0, maxBytes: 64 * 1024),
      ),
    );
    _reads += 1;
    _rangeReads += 1;
    _checkOriginal();
    expectSync(window.offset, 0);
    expectSync(window.sealed, isTrue);
    expectSync(window.bytes.length, window.availableThrough);
    expectSync(window.bytes, isNotEmpty);
    expectSync(window.bytes.length, lessThanOrEqualTo(64 * 1024));
    _peakWindowBytes = _peakWindowBytes < window.bytes.length
        ? window.bytes.length
        : _peakWindowBytes;
    _acceptBytes(window.bytes, 0, wasRunning);
    final eof = await _within(
      scope.readContent(
        reference: reference,
        range: ContentRange(offset: window.availableThrough, maxBytes: 1),
      ),
    );
    _reads += 1;
    _rangeReads += 1;
    expectSync(eof.offset, window.availableThrough);
    expectSync(eof.generation, window.generation);
    expectSync(eof.availableThrough, window.availableThrough);
    expectSync(eof.bytes, isEmpty);
    expectSync(eof.sealed, isTrue);
    _sealedEnds += 1;
  }

  Future<void> _readGroup(TimelineItem item) async {
    const demand = ReadDemand(maxItems: 1, maxBytes: 64 * 1024);
    final content = await _within(
      conversations.openGroupMembers(
        threadId: lease.threadId,
        reference: item.members!,
        demand: demand,
      ),
    );
    final first = _MemberSet();
    Observation? observation;
    ConversationQueryScope? scope;
    Object? failure;
    StackTrace? failureStack;
    try {
      observation = content.attachConsumer(first, demand: demand);
      final initial = await _within(first.batch.future);
      await _within(content.ready);
      final attempt = content.currentAttemptId;
      scope = content.openScope(generation: lease.generation);
      _memberScopes += 1;
      _memberPages += 1;
      var page = initial;
      var members = 0;
      int? laterOrder;
      while (true) {
        // Prepend reads walk backwards; check order without retaining old pages.
        for (final atom in page.atoms.toList().reversed) {
          expectSync(atom.source, item.source);
          expectSync(atom.turnId, turnId);
          expectSync(atom.lifecycle, isA<TerminalChatAtom>());
          expectSync(
            (atom.lifecycle as TerminalChatAtom).outcome,
            ChatTerminalOutcome.completed,
          );
          expectSync(atom.sourceOrder, isNotNull);
          if (laterOrder != null) {
            expectSync(atom.sourceOrder, lessThan(laterOrder));
          }
          laterOrder = atom.sourceOrder;
          members += 1;
          if (atom.kind == ChatAtomKind.text ||
              atom.kind == ChatAtomKind.reasoning) {
            await _readFrozen(scope, atom.completionItemId!, atom.contents);
          }
        }
        final before = page.before;
        if (before == null) break;
        page = await _within(scope.loadOlder(before: before, demand: demand));
        _memberPages += 1;
        expectSync(page.placement, ChatPlacement.prepend);
        expectSync(page.before, isNot(before));
      }
      expectSync(members, item.summary!.memberCount);
      expectSync(content.currentAttemptId, attempt);
      expectSync(content.state.value, isA<ChatReady<bool>>());
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    } finally {
      try {
        if (scope != null) {
          expectSync((await scope.close()).complete, isTrue);
          expectSync(scope.pendingQueries, 0);
        }
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
      try {
        observation?.cancel();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
      try {
        expectSync((await content.close()).complete, isTrue);
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack!);
    }
  }

  Future<void> readMany({
    required Future<void> Function() pump,
    required Future<void> Function() loadOlder,
    required int expectedItems,
    required int expectedBytes,
  }) async {
    final source = ForegroundTurnChatSource(turnId: turnId);
    final admitted = <String, int>{};
    final positions = <int, String>{};
    Future<void> consume(TimelineItem item) async {
      final position = item.position!;
      if (admitted.containsKey(item.id)) {
        expectSync(admitted[item.id], position);
        return;
      }
      expectSync(positions.containsKey(position), isFalse);
      admitted[item.id] = position;
      positions[position] = item.id;
      if (item.source == source) {
        expectSync(item.turnId, turnId);
        if (item.kind == TimelineItemKind.workGroup) {
          await _readGroup(item);
        } else if (item.atomKind == ChatAtomKind.text) {
          expectSync(item.outcome, ChatTerminalOutcome.completed);
          await _readFrozen(_scope, item.contentItemId!, item.contents);
        }
      }
    }

    while (true) {
      _checkOriginal();
      TimelineItem? next;
      for (final message in lease.controller.messages) {
        final unit =
            message.metadata![timelineDisplayUnitKey] as TimelineDisplayUnit;
        if (!admitted.containsKey(unit.id)) {
          expectSync(unit.live, isFalse);
          next = unit.item;
          break;
        }
      }
      if (next != null) {
        await consume(next);
        continue;
      }
      if (lease.hasOlder) {
        final before = lease.olderCursor;
        await _within(loadOlder());
        expectSync(lease.olderCursor, isNot(before));
        continue;
      }
      final turn = session.state.lastTurn;
      final current = lease.content.current.value;
      if (turn?.turnId == turnId &&
          turn?.state is CompletedStudioTurnState &&
          current != null &&
          current.activeTurn == null &&
          current.items.isEmpty) {
        break;
      }
      // Drain already admitted bodies before requesting another layout. A
      // Future timeout cannot cancel WidgetTester.pump, so always join that
      // guarded operation before a deadline failure can start teardown.
      if (_clock.elapsed >= const Duration(minutes: 6)) {
        throw TimeoutException('Original timeline consumption deadline');
      }
      await pump();
    }
    expectSync(_outputs.length, expectedItems);
    expectSync(_bytes, expectedBytes);
    expectSync(_sealedEnds, expectedItems);
    expectSync(_runningReads, greaterThanOrEqualTo(2));
    expectSync(_runningBytes, greaterThan(0));
  }

  Future<void> readGrowing(
    ContentRef reference, {
    required String owner,
    required int expectedBytes,
  }) async {
    expectSync(_outputs.add(owner), isTrue);
    var offset = 0;
    String? generation;
    final windows = StreamIterator(
      _scope.watchContent(
        reference: reference,
        range: const ContentRange(offset: 0, maxBytes: 64 * 1024),
      ),
    );
    var sealed = false;
    try {
      while (true) {
        _checkOriginal();
        final wasRunning = _running;
        if (!await _within(windows.moveNext())) {
          expectSync(
            sealed,
            isTrue,
            reason: 'the original body watch ends after sealing',
          );
          _watchEnded = true;
          break;
        }
        final window = windows.current;
        _reads += 1;
        _watchWindows += 1;
        _checkOriginal();
        generation ??= window.generation;
        expectSync(window.generation, generation);
        expectSync(window.offset, 0);
        expectSync(window.bytes.length, lessThanOrEqualTo(64 * 1024));
        expectSync(
          window.availableThrough,
          greaterThanOrEqualTo(window.bytes.length),
        );
        if (offset < window.bytes.length) {
          _acceptBytes(window.bytes.sublist(offset), offset, wasRunning);
          offset = window.bytes.length;
        }
        _peakWindowBytes = _peakWindowBytes < window.bytes.length
            ? window.bytes.length
            : _peakWindowBytes;
        while (offset < window.availableThrough) {
          final rangeWasRunning = _running;
          final suffix = await _within(
            _scope.readContent(
              reference: reference,
              range: ContentRange(offset: offset, maxBytes: 64 * 1024),
            ),
          );
          _reads += 1;
          _rangeReads += 1;
          _checkOriginal();
          expectSync(suffix.generation, generation);
          expectSync(suffix.offset, offset);
          expectSync(suffix.bytes, isNotEmpty);
          expectSync(suffix.bytes.length, lessThanOrEqualTo(64 * 1024));
          _acceptBytes(suffix.bytes, offset, rangeWasRunning);
          offset += suffix.bytes.length;
          _peakWindowBytes = _peakWindowBytes < suffix.bytes.length
              ? suffix.bytes.length
              : _peakWindowBytes;
        }
        sealed = window.sealed;
        if (sealed) expectSync(offset, window.availableThrough);
      }
    } finally {
      await windows.cancel();
    }
    expectSync(_bytes, expectedBytes);
    expectSync(offset, expectedBytes);
    expectSync(_runningReads, greaterThanOrEqualTo(2));
    expectSync(_runningBytes, greaterThan(0));
    final eof = await _within(
      _scope.readContent(
        reference: reference,
        range: ContentRange(offset: offset, maxBytes: 1),
      ),
    );
    _reads += 1;
    _rangeReads += 1;
    expectSync(eof.generation, generation);
    expectSync(eof.offset, offset);
    expectSync(eof.availableThrough, offset);
    expectSync(eof.bytes, isEmpty);
    expectSync(eof.sealed, isTrue);
    _sealedEnds = 1;
  }

  Future<Map<String, Object?>> close() async {
    final report = await _scope.close();
    expectSync(report.complete, isTrue);
    expectSync(_scope.pendingQueries, 0);
    return {
      'threadId': lease.threadId,
      'turnId': turnId,
      'executionId': executionId,
      'attemptId': _attempt?.value,
      'items': _outputs.length,
      'bytes': _bytes,
      'actualReads': _reads,
      'readContentCalls': _rangeReads,
      'watchWindows': _watchWindows,
      'originalRunningReads': _runningReads,
      'originalRunningBytes': _runningBytes,
      'runningWitness': 'sdk-current-execution-before-and-after-read',
      'memberScopes': _memberScopes,
      'memberPages': _memberPages,
      'sealedEnds': _sealedEnds,
      'bodyWatchEnded': _watchEnded,
      'peakWindowBytes': _peakWindowBytes,
      'originalScopeClosed': report.complete,
      'pendingQueriesAtClose': _scope.pendingQueries,
    };
  }
}

final class _MemberSet implements ConversationBatchConsumer {
  final batch = Completer<ChatBatch>();

  @override
  Future<void> applyBatch(ChatBatch value) async {
    // Accept immediately; reading bodies never holds the delivery acknowledgement.
    if (!batch.isCompleted) {
      expectSync(value.placement, ChatPlacement.set);
      batch.complete(value);
    }
  }
}
