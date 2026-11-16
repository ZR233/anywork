import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/lifecycle.dart';

mixin DirectoryFeedFixture on StudioTransport {
  ClientScope? _directoryLifecycleScope;
  ClientScope get lifecycleScope =>
      _directoryLifecycleScope ??= ClientScope(owner: 'directory-test-runtime');
  String directoryOwnerEpoch = 'test-runtime';
  int directoryRevision = 1;
  final Map<String, SessionDirectoryRow?> directoryThreads = {};
  final List<String> openedMetadataThreadIds = [];
  final Map<String, Completer<void>> metadataOpenGates = {};
  final Map<String, Completer<void>> _metadataOpenSignals = {};
  final List<DirectoryQuery> openedDirectoryQueries = [];
  final Map<String, List<_MetadataHandle>> _metadataHandles = {};
  final List<_ThreadsHandle> _threadsHandles = [];
  Object? directoryCloseFailure;
  int directoryCloseCalls = 0;

  void seedThread(SessionDirectoryRow row) =>
      directoryThreads[row.threadId] = row;

  Future<void> metadataOpenStarted(String threadId) =>
      _metadataOpenSignals.putIfAbsent(threadId, Completer<void>.new).future;

  void emitThread(
    SessionDirectoryRow? row,
    String id, {
    required int revision,
  }) {
    directoryRevision = revision;
    directoryThreads[id] = row;
    final frame = ThreadMetadataFrame(
      threadId: id,
      stamp: _stamp(revision),
      row: row,
    );
    for (final handle in _metadataHandles[id] ?? const []) {
      handle.add(frame);
    }
  }

  @override
  Future<ThreadObservationHandle> openThreadObservation(
    String threadId, {
    required ClientResourceId resourceId,
  }) async {
    final acquisition = lifecycleScope.open<_MetadataHandle>(
      'test-metadata-owner',
      (operation) async {
        openedMetadataThreadIds.add(threadId);
        final signal = _metadataOpenSignals.putIfAbsent(
          threadId,
          Completer<void>.new,
        );
        if (!signal.isCompleted) signal.complete();
        await metadataOpenGates[threadId]?.future;
        final handle = _MetadataHandle(
          operation.resourceId,
          _closeDirectoryHandle,
        );
        _metadataHandles.putIfAbsent(threadId, () => []).add(handle);
        handle.add(
          ThreadMetadataFrame(
            threadId: threadId,
            stamp: _stamp(directoryRevision),
            row: directoryThreads[threadId],
          ),
        );
        return handle;
      },
      identity: resourceId,
    );
    await acquisition.ready;
    return _MetadataProxy(acquisition);
  }

  @override
  Future<ThreadsObservationHandle> openThreadsObservation(
    DirectoryQuery query,
    DirectoryWindow window, {
    required ClientResourceId resourceId,
  }) async {
    final acquisition = lifecycleScope.open<_ThreadsHandle>(
      'test-directory-owner',
      (operation) async {
        openedDirectoryQueries.add(query);
        final handle = _ThreadsHandle(
          operation.resourceId,
          _closeDirectoryHandle,
        );
        _threadsHandles.add(handle);
        handle.add(
          ThreadDirectoryFrame(
            query: query,
            window: window,
            stamp: _stamp(directoryRevision),
            threadIds: directoryThreads.entries
                .where((entry) {
                  final row = entry.value;
                  return row != null &&
                      row.isRootRow &&
                      row.archived == query.archived &&
                      (query.workspaceId == null ||
                          row.workspaceId == query.workspaceId) &&
                      (query.threadIds == null ||
                          query.threadIds!.contains(row.threadId)) &&
                      !query.excludedThreadIds.contains(row.threadId);
                })
                .map((entry) => entry.key)
                .take(window.limit)
                .toList(),
          ),
        );
        return handle;
      },
      identity: resourceId,
    );
    await acquisition.ready;
    return _ThreadsProxy(acquisition);
  }

  ResourceStamp _stamp(int revision) => ResourceStamp(
    resourceKey: 'thread-directory',
    ownerEpoch: directoryOwnerEpoch,
    revision: revision,
  );

  Future<void> _closeDirectoryHandle() async {
    directoryCloseCalls += 1;
    final failure = directoryCloseFailure;
    directoryCloseFailure = null;
    if (failure != null) throw failure;
  }
}

abstract base class _PullHandle<T> implements ClientResource {
  _PullHandle(this.resourceId, this._close);

  @override
  final ClientResourceId resourceId;
  final Future<void> Function() _close;
  final List<T> _queued = [];
  Completer<T?>? _waiting;
  bool _closing = false;

  void add(T frame) {
    if (_closing) return;
    final waiting = _waiting;
    if (waiting == null) {
      _queued.add(frame);
    } else {
      _waiting = null;
      waiting.complete(frame);
    }
  }

  Future<T?> pull() {
    if (_queued.isNotEmpty) return Future.value(_queued.removeAt(0));
    if (_closing) return Future.value();
    return (_waiting = Completer<T?>()).future;
  }

  void request() {
    if (_closing) return;
    _closing = true;
    _waiting?.complete();
    _waiting = null;
  }

  Future<void> finish() async {
    request();
    await _close();
  }

  @override
  void requestClose() => request();
  @override
  Future<void> close() => finish();
  @override
  Future<void> retryClose() => finish();
}

final class _MetadataHandle extends _PullHandle<ThreadMetadataFrame>
    implements ThreadObservationHandle {
  _MetadataHandle(ClientResourceId resourceId, Future<void> Function() close)
    : super(resourceId, close);

  @override
  Future<ThreadMetadataFrame?> next() => pull();
  @override
  void requestClose() => request();
  @override
  Future<void> close() => finish();
}

final class _ThreadsHandle extends _PullHandle<ThreadDirectoryFrame>
    implements ThreadsObservationHandle {
  _ThreadsHandle(ClientResourceId resourceId, Future<void> Function() close)
    : super(resourceId, close);

  @override
  Future<ThreadDirectoryFrame?> next() => pull();
  @override
  void requestClose() => request();
  @override
  Future<void> close() => finish();
}

final class _MetadataProxy implements ThreadObservationHandle {
  _MetadataProxy(this.acquisition);
  final ClientAcquisition<_MetadataHandle> acquisition;

  @override
  ClientResourceId get resourceId => acquisition.resourceId;
  @override
  Future<ThreadMetadataFrame?> next() async => (await acquisition.ready).next();
  @override
  void requestClose() => acquisition.requestClose();
  @override
  Future<void> close() => acquisition.close();
  @override
  Future<void> retryClose() => acquisition.retryClose();
}

final class _ThreadsProxy implements ThreadsObservationHandle {
  _ThreadsProxy(this.acquisition);
  final ClientAcquisition<_ThreadsHandle> acquisition;

  @override
  ClientResourceId get resourceId => acquisition.resourceId;
  @override
  Future<ThreadDirectoryFrame?> next() async =>
      (await acquisition.ready).next();
  @override
  void requestClose() => acquisition.requestClose();
  @override
  Future<void> close() => acquisition.close();
  @override
  Future<void> retryClose() => acquisition.retryClose();
}
