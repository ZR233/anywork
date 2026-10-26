import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/drafts_native_fixture.dart';
import '../../../anywork_client/test/support/timeline_transport.dart';
import 'support/selector_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit cold selection reads only its metadata and opens only its history', () async {
    final fixture = await _fixture();
    final env = fixture.env;
    final rejected = await env.workspace
        .selectAgentThread(fixture.other.id)
        .result;
    expect(
      rejected,
      isA<RejectedCommandResult<WorkspaceSelectionResult>>().having(
        (result) => result.error.code,
        'code',
        StudioFailureCode.invalidArgument,
      ),
    );
    expect(env.directory.metadataReads, isEmpty);
    expect(fixture.sessions, isEmpty);
    expect(
      await env.workspace.selectAgentThread(fixture.child.id).result,
      isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
    );
    await _expectSelectedHistory(fixture);
  });

  test(
    'restored cold selection stays unopened until its explicit open command',
    () async {
      final fixture = await _fixture();
      final env = fixture.env;
      env.workspace.restoreSelection(
        WorkspaceSelection(
          projectId: fixture.root.projectId,
          threadId: fixture.child.id,
          needsOpen: true,
        ),
      );
      env.binding.start();
      expect(env.workspace.state.value.selection.needsOpen, isTrue);
      expect(env.directory.metadataReads, isEmpty);
      expect(fixture.sessions, isEmpty);
      expect(env.timeline.requests, isEmpty);
      expect(
        await env.workspace.openSelectedThread(fixture.child.id).result,
        isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
      );
      await _expectSelectedHistory(fixture);
    },
  );

  test('cold metadata failures and wrong identity cannot change selection or directory', () async {
    final fixture = await _fixture();
    final env = fixture.env;
    for (final response in [
      fixture.other,
      fixture.child.copyWith(rootThreadId: fixture.other.id),
      fixture.child.copyWith(
        projectId: 'foreign-project',
        workspacePath: '/foreign',
      ),
    ]) {
      env.directory.respond = (_) async => response;
      final result = await env.workspace
          .selectAgentThread(fixture.child.id)
          .result;
      expect(
        result,
        isA<RejectedCommandResult<WorkspaceSelectionResult>>().having(
          (result) => result.error.code,
          'code',
          StudioFailureCode.protocol,
        ),
      );
      expect(env.workspace.state.value.selection.threadId, fixture.root.id);
      expect(fixture.rootRows, [fixture.root.id, fixture.other.id]);
      expect(fixture.sessions, isEmpty);
    }
    const failure = StudioFailure(
      code: StudioFailureCode.storage,
      message: 'saved metadata unavailable',
      retryable: false,
      correlationId: 'saved-metadata',
    );
    env.directory.respond = (_) async => throw failure;
    final result = await env.workspace
        .selectAgentThread(fixture.child.id)
        .result;
    expect(
      result,
      isA<RejectedCommandResult<WorkspaceSelectionResult>>().having(
        (result) => result.error,
        'error',
        failure,
      ),
    );
    expect(env.workspace.state.value.selection.threadId, fixture.root.id);
    expect(fixture.rootRows, [fixture.root.id, fixture.other.id]);
    expect(fixture.rootQuery.state.value.projection.stamp!.revision, 7);
    expect(env.conversationPort.facets.execution, isEmpty);
    expect(env.timeline.requests, isEmpty);
  });

  test(
    'late cold metadata cannot override navigation or removed membership',
    () async {
      for (final invalidation in [
        'same-root-selection',
        'root',
        'project',
        'membership',
      ]) {
        final fixture = await _fixture();
        final env = fixture.env;
        final entered = Completer<void>();
        final reply = Completer<WorkspaceThreadRecord>();
        env.directory.respond = (_) {
          if (!entered.isCompleted) entered.complete();
          return reply.future;
        };
        final pending = env.workspace.selectAgentThread(fixture.child.id);
        await entered.future;
        switch (invalidation) {
          case 'same-root-selection':
            env.workspace.restoreSelection(
              WorkspaceSelection(
                projectId: fixture.root.projectId,
                threadId: 'cold-sibling',
                needsOpen: true,
              ),
            );
          case 'root':
            env.workspace.restoreSelection(
              WorkspaceSelection(
                projectId: fixture.other.projectId,
                threadId: fixture.other.id,
                needsOpen: true,
              ),
            );
          case 'project':
            env.workspace.restoreSelection(
              const WorkspaceSelection(
                projectId: 'foreign-project',
                threadId: null,
                needsOpen: false,
              ),
            );
          case 'membership':
            await env.directory.publishAgents(
              env.directory.agents
                  .where((agent) => agent.threadId != fixture.child.id)
                  .toList(),
            );
        }
        final newerSelection = env.workspace.state.value.selection;
        reply.complete(fixture.child);
        expect(
          (await pending.result
                  as AcknowledgedCommandResult<WorkspaceSelectionResult>)
              .value
              .disposition,
          SelectionDisposition.superseded,
          reason: invalidation,
        );
        expect(
          env.workspace.state.value.selection,
          newerSelection,
          reason: invalidation,
        );
        expect(fixture.rootRows, [
          fixture.root.id,
          fixture.other.id,
        ], reason: invalidation);
        expect(fixture.sessions, isEmpty, reason: invalidation);
        expect(env.directory.metadataReads, [fixture.child.id]);
        expect(
          env.conversationPort.facets.execution,
          isEmpty,
          reason: invalidation,
        );
        expect(env.timeline.requests, isEmpty, reason: invalidation);
      }
    },
  );

  test('a newer public cold selection invalidates the older queued read before publication', () async {
    await _expectLatestQueuedColdSelection();
  });

  test('superseded cold read errors are ignored but the latest read failure remains visible', () async {
    await _expectLatestQueuedColdSelection(oldFails: true);
    await _expectLatestQueuedColdSelection(newFails: true);
  });

  test('all queued directory navigation entries retire an older cold read at receipt', () async {
    for (final action in [
      'root',
      'project',
      'project-failure',
      'new-session',
      'startup-open',
      'restore-failure',
      'open-project',
      'open-remote',
    ]) {
      final fixture = await _fixture();
      final env = fixture.env;
      final entered = Completer<void>();
      final reply = Completer<WorkspaceThreadRecord>();
      env.directory.respond = (id) {
        if (id != fixture.child.id) {
          return Future.value(
            env.directory.threads.firstWhere((thread) => thread.id == id),
          );
        }
        if (!entered.isCompleted) entered.complete();
        return reply.future;
      };
      final oldNavigation = env.workspace.selectAgentThread(fixture.child.id);
      await entered.future;
      env.directory.onActivate = (id) async {
        if (action == 'project-failure') {
          throw const StudioFailure(
            code: StudioFailureCode.storage,
            message: 'activation rejected',
            retryable: false,
            correlationId: 'activation',
          );
        }
      };
      final next = switch (action) {
        'root' => env.workspace.selectThread(fixture.other.id).result,
        'project' => env.workspace.selectProject(fixture.root.projectId).result,
        'project-failure' =>
          env.workspace.selectProject('foreign-project').result,
        'new-session' =>
          env.workspace.beginNewThread(fixture.root.projectId).result,
        'startup-open' =>
          env.workspace.openSelectedThread(fixture.root.id).result,
        'restore-failure' =>
          env.workspace.restoreThread(fixture.root.id).result,
        'open-project' =>
          env.workspace.openProject('/saved/another-project').result,
        'open-remote' =>
          env.workspace.openRemoteProject('arm-dev', '/saved/remote').result,
        _ => throw StateError('Unknown test action $action'),
      };
      reply.complete(fixture.child);
      final retired =
          await oldNavigation.result
              as AcknowledgedCommandResult<WorkspaceSelectionResult>;
      expect(
        retired.value.disposition,
        SelectionDisposition.superseded,
        reason: action,
      );
      final result = await next;
      if (action.endsWith('-failure')) {
        expect(
          result,
          isA<RejectedCommandResult<WorkspaceSelectionResult>>().having(
            (value) => value.error.code,
            'code',
            StudioFailureCode.storage,
          ),
          reason: action,
        );
      } else {
        expect(
          result is AcknowledgedCommandResult<WorkspaceSelectionResult> ||
              result is WorkspaceOpenResult,
          isTrue,
          reason:
              '$action: ${result is RejectedCommandResult<WorkspaceSelectionResult> ? result.error.message : result}',
        );
      }
      expect(fixture.rootRows, [fixture.root.id, fixture.other.id]);
      expect(
        env.conversations.existingSession(fixture.child.id),
        isNull,
        reason: action,
      );
      expect(
        env.workspace.state.value.selection.threadId,
        isNot(fixture.child.id),
        reason: action,
      );
      expect(
        env.conversationPort.facets.execution.map((entry) => entry.threadId),
        isNot(contains(fixture.child.id)),
        reason: action,
      );
      expect(
        env.timeline.requests.map((entry) => entry.threadId),
        isNot(contains(fixture.child.id)),
        reason: action,
      );
      expect(
        env.directory.metadataReads.where((id) => id == fixture.child.id),
        [fixture.child.id],
        reason: action,
      );
      expect(env.commands.prompts.values, isEmpty, reason: action);
    }
  });

  test(
    'project-scoped new session cannot revive a superseded project activation',
    () async {
      final fixture = await _fixture();
      final env = fixture.env;
      final entered = Completer<void>();
      final activation = Completer<void>();
      env.directory.onActivate = (_) {
        entered.complete();
        return activation.future;
      };
      final draftNavigation = env.workspace.beginNewThread('foreign-project');
      await entered.future;
      final newer = env.workspace.selectThread(fixture.other.id);
      activation.complete();
      expect(
        (await draftNavigation.result
                as AcknowledgedCommandResult<WorkspaceSelectionResult>)
            .value
            .disposition,
        SelectionDisposition.superseded,
      );
      expect(
        await newer.result,
        isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
      );
      env.binding.start();
      await waitLatest(
        env.conversations.active,
        (session) => session?.threadId == fixture.other.id,
      );
      await waitLatest(
        env.conversations.active.value!.execution,
        (value) => value.sync.phase == FacetSyncPhase.ready,
      );
      expect(
        env.workspace.state.value.selection.projectId,
        fixture.other.projectId,
      );
      expect(env.workspace.state.value.selection.threadId, fixture.other.id);
      expect(fixture.sessions, [fixture.other.id]);
      expect(
        env.conversationPort.facets.execution.map((entry) => entry.threadId),
        [fixture.other.id],
      );
    },
  );

  test('new Thread creation and directory reads share the latest navigation boundary', () async {
    final fixture = await _fixture();
    final env = fixture.env;
    final sibling = fixture.sibling;
    await env.prepareStart();
    final start = env.drafts.start('project')..setText('A new root');
    final oldEntered = Completer<void>(), newEntered = Completer<void>();
    final oldReply = Completer<WorkspaceThreadRecord>(),
        newReply = Completer<WorkspaceThreadRecord>();
    env.directory.respond = (id) {
      if (id == fixture.child.id) {
        if (!oldEntered.isCompleted) oldEntered.complete();
        return oldReply.future;
      }
      if (!newEntered.isCompleted) newEntered.complete();
      return newReply.future;
    };
    final oldNavigation = env.workspace.selectAgentThread(fixture.child.id);
    await oldEntered.future;
    final created = start.submit();
    final begin = await env.creations.begins.at(0);
    final job = DraftCreationJob(
      begin.id,
      begin.request.projectId,
      begin.request.input.inputId,
    );
    begin.reply.complete(job);
    oldReply.complete(fixture.child);
    expect(
      (await oldNavigation.result
              as AcknowledgedCommandResult<WorkspaceSelectionResult>)
          .value
          .disposition,
      SelectionDisposition.superseded,
    );
    expect(fixture.rootRows, [fixture.root.id, fixture.other.id]);
    expect(fixture.sessions, isEmpty);
    final newer = env.workspace.selectAgentThread(sibling.id);
    await newEntered.future;
    final result = StartNewThreadResult(
      thread: fixture.root,
      receipt: SubmitPromptReceipt(
        threadId: fixture.root.id,
        inputId: begin.request.input.inputId,
        cursor: 1,
        requestDigest: 'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      ),
    );
    (await job.reads.at(0)).complete(result);
    final source = DraftCreatedSource(
      fixture.root.id,
      begin.request.input.inputId,
    );
    (await job.sourceCalls.at(0)).complete(source);
    await source.feed.listened.future;
    // The created-input handoff is non-activating. It cannot open UI/history or
    // overwrite the newer user navigation while its original metadata is held.
    source.feed.emit(
      ThreadExecutionFrame.data(
        deliverySequence: 1,
        event: ThreadExecutionEvent.baseline(
          identity: ThreadFeedIdentity(
            feedId: source.feed.feedId,
            runtimeEpoch: source.runtimeEpoch,
            incarnation: 1,
            facet: ThreadFacet.execution,
            mode: ThreadObservationMode.live,
          ),
          stamp: ThreadFacetStamp(
            runtimeEpoch: source.runtimeEpoch,
            incarnation: 1,
            facet: ThreadFacet.execution,
            revision: 1,
          ),
          value: env.conversationPort.facets.execution.isEmpty
              ? const ThreadExecutionBaseline(
                  status: ThreadStatus.idle,
                  activeTurn: null,
                  recentTerminalTurn: null,
                  interactions: InteractionIndexHeader(
                    reference: InteractionIndexRef(entry: 10, revision: 1),
                    total: 0,
                    pending: 0,
                  ),
                  activity: null,
                  storage: null,
                )
              : throw StateError('Creation must not activate a UI Session'),
        ),
      ),
    );
    await source.feed.acknowledged(1);
    (await env.commands.acceptances.at(0)).reply.complete(
      const InputAcceptanceEvidence(
        acceptedSequence: 1,
        requestDigest: 'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        disposition: PersistedInputDisposition.consumed,
      ),
    );
    expect(
      (await created.result as AcknowledgedCommandResult<StartNewThreadResult>)
          .value,
      same(result),
    );
    expect(
      env.workspace.state.value.selection.threadId,
      fixture.root.id,
      reason: 'accepted creation cannot navigate over newer queued intent',
    );
    expect(env.timeline.requests, isEmpty);
    newReply.complete(sibling);
    expect(
      await newer.result,
      isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
    );
    (await job.closes.at(0)).reply.complete(
      FeedCloseReport(
        feedId: job.id.value,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    env.binding.start();
    await waitLatest(
      env.conversations.active,
      (session) => session?.threadId == sibling.id,
    );
    // Active publishes the Session before its original native facet opens.
    await env.conversationPort.facets.executionOpened(0);
    expect(env.workspace.state.value.selection.threadId, sibling.id);
    expect(env.conversations.existingSession(fixture.child.id), isNull);
    expect(
      env.conversationPort.facets.execution.map((entry) => entry.threadId),
      [sibling.id],
    );
  });
}

Future<void> _expectLatestQueuedColdSelection({
  bool oldFails = false,
  bool newFails = false,
}) async {
  final fixture = await _fixture();
  final env = fixture.env;
  final oldEntered = Completer<void>(), newEntered = Completer<void>();
  final oldReply = Completer<WorkspaceThreadRecord>(),
      newReply = Completer<WorkspaceThreadRecord>();
  const oldError = StudioFailure(
    code: StudioFailureCode.storage,
    message: 'superseded read failed',
    retryable: false,
    correlationId: 'old-read',
  );
  const newError = StudioFailure(
    code: StudioFailureCode.storage,
    message: 'latest read failed',
    retryable: false,
    correlationId: 'new-read',
  );
  env.directory.respond = (id) {
    if (id == fixture.child.id) {
      if (!oldEntered.isCompleted) oldEntered.complete();
      return oldReply.future;
    }
    if (!newEntered.isCompleted) newEntered.complete();
    return newReply.future;
  };
  final oldNavigation = env.workspace.selectAgentThread(fixture.child.id);
  await oldEntered.future;
  final newNavigation = env.workspace.selectAgentThread(fixture.sibling.id);
  if (oldFails) {
    oldReply.completeError(oldError);
  } else {
    oldReply.complete(fixture.child);
  }
  expect(
    (await oldNavigation.result
            as AcknowledgedCommandResult<WorkspaceSelectionResult>)
        .value
        .disposition,
    SelectionDisposition.superseded,
    reason: '过期读取的失败不能泄漏到当前菜单',
  );
  await newEntered.future;
  expect(env.workspace.state.value.selection.threadId, fixture.root.id);
  expect(fixture.rootRows, [fixture.root.id, fixture.other.id]);
  expect(fixture.sessions, isEmpty);
  expect(env.conversationPort.facets.execution, isEmpty);
  expect(env.timeline.requests, isEmpty);
  if (newFails) {
    newReply.completeError(newError);
    expect(
      await newNavigation.result,
      isA<RejectedCommandResult<WorkspaceSelectionResult>>().having(
        (result) => result.error,
        'error',
        newError,
      ),
    );
    expect(env.workspace.state.value.selection.threadId, fixture.root.id);
    expect(fixture.rootRows, [fixture.root.id, fixture.other.id]);
    expect(fixture.sessions, isEmpty);
    expect(env.conversationPort.facets.execution, isEmpty);
    expect(env.timeline.requests, isEmpty);
  } else {
    newReply.complete(fixture.sibling);
    expect(
      await newNavigation.result,
      isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
    );
    await _expectSelectedHistory(
      fixture,
      child: fixture.sibling,
      supersededRead: fixture.child.id,
    );
  }
  expect(env.conversations.existingSession(fixture.child.id), isNull);
  expect(env.directory.metadataReads.take(2), [
    fixture.child.id,
    fixture.sibling.id,
  ]);
  expect(env.commands.prompts.values, isEmpty);
  expect(env.directory.restores, isEmpty);
}

Future<void> _expectSelectedHistory(
  _ColdFixture fixture, {
  WorkspaceThreadRecord? child,
  String? supersededRead,
}) async {
  final env = fixture.env;
  final target = child ?? fixture.child;
  env.binding.start();
  final session = (await waitLatest(
    env.conversations.active,
    (session) => session?.threadId == target.id,
  ))!;
  await waitLatest(
    session.execution,
    (value) => value.sync.phase == FacetSyncPhase.ready,
  );
  final consumer = session.timeline.attachConsumer((_) {});
  addTearDown(consumer.close);
  final opening = await env.timeline.opened(0);
  final native = TestTimelineConnection(
    initial: baseline(1, items: [timelineItem(1, threadId: target.id)]),
  );
  opening.result.complete(native);
  await session.timeline.ready;
  expect(env.workspace.state.value.selection.threadId, target.id);
  expect(env.workspace.state.value.selection.needsOpen, isFalse);
  expect(session.execution.value.value?.status, target.status);
  expect(fixture.rootRows, [fixture.root.id, fixture.other.id]);
  expect(
    fixture.rootQuery.state.value.projection.stamp!.revision,
    7,
    reason: '单实体 metadata 不能推进独立分页目录的水位',
  );
  expect(fixture.sessions, [target.id]);
  expect(env.directory.metadataReads.toSet(), {
    target.id,
    ?supersededRead,
  }, reason: '新架构 metadata borrows 只能读取显式请求的身份');
  expect(env.conversationPort.facets.execution.map((entry) => entry.threadId), [
    target.id,
  ]);
  expect(env.timeline.requests.map((entry) => entry.threadId), [target.id]);
  expect(env.commands.prompts.values, isEmpty);
  expect(env.directory.restores, isEmpty);
}

Future<_ColdFixture> _fixture() async {
  final env = SelectorEnvironment();
  addTearDown(env.close);
  await env.establish(catalog: false);
  // The new agent command requires an actually opened root metadata binding,
  // not a restored selection masquerading as opened. Bootstrap attachment is
  // deliberately deferred: metadata reads alone must not create Sessions.
  await env.selectThread('thread-main', bind: false);
  await env.workspace.loadAgents();
  final query = env.workspace.queryThreads(
    const DirectoryQuery(
      projectId: 'project',
      search: null,
      archived: false,
      filter: DirectoryFilter.all,
    ),
  );
  addTearDown(query.close);
  await query.loadMore();
  env.directory.metadataReads.clear();
  return _ColdFixture(env, query);
}

final class _ColdFixture {
  _ColdFixture(this.env, this.rootQuery);
  final SelectorEnvironment env;
  final ThreadDirectoryQuery rootQuery;
  WorkspaceThreadRecord get root => env.directory.threads[0];
  WorkspaceThreadRecord get child => env.directory.threads[1];
  WorkspaceThreadRecord get other => env.directory.threads[2];
  WorkspaceThreadRecord get sibling => env.directory.threads[3];
  List<String> get sessions => [
    for (final thread in env.directory.threads)
      if (env.conversations.existingSession(thread.id) != null) thread.id,
  ];
  List<String> get rootRows =>
      (rootQuery.state.value.threads
              as CurrentCollectionMirror<WorkspaceThreadRecord>)
          .window
          .rows
          .values
          .whereType<ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>>()
          .map((row) => row.current.value.id)
          .toList();
}
