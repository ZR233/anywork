import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

/// Only transport responses and asynchronous barriers are fake. Draft revision,
/// route freezing, attachment ownership and operation observation are production.
final class _DraftTransport implements StudioTransport, ChatWindowReader {
  _DraftTransport() {
    addTearDown(() => frames.close());
  }
  final StreamController<ThreadStreamFrame> frames =
      StreamController<ThreadStreamFrame>.broadcast();
  final Completer<StudioPromptInput> promptEntered = Completer();
  final Completer<SubmitPromptReceipt> promptReply = Completer();
  final Completer<
    ({
      StudioPromptInput input,
      ModeModelRouteView route,
      ThreadModeId mode,
      String? workspaceMode,
    })
  >
  startEntered = Completer();
  final Completer<StartNewThreadResult> startReply = Completer();
  final List<String> removed = [];
  int promptCalls = 0;
  int? promptRouteRevision;
  int? canonicalRouteRevision;
  final List<int> submittedRouteRevisions = [];
  int admissionCalls = 0;
  int settingsWrites = 0;
  bool removeSucceeds = true;
  final window = _DraftWindow();

  @override
  Stream<ThreadStreamFrame> subscribeThread(String threadId) => frames.stream;

  @override
  Future<StudioChatWindow> openChatWindow(String threadId) async => window;

  @override
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) {
    promptCalls += 1;
    promptRouteRevision = expectedModelRouteRevision;
    submittedRouteRevisions.add(expectedModelRouteRevision);
    if (canonicalRouteRevision != null &&
        canonicalRouteRevision != expectedModelRouteRevision) {
      return Future.error(
        const StudioFailure(
          code: StudioFailureCode.staleRevision,
          message: 'Route changed before admission',
          retryable: false,
          correlationId: 'fake-prompt-route-conflict',
        ),
      );
    }
    if (!promptEntered.isCompleted) promptEntered.complete(input);
    return promptReply.future;
  }

  @override
  Future<StartNewThreadResult> startNewThread(
    String projectId,
    StudioPromptInput input,
    ThreadModeId mode, {
    required ModeModelRouteView route,
    String? workspaceMode,
  }) {
    startEntered.complete((
      input: input,
      route: route,
      mode: mode,
      workspaceMode: workspaceMode,
    ));
    return startReply.future;
  }

  @override
  Future<List<AttachmentDraftView>> admitAttachmentDrafts(
    AttachmentAdmissionContext context,
    List<AttachmentDraftSource> sources,
  ) async {
    admissionCalls += 1;
    return [
      for (var index = 0; index < sources.length; index += 1)
        AttachmentDraftView(
          id: 'attachment-$admissionCalls-$index',
          modality: AttachmentModalityView.file,
          mediaType: 'application/octet-stream',
          filename: 'sample.bin',
          byteSize: 3,
        ),
    ];
  }

  @override
  Future<bool> removeAttachmentDraft(String draftId) async {
    if (removeSucceeds) removed.add(draftId);
    return removeSucceeds;
  }

  @override
  Future<SettingsCommandReply> applySettingsField(
    int expectedSettingsRevision,
    SettingsFieldCommand command, {
    required OperationId operationId,
  }) async {
    settingsWrites += 1;
    throw StateError('A draft submission must not mutate settings defaults');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused fake transport capability: ${invocation.memberName}',
  );
}

/// A controlled content source, with the production Session/ChatChannel reducer.
final class _DraftWindow implements StudioChatWindow {
  Completer<StudioChatFrame?>? _next;
  Completer<void> _nextReady = Completer();
  bool _closed = false;

  @override
  Future<StudioChatSnapshot> initial() async => const StudioChatSnapshot(
    focusedItemId: null,
    version: 1,
    items: [],
    hasOlder: false,
    hasNewer: false,
    canExtendLatest: false,
  );

  @override
  Future<StudioChatFrame?> next() {
    if (_closed) return Future.value(null);
    if (_next != null) throw StateError('Two outstanding next calls');
    final pending = Completer<StudioChatFrame?>();
    _next = pending;
    _nextReady.complete();
    return pending.future.whenComplete(() {
      _next = null;
      _nextReady = Completer();
    });
  }

