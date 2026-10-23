import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import 'scripted_feed.dart';
import 'thread_metadata_fixture.dart';
import 'timeline_transport.dart';

/// Public assembly with controlled external inputs, not another Session or
/// reducer. Silent facets keep their real feed owners alive without inventing
/// business baselines to exercise the independent Timeline capability.
final class ConversationFixture {
  ConversationFixture({ResourceBudget? budget, FixtureConversationContext? context})
      : budget = budget ?? ResourceBudget(),
        context = context ?? FixtureConversationContext() {
    operations = OperationRegistry(clientId: 'conversation-test', budget: this.budget);
    final assembly = createConversationRepository(
      port: facets,
      context: this.context,
      timeline: timeline,
      budget: this.budget,
      operations: operations,
    );
    repository = assembly.repository;
    demand = assembly.demand;
    archive = assembly.archive;
  }

  final ResourceBudget budget;
  final FixtureConversationContext context;
  final facets = FixtureConversationPort();
  final timeline = TimelineOpenQueue();
  late final OperationRegistry operations;
  late final ConversationRepository repository;
  late final ConversationDemand demand;
  late final WorkspaceArchiveCapturePort archive;
  int _selectionGeneration = 0;

  ConversationSession select(String threadId) {
    demand.select(threadId: threadId, needsOpen: false,
      selectionGeneration: ++_selectionGeneration);
    return repository.active.value!;
  }

  void deselect() => demand.select(threadId: null, needsOpen: false,
    selectionGeneration: ++_selectionGeneration);
}

WorkspaceThreadRecord fixtureThread(String threadId, {
  String? parentThreadId,
  String role = 'root',
}) => WorkspaceThreadRecord(
  id: threadId,
  projectId: 'project',
  title: 'Synthetic Thread',
  mode: ThreadModeId.simple,
  workspaceMode: ThreadWorkspaceMode.local,
  workspacePath: '/workspace/$threadId',
  rootThreadId: parentThreadId ?? threadId,
  parentThreadId: parentThreadId,
  role: role,
  agentPath: 'root',
  status: ThreadStatus.idle,
  createdAt: 1700000000,
  updatedAt: 1700000001,
  lastUserMessageAt: null,
  archived: false,
);

final class FixtureConversationContext implements ConversationContextPort {
  final metadataRequests = <String>[];
  final metadataOwners = <ThreadMetadata>[];
  final recoveryRequests = <WorkspaceThreadRecord>[];
  ThreadMetadata Function(String)? metadata;
  Future<ConversationRecoveryAccess> Function(WorkspaceThreadRecord)? recovery;

  @override
  ThreadMetadata openThreadMetadata(String threadId) {
    metadataRequests.add(threadId);
    final owner = metadata?.call(threadId) ?? ScriptedThreadMetadata(threadId,
      initial: metadataState(record: fixtureThread(threadId)));
    metadataOwners.add(owner);
    return owner;
  }

  @override
  Future<ConversationRecoveryAccess> readRecoveryAccess(WorkspaceThreadRecord thread) {
    recoveryRequests.add(thread);
    return recovery?.call(thread) ??
        Future.value(const ConversationRecoveryAccess.allowed());
  }
}

final class FacetOpen<T> {
  const FacetOpen(this.threadId, this.mode, this.feed);
  final String threadId;
  final ThreadObservationMode mode;
  final ScriptedFeed<T> feed;
}

final class FixtureConversationPort implements ConversationObservationPort {
  final execution = <FacetOpen<ThreadExecutionFrame>>[];
  final metrics = <FacetOpen<ThreadMetricsFrame>>[];
  final _metricsWaiters = <int, Completer<FacetOpen<ThreadMetricsFrame>>>{};
  final context = <FacetOpen<ThreadContextFrame>>[];
  final configuration = <FacetOpen<ThreadConfigurationFrame>>[];
  final authoring = <FacetOpen<ThreadAuthoringFrame>>[];
  int _sequence = 0;

  Future<FacetOpen<ThreadMetricsFrame>> metricsOpened(int index) => index < metrics.length ? Future.value(metrics[index])
    : _metricsWaiters.putIfAbsent(index, Completer<FacetOpen<ThreadMetricsFrame>>.new).future;

  Future<FeedConnection<T>> _open<T>(
    List<FacetOpen<T>> requests,
    String threadId,
    ThreadObservationMode mode,
    int? Function(T) sequenceOf,
    bool Function(T) isTerminal,
  ) {
    final feed = ScriptedFeed<T>(feedId: 'facet-${++_sequence}-$threadId',
      sequenceOf: sequenceOf, isTerminal: isTerminal);
    requests.add(FacetOpen(threadId, mode, feed));
    return Future.value(feed);
  }

