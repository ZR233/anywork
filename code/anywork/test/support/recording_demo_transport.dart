import 'dart:async';

import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';

import 'test_app_lifecycle.dart';

/// Records the Native observation boundary and delegates to production Demo.
class RecordingDemoTransport extends TestDemoStudioTransport {
  RecordingDemoTransport({super.lifecycleRoot, super.lspActivityLoop});

  final bootstrapDelivered = Completer<void>();
  int bootstrapCalls = 0;
  final List<RecordingConversationFeed> feeds = [];
  Completer<void>? nextFeedOpenGate;
  void Function(RecordingConversationFeed)? onFeedOpened;

  @override
  Duration get shutdownPhaseDelay => Duration.zero;

  @override
  Future<StudioBootstrap> readBootstrap() async {
    bootstrapCalls++;
    final result = await super.readBootstrap();
    if (!bootstrapDelivered.isCompleted) bootstrapDelivered.complete();
    return result;
  }

  RecordingConversationFeed feedFor(String threadId) =>
      feeds.lastWhere((feed) => feed.threadId == threadId && !feed.requested);

  SessionMetaSnapshot testMapSessionMeta(SessionMetaSnapshot snapshot) =>
      snapshot;

  @override
  Future<ConversationFeedHandle> openConversationFeed(
    String threadId, {
    int initialLimit = 50,
  }) async {
    final gate = nextFeedOpenGate;
    nextFeedOpenGate = null;
    final inner = await super.openConversationFeed(
      threadId,
      initialLimit: initialLimit,
    );
    final feed = RecordingConversationFeed(
      inner,
      initialLimit: initialLimit,
      mapSessionMeta: testMapSessionMeta,
    );
    feeds.add(feed);
    onFeedOpened?.call(feed);
    await gate?.future;
    return feed;
  }

  /// Injects the metadata used by command and eligibility scenarios.
  /// Demo commands and usage tests publish actual producer changes instead.
  Future<void> publishWorkspace(ThreadWorkspace workspace) async {
    final feed = feedFor(workspace.thread.id);
    await feed.listening.future;
    final base = feed.sessionMetaSnapshot;
    final revision = workspace.revision > base.revision
        ? workspace.revision
        : base.revision + 1;
    await feed.emitAndWait(
      ConversationSessionMeta(
        snapshot: sessionMetaFixture(
          base,
          workspace: workspace.copyWith(revision: revision),
        ),
      ),
    );
  }
}

/// The same handle records scope admission, event delivery and bounded reads.
final class RecordingConversationFeed implements ConversationFeedHandle {
  RecordingConversationFeed(
    this.inner, {
    required this.initialLimit,
    required this.mapSessionMeta,
  });

  final ConversationFeedHandle inner;
  final int initialLimit;
  final SessionMetaSnapshot Function(SessionMetaSnapshot) mapSessionMeta;
  final listening = Completer<void>();
  final joined = Completer<void>();
  final olderRequests = <({String cursor, int limit})>[];
  final memberRequests = <({int? afterSeq, int? beforeSeq})>[];
  final bodyRequests = <({BodyRef reference, int offset, int maxBytes})>[];
  final sessionDetailRequests =
      <({SessionDetailKind kind, int offset, int maxBytes})>[];
  final resetRequests = <int>[];
  final delivered = <ConversationFeedEvent>[];
  final _deliveryWaiters =
      Map<ConversationFeedEvent, Completer<void>>.identity();
  Future<TimelinePatch> Function(String cursor, int limit)? onLoadOlder;
  Future<List<WorkGroupMember>> Function(int? afterSeq, int? beforeSeq)?
  onLoadMembers;
  Future<BodyWindow> Function(BodyRef reference, int offset, int maxBytes)?
  onReadBody;
  Future<TimelineReset> Function(int limit)? onReset;
  TimelineReset Function(TimelineReset patch)? mapReset;
  Future<void> Function()? beforeClose;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  bool requested = false;
  SessionMetaSnapshot? _sessionMeta;
  LiveStatusSnapshot? _liveStatus;
  StreamSubscription<ConversationFeedEvent>? _subscription;
  Future<void>? _cancellation;
  Future<void>? _closing;
  late final _output = StreamController<ConversationFeedEvent>(
    onListen: _listen,
    onCancel: _cancel,
  );

  @override
  String get threadId => inner.threadId;

  @override
  SessionMetaSnapshot get sessionMetaSnapshot =>
      _sessionMeta ?? mapSessionMeta(inner.sessionMetaSnapshot);

  @override
  LiveStatusSnapshot get liveStatusSnapshot =>
      _liveStatus ?? inner.liveStatusSnapshot;