  Future<void> emit(StudioChatFrame frame) async {
    await _nextReady.future;
    _next!.complete(frame);
  }

  @override
  void requestClose() {
    _closed = true;
    final pending = _next;
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }

  @override
  Future<void> close() async {
    requestClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused content control: ${invocation.memberName}',
  );
}

const _project = StudioProject(
  id: 'project',
  name: 'Project',
  path: '/project',
);

StudioThread _thread([String id = 'thread']) => StudioThread(
  id: id,
  projectId: _project.id,
  title: 'Thread',
  mode: ThreadModeId.simple,
  updatedAt: DateTime.utc(2026),
  workspacePath: _project.path,
);

ThreadWorkspace _workspace({int revision = 1, StudioTurnView? turn}) =>
    ThreadWorkspace(
      thread: _thread(),
      revision: revision,
      items: const [],
      interactions: const [],
      activeTurn: turn,
      latestTurn: turn,
      runtime: const ThreadRuntimeView(
        model: 'alpha',
        contextTokens: 0,
        contextWindow: 100,
        totalTokens: 0,
        costLabel: '',
        activeSkills: [],
        activeMcpServers: [],
        activeLspServers: [],
        modelRoute: ThreadModelRouteView(
          providerId: 'provider',
          model: 'alpha',
          effort: 'medium',
          revision: 1,
          available: true,
        ),
      ),
    );

AnyworkClient _client(
  _DraftTransport transport, {
  String id = 'client',
  ResourceBudget? budget,
  Future<String?> Function(Uint8List)? stage,
  Future<void> Function(String)? cleanup,
}) {
  final client = AnyworkClient(
    transport: transport,
    clientId: id,
    budget: budget,
    clipboardImageStager: stage,
    clipboardImageCleanup: cleanup,
  );
  client.project.applyProjectDirectory(
    ProjectDirectoryState(values: [_project], revision: 1),
  );
  client.settings.merge(
    SettingsStateSnapshot(
      revision: 1,
      modelCatalogRevision: 1,
      providers: const [
        ProviderSettingsView(
          id: 'provider',
          name: 'Provider',
          baseUrl: 'http://local.invalid',
          defaultModel: 'alpha',
          status: 'configured',
          usageLabel: '',
          models: [
            ProviderModelView(
              slug: 'alpha',
              displayName: 'Alpha',
              reasoningEfforts: ['medium'],
              defaultReasoningEffort: 'medium',
            ),
            ProviderModelView(
              slug: 'beta',
              displayName: 'Beta',
              reasoningEfforts: ['high'],
              defaultReasoningEffort: 'high',
            ),
          ],
        ),
      ],
      modeModelRoutes: const [
        ModeModelRouteView(
          modeId: ThreadModeId.simple,
          providerId: 'provider',
          model: 'alpha',
          effort: 'medium',
        ),
      ],
    ),
  );
  client.selection.selectProject(_project.id);
  return client;
}

Future<void> _close(AnyworkClient client, _DraftTransport transport) async {
  await client.startDraft.close();
  await client.composer('thread').close();
  await client.attachments.close();
  await client.close();
  await transport.frames.close();
}