  @override
  Future<FeedConnection<ThreadExecutionFrame>> openThreadExecution(
    String threadId, {required ThreadObservationMode mode}
  ) => _open(execution, threadId, mode,
    (frame) => frame is ThreadExecutionData ? frame.deliverySequence : null,
    (frame) => frame is! ThreadExecutionData);

  @override
  Future<FeedConnection<ThreadMetricsFrame>> openThreadMetrics(
    String threadId, {required ThreadObservationMode mode}
  ) {
    final result = _open(metrics, threadId, mode,
    (frame) => frame is ThreadMetricsData ? frame.deliverySequence : null,
    (frame) => frame is! ThreadMetricsData);
    _metricsWaiters.remove(metrics.length - 1)?.complete(metrics.last);
    return result;
  }

  @override
  Future<FeedConnection<ThreadContextFrame>> openThreadContext(
    String threadId, {required ThreadObservationMode mode}
  ) => _open(context, threadId, mode,
    (frame) => frame is ThreadContextData ? frame.deliverySequence : null,
    (frame) => frame is! ThreadContextData);

  @override
  Future<FeedConnection<ThreadConfigurationFrame>> openThreadConfiguration(
    String threadId, {required ThreadObservationMode mode}
  ) => _open(configuration, threadId, mode,
    (frame) => frame is ThreadConfigurationData ? frame.deliverySequence : null,
    (frame) => frame is! ThreadConfigurationData);

  @override
  Future<FeedConnection<ThreadAuthoringFrame>> openThreadAuthoring(
    String threadId, {required ThreadObservationMode mode}
  ) => _open(authoring, threadId, mode,
    (frame) => frame is ThreadAuthoringData ? frame.deliverySequence : null,
    (frame) => frame is! ThreadAuthoringData);

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unscripted conversation read: ${invocation.memberName}');
}

final class TimelineOpenRequest {
  TimelineOpenRequest(this.threadId);
  final String threadId;
  final result = Completer<StudioTimelineConnection>();
}

/// Records actual port admission, including late opens belonging to retired
/// Sessions. Waiting for an index does not start or replay an open.
final class TimelineOpenQueue implements TimelineTransport {
  final requests = <TimelineOpenRequest>[];
  final _waiters = <int, Completer<TimelineOpenRequest>>{};

  Future<TimelineOpenRequest> opened(int index) {
    if (index < requests.length) return Future.value(requests[index]);
    return _waiters.putIfAbsent(index, Completer<TimelineOpenRequest>.new).future;
  }

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) {
    final request = TimelineOpenRequest(threadId);
    final index = requests.length;
    requests.add(request);
    _waiters.remove(index)?.complete(request);
    return request.result.future;
  }
}

/// Observes receipts of the existing native-boundary fake. This decorator owns
/// no protocol, cleanup state, body cache or retry policy of its own.
final class TimelineConnectionProbe implements StudioTimelineConnection {
  TimelineConnectionProbe(this.native);
  final TestTimelineConnection native;
  final _acks = <int, Completer<void>>{};
  final _pages = <int, Completer<({String? before, int? limit})>>{};
  final _details =
      <int, Completer<({String itemId, StudioTimelineDetailQuery query})>>{};

  Future<void> acknowledged(int prefix) {
    if (native.ackedThrough >= prefix) return Future.value();
    return _acks.putIfAbsent(prefix, Completer<void>.new).future;
  }

  Future<({String? before, int? limit})> pageRequested(int index) {
    if (index < native.pageRequests.length) {
      return Future.value(native.pageRequests[index]);
    }
    return _pages.putIfAbsent(index,
      Completer<({String? before, int? limit})>.new).future;
  }

  Future<({String itemId, StudioTimelineDetailQuery query})> detailRequested(int index) {
    if (index < native.detailRequests.length) {
      return Future.value(native.detailRequests[index]);
    }
    return _details.putIfAbsent(index,
      Completer<({String itemId, StudioTimelineDetailQuery query})>.new).future;
  }

  @override
  Stream<StudioTimelineFeedFrame> get events => native.events;

  @override
  Future<void> ackThrough(int deliverySequence) =>
      native.ackThrough(deliverySequence).then((_) {
        for (final prefix in _acks.keys.toList()) {
          if (prefix <= native.ackedThrough) _acks.remove(prefix)!.complete();
        }
      });

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) {
    final result = native.page(before: before, limit: limit);
    final index = native.pageRequests.length - 1;
    _pages.remove(index)?.complete(native.pageRequests[index]);
    return result;
  }
  @override
  Future<StudioTimelineDetailChunk> readDetail({required String itemId,
    required StudioTimelineDetailQuery query}) {
    final result = native.readDetail(itemId: itemId, query: query);
    final index = native.detailRequests.length - 1;
    _details.remove(index)?.complete(native.detailRequests[index]);
    return result;
  }
  @override
  void requestClose() => native.requestClose();
  @override
  Future<FeedCloseReport> close() => native.close();
  @override
  Future<FeedCloseReport> retryClose() => native.retryClose();
}
