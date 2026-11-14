import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/studio_client.dart';

/// Finite acceptance evidence from one original FRB reader; it owns no product projection.
final class TimelineReaderObservation {
  TimelineReaderObservation(this.reader, this.evidence)
    : _reader = reader.reader {
    evidence.addAll({
      'source': 'real-frb-timeline-reader',
      'readerId': reader.metadata.readerId,
      'threadId': _reader.threadId,
      'presentationVersion': reader.metadata.presentationVersion,
      'readerProtocolVersion': reader.metadata.readerProtocolVersion,
      'responses': _responses,
      'closeRequested': false,
      'nativeJoined': false,
    });
  }
  static const deadline = Duration(seconds: 20);
  final TimelineReader reader;
  final ConversationReader _reader;
  final Map<String, Object?> evidence;
  final _responses = <Map<String, Object?>>[];
  ViewUpdate? _held;
  bool _joined = false;

  Map<String, Object?> _cut(ViewUpdate update) => {
    'presentationVersion': update.presentationVersion,
    'readerProtocolVersion': update.readerProtocolVersion,
    'after': update.after.value,
    'next': update.next.value,
    'placement': update.history.placement.name,
    'fromOrder': update.history.fromOrder,
    'throughOrder': update.history.throughOrder,
    'before': update.history.before,
    'blocks': [
      for (final block in update.history.blocks)
        {'id': block.id, 'order': block.blockOrder},
    ],
    'tail': switch (update.tail) {
      KeepTail() => {'kind': 'keep'},
      ReplaceTail(:final snapshot) => {
        'kind': 'replace',
        'revision': snapshot.revision,
        'layoutRevision': snapshot.layoutRevision,
        'readyFrontier': snapshot.readyFrontier,
        'executionPresent': snapshot.executionPresent,
        'currentWorkId': snapshot.currentWorkId,
        'older': snapshot.older,
        'blocks': [
          for (final block in snapshot.blocks)
            {
              'id': block.id,
              'order': block.blockOrder,
              'state': block.state.name,
              'summary': block.thinkingSummary,
            },
        ],
      },
      TailStatus(
        :final baseLayoutRevision,
        :final revision,
        :final currentWorkId,
        :final thinkingSummary,
      ) =>
        {
          'kind': 'status',
          'baseLayoutRevision': baseLayoutRevision,
          'revision': revision,
          'currentWorkId': currentWorkId,
          'thinkingSummary': thinkingSummary,
        },
    },
  };
  Future<void> _replayHeld() async {
    final held = _held!;
    final replay = await reader.next(after: held.after).timeout(deadline);
    if (jsonEncode(_cut(held)) != jsonEncode(_cut(replay))) {
      throw StateError(
        'Retry changed the original response cursor or display cut',
      );
    }
    evidence['replayedSameCut'] = true;
  }

  void _validate(ViewUpdate update, ViewCursor after, {required bool initial}) {
    if (update.after != after ||
        update.next == after ||
        update.next.value.isEmpty ||
        update.presentationVersion != presentationVersion ||
        update.readerProtocolVersion != timelineReaderProtocolVersion ||
        (initial
            ? update.history.placement != HistoryPlacement.set ||
                  update.history.fromOrder != null ||
                  update.tail is! ReplaceTail
            : update.history.placement != HistoryPlacement.append ||
                  update.history.fromOrder != _held!.history.throughOrder ||
                  update.history.throughOrder < _held!.history.throughOrder)) {
      throw StateError('Timeline response changed its qualification or range');
    }
    var order = update.history.fromOrder ?? 0;
    final ids = <String>{};
    for (final block in update.history.blocks) {
      if (!ids.add(block.id) ||
          block.blockOrder <= order ||
          block.blockOrder > update.history.throughOrder) {
        throw StateError('Invalid history identity or range');
      }
      order = block.blockOrder;
    }
    if (update.tail case ReplaceTail(:final snapshot)) {
      if (snapshot.readyFrontier != update.history.throughOrder ||
          snapshot.blocks.any((b) => ids.contains(b.id))) {
        throw StateError('Tail does not share the captured history cut');
      }
    }
  }

  Future<void> holdInitialSet() async {
    final after = reader.metadata.initialCursor;
    final first = await reader.next(after: after).timeout(deadline);
    _validate(first, after, initial: true);
    _held = first;
    _responses.add(_cut(first));
    await _replayHeld();
  }

