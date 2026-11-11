import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/src/conversation/data/input_turn_facts.dart';
import 'package:anywork_client/src/drafts/data/drafts_dependencies.dart';
import 'package:anywork_client/src/drafts/data/drafts_repository_impl.dart';
import 'package:test/test.dart';

import 'support/accounts_test_runtime.dart';
import 'support/acp_business_port.dart';
import 'support/directory_feed.dart';

final _target = AcpSessionTargetView(
  sessionId: 'session',
  agentId: 'agent',
  threadId: 'thread',
  instance: BigInt.one,
);
const _capabilities = AcpAgentCapabilitiesView(
  image: true,
  audio: false,
  embeddedContext: true,
  loadSession: true,
  listSessions: false,
  resumeSession: false,
);
const _accepted = AcpSettledFrameView(AcpSuccessView<void>(null));
final _ready = AcpEventFrameView(
  AcpReadyEventView(
    AcpNewSessionResponseView(sessionId: const AcpRemoteSessionId('remote')),
  ),
);

SessionDirectoryRow _row() => SessionDirectoryRow(
  sessionId: 'session',
  agentId: 'agent',
  threadId: 'thread',
  workspaceId: 'workspace',
  title: 'ACP',
  mode: null,
  delegationMode: DelegationMode.automatic,
  delegationPreference: DelegationPreference.balanced,
  workspacePath: '/project',
  role: 'main',
  backend: const AcpAgentBackendView(
    reference: AcpSessionReferenceView(
      accountId: 'account',
      acpSessionId: 'remote',
      cwd: '/project',
    ),
  ),
  updatedAt: DateTime.utc(2026),
);

AttachmentDraftView _attachment(String id, AttachmentModalityView modality) =>
    AttachmentDraftView(
      id: id,
      modality: modality,
      mediaType: modality == AttachmentModalityView.image
          ? 'image/png'
          : 'application/octet-stream',
      filename: '$id.bin',
      byteSize: 3,
    );

final class _NoNative
    implements ConversationRepository, InputTurnFacts, DraftSubmissionCommands {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Unexpected Native dependency: ${invocation.memberName}');
  }
}

final class _Transport extends AccountsTestTransport with DirectoryFeedFixture {
  final removed = <String>[];
  final reads = <String>[];
  Completer<Uint8List>? bytesGate;
  final readEntered = Completer<void>();
  List<AttachmentDraftView> admissionResult = [];
  int admissions = 0;
  bool removeSucceeds = true;
  @override
  Future<List<AttachmentDraftView>> admitAttachmentDrafts(
    AttachmentAdmissionContext context,
    List<AttachmentDraftSource> sources,
  ) async {
    admissions++;
    expect(context, isA<ExistingThreadAttachmentAdmissionContext>());
    return admissionResult;
  }

  @override
  Future<Uint8List> readAttachmentDraft(String draftId) async {
    reads.add(draftId);
    if (!readEntered.isCompleted) readEntered.complete();
    return bytesGate == null
        ? Uint8List.fromList([1, 2, 3])
        : await bytesGate!.future;
  }

  @override
  Future<bool> removeAttachmentDraft(String draftId) async {
    removed.add(draftId);
    return removeSucceeds;
  }
}

