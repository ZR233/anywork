import 'dart:async';
import 'dart:collection';

import 'package:anywork_client/acp_sessions.dart';

/// Supplies source frames and records boundary calls, without Client semantics.
final class ControlledAcpBusinessPort implements AcpBusinessPort {
  final calls = <(String, Object)>[];
  final sources = Queue<ControlledAcpObservation>();
  Completer<AcpSessionObservationPort>? admission;
  Object? commandError;
  Completer<AcpRunIdView>? promptResult;
  Completer<void>? configureResult;
  Completer<void>? modeResult;
  Completer<void>? answerResult;
  Completer<void>? interruptResult;
  late AcpRunIdView run;
  late AcpBusinessSnapshotView snapshotValue;
  late AcpBusinessCloseView closeValue;
  late AcpListSessionsResponseView listValue;

  T record<T>(String name, Object request, T result) {
    calls.add((name, request));
    if (commandError case final error?) throw error;
    return result;
  }

  @override
  Future<AcpSessionObservationPort> open(
    OpenAcpSessionRequestView request,
  ) async {
    calls.add(('open', request));
    return admission == null ? sources.removeFirst() : await admission!.future;
  }

  @override
  Future<AcpRunIdView> prompt(AcpPromptRequestView request) async {
    record('prompt', request, run);
    return promptResult == null ? run : await promptResult!.future;
  }

  @override
  Future<AcpRunIdView> replace(AcpReplaceRequestView request) async =>
      record('replace', request, run);

  @override
  Future<void> interrupt(AcpInterruptRequestView request) async {
    record('interrupt', request, null);
    await interruptResult?.future;
  }

  @override
  Future<void> configure(AcpConfigureRequestView request) async {
    record('configure', request, null);
    await configureResult?.future;
  }

  @override
  Future<void> setMode(AcpSetModeRequestView request) async {
    record('setMode', request, null);
    await modeResult?.future;
  }

  @override
  Future<void> answerPermission(AcpPermissionAnswerRequestView request) async {
    record('answerPermission', request, null);
    await answerResult?.future;
  }

  @override
  Future<AcpListSessionsResponseView> list(AcpListRequestView request) async =>
      record('list', request, listValue);

  @override
  Future<AcpBusinessSnapshotView> snapshot(AcpSessionTargetView target) async =>
      record('snapshot', target, snapshotValue);

  @override
  Future<AcpBusinessCloseView> closeMember(AcpSessionTargetView target) async =>
      record('closeMember', target, closeValue);
}

final class ControlledAcpObservation implements AcpSessionObservationPort {
  ControlledAcpObservation([Iterable<AcpSessionFrameView> frames = const []])
    : frames = Queue.of(frames);

  final Queue<AcpSessionFrameView> frames;
  final enteredRead = Completer<void>();
  Completer<AcpSessionFrameView?>? read;
  Completer<void>? cleanup;
  Object? readError;
  Object? cleanupError;
  bool eof = false;
  int reads = 0;
  int closeSignals = 0;
  int closes = 0;

  @override
  Future<AcpSessionFrameView?> next() async {
    reads++;
    if (!enteredRead.isCompleted) enteredRead.complete();
    if (readError case final error?) throw error;
    if (frames.isNotEmpty) return frames.removeFirst();
    if (eof) return null;
    read = Completer<AcpSessionFrameView?>();
    return read!.future;
  }

  @override
  void requestClose() {
    closeSignals++;
    eof = true;
    final pending = read;
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }

  @override
  Future<void> close() async {
    closes++;
    if (cleanupError case final error?) throw error;
    await cleanup?.future;
  }
}
