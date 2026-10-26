import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import 'conversation_fixture.dart';
import 'scripted_feed.dart';

/// Records actual native entries; awaiting an index never starts work.
final class DraftCalls<T> {
  final values = <T>[];
  final _waiters = <int, Completer<T>>{};
  void add(T value) {
    values.add(value);
    _waiters.remove(values.length - 1)?.complete(value);
  }

  Future<T> at(int index) => index < values.length
      ? Future.value(values[index])
      : _waiters.putIfAbsent(index, Completer<T>.new).future;
}

final class DraftCloseCall {
  DraftCloseCall(this.retry);
  final bool retry;
  final reply = Completer<FeedCloseReport>();
}

/// Independent native result and cleanup receipts, not a fake SDK join owner.
abstract class DraftNativeJob<T> {
  DraftNativeJob(this.id);
  final OperationId id;
  final reads = DraftCalls<Completer<T>>();
  final closes = DraftCalls<DraftCloseCall>();
  int requests = 0;
  Future<T> readResult() {
    final result = Completer<T>();
    reads.add(result);
    return result.future;
  }

  void requestClose() => requests++;
  Future<FeedCloseReport> close() => _close(false);
  Future<FeedCloseReport> retryClose() => _close(true);
  Future<FeedCloseReport> _close(bool retry) {
    final call = DraftCloseCall(retry);
    closes.add(call);
    return call.reply.future;
  }
}

final class DraftAdmissionBegin {
  DraftAdmissionBegin(this.id, this.context, this.sources);
  final OperationId id;
  final AttachmentAdmissionContext context;
  final List<AttachmentDraftSource> sources;
  final reply = Completer<AttachmentAdmissionJob>();
}

final class DraftAdmissionJob extends DraftNativeJob<List<AttachmentMetadata>>
    implements AttachmentAdmissionJob {
  DraftAdmissionJob(super.id);
  @override
  OperationId get operationId => id;
  @override
  Future<List<AttachmentMetadata>> result() => readResult();
}

final class DraftLookup<T> {
  DraftLookup(this.id);
  final OperationId id;
  final reply = Completer<T?>();
}

final class DraftRemove {
  DraftRemove(this.id);
  final String id;
  final reply = Completer<bool>();
}

final class DraftAdmissionPort implements AttachmentAdmissionPort {
  final begins = DraftCalls<DraftAdmissionBegin>();
  final finds = DraftCalls<DraftLookup<AttachmentAdmissionJob>>();
  final removals = DraftCalls<DraftRemove>();

  /// Optional environment notification fired synchronously when the native
  /// removal is requested; it never replaces the recorded call or any cleanup.
  void Function(String draftId)? onRemove;
  @override
  Future<AttachmentAdmissionJob> begin(
    OperationId id,
    AttachmentAdmissionContext context,
    List<AttachmentDraftSource> sources,
  ) {
    final call = DraftAdmissionBegin(id, context, List.unmodifiable(sources));
    begins.add(call);
    return call.reply.future;
  }

  @override
  Future<AttachmentAdmissionJob?> find(OperationId id) {
    final call = DraftLookup<AttachmentAdmissionJob>(id);
    finds.add(call);
    return call.reply.future;
  }

  @override
  Future<bool> remove(String draftId) {
    final call = DraftRemove(draftId);
    removals.add(call);
    onRemove?.call(draftId);
    return call.reply.future;
  }
}

final class DraftPromptCall {
  DraftPromptCall(this.threadId, this.input, this.routeRevision);
  final String threadId;
  final StudioPromptInput input;
  final int routeRevision;
  final reply = Completer<SubmitPromptReceipt>();
}

final class DraftAcceptanceCall {
  DraftAcceptanceCall(this.threadId, this.inputId);
  final String threadId;
  final String inputId;
  final reply = Completer<InputAcceptanceEvidence?>();
}

