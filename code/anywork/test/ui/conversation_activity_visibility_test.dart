import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_activity_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/interaction_details_connector.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/conversation_activity_view_model.dart';
import 'package:anywork/src/features/conversation/timeline/state/conversation_activity_state.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_viewport.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_statistics_feed.dart';

const _status = ThreadActivityView(
  threadId: 'thread',
  identity: 'activity',
  revision: 1,
  turnId: 'turn',
  kind: ThreadActivityKind.thinking,
  summary: '思考中',
);
final _activity = ActivitySnapshot(
  revision: 1,
  completedThrough: 0,
  executionPresent: true,
  entries: const [],
);

PendingInteraction _userInput({
  required String id,
  required String questionId,
  String threadId = 'thread',
}) => PendingInteraction(
  id: id,
  threadId: threadId,
  turnId: 'turn',
  kind: InteractionKind.userInput,
  title: '待回答',
  body: '请作出决定',
  payload: UserInputInteractionPayload(
    questions: [
      UserQuestionView(
        id: questionId,
        header: '问题',
        question: '请作出决定',
        isOther: false,
        isSecret: false,
        options: const [],
      ),
    ],
  ),
);

PendingInteraction _toolApproval({String threadId = 'thread'}) =>
    PendingInteraction(
      id: 'approval',
      threadId: threadId,
      turnId: 'turn',
      kind: InteractionKind.toolApproval,
      title: '工具审批',
      body: '允许执行工具',
      payload: const ToolApprovalInteractionPayload(
        toolName: 'exec',
        arguments: {'command': 'echo approval'},
        workingDirectory: '',
      ),
    );

ConversationActivityState? _project(List<PendingInteraction> interactions) =>
    projectConversationActivityState(
      status: _status,
      activity: _activity,
      storage: null,
      interactions: interactions,
    );