final class _Harness {
  _Harness({
    bool ready = true,
    bool enabled = true,
    AcpAgentCapabilitiesView? capabilities = _capabilities,
  }) {
    transport.seedThread(_row());
    directory = ThreadDirectoryStore(feed: transport);
    source = ControlledAcpObservation([
      AcpAcceptedFrameView(target: _target, hasObservation: true),
      if (ready) ...[
        if (capabilities != null)
          AcpEventFrameView(AcpInitializedEventView(capabilities)),
        _ready,
        _accepted,
      ],
    ]);
    port = ControlledAcpBusinessPort()
      ..sources.add(source)
      ..run = AcpRunIdView(instance: BigInt.one, sequence: BigInt.one);
    sessions = AcpSessionClient(port: port);
    selection.selectProject('workspace');
    project.applyProjectDirectory(
      ProjectDirectoryState(
        values: const [
          StudioProject(id: 'workspace', name: 'Project', path: '/project'),
        ],
        revision: 1,
      ),
    );
    repository = DraftsRepositoryImpl(
      DraftsDependencies(
        mutations: MutationBoard(clientId: 'test'),
        conversations: native,
        inputFacts: native,
        settings: LatestValue(const SettingsStoreState()),
        project: project.source,
        selection: selection.source,
        recovery: LatestValue(
          const CanonicalClockState<RecoveryStateSnapshot>(),
        ),
        modelAccounts: () => const [],
        threadCommands: native,
        transport: transport,
        directory: directory,
        acpSessions: sessions,
        accountSummaries: LatestValue(
          AccountsState(
            stamp: const ResourceStamp(
              resourceKey: 'accounts',
              ownerEpoch: 'owner',
              revision: 1,
            ),
            accounts: [
              AccountSummary(
                identity: const AcpAccountIdentity('account'),
                name: 'Agent',
                isDefault: false,
                acpEnabled: enabled,
                acpConnectionRevision: 17,
                capabilities: const AccountCapabilities(
                  setDefault: false,
                  edit: true,
                  remove: true,
                  queryUsage: false,
                  syncModels: false,
                  editModels: false,
                  acpAuth: true,
                ),
              ),
            ],
          ),
        ),
        selectCreatedThread: (workspaceId, threadId) => selection.selectThread(
          workspaceId: workspaceId,
          threadId: threadId,
        ),
        selectionNavigationGeneration: () => selection.navigationGeneration,
      ),
    );
    addTearDown(() async {
      await repository.close();
      await sessions.dispose();
      await directory.close();
      expect(
        native.calls,
        0,
        reason: 'ACP must not consume Native state or ACK',
      );
    });
  }
  final transport = _Transport();
  final native = _NoNative();
  final selection = SelectionStore();
  final project = ProjectStore();
  late final ControlledAcpBusinessPort port;
  late final ControlledAcpObservation source;
  late final AcpSessionClient sessions;
  late final ThreadDirectoryStore directory;
  late final DraftsRepositoryImpl repository;

  void push(AcpSessionFrameView frame) {
    final read = source.read;
    if (read != null && !read.isCompleted) {
      read.complete(frame);
    } else {
      source.frames.add(frame);
    }
  }

  Future<AcpConversationSession> open() async {
    final owner = await sessions.openConversation(
      OpenAcpSessionRequestView(
        accountId: 'account',
        expectedConnectionRevision: BigInt.from(17),
        workspaceId: 'workspace',
        threadId: 'thread',
        intent: const AcpLoadIntentView(AcpRemoteSessionId('remote')),
      ),
    );
    await owner.source.waitFor((value) => value.ready && !value.openPending);
    return owner;
  }

  Future<ComposerDraftOwner> composer() async {
    final owner = repository.composer('thread');
    final metadata = directory.observeThread('thread');
    await metadata.state.waitFor((value) => value.frame != null);
    await metadata.release();
    return owner;
  }

  Iterable<Object> calls(String name) =>
      port.calls.where((call) => call.$1 == name).map((call) => call.$2);
}