final class DraftCommands extends UnscriptedConversationCommands {
  final prompts = DraftCalls<DraftPromptCall>();
  final acceptances = DraftCalls<DraftAcceptanceCall>();
  @override
  Future<InterruptTurnReply> interruptTurn(
    String threadId,
    String turnId, {
    required OperationId operationId,
  }) => throw UnsupportedError(
    'This Drafts scenario has no exact Turn interrupt',
  );
  @override
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) {
    final call = DraftPromptCall(threadId, input, expectedModelRouteRevision);
    prompts.add(call);
    return call.reply.future;
  }

  @override
  Future<InputAcceptanceEvidence?> readInputAcceptance(
    String threadId,
    String inputId,
  ) {
    final call = DraftAcceptanceCall(threadId, inputId);
    acceptances.add(call);
    return call.reply.future;
  }
}

final class DraftCreationBegin {
  DraftCreationBegin(this.id, this.request);
  final OperationId id;
  final NewThreadCreationRequest request;
  final reply = Completer<NewThreadCreation>();
}

final class DraftCreationJob extends DraftNativeJob<StartNewThreadResult>
    implements NewThreadCreation {
  DraftCreationJob(super.id, this.projectId, this.inputId);
  @override
  OperationId get operationId => id;
  @override
  final String projectId;
  @override
  final String inputId;
  final progressSource = LatestValue<ThreadPreparationProgress?>(null);
  @override
  ReadonlyLatestValue<ThreadPreparationProgress?> get progress =>
      progressSource.readonly;
  final sourceCalls = DraftCalls<Completer<CreatedInputExecutionSource>>();
  @override
  Future<StartNewThreadResult> result() => readResult();
  @override
  Future<CreatedInputExecutionSource> executionSource() {
    final call = Completer<CreatedInputExecutionSource>();
    sourceCalls.add(call);
    return call.future;
  }
}

final class DraftCreationPort implements NewThreadCreationPort {
  final begins = DraftCalls<DraftCreationBegin>();
  final finds = DraftCalls<DraftLookup<NewThreadCreation>>();
  @override
  Future<NewThreadCreation> begin(
    OperationId id,
    NewThreadCreationRequest request,
  ) {
    final call = DraftCreationBegin(id, request);
    begins.add(call);
    return call.reply.future;
  }

  @override
  Future<NewThreadCreation?> find(OperationId id) {
    final call = DraftLookup<NewThreadCreation>(id);
    finds.add(call);
    return call.reply.future;
  }
}

final class DraftCreatedSource implements CreatedInputExecutionSource {
  DraftCreatedSource(this.threadId, this.inputId);
  @override
  final String threadId;
  @override
  final String inputId;
  @override
  String get runtimeEpoch => 'draft-native-runtime';
  @override
  int get incarnation => 1;
  final opened = Completer<void>();
  int opens = 0;
  final feed = ScriptedFeed<ThreadExecutionFrame>(
    feedId: 'draft-created-execution',
    sequenceOf: (frame) =>
        frame is ThreadExecutionData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! ThreadExecutionData,
  );
  @override
  Future<FeedConnection<ThreadExecutionFrame>> openExecution() async {
    opens++;
    if (!opened.isCompleted) opened.complete();
    return feed;
  }
}

final class DraftBinaryOpen {
  DraftBinaryOpen(this.draftId, this.threadId, this.attachmentId);
  final String? draftId;
  final String? threadId;
  final String? attachmentId;
  final reply = Completer<AttachmentBinaryRead>();
}

final class DraftBinaryReadCall {
  DraftBinaryReadCall(this.offset, this.maxBytes);
  final int offset;
  final int maxBytes;
  final reply = Completer<AttachmentBinaryChunk>();
}