  @override
  Stream<ConversationFeedEvent> get events => _events;

  late final _events = _output.stream.map((event) {
    _deliveryWaiters.remove(event)?.complete();
    return event;
  });

  Future<void> emitAndWait(ConversationFeedEvent event) {
    _checkOpen();
    final waiter = _deliveryWaiters[event] = Completer<void>();
    emit(event);
    return waiter.future;
  }

  void _listen() {
    if (requested) return;
    _subscription = inner.events.listen(
      (event) {
        switch (event) {
          case ConversationSessionMeta(:final snapshot):
            emit(ConversationSessionMeta(snapshot: mapSessionMeta(snapshot)));
          case ConversationTimeline(patch: final TimelineReset patch):
            emit(ConversationTimeline(patch: mapReset?.call(patch) ?? patch));
          default:
            emit(event);
        }
      },
      onError: _output.addError,
      onDone: _output.close,
    );
    listening.complete();
  }

  Future<void> _cancel() =>
      _cancellation ??= _subscription?.cancel() ?? Future<void>.value();

  void emit(ConversationFeedEvent event) {
    if (requested || _output.isClosed) return;
    if (event case ConversationSessionMeta(:final snapshot)) {
      _sessionMeta = snapshot;
    }
    if (event case ConversationLiveStatus(:final snapshot)) {
      _liveStatus = snapshot;
    }
    delivered.add(event);
    _output.add(event);
  }

  void _checkOpen() {
    if (requested) throw StateError('Conversation feed is closing');
  }

  @override
  Future<TimelinePatch> loadOlder({
    required String cursor,
    int limit = 50,
  }) async {
    _checkOpen();
    olderRequests.add((cursor: cursor, limit: limit));
    return onLoadOlder?.call(cursor, limit) ??
        inner.loadOlder(cursor: cursor, limit: limit);
  }

  @override
  Future<List<WorkGroupMember>> loadWorkGroupMembers({
    int? afterSeq,
    int? beforeSeq,
  }) async {
    _checkOpen();
    memberRequests.add((afterSeq: afterSeq, beforeSeq: beforeSeq));
    return onLoadMembers?.call(afterSeq, beforeSeq) ??
        inner.loadWorkGroupMembers(afterSeq: afterSeq, beforeSeq: beforeSeq);
  }

  @override
  Future<BodyWindow> readBodyWindow({
    required BodyRef reference,
    required int offset,
    required int maxBytes,
  }) async {
    _checkOpen();
    bodyRequests.add((
      reference: reference,
      offset: offset,
      maxBytes: maxBytes,
    ));
    return onReadBody?.call(reference, offset, maxBytes) ??
        inner.readBodyWindow(
          reference: reference,
          offset: offset,
          maxBytes: maxBytes,
        );
  }

  @override
  Future<SessionDetailWindow> readSessionDetail({
    required SessionDetailKind kind,
    required int offset,
    required int maxBytes,
  }) async {
    _checkOpen();
    sessionDetailRequests.add((kind: kind, offset: offset, maxBytes: maxBytes));
    return inner.readSessionDetail(
      kind: kind,
      offset: offset,
      maxBytes: maxBytes,
    );
  }

  @override
  Future<TimelinePatch> resetToLatest({int limit = 50}) async {
    _checkOpen();
    resetRequests.add(limit);
    final reset = onReset;
    if (reset == null) return inner.resetToLatest(limit: limit);
    final patch = await reset(limit);
    emit(ConversationTimeline(patch: patch));
    return patch;
  }

  @override
  void requestClose() {
    if (requested) return;
    requested = true;
    requestCloseCalls++;
    inner.requestClose();
    for (final waiter in _deliveryWaiters.values) {
      waiter.completeError(
        StateError('Conversation feed closed before delivery'),
      );
    }
    _deliveryWaiters.clear();
    unawaited(_output.close());
  }

  @override
  Future<void> close() async {
    requestClose();
    final closing = _closing ??= _join();
    try {
      await closing;
    } catch (_) {
      if (identical(_closing, closing)) _closing = null;
      rethrow;
    }
  }

  Future<void> _join() async {
    closeCalls++;
    await _cancel();
    await beforeClose?.call();
    await inner.close();
    if (!joined.isCompleted) joined.complete();
  }
}