void main() {
  testWidgets(
    'plan confirmation unmounts real Activity tools and details; resolution and higher-priority approval restore them',
    (tester) async {
      const threadId = 'thread-main';
      final transport = RecordingDemoTransport();
      final graph = AppGraph(
        transport: transport,
        statisticsFeed: const TestStatisticsFeedPort(),
        clientId: 'plan-activity-visibility',
      );
      await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
      await pumpClientFuture(
        tester,
        (graph
              ..timeline.updateReadDemand(chatDemand)
              ..setConversationPageVisible(true))
            .client
            .directoryCommands
            .selectThread(threadId),
        'select thread',
      );
      final session = graph.client.conversations.session(threadId);
      await pumpClientUntil(
        tester,
        () => session.state.hasSnapshot && session.activity.value != null,
        'initial State and Activity',
      );
      final lease = graph.timeline.lease(threadId)!;
      final history = lease.controller.messages.toList();
      final previous = session.activity.value!;
      final snapshot = ActivitySnapshot(
        revision: previous.revision + 1,
        completedThrough: previous.completedThrough,
        executionPresent: true,
        entries: [
          ActivityEntry(
            identity: const ForegroundToolActivityIdentity(callId: 'wait-call'),
            atom: ChatAtom(
              id: 'wait-atom',
              source: const ForegroundTurnChatSource(turnId: 'turn'),
              sourceOrder: 1,
              kind: ChatAtomKind.toolCall,
              delivery: ChatDeliveryKind.foreground,
              lifecycle: const ActiveChatAtom(
                started: null,
                status: ChatActiveStatus.running,
              ),
              tool: const ChatToolIdentity(callId: 'wait-call', name: 'wait'),
              wait: ThreadWaitPresentationView(
                intent: ThreadWaitEventsIntentView(
                  targets: const [
                    ThreadWaitTargetView(
                      taskId: 'task:timer',
                      toolName: 'sleep',
                      status: ThreadWaitTargetStatusView.running,
                    ),
                  ],
                  timeoutMs: 120000,
                ),
                state: ThreadWaitStateView.waiting,
              ),
              contents: const [],
            ),
          ),
        ],
      );
      transport.feeds.single.emitActivity(snapshot);
      await pumpClientUntil(
        tester,
        () => identical(session.activity.value, snapshot),
        'nonempty real Activity',
      );
      final plan = _userInput(
        id: 'plan',
        questionId: agentSessionPlanConfirmationQuestionId,
        threadId: threadId,
      );
      final question = _userInput(
        id: 'question',
        questionId: 'ordinary-question',
        threadId: threadId,
      );
      Future<void> publish(List<PendingInteraction> interactions) =>
          pumpClientFuture(
            tester,
            transport.publishWorkspace(
              session.state.workspace!.copyWith(
                interactions: interactions,
                businessRefs: const ThreadBusinessRefs(
                  plan: null,
                  interactions: CurrentCollectionRef(
                    databaseId: 'visibility-test',
                    collection: 'interactions',
                    revision: 1,
                  ),
                ),
              ),
            ),
            'publish canonical pending interactions',
          );
      await publish([question]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appGraphProvider.overrideWithValue(graph)],
          child: MaterialApp(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: [ConversationActivityConnector(threadId: threadId)],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // An ordinary question has a null status view, but still presents tools.
      expect(find.byType(ConversationCurrentConnector), findsOneWidget);
      expect(find.byType(TimelineWaitPanel), findsOneWidget);
      expect(find.byType(InteractionDetailsConnector), findsOneWidget);

      final originalDisplay = lease.currentDisplay!;
      await publish([plan]);
      await tester.pump();
      expect(find.byType(ConversationCurrentConnector), findsNothing);
      expect(find.byType(ConversationActivityBar), findsNothing);
      expect(find.byType(TimelineWaitPanel), findsNothing);
      expect(find.byType(InteractionDetailsConnector), findsNothing);
      expect(find.byType(ConversationActivityViewport), findsNothing);
      expect(
        tester.getSize(find.byType(ConversationActivityConnector)).height,
        0,
      );
      expect(originalDisplay.isCurrent, isFalse);
      expect(lease.currentDisplay, isNull);
      expect(session.activity.value, same(snapshot));
      expect(lease.controller.messages, orderedEquals(history));

      // Approval and revision commands share this canonical removal boundary.
      // Their command/draft semantics are covered by plan_feedback_lifecycle_test.
      await publish(const []);
      await tester.pump();
      expect(find.byType(ConversationCurrentConnector), findsOneWidget);
      expect(find.byType(TimelineWaitPanel), findsOneWidget);
      expect(lease.currentDisplay, isNot(same(originalDisplay)));
      expect(session.activity.value, same(snapshot));

      await publish([plan]);
      await tester.pump();
      expect(find.byType(ConversationCurrentConnector), findsNothing);
      await publish([plan, _toolApproval(threadId: threadId)]);
      await tester.pump();
      expect(find.byType(ConversationCurrentConnector), findsOneWidget);
      expect(find.byType(TimelineWaitPanel), findsOneWidget);
      expect(find.byType(InteractionDetailsConnector), findsOneWidget);
      expect(session.activity.value, same(snapshot));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpClientFuture(
        tester,
        graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
        'activity visibility close',
      );
    },
  );

  test('Plan confirmation uses its State controls without hiding the actual activity snapshot', () {
    final state = _project([
      _userInput(
        id: 'plan',
        questionId: agentSessionPlanConfirmationQuestionId,
      ),
    ]);

    expect(state?.view, isNull);
    expect(state?.activity, same(_activity));
  });

  test('ordinary questions suppress duplicate status text and preserve unfinished operations', () {
    final state = _project([
      _userInput(id: 'question', questionId: 'ordinary-question'),
    ]);

    expect(state?.view, isNull);
    expect(state?.activity, same(_activity));
  });

  test('resolved interaction retains the real activity observation', () {
    final state = _project(const []);

    expect(state, isNotNull);
    expect(state!.activity, isNotNull);
    expect(state.view!.kind, ConversationActivityKind.thinking);
  });

  test('tool approval keeps the existing activity projection', () {
    final state = _project([
      _userInput(id: 'question', questionId: 'ordinary-question'),
      _toolApproval(),
    ]);

    expect(state, isNotNull);
    expect(state!.activity, isNotNull);
    expect(state.view!.kind, ConversationActivityKind.thinking);
  });
}