final class DraftBinaryPort implements AttachmentBinaryPort {
  final opens = DraftCalls<DraftBinaryOpen>();
  void Function()? onOpen;
  @override
  Future<AttachmentBinaryRead> openDraftBinary(String draftId) =>
      _open(draftId, null, null);
  @override
  Future<AttachmentBinaryRead> openThreadBinary(
    String threadId,
    String attachmentId,
  ) => _open(null, threadId, attachmentId);
  Future<AttachmentBinaryRead> _open(
    String? draftId,
    String? threadId,
    String? attachmentId,
  ) {
    final call = DraftBinaryOpen(draftId, threadId, attachmentId);
    opens.add(call);
    onOpen?.call();
    return call.reply.future;
  }
}

final class DraftBinaryPin implements AttachmentBinaryRead {
  DraftBinaryPin({
    required this.originalScopeId,
    required this.descriptor,
    required this.length,
  });
  final String originalScopeId;
  final AttachmentBinaryIdentity descriptor;
  final int length;
  Object? descriptorFailure;
  Object? scopeFailure;
  final reads = DraftCalls<DraftBinaryReadCall>();
  final closes = DraftCalls<DraftCloseCall>();
  int requests = 0;
  @override
  String get scopeId {
    if (scopeFailure case final error?) throw error;
    return originalScopeId;
  }

  @override
  AttachmentBinaryIdentity get identity {
    if (descriptorFailure case final error?) throw error;
    return descriptor;
  }

  @override
  int get byteLength => length;
  @override
  Future<AttachmentBinaryChunk> read({
    required int offset,
    int maxBytes = 65536,
  }) {
    final call = DraftBinaryReadCall(offset, maxBytes);
    reads.add(call);
    return call.reply.future;
  }

  @override
  void requestClose() => requests++;

  @override
  Future<FeedCloseReport> close() => _close(false);
  @override
  Future<FeedCloseReport> retryClose() => _close(true);
  Future<FeedCloseReport> _close(bool retry) {
    final call = DraftCloseCall(retry);
    closes.add(call);
    return call.reply.future;
  }
}

/// Mechanical original material only. Public Session scopes perform validation.
final class DraftTurnPin implements TurnReadConnection {
  DraftTurnPin(
    this.value, {
    this.headerReply,
    this.manualClose = false,
    this.scriptText = false,
  });
  final TurnReadHeader value;
  final Completer<TurnReadHeader>? headerReply;
  final bool manualClose;
  final bool scriptText;
  final entered = Completer<void>();
  final texts = DraftCalls<DraftTurnText>();
  final closes = DraftCalls<DraftCloseCall>();
  int headerCalls = 0;
  int requests = 0;
  @override
  Future<TurnReadHeader> header() {
    headerCalls++;
    if (!entered.isCompleted) entered.complete();
    return headerReply?.future ?? Future.value(value);
  }

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) {
    if (!scriptText)
      throw UnsupportedError(
        'No original Turn text field was scripted: $fieldId',
      );
    final call = DraftTurnText(fieldId, offset, maxBytes);
    texts.add(call);
    return call.reply.future;
  }

  @override
  void requestClose() => requests++;
  @override
  Future<FeedCloseReport> close() => _close(false);
  @override
  Future<FeedCloseReport> retryClose() => _close(true);
  Future<FeedCloseReport> _close(bool retry) {
    final call = DraftCloseCall(retry);
    closes.add(call);
    if (!manualClose)
      call.reply.complete(
        FeedCloseReport(
          feedId: value.scope.scopeId,
          outcome: const FeedCloseOutcome.clean(),
        ),
      );
    return call.reply.future;
  }
}

/// Thin original external text call. No matching, trimming or slicing policy.
final class DraftTurnText {
  DraftTurnText(this.fieldId, this.offset, this.maxBytes);
  final int fieldId;
  final int offset;
  final int maxBytes;
  final reply = Completer<TextChunk>();
}

final class DraftTurnOpen {
  DraftTurnOpen(this.threadId, this.reference, this.origin);
  final String threadId;
  final TurnReadRef reference;
  final ThreadFacetStamp origin;
  final reply = Completer<TurnReadConnection>();
}
