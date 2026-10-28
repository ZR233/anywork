import 'support/timeline_transport.dart';
import 'support/conversation_delivery.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';
import 'package:anywork_client/accounts_ports.dart';

import 'support/accounts_test_runtime.dart';

/// Only transport responses and asynchronous barriers are fake. Draft revision,
/// route freezing, attachment ownership and operation observation are production.
final class _DraftTransport extends AccountsTestTransport {
  _DraftTransport() {
    addTearDown(() => frames.close());
    addTearDown(() => _startEvents?.close());
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
      DelegationMode delegationMode,
      DelegationPreference delegationPreference,
      String? workspaceMode,
    })
  >
  startEntered = Completer();
  final Completer<StartNewThreadResult> startReply = Completer();
  Completer<void>? startCancelGate;
  StreamController<NewThreadStartEvent>? _startEvents;
  StreamController<NewThreadStartEvent> get startEvents =>
      _startEvents ??= startCancelGate == null
      ? StreamController<NewThreadStartEvent>.broadcast()
      : StreamController<NewThreadStartEvent>(
          onCancel: () => startCancelGate?.future,
        );
  ConversationBaseline? Function(String threadId)? initialForThread;
  int feedOpens = 0;
  int startCalls = 0;
  final List<String> removed = [];
  int promptCalls = 0;

  /// 非空时提交以该错误结束；用于证明已知拒绝不会被当成未知结果。
  Object? promptFailure;
  int? promptRouteRevision;
  int? canonicalRouteRevision;
  final List<int> submittedRouteRevisions = [];
  int admissionCalls = 0;
  final List<AttachmentAdmissionContext> admissionContexts = [];
  Object? admissionFailure;
  int settingsWrites = 0;
  bool removeSucceeds = true;
  late _DraftConnection window;
  @override
  Future<ConversationFeed> openConversationFeed(String threadId) async {
    feedOpens++;
    return window = _DraftConnection(
      threadId: threadId,
      states: frames.stream,
      initial: initialForThread?.call(threadId),
    );
  }

  @override
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) {
    promptCalls += 1;
    promptRouteRevision = expectedModelRouteRevision;
    submittedRouteRevisions.add(expectedModelRouteRevision);
    if (promptFailure case final failure?) return Future.error(failure);
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
  Stream<NewThreadStartEvent> startNewThread(
    String projectId,
    StudioPromptInput input,
    ThreadModeId mode, {
    required ModeModelRouteView route,
    required DelegationMode delegationMode,
    required DelegationPreference delegationPreference,
    String? workspaceMode,
  }) {
    startCalls += 1;
    startEntered.complete((
      input: input,
      route: route,
      mode: mode,
      delegationMode: delegationMode,
      delegationPreference: delegationPreference,
      workspaceMode: workspaceMode,
    ));
    unawaited(
      startReply.future.then(
        (result) {
          startEvents.add(NewThreadStartSucceeded(result));
          unawaited(startEvents.close());
        },
        onError: (Object error, StackTrace stack) {
          startEvents.addError(error, stack);
          unawaited(startEvents.close());
        },
      ),
    );
    return startEvents.stream;
  }

  @override
  Future<List<AttachmentDraftView>> admitAttachmentDrafts(
    AttachmentAdmissionContext context,
    List<AttachmentDraftSource> sources,
  ) async {
    admissionCalls += 1;
    admissionContexts.add(context);
    if (admissionFailure case final failure?) throw failure;
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

/// A controlled content source driven through the production timeline channel.
final class _DraftConnection extends ScriptedConversationFeed {
  _DraftConnection({
    required super.threadId,
    required super.states,
    ConversationBaseline? initial,
  }) : super(
         initial:
             initial ?? baseline(1, subscriptionId: 'draft', items: const []),
       );
  int _version = 1;
  Future<void> emit(ConversationChange change) async {
    final from = _version++;
    await deliver(
      ConversationUpdateEvent(
        update: patch(
          from,
          _version,
          subscriptionId: 'draft',
          changes: [change],
        ),
      ),
    );
  }
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
  delegationMode: DelegationMode.profile,
  delegationPreference: DelegationPreference.balanced,
  updatedAt: DateTime.utc(2026),
  workspacePath: _project.path,
);

ThreadWorkspace _workspace({
  int revision = 1,
  StudioTurnView? turn,
  StudioThread? thread,
}) => ThreadWorkspace(
  thread: thread ?? _thread(),
  revision: revision,
  interactions: const [],
  activeTurn: turn,
  latestTurn: turn,
  runtime: const ThreadRuntimeView(
    modelId: 'alpha',
    contextTokens: 0,
    contextWindow: 100,
    totalTokens: 0,
    costLabel: '',
    activeSkills: [],
    activeMcpServers: [],
    activeLspServers: [],
    modelRoute: ThreadModelRouteView(
      accountId: 'account',
      modelId: 'alpha',
      effort: 'medium',
      revision: 1,
      available: true,
    ),
  ),
);

Future<AnyworkClient> _client(
  _DraftTransport transport, {
  String id = 'client',
  ResourceBudget? budget,
  Future<String?> Function(Uint8List)? stage,
  Future<void> Function(String)? cleanup,
}) async {
  final resourcesBudget = budget ?? ResourceBudget();
  final coordinator = SettingsWriteCoordinator();
  final board = MutationBoard(clientId: id, budget: resourcesBudget);
  final domains = AccountDomainResources(
    feed: transport,
    configuration: transport,
    modelPort: transport,
    usagePort: transport,
    acpPort: transport,
    coordinator: coordinator,
    mutations: board,
    budget: resourcesBudget,
    owner: id,
  );
  domains.adoptOwnerEpoch('owner');
  addTearDown(
    () =>
        domains.close(deadline: DateTime.now().add(const Duration(seconds: 3))),
  );
  final client = AnyworkClient(
    transport: transport,
    clientId: id,
    budget: resourcesBudget,
    settingsWrites: coordinator,
    mutationBoard: board,
    accountDomains: domains,
    clipboardImageStager: stage,
    clipboardImageCleanup: cleanup,
  );
  client.project.applyProjectDirectory(
    ProjectDirectoryState(values: [_project], revision: 1),
  );
  final snapshot = SettingsStateSnapshot(
    revision: 1,
    modelCatalogRevision: 1,
    accounts: const [
      AccountSettingsView(
        id: 'account',
        name: 'Provider',
        baseUrl: 'http://local.invalid',
        defaultModelId: 'alpha',
        status: 'configured',
        usageLabel: '',
        models: [
          AccountModelView(
            modelId: 'alpha',
            displayName: 'Alpha',
            typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
            reasoningEfforts: ['medium'],
            defaultReasoningEffort: 'medium',
          ),
          AccountModelView(
            modelId: 'beta',
            displayName: 'Beta',
            typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
            reasoningEfforts: ['high'],
            defaultReasoningEffort: 'high',
          ),
        ],
      ),
    ],
    modeModelRoutes: const [
      ModeModelRouteView(
        modeId: ThreadModeId.simple,
        accountId: 'account',
        modelId: 'alpha',
        effort: 'medium',
      ),
    ],
  );
  client.settings.merge(snapshot);
  for (final frame in accountFrames(snapshot)) {
    domains.acceptFrame(frame);
  }
  client.selection.selectProject(_project.id);
  client.conversations.setVisibleThread('thread');
  await scriptedFeed('thread');
  return client;
}

Future<void> _close(AnyworkClient client, _DraftTransport transport) async {
  await client.drafts.startDraft.close();
  await client.drafts.composer('thread').close();
  await client.drafts.attachments.close();
  await client.close();
  await transport.frames.close();
}

ConversationItem _inputTurn(
  String inputId,
  StudioTurnState state, {
  String threadId = 'thread',
  String itemId = 'turn-item',
  bool saved = false,
  int revision = 1,
}) => ConversationItem(
  header: ConversationItemHeader(
    id: itemId,
    threadId: threadId,
    turnId: 'turn',
    ordinal: 1,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  revision: revision,
  descriptor: ConversationTurnDescriptor(
    ThreadTurnItemStateView(state, inputId: inputId),
  ),
  saved: saved,
  lifecycle: state.isTerminal
      ? ConversationLifecycle.terminal
      : ConversationLifecycle.streaming,
  fields: const [],
);

void main() {
  for (final evictBeforeReceipt in [false, true]) {
    test(
      'pre-dispatch input evidence survives unrelated patches and tail eviction=$evictBeforeReceipt',
      () async {
        final transport = _DraftTransport();
        final client = await _client(transport);
        await client.conversations
            .session('thread')
            .deliverWorkspace(_workspace());
        final baselineObservers = client.budget.used(ResourceKind.observer);
        final owner = client.drafts.composer('thread');
        owner.updateDraft('evidence before receipt');
        final submitting = owner.submit();
        final input = await transport.promptEntered.future;
        final operation = client.mutations.lookup(OperationId(input.inputId))!;
        expect(
          client.budget.used(ResourceKind.observer),
          baselineObservers + 1,
        );
        await transport.window.emit(
          ConversationAdd(
            _inputTurn(
              input.inputId,
              const CompletedStudioTurnState(
                startedAt: 1,
                completedAt: 2,
                completion: StudioTurnCompletion.normal,
              ),
            ),
          ),
        );
        // Descriptor is deliberately omitted: the conversation reducer supplies
        // input identity and typed status from its already reduced current item.
        await transport.window.emit(
          ConversationUpdateItem(
            itemId: 'turn-item',
            expectedRevision: 1,
            revision: 1,
            saved: true,
            lifecycle: ConversationLifecycle.terminal,
            header: ConversationItemHeader(
              id: 'turn-item',
              threadId: 'thread',
              turnId: 'rebound-turn',
              ordinal: 1,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026, 2),
            ),
            fields: const [],
          ),
        );
        if (evictBeforeReceipt) {
          for (var index = 0; index < 101; index++) {
            await transport.window.emit(
              ConversationAdd(
                timelineItem(index + 2, id: 'tail-$index', ordinal: index + 2),
              ),
            );
          }
        }
        await transport.window.emit(
          ConversationAdd(
            timelineItem(200, id: 'unrelated-last', ordinal: 200),
          ),
        );
        expect(
          (client.conversations.session('thread').content.lastDeliveredFrame!
                  as ConversationPatchFrame)
              .patch
              .changes
              .single,
          isA<ConversationAdd>().having(
            (change) => change.item.id,
            'unrelated final frame',
            'unrelated-last',
          ),
        );
        expect(operation.state.value.receipt, isNull);
        expect(
          operation.state.value.durable,
          isFalse,
          reason: 'Evidence alone is not backend acceptance',
        );
        transport.promptReply.complete(
          SubmitPromptReceipt(
            threadId: 'thread',
            inputId: input.inputId,
            cursor: 7,
          ),
        );
        await submitting;
        expect(operation.state.value.observed, isTrue);
        expect(operation.state.value.effective, isTrue);
        expect(operation.state.value.durable, isTrue);
        expect(owner.state.draft, isEmpty);
        expect(client.budget.used(ResourceKind.observer), baselineObservers);
        expect(
          transport.feedOpens,
          1,
          reason: 'Input evidence never opens a hidden feed',
        );
        await _close(client, transport);
      },
    );
  }

  test('new-thread first baseline before result future binds its pre-registered evidence', () async {
    final transport = _DraftTransport()..startCancelGate = Completer<void>();
    final client = await _client(transport);
    addTearDown(() {
      if (!transport.startCancelGate!.isCompleted)
        transport.startCancelGate!.complete();
    });
    final initialObservers = client.budget.used(ResourceKind.observer);
    final owner = client.drafts.startDraft;
    owner.updateDraft(_project.id, 'new input');
    final submission = owner.submit(_project.id);
    final request = await transport.startEntered.future;
    final operation = client.mutations.lookup(
      OperationId(request.input.inputId),
    )!;
    transport.initialForThread = (id) => baseline(
      1,
      subscriptionId: 'draft',
      items: [
        _inputTurn(
          request.input.inputId,
          const CompletedStudioTurnState(
            startedAt: 1,
            completedAt: 2,
            completion: StudioTurnCompletion.normal,
          ),
          threadId: id,
          saved: true,
        ),
      ],
    );
    final selected = client.selection.source.watch((state) {
      if (state.selectedThreadId == 'new-thread')
        client.conversations.setVisibleThread('new-thread');
    });
    transport.startReply.complete(
      StartNewThreadResult(
        thread: _thread('new-thread'),
        receipt: SubmitPromptReceipt(
          threadId: 'new-thread',
          inputId: request.input.inputId,
          cursor: 8,
        ),
      ),
    );
    final feed = await scriptedFeed('new-thread');
    await feed.acknowledged(1);
    expect(client.selection.state.selectedThreadId, 'new-thread');
    expect(
      operation.state.value.receipt,
      isNull,
      reason: 'ThreadCommands still joins its start stream',
    );
    expect(operation.state.value.durable, isFalse);
    transport.startCancelGate!.complete();
    expect(await submission, isTrue);
    expect(operation.state.value.observed, isTrue);
    expect(operation.state.value.effective, isTrue);
    expect(operation.state.value.durable, isTrue);
    expect(client.budget.used(ResourceKind.observer), initialObservers);
    selected.cancel();
    await _close(client, transport);
  });

  test('new-thread accepts a valid result before conflicting earlier-thread evidence fails synchronization', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    final initialObservers = client.budget.used(ResourceKind.observer);
    final owner = client.drafts.startDraft;
    owner.updateDraft(_project.id, 'preserve conflicted new-thread draft');
    final submission = owner.submit(_project.id);
    final request = await transport.startEntered.future;
    final operation = client.mutations.lookup(
      OperationId(request.input.inputId),
    )!;
    await transport.window.emit(
      ConversationAdd(
        _inputTurn(
          request.input.inputId,
          const CompletedStudioTurnState(
            startedAt: 1,
            completedAt: 2,
            completion: StudioTurnCompletion.normal,
          ),
          saved: true,
        ),
      ),
    );
    transport.startReply.complete(
      StartNewThreadResult(
        thread: _thread('new-thread'),
        receipt: SubmitPromptReceipt(
          threadId: 'new-thread',
          inputId: request.input.inputId,
          cursor: 8,
        ),
      ),
    );
    expect(await submission, isFalse);
    final state = operation.state.value;
    expect(state.phase, OperationPhase.syncFailed);
    expect(state.receipt, isNotNull);
    final stamp = state.receipt!.targets.single as ResourceStamp;
    expect(stamp.resourceKey, 'input:new-thread:${request.input.inputId}');
    expect(stamp.ownerEpoch, 'new-thread');
    expect(stamp.revision, 8);
    expect(state.observed, isFalse);
    expect(state.effective, isFalse);
    expect(state.durable, isFalse);
    expect(
      owner.state.forProject(_project.id).text,
      'preserve conflicted new-thread draft',
    );
    expect(client.budget.used(ResourceKind.observer), initialObservers);
    await _close(client, transport);
  });

  test('conflicting registered input identities after acceptance are sync failures, not rejection', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    await client.conversations.session('thread').deliverWorkspace(_workspace());
    final owner = client.drafts.composer('thread')
      ..updateDraft('keep conflicting submission');
    final baselineObservers = client.budget.used(ResourceKind.observer);
    final submitting = owner.submit();
    final input = await transport.promptEntered.future;
    for (final id in ['turn-item', 'conflicting-turn-item']) {
      await transport.window.emit(
        ConversationAdd(
          _inputTurn(
            input.inputId,
            const RunningStudioTurnState(
              startedAt: 1,
              activity: StudioTurnActivity.thinking,
            ),
            itemId: id,
          ),
        ),
      );
    }
    transport.promptReply.complete(
      SubmitPromptReceipt(
        threadId: 'thread',
        inputId: input.inputId,
        cursor: 7,
      ),
    );
    await submitting;
    final operation = client.mutations
        .lookup(OperationId(input.inputId))!
        .state
        .value;
    expect(operation.phase, OperationPhase.syncFailed);
    expect(operation.receipt, isNotNull);
    expect(operation.durable, isFalse);
    expect(owner.state.draft, 'keep conflicting submission');
    expect(client.budget.used(ResourceKind.observer), baselineObservers);
    await _close(client, transport);
  });

  test('preparation failure cancels pre-registered input evidence without dispatch', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    await client.conversations.session('thread').deliverWorkspace(_workspace());
    final owner = client.drafts.composer('thread')
      ..updateDraft('prepare failure');
    final count = client.budget.used(ResourceKind.observer);
    await owner.submit(
      beforeSubmit: () async {
        expect(client.budget.used(ResourceKind.observer), count + 1);
        throw StateError('preparation failed');
      },
    );
    expect(client.budget.used(ResourceKind.observer), count);
    expect(transport.promptCalls, 0);
    expect(client.mutations.operations.single.phase, OperationPhase.rejected);
    expect(owner.state.draft, 'prepare failure');
    await _close(client, transport);
  });

  test('synchronous composer notification reuses submission and close cancels before dispatch', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    await client.conversations.session('thread').deliverWorkspace(_workspace());
    final owner = client.drafts.composer('thread')..updateDraft('reentrant');
    Future<void>? nested;
    Future<void>? closing;
    final watch = owner.source.watch((state) {
      if (state.isSubmissionPending && nested == null) {
        nested = owner.submit();
        closing = owner.close();
      }
    });
    final submission = owner.submit();
    expect(identical(nested, submission), isTrue);
    await submission;
    await closing;
    expect(transport.promptCalls, 0);
    expect(client.mutations.operations.single.phase, OperationPhase.rejected);
    watch.cancel();
    await _close(client, transport);
  });

  test('synchronous command notification reuses submission and close joins the one actual RPC', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    await client.conversations.session('thread').deliverWorkspace(_workspace());
    final owner = client.drafts.composer('thread')..updateDraft('one RPC');
    Future<void>? nested;
    Future<void>? closing;
    var closed = false;
    final watch = client.threadCommands.source.watch((state) {
      if (state.commands['submit:thread']?.phase == CommandPhase.pending &&
          nested == null) {
        nested = owner.submit();
        closing = owner.close().then((_) {
          closed = true;
        });
      }
    });
    final submission = owner.submit();
    final input = await transport.promptEntered.future;
    expect(identical(nested, submission), isTrue);
    expect(transport.promptCalls, 1);
    expect(closed, isFalse);
    transport.promptReply.complete(
      SubmitPromptReceipt(
        threadId: 'thread',
        inputId: input.inputId,
        cursor: 7,
      ),
    );
    await submission;
    await closing;
    expect(closed, isTrue);
    expect(transport.promptCalls, 1);
    expect(
      client.mutations.lookup(OperationId(input.inputId))!.state.value.receipt,
      isNotNull,
    );
    watch.cancel();
    await _close(client, transport);
  });

  test('new-thread synchronous notification rejects reentrant submission and close joins preparation', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    final owner = client.drafts.startDraft;
    owner.updateDraft(_project.id, 'one new-thread preparation');
    final initialObservers = client.budget.used(ResourceKind.observer);
    Future<bool>? nested;
    Future<void>? closing;
    var closed = false;
    final watch = owner.source.watch((state) {
      if (state.submitting && nested == null) {
        nested = owner.submit(_project.id);
        closing = owner.close().then((_) {
          closed = true;
        });
      }
    });
    final submission = owner.submit(_project.id);
    expect(nested, isNotNull);
    expect(closed, isFalse, reason: 'Close joins the registered preparation');
    expect(await nested, isFalse);
    expect(await submission, isFalse);
    await closing;
    expect(closed, isTrue);
    expect(transport.startCalls, 0);
    expect(client.mutations.operations.single.phase, OperationPhase.rejected);
    expect(client.budget.used(ResourceKind.observer), initialObservers);
    expect(
      owner.state.forProject(_project.id).text,
      'one new-thread preparation',
    );
    watch.cancel();
    await _close(client, transport);
  });

  test('child conversation is read-only before submission preparation or attachment admission', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    await client.conversations
        .session('thread')
        .deliverWorkspace(
          _workspace(thread: _thread().copyWith(parentThreadId: 'parent')),
        );
    final owner = client.drafts.composer('thread');
    owner.updateDraft('  子会话只读\n');
    var prepared = false;
    await owner.submit(
      beforeSubmit: () async {
        prepared = true;
      },
    );
    await owner.addLocalAttachments(['/child.bin']);
    expect(prepared, isFalse);
    expect(transport.promptCalls, 0);
    expect(transport.admissionCalls, 0);
    expect(owner.state.draft, '  子会话只读\n');
    expect(owner.state.attachments, isEmpty);
    expect(owner.state.isSubmissionPending, isFalse);
    expect(owner.state.error, isNotNull);
    expect(client.mutations.operations, isEmpty);
    await _close(client, transport);
  });

  test('new Thread attachments freeze the selected route and recover after rejection', () async {
    final transport = _DraftTransport();
    final staged = Completer<String?>();
    final cleaned = <String>[];
    final client = await _client(
      transport,
      stage: (_) => staged.future,
      cleanup: (path) async => cleaned.add(path),
    );
    final owner = client.drafts.startDraft;
    owner.updateDraft(_project.id, 'keep this draft');
    owner.setModelIntent(ThreadModeId.simple, 'account', 'beta');
    await client.drafts.attachments.admitNewThread(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      sources: [const AttachmentDraftSource.localFile('/first.bin')],
    );
    await client.drafts.attachments.addNewThreadRemote(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      url: 'https://example.invalid/second.bin',
    );
    final paste = client.drafts.attachments.addNewThreadClipboard(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      pngBytes: Uint8List.fromList([1, 2, 3]),
    );
    owner.setModelIntent(ThreadModeId.simple, 'account', 'alpha');
    staged.complete('/clipboard.png');
    await paste;
    expect(
      transport.admissionContexts.map((context) {
        final route = (context as NewThreadAttachmentAdmissionContext).route;
        return (route.accountId, route.modelId, route.effort);
      }),
      List.filled(3, ('account', 'beta', 'high')),
      reason: 'All sources use the selection at admission intent, including before staging',
    );
    expect(cleaned, ['/clipboard.png']);
    final admitted = client.drafts.attachments.state
        .newThread(_project.id)
        .attachments;
    transport.admissionFailure = const StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'Unsupported file media type',
      retryable: false,
      correlationId: 'rejected-file',
    );
    await client.drafts.attachments.admitNewThread(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      sources: [const AttachmentDraftSource.localFile('/unsupported.bin')],
    );
    final rejected = client.drafts.attachments.state.newThread(_project.id);
    expect(rejected.error, contains('Unsupported file media type'));
    expect(rejected.attachments, admitted);
    expect(owner.state.forProject(_project.id).text, 'keep this draft');
    expect(client.budget.used(ResourceKind.attachment), 3);
    transport.admissionFailure = null;
    await client.drafts.attachments.admitNewThread(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      sources: [const AttachmentDraftSource.localFile('/supported.bin')],
    );
    final recovered = client.drafts.attachments.state.newThread(_project.id);
    expect(recovered.error, isNull);
    expect(recovered.attachments.length, 4);
    final last =
        transport.admissionContexts.last as NewThreadAttachmentAdmissionContext;
    expect(last.route.modelId, 'alpha');
    expect(transport.settingsWrites, 0);
    await owner.discardProject(_project.id);
    await _close(client, transport);
    expect(client.budget.used(ResourceKind.attachment), 0);
  });

  test('actual composer preserves revision 9 text and attachments after revision 8 ACK', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    final session = client.conversations.session('thread');
    await session.deliverWorkspace(_workspace());
    final owner = client.drafts.composer('thread');
    owner.updateDraft('  submitted text\n');
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
    await session.deliverWorkspace(_workspace(revision: 2, turn: queued));
    await transport.window.emit(
      ConversationAdd(_inputTurn(input.inputId, queued.state)),
    );
    transport.promptReply.complete(
      SubmitPromptReceipt(
        threadId: 'thread',
        inputId: input.inputId,
        cursor: 7,
      ),
    );
    await submitted;

    expect(input.text, '  submitted text\n');
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

    await session.deliverWorkspace(
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
    await transport.window.emit(
      ConversationAdd(
        _inputTurn(
          input.inputId,
          const CompletedStudioTurnState(
            startedAt: 1,
            completedAt: 2,
            completion: StudioTurnCompletion.normal,
          ),
          revision: 2,
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
    final client = await _client(transport);
    final owner = client.drafts.startDraft;
    void defaults(
      int revision,
      DelegationMode mode,
      DelegationPreference preference,
    ) {
      final canonical = client.settings.state.canonical!;
      client.settings.merge(
        SettingsStateSnapshot(
          revision: revision,
          modelCatalogRevision: canonical.modelCatalogRevision,
          modeModelRoutes: canonical.modeModelRoutes,
          delegation: DelegationSettingsView(
            mode: mode,
            preference: preference,
          ),
        ),
      );
    }

    owner.updateDraft(_project.id, 'first request');
    owner.setWorkspaceMode(_project.id, ThreadWorkspaceMode.worktree);
    owner.setDelegationPreferenceOverride(
      _project.id,
      DelegationPreference.fast,
    );
    owner.updateDraft('other-project', 'independent draft');
    owner.setDelegationModeOverride('other-project', DelegationMode.profile);
    defaults(2, DelegationMode.automatic, DelegationPreference.economy);
    await client.drafts.attachments.admitNewThread(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      sources: [const AttachmentDraftSource.localFile('/one.bin')],
    );
    final submission = owner.submit(_project.id);
    defaults(3, DelegationMode.profile, DelegationPreference.balanced);
    final request = await transport.startEntered.future;
    final revision = owner.state.revision;
    final progressObserved = owner.source.waitFor(
      (value) =>
          value.preparations[_project.id]?.progress?.stage ==
          ThreadPreparationStage.creatingWorktree,
    );
    transport.startEvents.add(
      NewThreadStartProgress(
        ThreadPreparationProgress(
          projectId: _project.id,
          inputId: request.input.inputId,
          stage: ThreadPreparationStage.creatingWorktree,
          workspacePath: '/isolated/worktree',
          branch: 'pure/session',
        ),
      ),
    );
    await progressObserved;
    expect(
      owner.state.revision,
      revision,
      reason: 'progress is not a draft edit',
    );
    expect(
      owner.state.preparations[_project.id]?.progress?.workspacePath,
      '/isolated/worktree',
    );
    owner.updateDraft(_project.id, 'second request');
    owner.setModelIntent(ThreadModeId.simple, 'account', 'beta');
    owner.setEffortIntent(ThreadModeId.simple, 'high');
    owner.setWorkspaceMode(_project.id, ThreadWorkspaceMode.local);
    owner.setDelegationModeOverride(_project.id, DelegationMode.profile);
    owner.setDelegationPreferenceOverride(_project.id, null);
    expect(
      owner.state.preparations[_project.id]?.workspaceMode,
      ThreadWorkspaceMode.worktree,
    );
    await client.drafts.attachments.admitNewThread(
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
    expect(owner.state.preparations, isEmpty);

    expect(request.input.text, 'first request');
    expect(request.input.attachmentDraftIds, ['attachment-1-0']);
    expect(
      (request.delegationMode, request.delegationPreference),
      (DelegationMode.automatic, DelegationPreference.fast),
      reason: 'Submission freezes latest inherited mode plus independent explicit preference synchronously',
    );
    expect(
      (request.route.accountId, request.route.modelId, request.route.effort),
      ('account', 'alpha', 'medium'),
    );
    expect(transport.settingsWrites, 0);
    expect(owner.state.forProject(_project.id).text, 'second request');
    expect(owner.state.modelIntentFor(ThreadModeId.simple)?.modelId, 'beta');
    expect(owner.state.effortIntentFor(ThreadModeId.simple), 'high');
    expect(
      owner.state
          .forProject(_project.id)
          .resolveDelegation(client.settings.state.canonical!.delegation),
      const DelegationSettingsView(
        mode: DelegationMode.profile,
        preference: DelegationPreference.balanced,
      ),
    );
    expect(owner.state.forProject('other-project').text, 'independent draft');
    expect(
      owner.state.forProject('other-project').delegationModeOverride,
      DelegationMode.profile,
    );
    expect(
      owner.state.forProject('other-project').delegationPreferenceOverride,
      isNull,
    );
    defaults(4, DelegationMode.automatic, DelegationPreference.economy);
    expect(
      owner.state
          .forProject(_project.id)
          .resolveDelegation(client.settings.state.canonical!.delegation),
      const DelegationSettingsView(
        mode: DelegationMode.profile,
        preference: DelegationPreference.economy,
      ),
      reason: 'Cleared preference inherits independently while fixed mode retains the chosen value',
    );
    expect(
      client.settings.state.canonical!.delegation.mode,
      DelegationMode.automatic,
    );
    expect(
      client.drafts.attachments.state
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

  test('new Thread completion does not replace a newer A to B to A navigation intent', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    const other = StudioProject(id: 'other', name: 'Other', path: '/other');
    client.project.applyProjectDirectory(
      ProjectDirectoryState(values: [_project, other], revision: 2),
    );
    final owner = client.drafts.startDraft;
    owner.updateDraft(_project.id, 'prepare a session');
    final submitted = owner.submit(_project.id);
    final request = await transport.startEntered.future;
    client.selection.selectProject(other.id);
    client.selection.selectProject(_project.id);
    final thread = _thread('new-thread');
    transport.startReply.complete(
      StartNewThreadResult(
        thread: thread,
        receipt: SubmitPromptReceipt(
          threadId: thread.id,
          inputId: request.input.inputId,
          cursor: 1,
        ),
      ),
    );
    expect(await submitted, isTrue);
    expect(client.selection.state.selectedProjectId, _project.id);
    expect(client.selection.state.selectedThreadId, isNull);
    await _close(client, transport);
  });

  test('definite preparation failure retains the failed stage, newer draft and attachments', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    final owner = client.drafts.startDraft;
    owner.updateDraft(_project.id, 'first request');
    await client.drafts.attachments.admitNewThread(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      sources: [const AttachmentDraftSource.localFile('/one.bin')],
    );
    final submitted = owner.submit(_project.id);
    final request = await transport.startEntered.future;
    final observed = owner.source.waitFor(
      (value) =>
          value.preparations[_project.id]?.progress?.stage ==
          ThreadPreparationStage.creatingWorktree,
    );
    transport.startEvents.add(
      NewThreadStartProgress(
        ThreadPreparationProgress(
          projectId: _project.id,
          inputId: request.input.inputId,
          stage: ThreadPreparationStage.creatingWorktree,
          workspacePath: '/isolated/worktree',
        ),
      ),
    );
    await observed;
    owner.updateDraft(_project.id, 'newer request');
    const failure = StudioFailure(
      code: StudioFailureCode.internal,
      message: 'checkout failed',
      retryable: false,
      correlationId: 'preparation-failure',
    );
    transport.startEvents.add(const NewThreadStartFailed(failure));
    expect(await submitted, isFalse);
    final preparation = owner.state.preparations[_project.id]!;
    expect(preparation.phase, NewThreadPreparationPhase.failed);
    expect(
      preparation.progress?.stage,
      ThreadPreparationStage.creatingWorktree,
    );
    expect(preparation.failure, same(failure));
    expect(owner.state.forProject(_project.id).text, 'newer request');
    expect(
      client.drafts.attachments.state
          .newThread(_project.id)
          .attachments
          .single
          .id,
      'attachment-1-0',
    );
    expect(
      client.mutations.latest('start:${_project.id}')?.state.value.phase,
      OperationPhase.rejected,
    );
    transport.startEvents.add(
      NewThreadStartProgress(
        ThreadPreparationProgress(
          projectId: _project.id,
          inputId: request.input.inputId,
          stage: ThreadPreparationStage.submittingPrompt,
        ),
      ),
    );
    await transport.startEvents.close();
    expect(
      owner.state.preparations[_project.id],
      same(preparation),
      reason: 'late progress cannot revive a terminal operation',
    );
    await owner.discardProject(_project.id);
    expect(transport.removed, [
      'attachment-1-0',
    ], reason: 'definite rejection released the frozen attachment owner');
    await _close(client, transport);
  });

  test('EOF without a creation outcome remains unknown and never automatically resubmits', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    final owner = client.drafts.startDraft;
    owner.updateDraft(_project.id, 'do not duplicate this request');
    final submitted = owner.submit(_project.id);
    await transport.startEntered.future;
    await transport.startEvents.close();
    expect(await submitted, isFalse);
    expect(
      owner.state.preparations[_project.id]?.phase,
      NewThreadPreparationPhase.unknownOutcome,
    );
    expect(
      client.mutations.latest('start:${_project.id}')?.state.value.phase,
      OperationPhase.unknownOutcome,
    );
    expect(await owner.submit(_project.id), isFalse);
    expect(transport.startCalls, 1);
    expect(
      owner.state.forProject(_project.id).text,
      'do not duplicate this request',
    );
    await _close(client, transport);
  });

  test(
    'stream errors cannot replace the missing typed creation outcome',
    () async {
      final transport = _DraftTransport();
      final client = await _client(transport);
      addTearDown(() => _close(client, transport));
      final owner = client.drafts.startDraft;
      owner.updateDraft(_project.id, 'keep an uncertain request');
      final submitted = owner.submit(_project.id);
      await transport.startEntered.future;
      transport.startEvents.addError(
        const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'the creation stream was interrupted',
          retryable: true,
          correlationId: 'interrupted-start-stream',
        ),
      );
      expect(await submitted, isFalse);
      expect(
        owner.state.preparations[_project.id]?.phase,
        NewThreadPreparationPhase.unknownOutcome,
      );
      expect(
        client.mutations.latest('start:${_project.id}')?.state.value.phase,
        OperationPhase.unknownOutcome,
      );
      expect(await owner.submit(_project.id), isFalse);
      expect(transport.startCalls, 1);
      expect(
        owner.state.forProject(_project.id).text,
        'keep an uncertain request',
      );
      await transport.startEvents.close();
    },
  );

  test('closing the start owner joins its creation while ignoring later display updates', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    final owner = client.drafts.startDraft;
    owner.updateDraft(_project.id, 'prepare before close');
    final submitted = owner.submit(_project.id);
    final request = await transport.startEntered.future;
    var closed = false;
    final closing = owner.close().then((_) => closed = true);
    expect(closed, isFalse);
    final before = owner.state;
    final thread = _thread('new-thread');
    transport.startEvents.add(
      NewThreadStartProgress(
        ThreadPreparationProgress(
          projectId: _project.id,
          inputId: request.input.inputId,
          stage: ThreadPreparationStage.initializingSession,
        ),
      ),
    );
    transport.startReply.complete(
      StartNewThreadResult(
        thread: thread,
        receipt: SubmitPromptReceipt(
          threadId: thread.id,
          inputId: request.input.inputId,
          cursor: 1,
        ),
      ),
    );
    expect(await submitted, isTrue);
    await closing;
    expect(closed, isTrue);
    expect(owner.state, same(before));
    await _close(client, transport);
  });

  test('actual accepted input waits for its Chat Turn saved flag after execution completes', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    final session = client.conversations.session('thread');
    await session.deliverWorkspace(_workspace());
    await session.content.ready;
    final baselineObservers = client.budget.used(ResourceKind.observer);
    final owner = client.drafts.composer('thread');
    owner.updateDraft('durable input');
    final submission = owner.submit();
    final input = await transport.promptEntered.future;
    await session.deliverWorkspace(
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
    await transport.window.emit(
      ConversationAdd(
        _inputTurn(
          input.inputId,
          const RunningStudioTurnState(
            startedAt: 1,
            activity: StudioTurnActivity.thinking,
          ),
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

    final terminal = ConversationItem(
      header: ConversationItemHeader(
        id: 'turn-item',
        threadId: 'thread',
        turnId: 'turn',
        ordinal: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      revision: 2,
      saved: false,
      lifecycle: ConversationLifecycle.terminal,
      descriptor: ConversationTurnDescriptor(
        ThreadTurnItemStateView(
          const CompletedStudioTurnState(
            startedAt: 1,
            completedAt: 2,
            completion: StudioTurnCompletion.normal,
          ),
          inputId: input.inputId,
        ),
      ),
      fields: const [],
    );
    await transport.window.emit(ConversationAdd(terminal));
    await session.content.state.waitFor(
      (state) => state.snapshot is ConversationPatchFrame,
    );
    expect(
      operation.state.value.durable,
      isFalse,
      reason: 'A terminal Turn that has not been saved is not durable',
    );
    expect(client.budget.used(ResourceKind.observer), baselineObservers + 1);
    await transport.window.emit(
      const ConversationUpdateItem(
        itemId: 'turn-item',
        expectedRevision: 2,
        revision: 2,
        saved: true,
        lifecycle: ConversationLifecycle.terminal,
        fields: [],
      ),
    );
    await session.content.state.waitFor(
      (state) =>
          state.snapshot is ConversationPatchFrame &&
          (state.snapshot! as ConversationPatchFrame).patch.to == 4,
    );
    expect(operation.state.value.durable, isTrue);
    expect(client.budget.used(ResourceKind.observer), baselineObservers);
    await _close(client, transport);
  });

  test('pre-dispatch input observer budget failure never sends and preserves draft references', () async {
    final transport = _DraftTransport();
    final client = await _client(
      transport,
      budget: ResourceBudget(
        capacities: {...ResourceBudget().capacities, ResourceKind.observer: 0},
      ),
    );
    await client.conversations.session('thread').deliverWorkspace(_workspace());
    final owner = client.drafts.composer('thread');
    owner.updateDraft('keep after observation admission failure');
    await owner.addLocalAttachments(['/payload.bin']);
    await owner.submit();
    expect(transport.promptCalls, 0);
    final operation = client.mutations.operations.single;
    expect(operation.phase, OperationPhase.rejected);
    expect(operation.error, isA<ResourceBudgetExceeded>());
    expect(operation.receipt, isNull);
    expect(owner.state.draft, 'keep after observation admission failure');
    expect(owner.state.attachments.single.id, 'attachment-1-0');
    expect(transport.removed, isEmpty);
    expect(client.budget.used(ResourceKind.attachment), 1);
    await owner.discard();
    await _close(client, transport);
  });

  test('actual composer queued submission keeps its frozen route revision and preserves rejected draft', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    final session = client.conversations.session('thread');
    await session.deliverWorkspace(_workspace());
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

    final owner = client.drafts.composer('thread');
    owner.updateDraft('draft frozen on route one');
    await owner.addLocalAttachments(['/payload.bin']);
    final queued = owner.submit();
    final changed = _workspace(revision: 2);
    await session.deliverWorkspace(
      changed.copyWith(
        runtime: changed.runtime.copyWith(
          modelRoute: const ThreadModelRouteView(
            accountId: 'account',
            modelId: 'beta',
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

  test(
    'the preparation hook runs after freezing and before the backend submit',
    () async {
      final transport = _DraftTransport();
      final client = await _client(transport);
      await client.conversations
          .session('thread')
          .deliverWorkspace(_workspace());
      final owner = client.drafts.composer('thread');
      owner.updateDraft('prepare before sending');
      await owner.addLocalAttachments(['/payload.bin']);

      var hookCalls = 0;
      String? frozenTarget;
      final submission = owner.submit(
        beforeSubmit: () async {
          hookCalls += 1;
          // 冻结目标与冻结附件在钩子运行前已经成立，后端此刻还没有收到提交。
          frozenTarget = client.mutations.operations.single.target;
          expect(transport.promptCalls, 0);
          expect(owner.state, isA<SubmittingComposerThreadState>());
        },
      );
      final input = await transport.promptEntered.future;
      transport.promptReply.complete(
        SubmitPromptReceipt(
          threadId: 'thread',
          inputId: input.inputId,
          cursor: 3,
        ),
      );
      await submission;
      expect(hookCalls, 1);
      expect(frozenTarget, 'submit:thread');
      expect(transport.promptCalls, 1);
      await _close(client, transport);
    },
  );

  test('a failing preparation is a known non-submission and keeps the draft usable', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    await client.conversations.session('thread').deliverWorkspace(_workspace());
    final owner = client.drafts.composer('thread');
    owner.updateDraft('send after display preparation');
    await owner.addLocalAttachments(['/payload.bin']);
    const failure = StudioFailure(
      code: StudioFailureCode.storage,
      message: 'display preparation failed',
      retryable: true,
      correlationId: 'prepare-failure',
    );

    await owner.submit(beforeSubmit: () => Future.error(failure));
    // 展示准备发生在 backend 提交之前：这是已知未提交，不是未知结果。
    expect(transport.promptCalls, 0);
    expect(
      client.mutations.operations.single.phase,
      isNot(OperationPhase.unknownOutcome),
    );
    expect(owner.state, isA<FailedComposerThreadState>());
    expect(owner.state.draft, 'send after display preparation');
    expect(owner.state.attachments.single.id, 'attachment-1-0');
    expect(client.budget.used(ResourceKind.attachment), 1);

    // 草稿没有被永久封住：再次提交可以真正进入后端。
    final submission = owner.submit();
    final input = await transport.promptEntered.future;
    expect(transport.promptCalls, 1);
    expect(input.attachmentDraftIds, ['attachment-1-0']);
    transport.promptReply.complete(
      SubmitPromptReceipt(
        threadId: 'thread',
        inputId: input.inputId,
        cursor: 4,
      ),
    );
    await submission;
    expect(owner.state.draft, isEmpty);
    await _close(client, transport);
  });

  test('unknown actual submission retains attachment owner and never automatically replays', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    await client.conversations.session('thread').deliverWorkspace(_workspace());
    final observers = client.budget.used(ResourceKind.observer);
    final owner = client.drafts.composer('thread');
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
    expect(
      client.budget.used(ResourceKind.observer),
      observers + 1,
      reason: 'Unknown outcome retains the original registered evidence, without re-registering or resending',
    );
    await owner.discard();
    expect(
      transport.removed,
      isEmpty,
      reason: 'Discarding the visible draft cannot release an unknown submission owner',
    );
    expect(client.budget.used(ResourceKind.attachment), 1);
    await owner.close();
    expect(client.budget.used(ResourceKind.observer), observers);
    await _close(client, transport);
  });

  test('actual attachment cleanup failure retains budget until explicit successful retry', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    await client.conversations.session('thread').deliverWorkspace(_workspace());
    final owner = client.drafts.composer('thread');
    await owner.addLocalAttachments(['/payload.bin']);
    transport.removeSucceeds = false;
    await owner.discard();
    expect(client.drafts.attachments.unresolvedAttachmentIds, [
      'attachment-1-0',
    ]);
    expect(client.budget.used(ResourceKind.attachment), 1);
    transport.removeSucceeds = true;
    await client.drafts.attachments.retryCleanup();
    expect(client.drafts.attachments.unresolvedAttachmentIds, isEmpty);
    expect(client.budget.used(ResourceKind.attachment), 0);
    await _close(client, transport);
  });

  test('closed actual attachment owner retries cleanup without reopening admissions', () async {
    final transport = _DraftTransport();
    var staged = 0;
    final client = await _client(
      transport,
      stage: (_) async {
        staged += 1;
        return '/unexpected-staging.png';
      },
    );
    await client.conversations.session('thread').deliverWorkspace(_workspace());
    final owner = client.drafts.composer('thread');
    await owner.addLocalAttachments(['/payload.bin']);
    transport.removeSucceeds = false;
    await owner.discard();
    final closing = client.drafts.attachments.close();
    await expectLater(closing, throwsA(isA<AttachmentCleanupUnresolved>()));
    expect(identical(closing, client.drafts.attachments.close()), isTrue);
    expect(client.budget.used(ResourceKind.attachment), 1);

    transport.removeSucceeds = true;
    await client.drafts.attachments.retryCleanup();
    expect(client.drafts.attachments.unresolvedAttachmentIds, isEmpty);
    expect(client.budget.used(ResourceKind.attachment), 0);
    await owner.addLocalAttachments(['/forbidden.bin']);
    await owner.addClipboardImage(Uint8List.fromList([1, 2, 3]));
    expect(transport.admissionCalls, 1);
    expect(staged, 0);
    expect(
      identical(closing, client.drafts.attachments.close()),
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
      final client = await _client(
        transport,
        stage: (_) async {
          staged += 1;
          return '/unexpected-staging.png';
        },
      );
      final session = client.conversations.session('thread');
      await session.deliverWorkspace(_workspace());
      final owner = client.drafts.composer('thread');
      owner.updateDraft('accepted during exit');
      await owner.addLocalAttachments(['/payload.bin']);
      final submission = owner.submit();
      final input = await transport.promptEntered.future;
      await client.drafts.attachments.close();
      await owner.addLocalAttachments(['/forbidden.bin']);
      await owner.addClipboardImage(Uint8List.fromList([1, 2, 3]));
      expect(transport.admissionCalls, 1);
      expect(staged, 0);
      expect(
        client.budget.used(ResourceKind.attachment),
        1,
        reason: 'The pending operation still owns its admitted attachment',
      );

      await session.deliverWorkspace(
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
    final client = await _client(
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
    final admission = client.drafts.attachments.addNewThreadClipboard(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      pngBytes: Uint8List.fromList([1, 2, 3]),
    );
    addTearDown(() async {
      final attachmentClosing = client.drafts.attachments.close();
      if (!staged.isCompleted) staged.complete('/clipboard-staging.png');
      if (!cleaned.isCompleted) cleaned.complete();
      await admission;
      await attachmentClosing;
      await client.close();
      await client.retryCleanup();
    });
    await stageEntered.future;
    expect(client.budget.used(ResourceKind.attachment), 1);
    expect(client.drafts.attachments.unresolvedAttachmentIds, isEmpty);
    expect(client.drafts.attachments.unresolvedStagingPaths, isEmpty);

    final pastDeadline = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final closing = client.close(deadline: pastDeadline);
    final firstReport = await closing;
    expect(firstReport.complete, isFalse);
    expect(
      firstReport.unresolved.map((entry) => entry.owner),
      contains('drafts'),
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
      contains('drafts'),
    );
    expect(client.drafts.attachments.unresolvedAttachmentIds, isEmpty);
    expect(client.drafts.attachments.unresolvedStagingPaths, isEmpty);
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
      contains('drafts'),
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
      final client = await _client(
        transport,
        stage: (_) => staged.future,
        cleanup: (path) {
          cleanupStarted.complete(path);
          return cleaned.future;
        },
      );
      final admission = client.drafts.attachments.addNewThreadClipboard(
        projectId: _project.id,
        mode: ThreadModeId.simple,
        pngBytes: Uint8List.fromList([1, 2, 3]),
      );
      var closed = false;
      final closing = client.drafts.attachments.close().then((_) {
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
    final client = await _client(
      transport,
      stage: (_) async => '/clipboard-staging.png',
      cleanup: (path) async {
        if (!cleanupSucceeds) throw StateError('staging file is still in use');
      },
    );
    await client.drafts.attachments.addNewThreadClipboard(
      projectId: _project.id,
      mode: ThreadModeId.simple,
      pngBytes: Uint8List.fromList([1, 2, 3]),
    );
    expect(client.drafts.attachments.unresolvedStagingPaths, [
      '/clipboard-staging.png',
    ]);
    expect(
      client.budget.used(ResourceKind.attachment),
      2,
      reason: 'Native draft and staging cleanup are distinct owned resources',
    );
    await client.drafts.attachments.discardProject(_project.id);
    expect(client.budget.used(ResourceKind.attachment), 1);
    await expectLater(
      client.drafts.attachments.close(),
      throwsA(isA<AttachmentCleanupUnresolved>()),
    );
    cleanupSucceeds = true;
    await client.drafts.attachments.retryCleanup();
    expect(client.drafts.attachments.unresolvedStagingPaths, isEmpty);
    expect(client.budget.used(ResourceKind.attachment), 0);
    await client.close();
  });

  test('a child target rejection stays typed, keeps the draft and never becomes unknown', () async {
    final transport = _DraftTransport();
    final client = await _client(transport);
    await client.conversations.session('thread').deliverWorkspace(_workspace());
    final owner = client.drafts.composer('thread');
    owner.updateDraft('继续这个子任务');
    await owner.addLocalAttachments(['/child.bin']);
    final attachmentIds = owner.state.attachments
        .map((item) => item.id)
        .toList();
    transport.promptFailure = const StudioFailure(
      code: StudioFailureCode.permissionDenied,
      message: 'A child agent is continued and instructed by the main session, not by the user',
      retryable: false,
      correlationId: 'child-requires-parent-scheduling',
      reason: StudioFailureReason.childThreadRequiresParentScheduling,
    );
    await owner.submit();

    expect(transport.promptCalls, 1);
    expect(
      owner.state.draft,
      '继续这个子任务',
      reason: 'A typed rejection never clears the user draft',
    );
    expect(owner.state.attachments.map((item) => item.id), attachmentIds);
    expect(owner.state.isSubmissionPending, isFalse);
    expect(owner.state.error, isNotNull);
    final operation = client.mutations.operations.single;
    expect(
      operation.failurePhase,
      OperationPhase.rejected,
      reason: 'A known rejection is not an unknown outcome',
    );
    expect(
      (operation.error! as StudioFailure).reason,
      StudioFailureReason.childThreadRequiresParentScheduling,
    );
    expect(
      transport.removed,
      isEmpty,
      reason: 'Rejected admission keeps the frozen attachment references',
    );
    await owner.discard();
    await _close(client, transport);
  });
}
