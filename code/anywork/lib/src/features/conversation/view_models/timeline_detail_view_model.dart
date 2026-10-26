import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../state/timeline_detail_state.dart';
import 'read_validation.dart';

part 'timeline_detail_view_model.g.dart';

@riverpod
class TimelineDetailViewModel extends _$TimelineDetailViewModel {
  Future<void>? _running;
  bool _closing = false;
  int _intent = 0;
  Object? queryCause;
  StackTrace? queryTrace;

  @override
  FutureOr<TimelineDetailViewState> build(TimelineDetailKey key) {
    ref.onDispose(() {
      _closing = true;
      _intent++;
    });
    return TimelineDetailViewState(key: key);
  }

  /// Smart captures the exact display in typed callbacks. The VM receives no
  /// UI binding, shared query close capability, Widget or Controller.
  Future<void> readFrom({
    required Future<StudioTimelineDetailChunk> Function(
      StudioTimelineDetailQuery,
    )
    read,
    required bool Function() current,
  }) {
    final running = _running;
    if (running != null) return running;
    if (_closing || !current()) return Future<void>.value();
    final intent = ++_intent;
    final done = Completer<void>();
    _running = done.future;
    state = AsyncData(TimelineDetailViewState(key: key, loading: true));
    Future<void>.sync(() => _read(read, current, intent)).then<void>(
      (_) {
        if (identical(_running, done.future)) _running = null;
        done.complete();
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_running, done.future)) _running = null;
        done.completeError(error, stack);
      },
    );
    done.future.ignore();
    return done.future;
  }

  bool _current(int intent) => !_closing && ref.mounted && intent == _intent;

  Future<void> _read(
    Future<StudioTimelineDetailChunk> Function(StudioTimelineDetailQuery) read,
    bool Function() current,
    int intent,
  ) async {
    try {
      while (_current(intent) && current()) {
        final before = state.requireValue;
        final chunk = await read(
          StudioTimelineDetailQuery(
            field: key.field,
            revision: key.revision,
            continuation: before.continuation,
            maxBytes: 65536,
          ),
        );
        if (!_current(intent)) return;
        if (!current()) {
          throw const StudioFailure(
            code: StudioFailureCode.cancelled,
            message: 'The timeline read connection changed',
            retryable: true,
            correlationId: 'timeline-detail-scope-changed',
          );
        }
        final bytes = utf8.encode(chunk.text).length;
        final loaded = before.loadedBytes + bytes;
        if (chunk.itemId != key.itemId ||
            chunk.field != key.field ||
            chunk.revision != key.revision ||
            (before.totalBytes != null &&
                chunk.totalBytes != before.totalBytes) ||
            loaded > chunk.totalBytes ||
            (chunk.continuation != null &&
                (bytes == 0 ||
                    chunk.continuation == before.continuation ||
                    loaded >= chunk.totalBytes)) ||
            (chunk.continuation == null && loaded != chunk.totalBytes)) {
          throw readProtocol('timeline-detail');
        }
        state = AsyncData(
          before.copyWith(
            text: before.text + chunk.text,
            loadedBytes: loaded,
            totalBytes: chunk.totalBytes,
            continuation: chunk.continuation,
            complete: chunk.continuation == null,
          ),
        );
        if (chunk.continuation == null) break;
      }
    } on StudioFailure catch (error) {
      if (_current(intent)) {
        final terminal =
            error.code == StudioFailureCode.staleRevision ||
            error.code == StudioFailureCode.superseded ||
            error.code == StudioFailureCode.notFound;
        state = AsyncData(
          state.requireValue.copyWith(
            error: error,
            text: terminal ? '' : state.requireValue.text,
            loadedBytes: terminal ? 0 : state.requireValue.loadedBytes,
            continuation: terminal ? null : state.requireValue.continuation,
            complete: false,
          ),
        );
      }
    } catch (error, stack) {
      queryCause = error;
      queryTrace = stack;
      if (_current(intent)) {
        state = AsyncData(
          state.requireValue.copyWith(
            error: const StudioFailure(
              code: StudioFailureCode.internal,
              message: 'The timeline detail could not be read',
              retryable: false,
              correlationId: 'timeline-detail-internal',
            ),
            complete: false,
          ),
        );
      }
    } finally {
      if (_current(intent)) {
        state = AsyncData(state.requireValue.copyWith(loading: false));
      }
    }
  }

  Future<void> closeReader() async {
    _closing = true;
    _intent++;
    if (ref.mounted && state.hasValue) {
      state = AsyncData(
        state.requireValue.copyWith(
          closing: true,
          complete: false,
          text: '',
          continuation: null,
        ),
      );
    }
    final running = _running;
    if (running != null) await running;
    // Wait for this reader's accepted call, not close the shared display scope.
  }
}
