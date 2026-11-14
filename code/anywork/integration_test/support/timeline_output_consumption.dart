import 'dart:async';

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
  }) : _readerId = lease.reader.metadata.readerId,
       _scope = lease.openScope(generation: lease.generation);

  final TimelineDisplayLease lease;
  final ConversationSession session;
  final ConversationRepository conversations;
  final String turnId;
  final String executionId;
  final String _readerId;
  final ConversationQueryScope _scope;
  final _clock = Stopwatch()..start();
  final _outputs = <String>{};
  int _bytes = 0;
  int _reads = 0;
  int _rangeReads = 0;
  int _watchWindows = 0;
  int _runningReads = 0;
  int _runningBytes = 0;
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
    expectSync(lease.reader.metadata.readerId, _readerId);
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
      'readerId': _readerId,
      'items': _outputs.length,
      'bytes': _bytes,
      'actualReads': _reads,
      'readContentCalls': _rangeReads,
      'watchWindows': _watchWindows,
      'originalRunningReads': _runningReads,
      'originalRunningBytes': _runningBytes,
      'runningWitness': 'sdk-current-execution-before-and-after-read',
      'sealedEnds': _sealedEnds,
      'bodyWatchEnded': _watchEnded,
      'peakWindowBytes': _peakWindowBytes,
      'originalScopeClosed': report.complete,
      'pendingQueriesAtClose': _scope.pendingQueries,
    };
  }
}