void main() {
  test('failed attachment removal follows the transferred draft for explicit cleanup', () async {
    final h = _Harness();
    final start = h.repository.startDraft;
    start.setAcpService('workspace', 'account');
    h.repository.attachments.seedNewThreadIfEmpty(
      'workspace',
      ComposerThreadState.idle(
        attachments: [_attachment('blob', AttachmentModalityView.file)],
      ),
    );
    h.transport.removeSucceeds = false;
    await h.repository.attachments.removeNewThreadDraft('workspace', 'blob');
    expect(h.repository.attachments.unresolvedAttachmentIds, ['blob']);
    expect(await start.submit('workspace'), isTrue);
    final composer = await h.composer();
    expect(composer.state.attachments.single.id, 'blob');
    h.transport.removeSucceeds = true;
    await h.repository.retryCleanup();
    expect(composer.state.attachments, isEmpty);
    expect(h.repository.attachments.unresolvedAttachmentIds, isEmpty);
  });

  test('creation waits for original ready and settled, transfers newest draft without prompt', () async {
    final h = _Harness(ready: false);
    final start = h.repository.startDraft;
    start.setAcpService('workspace', 'account');
    start.updateDraft('workspace', 'first');
    h.repository.attachments.seedNewThreadIfEmpty(
      'workspace',
      ComposerThreadState.idle(
        attachments: [_attachment('old', AttachmentModalityView.file)],
      ),
    );
    final created = start.submit('workspace');
    expect(await start.submit('workspace'), isFalse);
    await h.source.enteredRead.future;
    await Future<void>.delayed(Duration.zero);
    start.updateDraft('workspace', 'edited while opening');
    var finished = false;
    unawaited(created.then((_) => finished = true));
    h.push(const AcpEventFrameView(AcpInitializedEventView(_capabilities)));
    h.push(_ready);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    h.push(_accepted);
    expect(await created, isTrue);
    final composer = h.repository.composer('thread');
    expect(composer.state.draft, 'edited while opening');
    expect(composer.state.attachments.single.id, 'old');
    expect(h.selection.state.selectedThreadId, 'thread');
    expect(h.calls('open'), hasLength(1));
    expect(
      (h.calls('open').single as OpenAcpSessionRequestView)
          .expectedConnectionRevision,
      BigInt.from(17),
    );
    expect(h.calls('prompt'), isEmpty);
    expect(h.transport.removed, isEmpty);
    expect(start.state.forProject('workspace').text, isEmpty);
    await composer.discard();
    expect(h.transport.removed, ['old'], reason: 'ownership moved, not copied');
  });

  test(
    'explicit prompt uses ACP without Native route and preserves newer edits',
    () async {
      final h = _Harness();
      await h.open();
      final composer = await h.composer();
      composer.updateDraft('frozen');
      h.port.promptResult = Completer<AcpRunIdView>();
      final sending = composer.submit();
      await Future<void>.delayed(Duration.zero);
      composer.updateDraft('newer');
      expect(h.calls('prompt'), hasLength(1));
      expect(
        (h.calls('prompt').single as AcpPromptRequestView).content.single,
        isA<AcpTextContentView>().having(
          (value) => value.text,
          'text',
          'frozen',
        ),
      );
      h.port.promptResult!.complete(h.port.run);
      await sending;
      expect(composer.state.draft, 'newer');
      expect(
        composer.submissions.value,
        isEmpty,
        reason: 'no Native Input ACK placeholder',
      );
    },
  );

  test(
    'same-value navigation intent cannot be replaced by late ACP creation',
    () async {
      final h = _Harness(ready: false);
      final start = h.repository.startDraft;
      start.setAcpService('workspace', 'account');
      start.updateDraft('workspace', 'preserved in created composer');
      final creating = start.submit('workspace');
      await h.source.enteredRead.future;
      await Future<void>.delayed(Duration.zero);
      h.selection.beginNewThread();
      h.push(_ready);
      h.push(_accepted);
      expect(await creating, isTrue);
      expect(h.selection.state.selectedThreadId, isNull);
      expect(
        h.repository.composer('thread').state.draft,
        'preserved in created composer',
      );
    },
  );

  test(
    'attachment bytes and ledger survive removal during serialization and send',
    () async {
      final h = _Harness();
      await h.open();
      final composer = await h.composer();
      h.transport.admissionResult = [
        _attachment('blob', AttachmentModalityView.file),
      ];
      await composer.addLocalAttachments(['/input.bin']);
      h.transport.bytesGate = Completer<Uint8List>();
      h.port.promptResult = Completer<AcpRunIdView>();
      final sending = composer.submit();
      await h.transport.readEntered.future;
      await composer.removeAttachment('blob');
      expect(h.transport.removed, isEmpty);
      h.transport.bytesGate!.complete(Uint8List.fromList([9, 8, 7]));
      await Future<void>.delayed(Duration.zero);
      final block =
          (h.calls('prompt').single as AcpPromptRequestView).content.single
              as AcpEmbeddedResourceView;
      expect(
        (block.resource as AcpBlobResourceContentsView).blob,
        base64Encode([9, 8, 7]),
      );
      expect(block.resource.uri, isNot(contains('/input.bin')));
      expect(h.transport.removed, isEmpty);
      h.port.promptResult!.complete(h.port.run);
      await sending;
      expect(h.transport.removed, ['blob']);
    },
  );

  test(
    'image uses original bytes, not preview, and clears after admission',
    () async {
      final h = _Harness();
      await h.open();
      final composer = await h.composer();
      h.transport.admissionResult = [
        _attachment('image', AttachmentModalityView.image),
      ];
      await composer.addLocalAttachments(['/image.png']);
      await composer.submit();
      final image =
          (h.calls('prompt').single as AcpPromptRequestView).content.single
              as AcpImageContentView;
      expect(image.data, base64Encode([1, 2, 3]));
      expect(image.mimeType, 'image/png');
      expect(composer.state.attachments, isEmpty);
      expect(h.transport.removed, ['image']);
    },
  );

  test(
    'unknown prompt preserves draft and blocks resend even after edits',
    () async {
      final h = _Harness();
      await h.open();
      final composer = await h.composer();
      composer.updateDraft('first');
      h.port.commandError = const AcpCommandOutcomeUnknown(
        command: 'prompt',
        cause: 'lost',
      );
      await composer.submit();
      expect(composer.state.draft, 'first');
      composer.updateDraft('edited');
      h.port.commandError = null;
      await composer.submit();
      expect(h.calls('prompt'), hasLength(1));
      expect(composer.state.draft, 'edited');
    },
  );

  test(
    'unknown creation cannot issue another new session after edits',
    () async {
      final h = _Harness(ready: false);
      final start = h.repository.startDraft;
      start.setAcpService('workspace', 'account');
      start.updateDraft('workspace', 'preserved');
      h.source.readError = const AcpCommandOutcomeUnknown(
        command: 'new',
        cause: 'lost',
      );
      expect(await start.submit('workspace'), isFalse);
      start.updateDraft('workspace', 'newer');
      h.source.readError = null;
      expect(await start.submit('workspace'), isFalse);
      expect(h.calls('open'), hasLength(1));
      expect(start.state.forProject('workspace').text, 'newer');
    },
  );

  test(
    'synchronous close notification prevents ACP creation and prompt dispatch',
    () async {
      final creating = _Harness();
      final start = creating.repository.startDraft;
      start.setAcpService('workspace', 'account');
      Future<void>? closeStart;
      final startWatch = start.source.watch((value) {
        if (value.submitting) closeStart ??= start.close();
      });
      expect(await start.submit('workspace'), isFalse);
      await closeStart;
      startWatch.cancel();
      expect(creating.calls('open'), isEmpty);

      final sending = _Harness();
      await sending.open();
      final composer = await sending.composer();
      composer.updateDraft('preserved');
      Future<void>? closeComposer;
      final composerWatch = composer.source.watch((value) {
        if (value.isSubmissionPending) closeComposer ??= composer.close();
      });
      await composer.submit();
      await closeComposer;
      composerWatch.cancel();
      expect(sending.calls('prompt'), isEmpty);
      expect(composer.state.draft, 'preserved');
    },
  );

  test('closing the draft releases ready wait without repeating or stopping the business owner', () async {
    final h = _Harness(ready: false);
    final start = h.repository.startDraft;
    start.setAcpService('workspace', 'account');
    final creating = start.submit('workspace');
    await h.source.enteredRead.future;
    await Future<void>.delayed(Duration.zero);
    await start.close();
    expect(await creating, isFalse);
    expect(h.calls('open'), hasLength(1));
    expect(h.calls('closeMember'), isEmpty);
    expect(h.source.closes, 0);
  });

  test('metadata removal during preparation blocks the frozen target and keeps the draft', () async {
    final h = _Harness();
    await h.open();
    final composer = await h.composer();
    composer.updateDraft('do not redirect');
    final entered = Completer<void>();
    final gate = Completer<void>();
    final sending = composer.submit(
      beforeSubmit: () async {
        entered.complete();
        await gate.future;
      },
    );
    await entered.future;
    h.transport.emitThread(null, 'thread', revision: 2);
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await sending;
    expect(h.calls('prompt'), isEmpty);
    expect(composer.state.draft, 'do not redirect');
    await composer.close();
    expect(h.transport.directoryCloseCalls, greaterThan(0));
  });

  test(
    'known prompt rejection keeps attachments and permits an explicit retry',
    () async {
      final h = _Harness();
      await h.open();
      final composer = await h.composer();
      h.transport.admissionResult = [
        _attachment('blob', AttachmentModalityView.file),
      ];
      await composer.addRemoteAttachment('https://example.test/data.bin');
      h.port.commandError = AcpBusinessFailureView(
        kind: AcpBusinessFailureKindView.invalidOption,
        message: 'rejected',
      );
      await composer.submit();
      expect(composer.state.attachments.single.id, 'blob');
      expect(h.transport.removed, isEmpty);
      h.port.commandError = null;
      await composer.submit();
      expect(h.calls('prompt'), hasLength(2));
      expect(composer.state.attachments, isEmpty);
      expect(h.transport.removed, ['blob']);
    },
  );

  test(
    'pending and failed configuration prevent sending old configuration',
    () async {
      final h = _Harness();
      final session = await h.open();
      final composer = await h.composer();
      composer.updateDraft('preserved');
      h.port.configureResult = Completer<void>();
      final configuring = session.configure(
        const AcpConfigId('effort'),
        const AcpBooleanConfigValueView(true),
      );
      await composer.submit();
      expect(h.calls('prompt'), isEmpty);
      h.port.configureResult!.completeError(StateError('failed'));
      await expectLater(configuring, throwsStateError);
      await composer.submit();
      expect(h.calls('prompt'), isEmpty);
      expect(composer.state.draft, 'preserved');
    },
  );

  test('unsupported video and unknown image capability keep attachments without reading', () async {
    for (final modality in [
      AttachmentModalityView.video,
      AttachmentModalityView.image,
    ]) {
      final h = _Harness(capabilities: null);
      h.repository.attachments.seedNewThreadIfEmpty(
        'workspace',
        ComposerThreadState.idle(
          attachments: [_attachment('unsupported', modality)],
        ),
      );
      h.repository.startDraft.setAcpService('workspace', 'account');
      expect(await h.repository.startDraft.submit('workspace'), isTrue);
      final composer = await h.composer();
      await composer.submit();
      expect(composer.state.attachments.single.id, 'unsupported');
      expect(h.transport.reads, isEmpty);
      expect(h.calls('prompt'), isEmpty);
      expect(h.transport.removed, isEmpty);
    }
  });

  test(
    'ACP uses the existing workspace without consuming Native worktree intent',
    () async {
      final h = _Harness();
      final start = h.repository.startDraft;
      start.setAcpService('workspace', 'account');
      start.setWorkspaceMode('workspace', ThreadWorkspaceMode.worktree);
      expect(await start.submit('workspace'), isTrue);
      expect(h.calls('open'), hasLength(1));
      expect(h.calls('prompt'), isEmpty);
      expect(h.native.calls, 0);
    },
  );

  test(
    'disabled ACP service is rejected before open and preserves draft',
    () async {
      final h = _Harness(enabled: false);
      final start = h.repository.startDraft;
      start.setAcpService('workspace', 'account');
      start.updateDraft('workspace', 'preserved');
      expect(await start.submit('workspace'), isFalse);
      expect(h.calls('open'), isEmpty);
      expect(start.state.forProject('workspace').text, 'preserved');
    },
  );

  test('SSH creation is rejected before ACP open', () async {
    final h = _Harness();
    final start = h.repository.startDraft;
    start.setAcpService('workspace', 'account');
    h.project.applyProjectDirectory(
      ProjectDirectoryState(
        values: const [
          StudioProject(
            id: 'workspace',
            name: 'Remote',
            path: '/project',
            sshAlias: 'ssh',
          ),
        ],
        revision: 2,
      ),
    );
    expect(await start.submit('workspace'), isFalse);
    expect(h.calls('open'), isEmpty);
  });
}