void main() {
  test('actual composer preserves revision 9 text and attachments after revision 8 ACK', () async {
    final transport = _DraftTransport();
    final client = _client(transport);
    final session = client.session('thread');
    session.applySnapshot(_workspace());
    final owner = client.composer('thread');
    owner.updateDraft('submitted text');
    await owner.addLocalAttachments(['/first.bin']);
    final submitted = owner.submit();
    final input = await transport.promptEntered.future;

    owner.updateDraft('new text typed during submission');
    await owner.addLocalAttachments(['/second.bin']);
    final queued = StudioTurnView(
      inputId: input.inputId,
      turnId: 'turn',
      threadId: 'thread',
      revision: 1,
      state: const QueuedStudioTurnState(queuedAt: 1),
      updatedAt: DateTime.utc(2026),
    );
    // Frame arrives before the command receipt. Atomic watchLatest must see it.
    session.applySnapshot(_workspace(revision: 2, turn: queued));
    transport.promptReply.complete(
      SubmitPromptReceipt(
        threadId: 'thread',
        inputId: input.inputId,
        cursor: 7,
      ),
    );
    await submitted;

    expect(input.text, 'submitted text');
    expect(transport.promptRouteRevision, 1);
    expect(input.attachmentDraftIds, ['attachment-1-0']);
    expect(owner.state.draft, 'new text typed during submission');
    expect(owner.state.attachments.map((item) => item.id), [
      'attachment-1-0',
      'attachment-2-0',
    ]);
    expect(owner.state.isSubmissionPending, isFalse);
    expect(
      transport.removed,
      isEmpty,
      reason: 'The logical revision 9 draft still owns both staging IDs',
    );
    final operation = client.mutations.operations.single;
    expect(operation.observed, isTrue);
    expect(
      operation.effective,
      isFalse,
      reason: 'Queued input is not effective',
    );
    expect(operation.durable, isFalse);

    session.applySnapshot(
      _workspace(
        revision: 3,
        turn: StudioTurnView(
          inputId: input.inputId,
          turnId: 'turn',
          threadId: 'thread',
          revision: 2,
          state: const RunningStudioTurnState(
            startedAt: 2,
            activity: StudioTurnActivity.thinking,
          ),
          updatedAt: DateTime.utc(2026),
        ),
      ),
    );
    expect(client.mutations.operations.single.effective, isTrue);
    expect(client.mutations.operations.single.durable, isFalse);
    await owner.discard();
    expect(
      transport.removed,
      unorderedEquals(['attachment-1-0', 'attachment-2-0']),
    );
    expect(client.budget.used(ResourceKind.attachment), 0);
    await _close(client, transport);
  });

  test('actual start owner freezes complete route without settings writes and preserves later edits', () async {
    final transport = _DraftTransport();
    final client = _client(transport);
    final owner = client.startDraft;
    owner.updateDraft(_project.id, 'first request');
    await client.attachments.admitNewThread(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      sources: [const AttachmentDraftSource.localFile('/one.bin')],
    );
    final submission = owner.submit(_project.id);
    final request = await transport.startEntered.future;
    owner.updateDraft(_project.id, 'second request');
    owner.setModelIntent(ThreadModeId.simple, 'provider', 'beta');
    owner.setEffortIntent(ThreadModeId.simple, 'high');
    await client.attachments.admitNewThread(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      sources: [const AttachmentDraftSource.localFile('/two.bin')],
    );
    final thread = _thread('new-thread');
    transport.startReply.complete(
      StartNewThreadResult(
        thread: thread,
        receipt: SubmitPromptReceipt(
          threadId: thread.id,
          inputId: request.input.inputId,
          cursor: 4,
        ),
      ),
    );
    expect(await submission, isTrue);

    expect(request.input.text, 'first request');
    expect(request.input.attachmentDraftIds, ['attachment-1-0']);
    expect(
      (request.route.providerId, request.route.model, request.route.effort),
      ('provider', 'alpha', 'medium'),
    );
    expect(transport.settingsWrites, 0);
    expect(owner.state.forProject(_project.id).text, 'second request');
    expect(owner.state.modelIntentFor(ThreadModeId.simple)?.model, 'beta');
    expect(owner.state.effortIntentFor(ThreadModeId.simple), 'high');
    expect(
      client.attachments.state
          .newThread(_project.id)
          .attachments
          .map((item) => item.id),
      ['attachment-1-0', 'attachment-2-0'],
    );
    expect(transport.removed, isEmpty);
    await owner.discardProject(_project.id);
    expect(
      transport.removed,
      unorderedEquals(['attachment-1-0', 'attachment-2-0']),
    );
    await _close(client, transport);
  });

  test('actual accepted input waits for its Chat Turn saved flag after execution completes', () async {
    final transport = _DraftTransport();
    final client = _client(transport);
    final session = client.session('thread');
    session.applySnapshot(_workspace());
    session.start();
    await session.source.waitFor((state) => state.chatVersion == 1);
    final baselineObservers = client.budget.used(ResourceKind.observer);
    final owner = client.composer('thread');
    owner.updateDraft('durable input');
    final submission = owner.submit();
    final input = await transport.promptEntered.future;
    session.applySnapshot(
      _workspace(
        revision: 2,
        turn: StudioTurnView(
          inputId: input.inputId,
          turnId: 'turn',
          threadId: 'thread',
          revision: 1,
          state: const RunningStudioTurnState(
            startedAt: 1,
            activity: StudioTurnActivity.thinking,
          ),
          updatedAt: DateTime.utc(2026),
        ),
      ),
    );
    transport.promptReply.complete(
      SubmitPromptReceipt(
        threadId: 'thread',
        inputId: input.inputId,
        cursor: 7,
      ),
    );
    await submission;
    final operation = client.mutations.lookup(OperationId(input.inputId))!;
    expect(operation.state.value.observed, isTrue);
    expect(operation.state.value.effective, isTrue);
    expect(operation.state.value.durable, isFalse);
    expect(client.budget.used(ResourceKind.observer), baselineObservers + 1);

    final terminal = ThreadItemView(
      id: 'turn-item',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 1,
      revision: 2,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      saved: false,
      executionTerminal: true,
      state: ThreadTurnItemStateView(
        const CompletedStudioTurnState(
          startedAt: 1,
          completedAt: 2,
          completion: StudioTurnCompletion.normal,
        ),
        inputId: input.inputId,
      ),
    );
    await transport.window.emit(
      StudioChatPatch(
        from: 1,
        to: 2,
        changes: [
          StudioViewSplice(
            index: 0,
            remove: 0,
            items: [
              StudioChatItem(
                terminal,
                saved: false,
                lifecycle: StudioChatLifecycle.terminal,
              ),
            ],
          ),
        ],
        hasNewer: false,
      ),
    );
    await session.source.waitFor((state) => state.chatVersion == 2);
    expect(
      operation.state.value.durable,
      isFalse,
      reason: 'A terminal Turn that has not been saved is not durable',
    );
    expect(client.budget.used(ResourceKind.observer), baselineObservers + 1);
    await transport.window.emit(
      const StudioChatPatch(
        from: 2,
        to: 3,
        changes: [
          StudioViewItemUpdate(
            itemId: 'turn-item',
            expectedRevision: 2,
            revision: 2,
            omittedUnits: 0,
            saved: true,
            fields: [],
          ),
        ],
        hasNewer: false,
      ),
    );
    await session.source.waitFor((state) => state.chatVersion == 3);
    expect(operation.state.value.durable, isTrue);
    expect(client.budget.used(ResourceKind.observer), baselineObservers);
    await _close(client, transport);
  });

  test('accepted input observer budget failure preserves the draft and attachments', () async {
    final transport = _DraftTransport();
    final defaults = ResourceBudget().capacities;
    final client = _client(
      transport,
      budget: ResourceBudget(
        capacities: {...defaults, ResourceKind.observer: 0},
      ),
    );
    client.session('thread').applySnapshot(_workspace());
    final owner = client.composer('thread');
    owner.updateDraft('keep after local sync failure');
    await owner.addLocalAttachments(['/payload.bin']);
    final submission = owner.submit();
    final input = await transport.promptEntered.future;
    transport.promptReply.complete(
      SubmitPromptReceipt(
        threadId: 'thread',
        inputId: input.inputId,
        cursor: 7,
      ),
    );
    await submission;
    final operation = client.mutations.lookup(OperationId(input.inputId))!;
    expect(operation.state.value.phase, OperationPhase.syncFailed);
    expect(operation.state.value.error, isA<ResourceBudgetExceeded>());
    expect(
      operation.state.value.receipt,
      isNotNull,
      reason: 'Local observation failure does not erase backend acceptance',
    );
    expect(owner.state.draft, 'keep after local sync failure');
    expect(owner.state.attachments.single.id, 'attachment-1-0');
    expect(transport.removed, isEmpty);
    expect(client.budget.used(ResourceKind.attachment), 1);
    await owner.discard();
    await _close(client, transport);
  });

  test('actual composer queued submission keeps its frozen route revision and preserves rejected draft', () async {
    final transport = _DraftTransport();
    final client = _client(transport);
    final session = client.session('thread');
    session.applySnapshot(_workspace());
    const blockerInput = StudioPromptInput(
      inputId: 'earlier-input',
      text: 'earlier command',
      attachmentDraftIds: [],
    );
    final blocker = client.threadCommands.submitComposer(
      'thread',
      blockerInput,
      expectedModelRouteRevision: 1,
    );
    await transport.promptEntered.future;

    final owner = client.composer('thread');
    owner.updateDraft('draft frozen on route one');
    await owner.addLocalAttachments(['/payload.bin']);
    final queued = owner.submit();
    final changed = _workspace(revision: 2);
    session.applySnapshot(
      changed.copyWith(
        runtime: changed.runtime.copyWith(
          modelRoute: const ThreadModelRouteView(
            providerId: 'provider',
            model: 'beta',
            effort: 'high',
            revision: 2,
            available: true,
          ),
        ),
      ),
    );
    transport.canonicalRouteRevision = 2;
    transport.promptReply.complete(
      const SubmitPromptReceipt(
        threadId: 'thread',
        inputId: 'earlier-input',
        cursor: 1,
      ),
    );
    await blocker;
    await queued;

    expect(transport.submittedRouteRevisions, [
      1,
      1,
    ], reason: 'The command lane must not substitute a later mirror route');
    expect(client.mutations.operations.single.phase, OperationPhase.rejected);
    expect(owner.state.draft, 'draft frozen on route one');
    expect(owner.state.attachments.single.id, 'attachment-1-0');
    expect(transport.removed, isEmpty);
    await owner.discard();
    await _close(client, transport);
  });

  test('unknown actual submission retains attachment owner and never automatically replays', () async {
    final transport = _DraftTransport();
    final client = _client(transport);
    client.session('thread').applySnapshot(_workspace());
    final owner = client.composer('thread');
    owner.updateDraft('request with uncertain reply');
    await owner.addLocalAttachments(['/payload.bin']);
    final submission = owner.submit();
    await transport.promptEntered.future;
    transport.promptReply.completeError(StateError('reply transport closed'));
    await submission;
    expect(
      client.mutations.operations.single.phase,
      OperationPhase.unknownOutcome,
    );
    client.workspace.showSettings();
    client.workspace.hideSettings();
    await owner.submit();
    expect(transport.promptCalls, 1);
    await owner.discard();
    expect(
      transport.removed,
      isEmpty,
      reason: 'Discarding the visible draft cannot release an unknown submission owner',
    );
    expect(client.budget.used(ResourceKind.attachment), 1);
    await _close(client, transport);
  });

  test('actual attachment cleanup failure retains budget until explicit successful retry', () async {
    final transport = _DraftTransport();
    final client = _client(transport);
    client.session('thread').applySnapshot(_workspace());
    final owner = client.composer('thread');
    await owner.addLocalAttachments(['/payload.bin']);
    transport.removeSucceeds = false;
    await owner.discard();
    expect(client.attachments.unresolvedAttachmentIds, ['attachment-1-0']);
    expect(client.budget.used(ResourceKind.attachment), 1);
    transport.removeSucceeds = true;
    await client.attachments.retryCleanup();
    expect(client.attachments.unresolvedAttachmentIds, isEmpty);
    expect(client.budget.used(ResourceKind.attachment), 0);
    await _close(client, transport);
  });

  test('closed actual attachment owner retries cleanup without reopening admissions', () async {
    final transport = _DraftTransport();
    var staged = 0;
    final client = _client(
      transport,
      stage: (_) async {
        staged += 1;
        return '/unexpected-staging.png';
      },
    );
    client.session('thread').applySnapshot(_workspace());
    final owner = client.composer('thread');
    await owner.addLocalAttachments(['/payload.bin']);
    transport.removeSucceeds = false;
    await owner.discard();
    final closing = client.attachments.close();
    await expectLater(closing, throwsA(isA<AttachmentCleanupUnresolved>()));
    expect(identical(closing, client.attachments.close()), isTrue);
    expect(client.budget.used(ResourceKind.attachment), 1);

    transport.removeSucceeds = true;
    await client.attachments.retryCleanup();
    expect(client.attachments.unresolvedAttachmentIds, isEmpty);
    expect(client.budget.used(ResourceKind.attachment), 0);
    await owner.addLocalAttachments(['/forbidden.bin']);
    await owner.addClipboardImage(Uint8List.fromList([1, 2, 3]));
    expect(transport.admissionCalls, 1);
    expect(staged, 0);
    expect(
      identical(closing, client.attachments.close()),
      isTrue,
      reason: 'Explicit cleanup does not rewrite the original close result',
    );
    await client.close();
  });

  test(
    'sealing attachment admissions preserves frozen submission completion',
    () async {
      final transport = _DraftTransport();
      var staged = 0;
      final client = _client(
        transport,
        stage: (_) async {
          staged += 1;
          return '/unexpected-staging.png';
        },
      );
      final session = client.session('thread');
      session.applySnapshot(_workspace());
      final owner = client.composer('thread');
      owner.updateDraft('accepted during exit');
      await owner.addLocalAttachments(['/payload.bin']);
      final submission = owner.submit();
      final input = await transport.promptEntered.future;
      client.attachments.sealAdmissions();
      await owner.addLocalAttachments(['/forbidden.bin']);
      await owner.addClipboardImage(Uint8List.fromList([1, 2, 3]));
      expect(transport.admissionCalls, 1);
      expect(staged, 0);
      expect(
        client.budget.used(ResourceKind.attachment),
        1,
        reason: 'The pending operation still owns its admitted attachment',
      );

      session.applySnapshot(
        _workspace(
          revision: 2,
          turn: StudioTurnView(
            inputId: input.inputId,
            turnId: 'turn',
            threadId: 'thread',
            revision: 1,
            state: const QueuedStudioTurnState(queuedAt: 1),
            updatedAt: DateTime.utc(2026),
          ),
        ),
      );
      transport.promptReply.complete(
        SubmitPromptReceipt(
          threadId: 'thread',
          inputId: input.inputId,
          cursor: 2,
        ),
      );
      await submission;
      expect(owner.state.draft, isEmpty);
      expect(owner.state.attachments, isEmpty);
      expect(transport.removed, ['attachment-1-0']);
      expect(
        client.budget.used(ResourceKind.attachment),
        0,
        reason: 'Sealing new work permits the last frozen owner to release',
      );
      await _close(client, transport);
    },
  );

  test('Client cleanup retry preserves a pending attachment close with empty failure maps', () async {
    final transport = _DraftTransport();
    final stageEntered = Completer<void>();
    final staged = Completer<String?>();
    final cleanupEntered = Completer<String>();
    final cleaned = Completer<void>();
    final client = _client(
      transport,
      stage: (_) {
        stageEntered.complete();
        return staged.future;
      },
      cleanup: (path) {
        cleanupEntered.complete(path);
        return cleaned.future;
      },
    );
    final admission = client.attachments.addNewThreadClipboard(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      pngBytes: Uint8List.fromList([1, 2, 3]),
    );
    addTearDown(() async {
      client.attachments.sealAdmissions();
      if (!staged.isCompleted) staged.complete('/clipboard-staging.png');
      if (!cleaned.isCompleted) cleaned.complete();
      await admission;
      await client.close();
      await client.retryCleanup();
    });
    await stageEntered.future;
    expect(client.budget.used(ResourceKind.attachment), 1);
    expect(client.attachments.unresolvedAttachmentIds, isEmpty);
    expect(client.attachments.unresolvedStagingPaths, isEmpty);

    final pastDeadline = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final closing = client.close(deadline: pastDeadline);
    final firstReport = await closing;
    expect(firstReport.complete, isFalse);
    expect(
      firstReport.unresolved.map((entry) => entry.owner),
      contains('attachments'),
    );
    expect(staged.isCompleted, isFalse);

    // The retry's attachment task can return immediately because there are
    // no recorded failures yet. It must still join the original staging task.
    final pendingStageReport = await client.retryCleanup(
      deadline: pastDeadline,
    );
    expect(pendingStageReport.complete, isFalse);
    expect(
      pendingStageReport.unresolved.map((entry) => entry.owner),
      contains('attachments'),
    );
    expect(client.attachments.unresolvedAttachmentIds, isEmpty);
    expect(client.attachments.unresolvedStagingPaths, isEmpty);
    expect(client.budget.used(ResourceKind.attachment), 1);
    expect(identical(closing, client.close(deadline: pastDeadline)), isTrue);

    staged.complete('/clipboard-staging.png');
    expect(await cleanupEntered.future, '/clipboard-staging.png');
    expect(
      transport.admissionCalls,
      0,
      reason: 'Exit sealed native admissions before late staging completed',
    );
    final pendingCleanupReport = await client.retryCleanup(
      deadline: pastDeadline,
    );
    expect(pendingCleanupReport.complete, isFalse);
    expect(
      pendingCleanupReport.unresolved.map((entry) => entry.owner),
      contains('attachments'),
    );
    expect(
      client.budget.used(ResourceKind.attachment),
      1,
      reason: 'The staging file still belongs to its in-flight cleanup',
    );

    cleaned.complete();
    await admission;
    final finalReport = await client.retryCleanup();
    expect(finalReport.complete, isTrue);
    expect(client.unresolvedResources, isEmpty);
    expect(client.budget.usage, isEmpty);
    expect(
      firstReport.complete,
      isFalse,
      reason: 'A later retry does not rewrite the original deadline report',
    );
  });

  test(
    'actual attachment close joins late clipboard staging and its file cleanup',
    () async {
      final transport = _DraftTransport();
      final staged = Completer<String?>();
      final cleanupStarted = Completer<String>();
      final cleaned = Completer<void>();
      final client = _client(
        transport,
        stage: (_) => staged.future,
        cleanup: (path) {
          cleanupStarted.complete(path);
          return cleaned.future;
        },
      );
      final admission = client.attachments.addNewThreadClipboard(
        projectId: _project.id,
        mode: ThreadModeId.simple,
        pngBytes: Uint8List.fromList([1, 2, 3]),
      );
      var closed = false;
      final closing = client.attachments.close().then((_) {
        closed = true;
      });
      expect(closed, isFalse);
      staged.complete('/clipboard-staging.png');
      expect(await cleanupStarted.future, '/clipboard-staging.png');
      expect(
        closed,
        isFalse,
        reason: 'Native clipboard staging cleanup is still in flight',
      );
      cleaned.complete();
      await admission;
      await closing;
      expect(transport.admissionCalls, 0);
      await _close(client, transport);
    },
  );

  test('clipboard staging cleanup failure remains owned through close and explicit retry', () async {
    final transport = _DraftTransport();
    var cleanupSucceeds = false;
    final client = _client(
      transport,
      stage: (_) async => '/clipboard-staging.png',
      cleanup: (path) async {
        if (!cleanupSucceeds) throw StateError('staging file is still in use');
      },
    );
    await client.attachments.addNewThreadClipboard(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      pngBytes: Uint8List.fromList([1, 2, 3]),
    );
    expect(client.attachments.unresolvedStagingPaths, [
      '/clipboard-staging.png',
    ]);
    expect(
      client.budget.used(ResourceKind.attachment),
      2,
      reason: 'Native draft and staging cleanup are distinct owned resources',
    );
    await client.attachments.discardProject(_project.id);
    expect(client.budget.used(ResourceKind.attachment), 1);
    await expectLater(
      client.attachments.close(),
      throwsA(isA<AttachmentCleanupUnresolved>()),
    );
    cleanupSucceeds = true;
    await client.attachments.retryCleanup();
    expect(client.attachments.unresolvedStagingPaths, isEmpty);
    expect(client.budget.used(ResourceKind.attachment), 0);
    await client.close();
  });
}
