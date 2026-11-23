import 'package:anywork/src/features/conversation/timeline/state/timeline_display_models.dart';
import 'package:anywork/src/features/conversation/timeline/timeline_views.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadActivityView _activity(
  ThreadActivityKind kind, {
  String identity = 'act-1',
  String? turnId = 'turn-1',
  String summary = '',
  String? thinkingSummary,
  int? thinkingSeconds,
  ThreadActivityTools tools = ThreadActivityTools.empty,
  List<CurrentStateField> deferred = const [],
}) => ThreadActivityView(
  threadId: 'thread-1',
  identity: identity,
  revision: 1,
  turnId: turnId,
  kind: kind,
  summary: summary,
  thinkingSummary: thinkingSummary,
  thinkingSeconds: thinkingSeconds,
  tools: tools,
  deferred: deferred,
);

CurrentAtom _textAtom({
  required String id,
  required String turnId,
  bool hasContent = true,
}) => CurrentAtom(
  id: id,
  source: ForegroundTurnChatSource(turnId: turnId),
  kind: ChatAtomKind.text,
  delivery: ChatDeliveryKind.foreground,
  lifecycle: const ActiveChatAtom(
    started: null,
    status: ChatActiveStatus.running,
  ),
  turnId: turnId,
  startedAt: 100,
  contents: hasContent
      ? [
          CurrentAtomContent(
            role: ChatContentRole.body,
            reference: CurrentContentRef(
              ownerId: 'owner-1',
              domain: 'chat',
              entityId: id,
              contentKey: 'body',
              generation: '1',
            ),
          ),
        ]
      : const [],
);

CurrentAtom _toolAtom({required String id, String? callId}) => CurrentAtom(
  id: id,
  source: const ForegroundTurnChatSource(turnId: 'turn-1'),
  kind: ChatAtomKind.toolCall,
  delivery: ChatDeliveryKind.foreground,
  lifecycle: const ActiveChatAtom(
    started: null,
    status: ChatActiveStatus.running,
  ),
  turnId: 'turn-1',
  tool: callId == null ? null : ChatToolIdentity(callId: callId, name: 'exec'),
  startedAt: 105,
  contents: const [],
);

CurrentAtom _compactionAtom({required String id}) => CurrentAtom(
  id: id,
  source: const ForegroundTurnChatSource(turnId: 'turn-1'),
  kind: ChatAtomKind.compaction,
  delivery: ChatDeliveryKind.foreground,
  lifecycle: const ActiveChatAtom(
    started: null,
    status: ChatActiveStatus.running,
  ),
  turnId: 'turn-1',
  startedAt: 105,
  contents: const [],
);

DisplayBlock _openWorkBlock({
  String id = 'work-1',
  bool executionPresent = true,
  int unfinishedCount = 1,
  bool groupClosed = false,
  String? summary,
  WorkTiming timing = const WorkTiming(startedAtMillis: 100_000),
}) => DisplayBlock(
  id: id,
  blockOrder: 1,
  body: WorkDisplayBlock(
    timing: timing,
    summary: summary,
    members: DisplayBlockRef(
      blockId: id,
      cut: const HistoryCut(''),
      anchorSeq: 1,
      headSeq: 1,
      afterSeq: 0,
    ),
    executionPresent: executionPresent,
    memberCount: 2,
    unfinishedCount: unfinishedCount,
    groupClosed: groupClosed,
  ),
);

