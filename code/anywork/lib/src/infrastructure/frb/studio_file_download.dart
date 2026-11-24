import 'dart:async';

import '../../features/conversation/timeline/connectors/timeline_file_download.dart';
import '../../rust/api/studio/handlers/file_download.dart' as native;

class FrbTimelineFileDownload implements TimelineFileDownload {
  FrbTimelineFileDownload._(this._handle) {
    unawaited(_observe());
  }

  factory FrbTimelineFileDownload.start({
    required Future<void> Function() ensureReady,
    required String threadId,
    required String itemId,
    required int index,
    required String destination,
  }) {
    return FrbTimelineFileDownload._(
      ensureReady().then(
        (_) => native.startFileDownload(
          threadId: threadId,
          itemId: itemId,
          index: index,
          destination: destination,
        ),
      ),
    );
  }

  final Future<native.BridgeFileDownload> _handle;
  final _progress = StreamController<int>();
  final _finished = Completer<void>();

  @override
  Stream<int> get progress => _progress.stream;

  @override
  Future<void> get finished => _finished.future;

  @override
  Future<void> pause() async => (await _handle).setPaused(paused: true);

  @override
  Future<void> resume() async => (await _handle).setPaused(paused: false);

  @override
  Future<void> stop() async => (await _handle).close();

  Future<void> _observe() async {
    try {
      final handle = await _handle;
      try {
        var revision = BigInt.zero;
        var written = 0;
        while (true) {
          final snapshot = await handle.nextStatus(afterRevision: revision);
          revision = snapshot.revision;
          final next = snapshot.written.toInt();
          if (written != next) {
            written = next;
            _progress.add(next);
          }
          switch (snapshot.phase) {
            case native.BridgeFileDownloadPhase.downloading:
            case native.BridgeFileDownloadPhase.paused:
              continue;
            case native.BridgeFileDownloadPhase.saved:
              break;
            case native.BridgeFileDownloadPhase.stopped:
              throw StateError('Download stopped');
            case native.BridgeFileDownloadPhase.failed:
              throw StateError(snapshot.error?.message ?? 'Download failed');
          }
          break;
        }
      } finally {
        await handle.close();
      }
      _finished.complete();
    } catch (error, stack) {
      _finished.completeError(error, stack);
    } finally {
      unawaited(_progress.close());
    }
  }
}
