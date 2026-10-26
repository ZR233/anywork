import 'dart:async';

import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

/// This environment explicitly refused admission; it issued no native call.
/// Do not turn a missing script into lost-reply recovery or a pending find.
Never rejectUnscriptedConfigurationBegin(String message) =>
    throw CommandDispatchFailure.rejected(
      failure: StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: message,
        retryable: false,
        correlationId: 'configuration-fixture:unscripted-begin',
      ),
    );

/// A recorded native begin invocation, not the SDK's command/attempt owner.
/// Tests may lose/reject the begin reply without inventing another mutation.
final class RecordedConfigurationCall<T> {
  RecordedConfigurationCall(this.request, this.native);
  final T request;
  final ScriptedConfigurationCommandCall native;
  final beginReply = Completer<ConfigurationCommandCall>();

  void accept() => beginReply.complete(native);
}

final class RecordedConfigurationLookup {
  RecordedConfigurationLookup(this.operationId);
  final OperationId operationId;
  final reply = Completer<ConfigurationCommandCall?>();
}

final class RecordedConfigurationResult {
  final entered = Completer<void>();
  final reply = Completer<ConfigurationCommandReply>();
}

final class RecordedConfigurationClose {
  RecordedConfigurationClose({required this.retry});
  final bool retry;
  final reply = Completer<FeedCloseReport>();
}

/// Explicit original native identity plus independent result/close gates.
/// Every result query and every cleanup call has its own scripted response;
/// no Future failure cache, observed/CAS policy, lookup algorithm, automatic
/// retry, target synchronization or automatic Clean is implemented here.
final class ScriptedConfigurationCommandCall
    implements ConfigurationCommandCall {
  ScriptedConfigurationCommandCall({
    required this.callId,
    required this.operationId,
  });
  @override
  final String callId;
  @override
  final OperationId operationId;
  final _results = <int, RecordedConfigurationResult>{};
  final closes = <RecordedConfigurationClose>[];
  final _closeWaiters = <int, Completer<RecordedConfigurationClose>>{};
  int resultCalls = 0;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  int retryCloseCalls = 0;

  RecordedConfigurationResult resultAt(int index) =>
      _results.putIfAbsent(index, RecordedConfigurationResult.new);

  Future<RecordedConfigurationResult> resultRead(int index) async {
    final read = resultAt(index);
    await read.entered.future;
    return read;
  }

  Future<RecordedConfigurationClose> closed(int index) => index < closes.length
      ? Future.value(closes[index])
      : _closeWaiters
            .putIfAbsent(index, Completer<RecordedConfigurationClose>.new)
            .future;

  @override
  Future<ConfigurationCommandReply> result() {
    final read = resultAt(resultCalls++);
    read.entered.complete();
    return read.reply.future;
  }

  @override
  void requestClose() => requestCloseCalls++;

  @override
  Future<FeedCloseReport> close() {
    closeCalls++;
    return _close(retry: false);
  }

  @override
  Future<FeedCloseReport> retryClose() {
    retryCloseCalls++;
    return _close(retry: true);
  }

  Future<FeedCloseReport> _close({required bool retry}) {
    final call = RecordedConfigurationClose(retry: retry);
    closes.add(call);
    _closeWaiters.remove(closes.length - 1)?.complete(call);
    return call.reply.future;
  }
}
