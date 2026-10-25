import 'dart:async';

import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/resources_ports.dart';

/// A native begin reply is independent of the original call's result/cleanup.
/// Admission rejection creates no call and must not be treated as a lost reply.
final class RecordedProfileCall<T> {
  RecordedProfileCall(this.request, this.native);
  final T request;
  final ScriptedProfileCommandCall native;
  final beginReply = Completer<ProfileCommandCall>();
  bool accepted = false;

  void accept() {
    accepted = true;
    beginReply.complete(native);
  }
}

final class RecordedProfileLookup {
  RecordedProfileLookup(this.operationId);
  final OperationId operationId;
  final reply = Completer<ProfileCommandCall?>();
}

final class RecordedProfileResult<R> {
  final entered = Completer<void>();
  final reply = Completer<R>();
}

final class RecordedProfileClose {
  RecordedProfileClose({required this.retry});
  final bool retry;
  final reply = Completer<FeedCloseReport>();
}

/// Only native metadata and independently scripted API responses. This does
/// not implement SDK ownership, CAS, find, replay, observation or close-join.
/// In particular, no result query or cleanup attempt automatically succeeds.
abstract base class ScriptedProfileNativeCall<R> {
  ScriptedProfileNativeCall({required this.callId, required this.operationId});
  final String callId;
  final OperationId operationId;
  final _results = <int, RecordedProfileResult<R>>{};
  final closes = <RecordedProfileClose>[];
  final _closeWaiters = <int, Completer<RecordedProfileClose>>{};
  int resultCalls = 0;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  int retryCloseCalls = 0;

  RecordedProfileResult<R> resultAt(int index) =>
      _results.putIfAbsent(index, RecordedProfileResult<R>.new);

  Future<RecordedProfileResult<R>> resultRead(int index) async {
    final read = resultAt(index);
    await read.entered.future;
    return read;
  }

  Future<RecordedProfileClose> closed(int index) => index < closes.length
      ? Future.value(closes[index])
      : _closeWaiters
            .putIfAbsent(index, Completer<RecordedProfileClose>.new)
            .future;

  Future<R> result() {
    final read = resultAt(resultCalls++);
    read.entered.complete();
    return read.reply.future;
  }

  void requestClose() => requestCloseCalls++;

  Future<FeedCloseReport> close() {
    closeCalls++;
    return _close(retry: false);
  }

  Future<FeedCloseReport> retryClose() {
    retryCloseCalls++;
    return _close(retry: true);
  }

  Future<FeedCloseReport> _close({required bool retry}) {
    final call = RecordedProfileClose(retry: retry);
    closes.add(call);
    _closeWaiters.remove(closes.length - 1)?.complete(call);
    return call.reply.future;
  }
}

final class ScriptedProfileCommandCall
    extends ScriptedProfileNativeCall<ProfileCommandReply>
    implements ProfileCommandCall {
  ScriptedProfileCommandCall({
    required super.callId,
    required super.operationId,
  });
}
