import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/thread_runtime_fields.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/conversation.dart'
    show ConversationSession, CurrentReader;
import 'package:anywork_client/models.dart';
import 'package:anywork_client/studio_client.dart'
    show
        ThreadNotificationFrame,
        ThreadRuntimeUpdate,
        ThreadSnapshotFrame,
        ThreadStreamFrame;
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

import '../support/chat_fixtures.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_app_lifecycle.dart';
import '../support/test_statistics_feed.dart';

const _threadId = 'thread-main';
final _todo = threadTodoProvider(_threadId);
final _workflow = threadWorkflowRunProvider(_threadId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'inline and deferred fields switch as Current joins an existing lease',
    () async {
      final fixture = await _RuntimeFixture.open();
      final todoBody = fixture.todoBody('1', 'Deferred step');
      final workflowBody = fixture.workflowBody('1', 'Deferred workflow');
      const inlineTodo = TimelineTodoListUpdate(
        callId: 'inline',
        items: [TimelineTodoItem(step: 'Inline step', status: 'pending')],
      );
      final inlineRun = WorkflowRunView(
        lineageId: 'test-lineage',
        runId: 'inline-run',
        modeId: 'mode.auto',
        graphRevision: 1,
        graphHash: 'inline-graph',
        currentStateId: 'inline',
        currentStateTitle: 'Inline stage',
        terminal: false,
        startedAt: DateTime.utc(2025),
        updatedAt: DateTime.utc(2025),
      );
      await fixture.publish(todo: inlineTodo, run: inlineRun);
      fixture.container.listen(_todo, (_, _) {});
      fixture.container.listen(_workflow, (_, _) {});
      expect(fixture.container.read(_todo).requireValue, inlineTodo);
      expect(fixture.container.read(_workflow).requireValue?.run, inlineRun);

      await fixture.publish(
        todo: inlineTodo,
        run: inlineRun,
        deferred: [todoBody.field, workflowBody.field],
      );
      expect(fixture.graph.timeline.lease(_threadId), isNull);
      expect(fixture.container.read(_todo).isLoading, isTrue);
      expect(fixture.container.read(_workflow).isLoading, isTrue);

      final currentOpen = Completer<void>();
      addTearDown(() {
        if (!currentOpen.isCompleted) currentOpen.complete();
      });
      fixture.transport.nextCurrentOpenGate = currentOpen;
      fixture.graph.timeline.updateReadDemand(chatDemand);
      await timelineReady(fixture.graph.timeline, _threadId);
      final lease = fixture.graph.timeline.lease(_threadId)!;
      expect(lease.current, isNull);
      expect(fixture.container.read(_todo).isLoading, isTrue);
      expect(todoBody.reads, 0);

      currentOpen.complete();
      await Future.wait([todoBody.started.future, workflowBody.started.future]);
      expect(fixture.graph.timeline.lease(_threadId), same(lease));
      expect(
        (await fixture.container.read(_todo.future))?.items.single.step,
        'Deferred step',
      );
      expect(
        (await fixture.container.read(_workflow.future))?.run.currentStateTitle,
        'Deferred workflow',
      );
      expect(todoBody.reads, 1);
      expect(workflowBody.reads, 1);

      await fixture.publish(todo: inlineTodo, run: inlineRun);
      expect(fixture.container.read(_todo).requireValue, inlineTodo);
      expect(fixture.container.read(_workflow).requireValue?.run, inlineRun);
    },
  );

  for (final failOldRead in [false, true]) {
    test(
      'a superseded workflow field ignores late ${failOldRead ? 'errors' : 'data'}',
      () async {
        final fixture = await _RuntimeFixture.open();
        final old = fixture.workflowBody('1', 'Old workflow', hold: true);
        final current = fixture.workflowBody('2', 'Current workflow');
        final seen = <AsyncValue<ThreadWorkflowRun?>>[];
        fixture.container.listen(_workflow, (_, next) => seen.add(next));
        await fixture.publish(deferred: [old.field]);
        fixture.graph.timeline.updateReadDemand(chatDemand);
        await old.started.future;

        await fixture.publish(deferred: [current.field]);
        await current.started.future;
        final run = await fixture.container.read(_workflow.future);
        expect(run?.run.currentStateTitle, 'Current workflow');

        if (failOldRead) {
          old.gate!.completeError(StateError('Retired workflow'));
        } else {
          old.gate!.complete();
        }
        await fixture.container.pump();
        expect(fixture.container.read(_workflow).requireValue, run);
        expect(seen.any((state) => state.hasError), isFalse);
        expect(
          seen.any(
            (state) =>
                state.asData?.value?.run.currentStateTitle == 'Old workflow',
          ),
          isFalse,
        );
      },
    );
  }

  test(
    'a current body failure is surfaced and retry reads the same reference',
    () async {
      final fixture = await _RuntimeFixture.open();
      final body = fixture.todoBody('1', 'Recovered step', hold: true);
      fixture.container.listen(_todo, (_, _) {});
      await fixture.publish(deferred: [body.field]);
      fixture.graph.timeline.updateReadDemand(chatDemand);
      await body.started.future;

      final error = StateError('Current field could not be read');
      final failed = expectLater(
        fixture.container.read(_todo.future),
        throwsA(same(error)),
      );
      body.gate!.completeError(error);
      await failed;
      expect(fixture.container.read(_todo).asError?.error, same(error));
      expect(body.reads, 1);

      fixture.container.invalidate(_todo);
      expect(
        (await fixture.container.read(_todo.future))?.items.single.step,
        'Recovered step',
      );
      expect(body.reads, 2);
    },
  );

  test('dropping the field observation stops further body windows', () async {
    final fixture = await _RuntimeFixture.open();
    // More than one body window. A retired read must not request the second.
    final body = fixture.todoBody('1', 'long step ' * 7000, hold: true);
    final subscription = fixture.container.listen(_todo, (_, _) {});
    await fixture.publish(deferred: [body.field]);
    fixture.graph.timeline.updateReadDemand(chatDemand);
    await body.started.future;
    final lease = fixture.graph.timeline.lease(_threadId)!;
    final reader = lease.current! as RecordingCurrentReader;

    subscription.close();
    await fixture.container.pump();
    expect(reader.requested, isFalse);

    body.gate!.complete();
    // Let the completed window cross the read scope before inspecting calls.
    await Future<void>(() {});
    expect(fixture.graph.timeline.lease(_threadId), same(lease));
    expect(body.reads, 1);
  });

  test(
    'a replacement lease reads the same field and joins the old scope',
    () async {
      final fixture = await _RuntimeFixture.open();
      final body = fixture.workflowBody('1', 'Current workflow', hold: true);
      final errors = <Object>[];
      fixture.container.listen(_workflow, (_, next) {
        if (next.asError case final error?) errors.add(error.error);
      });
      await fixture.publish(deferred: [body.field]);
      final timeline = fixture.graph.timeline;
      timeline.updateReadDemand(chatDemand);
      await body.started.future;
      final old = timeline.lease(_threadId)!;
      final oldReader = old.current!;
      final retired = timeline.retire();
      timeline.select(_threadId);
      await body.reread.future;
      final current = timeline.lease(_threadId)!;
      expect(current, isNot(same(old)));
      expect(current.current, isNot(same(oldReader)));
      final run = await fixture.container.read(_workflow.future);
      expect(run?.run.currentStateTitle, 'Current workflow');
      expect(old.isReleased, isFalse);

      body.gate!.completeError(StateError('Retired reader'));
      await retired;
      await fixture.container.pump();
      expect(old.isReleased, isTrue);
      expect(fixture.container.read(_workflow).requireValue, run);
      expect(errors, isEmpty);
    },
  );
}