/// Replaces only the facts named by a scenario, retaining the Demo identity and
/// usage baseline. A workspace override is convenient for command-context tests.
SessionMetaSnapshot sessionMetaFixture(
  SessionMetaSnapshot base, {
  ThreadWorkspace? workspace,
  ThreadStatusView? status,
  WorkflowRuntimeView? workflow,
  bool clearExecution = false,
  List<PendingInteraction>? interactions,
}) {
  final current = base.runtime;
  final runtime = workspace?.runtime;
  final usage = runtime == null
      ? current?.usage
      : ConversationRuntimeUsage(
          diagnostics: runtime.usageDiagnostics,
          hasIncompleteUsage: runtime.hasIncompleteUsage,
          modelId: runtime.modelId,
          contextWindow: runtime.contextWindow,
          maxContextWindow: runtime.maxContextWindow,
          autoCompactLimit: runtime.autoCompactLimit,
          latestContextTokens: runtime.contextTokens,
          promptTokens: runtime.promptTokens,
          completionTokens: runtime.completionTokens,
          cachedPromptTokens: runtime.cachedPromptTokens,
          cacheWriteTokens: runtime.cacheWriteTokens,
          reasoningTokens: runtime.reasoningTokens,
          inferenceCount: runtime.inferenceCount,
          totalTokens: runtime.totalTokens,
          cacheUsage: runtime.cacheUsage,
          estimatedCosts: runtime.estimatedCosts,
          estimatedCacheSavings: runtime.estimatedCacheSavings,
          hasUnpricedUsage: runtime.hasUnpricedUsage,
          promptGeneration: runtime.promptGeneration,
          promptCachePolicy: runtime.promptCachePolicy,
          prefixChangedReason: ConversationPromptPrefixChangedReason.values
              .where((reason) => reason.name == runtime.prefixChangedReason)
              .firstOrNull,
          updatedAt: current?.usage.updatedAt ?? 0,
        );
  final nextRuntime = usage == null
      ? null
      : ConversationRuntimeSnapshot(
          threadId: base.threadId,
          deferred: runtime?.deferred ?? current?.deferred ?? const [],
          usage: usage,
          liveUsage: runtime == null ? current?.liveUsage : runtime.liveUsage,
          turnCompletionTokens:
              runtime?.turnCompletionTokens ??
              current?.turnCompletionTokens ??
              0,
          turnResponseMillis:
              runtime?.turnResponseMillis ?? current?.turnResponseMillis ?? 0,
          todo: workspace == null ? current?.todo : workspace.todo,
          activeSkills:
              runtime?.activeSkills ?? current?.activeSkills ?? const [],
          activeMcpServers:
              runtime?.activeMcpServers ??
              current?.activeMcpServers ??
              const [],
          activeLspServers:
              runtime?.activeLspServers ??
              current?.activeLspServers ??
              const [],
          progress: current?.progress,
          mcpHealth: current?.mcpHealth,
          workflow:
              workflow ??
              (runtime == null ? current?.workflow : runtime.workflow),
          plan: runtime == null ? current?.plan : runtime.plan,
          execution: clearExecution
              ? null
              : runtime == null
              ? current?.execution
              : runtime.execution,
          continuation: clearExecution
              ? null
              : runtime == null
              ? current?.continuation
              : runtime.continuation,
          updatedAt: current?.updatedAt ?? 0,
        );
  final pending = interactions ?? workspace?.interactions ?? base.interactions;
  return SessionMetaSnapshot(
    threadId: base.threadId,
    status: status ?? workspace?.thread.status ?? base.status,
    title: workspace == null ? base.title : workspace.thread.title,
    parentThreadId: base.parentThreadId,
    rootThreadId: base.rootThreadId,
    ownerEpoch: base.ownerEpoch,
    revision: workspace?.revision ?? base.revision,
    activeTurn: workspace == null ? base.activeTurn : workspace.activeTurn,
    lastTurn: workspace == null ? base.lastTurn : workspace.lastTurn,
    activity: workspace == null ? base.activity : workspace.activity,
    usage: base.usage,
    contextMetrics: usage,
    modelRoute: workspace == null ? base.modelRoute : workspace.modelRoute,
    runtime: nextRuntime,
    storageState: workspace == null ? base.storageState : workspace.storage,
    interactions: pending,
    pendingInteractionCount: pending.length,
    plan: nextRuntime?.plan,
    mode: workspace == null ? base.mode : workspace.thread.mode,
    executionPresent: nextRuntime?.execution != null,
  );
}

/// Awaits the actual GUI application boundary.
Future<void> timelineReady(TimelineSessionOwner owner, String threadId) async {
  final state = await owner.source.waitFor(
    (value) =>
        value?.threadId == threadId &&
        (value?.connection == TimelineConnectionPhase.ready ||
            value?.connection == TimelineConnectionPhase.failed),
  );
  if (state?.connection == TimelineConnectionPhase.failed) {
    throw state!.connectionError!;
  }
}