void main() {
  group('LiveStatusMachine', () {
    test('returns LiveStatusIdle when no live state or blocker exists', () {
      final view = LiveStatusMachine.project(
        threadId: 'thread-1',
        inputs: const LiveStatusInputs.empty(),
      );

      expect(view.gate, const LiveStatusIdle());
      expect(view.primaryActivity, isNull);
    });

    test('projects pre-stream waitingApi as LiveActivityPhase(thinking)', () {
      final view = LiveStatusMachine.project(
        threadId: 'thread-1',
        inputs: LiveStatusInputs(
          activeTurnId: 'turn-1',
          activity: _activity(
            ThreadActivityKind.waitingApi,
            summary: '  line 1\n line 2  ',
            thinkingSummary: 'Inspecting state',
            thinkingSeconds: 17,
          ),
        ),
      );

      final presenting = view.gate as LiveStatusPresenting;
      final phase = presenting.presentation.primary as LiveActivityPhase;
      expect(phase.activity.kind, ConversationActivityKind.thinking);
      expect(phase.activity.summary, 'line 1 line 2');
      expect(phase.activity.thinkingSummary, 'Inspecting state');
      expect(phase.activity.thinkingSeconds, 17);
      expect(presenting.presentation.attentions, isEmpty);
      expect(view.primaryActivity, phase.activity);
    });

    test('projects LiveWorkPhase modes accurately (active, waiting, coldUnrestored)', () {
      final wait = ThreadWaitPresentationView(
        intent: ThreadWaitTimerIntentView(durationMs: 5000),
        state: ThreadWaitStateView.waiting,
      );
      final waitingView = LiveStatusMachine.project(
        threadId: 'thread-1',
        inputs: LiveStatusInputs(
          activeTurnId: 'turn-1',
          liveOpenWork: _openWorkBlock(),
          activity: _activity(
            ThreadActivityKind.runningTool,
            tools: ThreadActivityTools(
              count: 1,
              active: [
                ThreadActivityToolEntry(
                  callId: 'c1',
                  name: 'sleep',
                  summary: '等待 5 秒',
                  arguments: ThreadActivityArgumentsKind.commandLine,
                  state: ThreadActivityToolState.running,
                  wait: wait,
                ),
              ],
            ),
          ),
          current: CurrentAtomSnapshot(
            revision: 1,
            executionPresent: true,
            currentAtoms: [_toolAtom(id: 'a1', callId: 'c1')],
          ),
        ),
      );
      final waitingWork =
          ((waitingView.gate as LiveStatusPresenting).presentation.primary
              as LiveWorkPhase);
      expect(waitingWork.mode, LiveWorkGroupMode.waiting);
      expect(waitingWork.activity?.wait, wait);

      final coldView = LiveStatusMachine.project(
        threadId: 'thread-1',
        inputs: LiveStatusInputs(
          liveOpenWork: _openWorkBlock(
            executionPresent: false,
            unfinishedCount: 2,
          ),
        ),
      );
      final coldWork =
          ((coldView.gate as LiveStatusPresenting).presentation.primary
              as LiveWorkPhase);
      expect(coldWork.mode, LiveWorkGroupMode.coldUnrestored);
      expect(coldWork.executionPresent, isFalse);
      expect(coldWork.hasUnfinishedMembers, isTrue);
    });

    test('suppresses same-turn responding status only after response layout witness fires', () {
      final atom = _textAtom(id: 'atom-body', turnId: 'turn-1');
      final unlaid = LiveStatusMachine.project(
        threadId: 'thread-1',
        inputs: LiveStatusInputs(
          activeTurnId: 'turn-1',
          activity: _activity(ThreadActivityKind.responding),
          current: CurrentAtomSnapshot(
            revision: 1,
            executionPresent: true,
            currentAtoms: [atom],
          ),
          renderedCurrentAtomIds: const {},
        ),
      );
      final unlaidPrimary =
          ((unlaid.gate as LiveStatusPresenting).presentation.primary
              as LiveResponsePhase);
      expect(unlaidPrimary.activity, isNotNull);

      final laidOut = LiveStatusMachine.project(
        threadId: 'thread-1',
        inputs: LiveStatusInputs(
          activeTurnId: 'turn-1',
          activity: _activity(ThreadActivityKind.responding),
          current: CurrentAtomSnapshot(
            revision: 1,
            executionPresent: true,
            currentAtoms: [atom],
          ),
          renderedCurrentAtomIds: const {'atom-body'},
        ),
      );
      final laidPrimary =
          ((laidOut.gate as LiveStatusPresenting).presentation.primary
              as LiveResponsePhase);
      expect(laidPrimary.activity, isNull);

      final crossTurn = LiveStatusMachine.project(
        threadId: 'thread-1',
        inputs: LiveStatusInputs(
          activeTurnId: 'turn-1',
          activity: _activity(ThreadActivityKind.responding),
          current: CurrentAtomSnapshot(
            revision: 2,
            executionPresent: true,
            currentAtoms: [_textAtom(id: 'atom-other', turnId: 'turn-other')],
          ),
          renderedCurrentAtomIds: const {'atom-other'},
        ),
      );
      final crossPrimary =
          ((crossTurn.gate as LiveStatusPresenting).presentation.primary
              as LiveResponsePhase);
      expect(crossPrimary.activity, isNotNull);
    });

    test(
      'suppresses compacting status once active compaction atom is rendered',
      () {
        final view = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            activity: _activity(ThreadActivityKind.compacting),
            current: CurrentAtomSnapshot(
              revision: 1,
              executionPresent: true,
              currentAtoms: [_compactionAtom(id: 'cmp-1')],
            ),
            renderedCurrentAtomIds: const {'cmp-1'},
          ),
        );

        expect(view.gate, const LiveStatusIdle());
      },
    );

    test(
      'attaches companionWork onto LiveResponsePhase when open work coexists',
      () {
        final view = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            activity: _activity(ThreadActivityKind.responding),
            liveOpenWork: _openWorkBlock(summary: 'Coexisting work'),
            current: CurrentAtomSnapshot(
              revision: 2,
              executionPresent: true,
              currentAtoms: [_textAtom(id: 'body-1', turnId: 'turn-1')],
            ),
            renderedCurrentAtomIds: const {'body-1'},
          ),
        );

        final phase =
            ((view.gate as LiveStatusPresenting).presentation.primary
                as LiveResponsePhase);
        expect(phase.companionWork, isNotNull);
        expect(phase.companionWork!.id, 'work-1');
        expect(phase.companionWork!.activity, isNull);
      },
    );

    test(
      'deduplicates approval/stopping/storage/connection attentions cleanly',
      () {
        final view = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            hasContentOwner: true,
            businessRefs: const ThreadBusinessRefs(
              plan: null,
              interactions: CurrentCollectionRef(
                ownerId: 'o1',
                collection: 'interactions',
                revision: 1,
              ),
            ),
            activity: _activity(
              ThreadActivityKind.awaitingApproval,
              summary: 'exec',
            ),
            interactions: const [
              PendingInteraction(
                id: 'int-1',
                threadId: 'thread-1',
                turnId: 'turn-1',
                kind: InteractionKind.toolApproval,
                title: 'Approve',
                body: 'Allow?',
                payload: ToolApprovalInteractionPayload(
                  toolName: 'exec',
                  workingDirectory: '/ws',
                ),
              ),
            ],
            storage: const ThreadStorageStateView(
              fault: ThreadHistoryFault.writeFailed,
              faultGeneration: 2,
              execution: ThreadStorageExecution.paused,
              resumeRequired: true,
              canResume: true,
            ),
            connectionStatus: LiveConnectionStatus.reconnecting,
            connectionDetail: 'Retrying',
          ),
          currentAtomsError: 'Atom load failed',
        );

        final presenting = view.gate as LiveStatusPresenting;
        expect(presenting.presentation.showInteractionDetails, isTrue);
        expect(
          presenting.presentation.attentions.whereType<LiveApprovalAttention>(),
          hasLength(1),
        );
        final storageAttention = presenting.presentation.attentions
            .whereType<LiveStorageAttention>()
            .single;
        expect(storageAttention.severity, LiveStorageSeverity.resumeReady);
        expect(
          presenting.presentation.attentions
              .whereType<LiveConnectionAttention>()
              .single
              .status,
          LiveConnectionStatus.reconnecting,
        );
        expect(
          presenting.presentation.attentions
              .whereType<LiveErrorAttention>()
              .single
              .retryable,
          isTrue,
        );
      },
    );

    test('classifies all five storage severities from typed flags', () {
      LiveStorageSeverity classify(ThreadStorageStateView storage) {
        final view = LiveStatusMachine.project(
          threadId: 't',
          inputs: LiveStatusInputs(storage: storage),
        );
        return ((view.gate as LiveStatusPresenting)
                    .presentation
                    .attentions
                    .single
                as LiveStorageAttention)
            .severity;
      }

      expect(
        classify(
          const ThreadStorageStateView(
            fault: ThreadHistoryFault.writeFailed,
            resumeRequired: true,
            canResume: true,
          ),
        ),
        LiveStorageSeverity.resumeReady,
      );
      expect(
        classify(
          const ThreadStorageStateView(fault: ThreadHistoryFault.writeFailed),
        ),
        LiveStorageSeverity.fault,
      );
      expect(
        classify(const ThreadStorageStateView(pressurePaused: true)),
        LiveStorageSeverity.pressure,
      );
      expect(
        classify(
          const ThreadStorageStateView(resumeRequired: true, canResume: false),
        ),
        LiveStorageSeverity.resumeRequired,
      );
      expect(
        classify(
          const ThreadStorageStateView(
            execution: ThreadStorageExecution.paused,
          ),
        ),
        LiveStorageSeverity.paused,
      );
    });

    test(
      'suppresses dock for userInput and plan confirmation appropriately',
      () {
        const userQuestion = PendingInteraction(
          id: 'q-1',
          threadId: 'thread-1',
          turnId: 'turn-1',
          kind: InteractionKind.userInput,
          title: 'Question',
          body: '',
          payload: UserInputInteractionPayload(questions: []),
        );
        final questionMasked = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            hasContentOwner: true,
            businessRefs: const ThreadBusinessRefs(
              plan: null,
              interactions: CurrentCollectionRef(
                ownerId: 'o1',
                collection: 'interactions',
                revision: 1,
              ),
            ),
            activity: _activity(ThreadActivityKind.thinking),
            interactions: const [userQuestion],
          ),
        );
        final qGate = questionMasked.gate as LiveStatusSuppressed;
        expect(qGate.interactionId, 'q-1');
        expect(qGate.showInteractionDetails, isTrue);
        expect(qGate.obscured, isNotNull);
        expect(questionMasked.primaryActivity, isNull);

        const planConfirm = PendingInteraction(
          id: 'plan-1',
          threadId: 'thread-1',
          turnId: 'turn-1',
          kind: InteractionKind.userInput,
          title: 'Plan',
          body: '',
          payload: UserInputInteractionPayload(
            questions: [
              UserQuestionView(
                id: agentSessionPlanConfirmationQuestionId,
                header: 'Plan',
                question: 'Approve?',
                isOther: false,
                isSecret: false,
                options: [],
              ),
            ],
          ),
        );
        final planMasked = LiveStatusMachine.project(
          threadId: 'thread-1',
          inputs: LiveStatusInputs(
            activeTurnId: 'turn-1',
            hasContentOwner: true,
            businessRefs: const ThreadBusinessRefs(
              plan: null,
              interactions: CurrentCollectionRef(
                ownerId: 'o1',
                collection: 'interactions',
                revision: 1,
              ),
            ),
            activity: _activity(ThreadActivityKind.awaitingInput),
            interactions: const [planConfirm],
          ),
        );
        final pGate = planMasked.gate as LiveStatusSuppressed;
        expect(pGate.interactionId, 'plan-1');
        expect(pGate.showInteractionDetails, isFalse);
        expect(planMasked.primaryActivity, isNull);
      },
    );

    test('suppresses duplicate responding status in preview mode without breaking live layout gate', () {
      final previewView = LiveStatusMachine.project(
        threadId: 'thread-1',
        inputs: LiveStatusInputs(
          activeTurnId: 'turn-1',
          activity: _activity(ThreadActivityKind.responding),
          previewResponseText: 'preview body',
          previewResponseStartedAt: 100,
        ),
      );
      final previewPhase =
          (previewView.gate as LiveStatusPresenting).presentation.primary
              as LiveResponsePhase;
      expect(previewPhase.activity, isNull);
      expect(previewPhase.previewText, 'preview body');

      final erroredPreview = LiveStatusMachine.project(
        threadId: 'thread-1',
        inputs: LiveStatusInputs(
          activeTurnId: 'turn-1',
          activity: _activity(ThreadActivityKind.responding),
          previewResponseText: 'preview body',
          previewResponseStartedAt: 100,
          currentAtomsError: 'stream interrupted',
        ),
      );
      final erroredPresentation =
          (erroredPreview.gate as LiveStatusPresenting).presentation;
      expect(
        erroredPresentation.attentions.whereType<LiveErrorAttention>(),
        hasLength(1),
      );

      final unlaidStream = LiveStatusMachine.project(
        threadId: 'thread-1',
        inputs: LiveStatusInputs(
          activeTurnId: 'turn-1',
          activity: _activity(ThreadActivityKind.responding),
          previewResponseText: 'preview body',
          current: CurrentAtomSnapshot(
            revision: 1,
            executionPresent: true,
            currentAtoms: [_textAtom(id: 'body-1', turnId: 'turn-1')],
          ),
          renderedCurrentAtomIds: const {},
        ),
      );
      final unlaidPhase =
          (unlaidStream.gate as LiveStatusPresenting).presentation.primary
              as LiveResponsePhase;
      expect(unlaidPhase.activity, isNotNull);
    });
  });
}