final class _RuntimeFixture {
  _RuntimeFixture(
    this.graph,
    this.transport,
    this.container,
    this.session,
    this.reader,
  );

  final AppGraph graph;
  final _RuntimeTransport transport;
  final ProviderContainer container;
  final ConversationSession session;
  final RecordingCurrentReader reader;

  static Future<_RuntimeFixture> open() async {
    final transport = _RuntimeTransport();
    final graph = testAppGraph(
      transport: transport,
      statisticsFeed: const TestStatisticsFeedPort(),
      clientId: 'runtime-fields',
    );
    final container = ProviderContainer(
      overrides: [appGraphProvider.overrideWithValue(graph)],
    );
    addTearDown(() async {
      container.dispose();
      for (final body in transport.bodies.values) {
        if (body.gate case final gate? when !gate.isCompleted) gate.complete();
      }
      final report = await graph.close(budget: testCloseBudget());
      expect(report.complete, isTrue, reason: describeTestCloseReport(report));
    });
    await graph.client.bootstrap();
    graph.setConversationPageVisible(true);
    await graph.client.directoryCommands.selectThread(_threadId);
    await graph.client.conversations.visibleThreadId.waitFor(
      (id) => id == _threadId,
    );
    final session = graph.client.conversations.existingSession(_threadId)!;
    await session.source.waitFor((state) => state.hasSnapshot);
    final reader = transport.currentReaders.singleWhere(
      (reader) => reader.threadId == _threadId && reader.demand.maxItems == 128,
    );
    await reader.watchEntered.future;
    return _RuntimeFixture(graph, transport, container, session, reader);
  }