  Future<void> queryCompletedText({
    required String blockId,
    required int blockOrder,
    required SingleDisplayBlock single,
  }) async {
    final atom = single.record.atom;
    final source = single.record.contentSource;
    final itemId = source is CompletedOriginal ? source.completionId : null;
    final terminal = atom.lifecycle;
    if (_responses.length != 1 ||
        itemId == null ||
        atom.kind != ChatAtomKind.text ||
        blockOrder <= _held!.history.throughOrder ||
        terminal is! TerminalChatAtom ||
        terminal.outcome != ChatTerminalOutcome.completed ||
        _held!.history.blocks.any((b) => b.id == blockId)) {
      throw StateError(
        'Query must name a new truly completed text on the original reader',
      );
    }
    final manifest = await _reader
        .listContents(
          itemId: itemId,
          demand: const ReadDemand(maxItems: 32, maxBytes: 64 * 1024),
        )
        .timeout(deadline);
    final body = manifest.entries.singleWhere((entry) => entry.key == 'body');
    final metadata = jsonDecode(utf8.decode(body.payload)) as Map;
    final byteLength = metadata['byteLength'];
    if (byteLength is! int || byteLength <= 0) {
      throw StateError('Completed text manifest has no positive byteLength');
    }
    final target = body.reference.target;
    if (target is! BodyContentTarget ||
        target.owner is! ItemContentOwner ||
        (target.owner as ItemContentOwner).itemId != itemId ||
        target.key != body.key) {
      throw StateError('Manifest reference does not name the completed item');
    }
    // This one explicit test query reads only a bounded prefix, never the
    // hidden full body to fill a viewport.
    final content = await _reader
        .readContent(
          reference: body.reference,
          range: const ContentRange(offset: 0, maxBytes: 64),
        )
        .timeout(deadline);
    final expectedBytes = byteLength < 64 ? byteLength : 64;
    if (content.offset != 0 ||
        content.bytes.isEmpty ||
        content.bytes.length != expectedBytes ||
        content.availableThrough != byteLength ||
        !content.sealed) {
      throw StateError('Original held reader did not return sealed text bytes');
    }
    evidence['query'] = {
      'blockId': blockId,
      'blockOrder': blockOrder,
      'recordId': itemId,
      'readerSource': 'original-held-reader',
      'byteLength': byteLength,
      'actualBytes': content.bytes.length,
      'offset': content.offset,
      'availableThrough': content.availableThrough,
      'sealed': content.sealed,
    };
    await _replayHeld();
  }

  Future<void> observeSuccessors({
    required String blockId,
    required int blockOrder,
  }) async {
    final query = evidence['query'];
    if (query is! Map ||
        query['blockId'] != blockId ||
        query['blockOrder'] != blockOrder) {
      throw StateError('Target must be the original queried completed text');
    }
    final clock = Stopwatch()..start();
    for (var count = 0; count < 128; count++) {
      final remaining = deadline - clock.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException(
          'Target delivery exceeded the observation budget',
        );
      }
      final after = _held!.next;
      final update = await reader.next(after: after).timeout(remaining);
      _validate(update, after, initial: false);
      _held = update;
      _responses.add(_cut(update));
      final target = update.history.blocks
          .where((b) => b.id == blockId)
          .singleOrNull;
      if (target != null) {
        if (target.blockOrder != blockOrder) {
          throw StateError('Target arrived at another history position');
        }
        evidence['targetDelivery'] = {
          'blockId': blockId,
          'blockOrder': blockOrder,
          'after': after.value,
          'next': update.next.value,
          'throughOrder': update.history.throughOrder,
        };
        await _replayHeld();
        return;
      }
      if (update.history.throughOrder >= blockOrder) {
        throw StateError('Timeline passed the target without delivering it');
      }
    }
    throw StateError('Observation response budget exhausted');
  }

  Future<void> verifyClosed(String itemId) async {
    await close();
    Future<void> rejected(Future<void> Function() action) async {
      try {
        await action();
      } on StudioFailure catch (error) {
        if (error.code == StudioFailureCode.cancelled) return;
        rethrow;
      }
      throw StateError('Closed reader still admits work');
    }

    await rejected(() async {
      await _reader.listContents(
        itemId: itemId,
        demand: const ReadDemand(maxItems: 32, maxBytes: 65536),
      );
    });
    await rejected(() async {
      await reader.next(after: _held!.after);
    });
    evidence['closedAdmissionsVerified'] = true;
  }

  Future<void> close() async {
    if (_joined) return;
    evidence['closeRequested'] = true;
    reader.requestClose();
    await reader.close().timeout(deadline);
    _joined = true;
    evidence['nativeJoined'] = true;
  }
}