  Future<void> publish({
    TimelineTodoListUpdate? todo,
    WorkflowRunView? run,
    List<CurrentStateField> deferred = const [],
  }) async {
    final workflow = WorkflowRuntimeView(
      revision: session.state.revision + 1,
      currentRun: run,
    );
    transport.deferred = deferred;
    final published = transport.seedConversationState(
      _threadId,
      ThreadRuntimeUpdate(
        runtime: session.state.runtime!.copyWith(workflow: workflow),
        todo: todo,
        modelRoute: session.state.modelRoute,
      ),
    );
    final state = await session.source
        .waitFor(
          (state) =>
              state.revision >= published.revision &&
              state.workflow == workflow,
        )
        .timeout(const Duration(seconds: 5));
    expect(state.runtime?.deferred, deferred);
    expect(state.workspace?.todo, todo);
    await container.pump();
  }

  _Body todoBody(String generation, String step, {bool hold = false}) =>
      _body('todo', generation, {
        'callId': 'todo-$generation',
        'items': [
          {'step': step, 'status': 'pending'},
        ],
      }, hold: hold);

  _Body workflowBody(String generation, String title, {bool hold = false}) =>
      _body('workflow', generation, {
        'revision': int.parse(generation),
        'currentRun': {
          'lineageId': 'workflow-lineage',
          'runId': 'workflow-run',
          'modeId': 'mode.auto',
          'graphRevision': 1,
          'graphHash': 'frozen-graph',
          'currentStateId': 'triage',
          'currentStateTitle': title,
          'lifecycle': 'active',
          'startedAt': 1,
          'updatedAt': 1,
        },
      }, hold: hold);

  _Body _body(
    String name,
    String generation,
    Map<String, Object> payload, {
    required bool hold,
  }) {
    final reference = CurrentContentRef(
      ownerId: reader.metadata.currentOwnerId,
      domain: 'state:runtime',
      entityId: 'state',
      contentKey: name,
      generation: generation,
    );
    return transport.bodies[reference] = _Body(
      reference,
      utf8.encode(jsonEncode(payload)),
      hold: hold,
    );
  }
}

final class _RuntimeTransport extends RecordingDemoTransport {
  final bodies = <CurrentContentRef, _Body>{};
  List<CurrentStateField> deferred = const [];

  // Demo emits canonical Current frames but does not produce deferred Todo or
  // workflow bodies. Supply those wire fields at its existing transport seam.
  @override
  ThreadStreamFrame testMapCurrentState(ThreadStreamFrame frame) =>
      switch (frame) {
        ThreadSnapshotFrame(:final workspace, :final schemaVersion) =>
          ThreadSnapshotFrame(
            workspace: workspace.copyWith(
              runtime: workspace.runtime.copyWith(deferred: deferred),
            ),
            schemaVersion: schemaVersion,
          ),
        ThreadNotificationFrame(
          :final threadId,
          :final epoch,
          :final baseRevision,
          :final revision,
          update: ThreadRuntimeUpdate(
            :final runtime,
            :final todo,
            :final modelRoute,
          ),
        ) =>
          ThreadNotificationFrame(
            threadId: threadId,
            epoch: epoch,
            baseRevision: baseRevision,
            revision: revision,
            update: ThreadRuntimeUpdate(
              runtime: runtime.copyWith(deferred: deferred),
              todo: todo,
              modelRoute: modelRoute,
            ),
          ),
        _ => frame,
      };

  @override
  Future<CurrentReader> openCurrentReader(
    String threadId, {
    required int currentProtocolVersion,
    required ReadDemand demand,
  }) async {
    final reader = await super.openCurrentReader(
      threadId,
      currentProtocolVersion: currentProtocolVersion,
      demand: demand,
    ) as RecordingCurrentReader;
    reader.onReadBody = (reference, range) =>
        bodies[reference]?.read(range) ??
        reader.inner.readBody(reference: reference, range: range);
    return reader;
  }
}

final class _Body {
  _Body(this.reference, this.bytes, {required bool hold})
    : gate = hold ? Completer<void>() : null;

  final CurrentContentRef reference;
  final List<int> bytes;
  final Completer<void>? gate;
  final started = Completer<void>();
  final reread = Completer<void>();
  int reads = 0;

  BodyCurrentStateField get field => BodyCurrentStateField(
    field: reference.contentKey,
    reference: reference,
    byteLength: bytes.length,
  );

  Future<ContentWindow> read(ContentRange range) async {
    if (++reads == 1) {
      started.complete();
      await gate?.future;
    } else if (!reread.isCompleted) {
      reread.complete();
    }
    return ContentWindow(
      offset: range.offset,
      bytes: bytes.skip(range.offset).take(range.maxBytes).toList(),
      generation: reference.generation,
      availableThrough: bytes.length,
      sealed: true,
    );
  }
}
