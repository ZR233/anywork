import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/views/composer_dock_view.dart';
import 'package:anywork/src/features/conversation/interactions/state/interaction_payload.dart';
import 'package:anywork/src/features/conversation/interactions/views/tool_approval_view.dart';
import 'package:anywork/src/features/conversation/interactions/views/user_input_view.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/src/contracts/stamps.dart';
import 'package:anywork_client/src/lifecycle/close_report.dart';
import 'package:anywork_client/src/observation/latest_value.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

const _source = ForegroundTurnChatSource(turnId: 'T');
ContentRef _ref({int revision = 1}) => ContentRef(
  databaseId: 'database',
  target: BodyContentTarget(
    owner: CurrentContentOwner(
      domain: 'execution',
      id: 'reasoning',
      revision: revision,
    ),
    key: 'body',
  ),
);

ContentWindow _window(String text, {int offset = 0}) => ContentWindow(
  bytes: utf8.encode(text),
  offset: offset,
  generation: 'g',
  availableThrough: 100000,
  sealed: false,
);

Future<void> _flush(WidgetTester tester) async {
  // Live indicators continuously animate. Drain only the disclosure animation
  // and original scope cancellation chain, not all future animation frames.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

final class _Content extends Fake implements ConversationContent {
  final source = LatestValue<ChatUiState<bool>>(
    const ChatReady('thread', true),
  );
  final scopes = <_Scope>[];
  Future<ContentWindow> Function(ContentRef, ContentRange)? onRead;
  @override
  bool get isClosed => false;
  @override
  ValueObservation<ChatUiState<bool>> get state => source;
  @override
  AttemptId get currentAttemptId => const AttemptId(1);
  @override
  ConversationQueryScope openScope({required int generation}) {
    final scope = _Scope()..onRead = onRead;
    scopes.add(scope);
    return scope;
  }
}

final class _Scope extends Fake implements ConversationQueryScope {
  final watches = <StreamController<ContentWindow>>[];
  final requests = <(ContentRef, ContentRange)>[];
  bool active = true;
  bool closed = false;
  int cancels = 0;
  Completer<void>? cancelGate;
  Object? closeFailure;
  Future<ContentWindow> Function(ContentRef, ContentRange)? onRead;
  final reads = <(ContentRef, ContentRange)>[];
  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    reads.add((reference, range));
    return onRead!(reference, range);
  }

  @override
  bool get isActive => active;
  @override
  Stream<ContentWindow> watchContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    requests.add((reference, range));
    final watch = StreamController<ContentWindow>(
      onCancel: () {
        cancels++;
        return cancelGate?.future;
      },
    );
    watches.add(watch);
    return watch.stream;
  }

  @override
  void retire() {
    active = false;
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    await cancelGate?.future;
    if (closeFailure case final failure?) {
      return CloseReport(
        unresolved: [
          UnresolvedResource(
            owner: 'scope',
            attemptId: const AttemptId(1),
            reason: failure,
          ),
        ],
      );
    }
    closed = true;
    return CloseReport();
  }
}

CurrentProjection _current(List<TimelineItem> items) => CurrentProjection(
  sourceEffectSeq: 1,
  logicalStatus: ThreadStatusView.running,
  executionPresent: true,
  activeTurn: const CurrentTurnHead(
    id: 'T',
    phase: StudioTurnActivity.thinking,
  ),
  sources: const [],
  atoms: const [],
  items: items,
  previews: const [],
  collections: const [],
);
TimelineItem _textItem({int revision = 1, PayloadData? payload}) =>
    TimelineItem(
      id: 'response',
      kind: TimelineItemKind.text,
      source: _source,
      delivery: ChatDeliveryKind.foreground,
      textChannel: ThreadTextChannel.finalAnswer,
      payload: payload,
      contents: [
        ChatAtomContent(
          role: ChatContentRole.body,
          reference: _ref(revision: revision),
        ),
      ],
      admissionClosed: false,
    );
Widget _host(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

final class _Harness {
  final content = _Content();
  final controller = InMemoryChatController();
  final images = TimelineImageResources(threadId: 'thread');
  late final presentation = TimelineMessageController(
    controller,
    generation: 1,
  );
  CurrentProjection current = _current([]);
  TimelineCurrentDisplay? display;
  Future<void> accept(List<TimelineItem> items) async {
    await acceptCurrent(_current(items));
  }

  Future<void> acceptCurrent(CurrentProjection snapshot) async {
    current = snapshot;
    await presentation.applyBatch(
      ChatBatch(
        placement: ChatPlacement.append,
        entries: const [],
        current: current,
      ),
    );
  }

  Widget host({
    ConversationActivityView? view = const ConversationActivityView(
      identity: 'active',
      kind: ConversationActivityKind.thinking,
      summary: '思考中',
      expandable: true,
    ),
    Widget? dock,
  }) {
    for (final unit in presentation.live.value) {
      unit.expansion.expanded ??= false;
    }
    final currentView = ConversationCurrentConnector(
      key: ObjectKey(content),
      current: current,
      content: content,
      view: view,
      units: presentation.live,
      images: images,
      readAttachment: (_) async => Uint8List(0),
      isDisplayActive: () => true,
      registerDisplay: (value) {
        display = value;
        return () => display = null;
      },
    );
    return _host(
      dock == null
          ? currentView
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [currentView, dock],
            ),
    );
  }

  void dispose() {
    presentation.dispose();
    images.release();
    controller.dispose();
  }
}

void main() {
  testWidgets(
    'an expanded member keeps its identity and reads terminal output across Append',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      final members = _MemberContent();
      await h.accept([workItem('tool-group', closed: false, active: 1)]);
      h.presentation.live.value.single.expansion.openMembers = (_, _) async =>
          members;
      await tester.pumpWidget(h.host());
      final header = find.byKey(
        const ValueKey('source-unit-header:tool-group'),
      );
      await tester.tap(header);
      await _flush(tester);
      final active = ChatAtom(
        id: 'tool-member',
        source: _source,
        sourceOrder: 1,
        kind: ChatAtomKind.toolCall,
        delivery: ChatDeliveryKind.foreground,
        lifecycle: const ActiveChatAtom(
          started: null,
          status: ChatActiveStatus.running,
        ),
        tool: const ChatToolIdentity(callId: 'call', name: 'exec'),
        contents: [
          ChatAtomContent(role: ChatContentRole.toolOutput, reference: _ref()),
        ],
      );
      await members.consumer!.applyBatch(
        ChatBatch(
          placement: ChatPlacement.set,
          entries: [ChatAtomEntry(active)],
        ),
      );
      await _flush(tester);
      final memberState = tester.state(find.byType(TimelineMemberAtom));
      await tester.tap(
        find
            .descendant(
              of: find.byType(TimelineToolDetails),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await _flush(tester);
      final original = members.scopes.single;
      expect(original.watches, hasLength(1));
      original.watches.single.add(_window('running output'));
      await tester.pump();
      final bytes = utf8.encode('terminal output');
      members.onRead = (_, _) async => ContentWindow(
        bytes: bytes,
        offset: 0,
        generation: 'sealed',
        availableThrough: bytes.length,
        sealed: true,
      );
      final completed = ChatAtom(
        id: active.id,
        source: _source,
        sourceOrder: 1,
        completionItemId: 'completion',
        completionSeq: 1,
        kind: active.kind,
        delivery: active.delivery,
        tool: active.tool,
        lifecycle: const TerminalChatAtom(
          started: null,
          ended: null,
          outcome: ChatTerminalOutcome.completed,
        ),
        contents: const [
          ChatAtomContent(
            role: ChatContentRole.toolOutput,
            reference: ContentRef(
              databaseId: 'database',
              target: BodyContentTarget(
                owner: ItemContentOwner(itemId: 'completion'),
                key: 'tool.result',
              ),
            ),
          ),
        ],
        payload: InlinePayload(
          bytes: utf8.encode(
            jsonEncode({
              'contract': 'anywork.chat/1',
              'type': 'tool',
              'data': {
                'invocation': {
                  'toolCallId': 'call',
                  'name': 'exec',
                  'presentationContract': 'builtin.exec@2',
                },
                'state': {
                  'kind': 'succeeded',
                  'completedAt': 12,
                  'output': {'exitCode': 0, 'attachments': []},
                },
              },
              'bodies': [
                {
                  'key': 'tool.arguments',
                  'byteLength': 2,
                  'inline': utf8.encode('{}'),
                },
              ],
            }),
          ),
        ),
      );
      await members.consumer!.applyBatch(
        ChatBatch(
          placement: ChatPlacement.append,
          entries: [ChatAtomEntry(completed)],
        ),
      );
      await _flush(tester);
      expect(tester.state(find.byType(TimelineMemberAtom)), same(memberState));
      expect(original.closed, isTrue);
      expect(original.cancels, 1);
      expect(
        tester
            .widget<TimelineToolDetails>(find.byType(TimelineToolDetails))
            .initiallyExpanded,
        isTrue,
      );
      expect(members.scopes.last.reads, hasLength(1));
      expect(find.textContaining('terminal output'), findsWidgets);
      await tester.tap(header);
      await _flush(tester);
      expect(
        members.scopes.every((scope) => !scope.isActive && scope.closed),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final kind in [
    InteractionKind.userInput,
    InteractionKind.toolApproval,
  ]) {
    testWidgets(
      'cold unfinished group stays readable with restored $kind dock, but only executionPresent enables activity',
      (tester) async {
        final h = _Harness();
        addTearDown(h.dispose);
        final group = workItem(
          'cold-group',
          closed: false,
          active: 2,
          count: 7,
          start: 10,
        );
        final originalSummary = group.summary!;
        CurrentProjection snapshot(bool executionPresent) => CurrentProjection(
          sourceEffectSeq: 8,
          logicalStatus: ThreadStatusView.running,
          executionPresent: executionPresent,
          active: null,
          activeTurn: null,
          sources: const [],
          atoms: const [],
          items: [group],
          previews: const [],
          collections: const [],
        );
        final pending = PendingInteraction(
          id: 'restored-${kind.name}',
          threadId: 'thread',
          turnId: 'T',
          kind: kind,
          title: '恢复的待决交互',
          body: '保存前仍需用户决议',
          revision: 7,
          payload: kind == InteractionKind.userInput
              ? const UserInputInteractionPayload(
                  questions: [
                    UserQuestionView(
                      id: 'restored-question',
                      header: '恢复问答',
                      question: '请选择恢复后的处理方式',
                      isOther: true,
                      isSecret: false,
                      options: [],
                    ),
                  ],
                )
              : const ToolApprovalInteractionPayload(
                  toolName: 'exec',
                  arguments: {'command': 'echo restored'},
                  workingDirectory: '',
                ),
        );
        final payload = InteractionPayloadSnapshot.from(pending);
        final reason = TextEditingController();
        addTearDown(reason.dispose);
        final answers = <UserInputResolutionCommand>[];
        var approvals = 0;
        final dock = ComposerDockView(
          compact: true,
          additionalDiagnostics: const [],
          childInteractions: null,
          content: kind == InteractionKind.userInput
              ? UserInputView(
                  payload: payload,
                  enabled: true,
                  onSubmit: answers.add,
                )
              : ToolApprovalView(
                  payload: payload,
                  enabled: true,
                  reasonController: reason,
                  onReasonChanged: (_) {},
                  onApprove: () => approvals++,
                  onDeny: () {},
                ),
        );
        await h.acceptCurrent(snapshot(false));
        final view = projectConversationActivity(
          current: h.current,
          interaction: pending,
        );
        expect(view, isNotNull);
        expect(h.current.active, isNull);
        expect(h.current.activeTurn, isNull);
        final members = _MemberContent();
        var memberOpens = 0;
        h.presentation.live.value.single.expansion.openMembers =
            (reference, demand) async {
              memberOpens++;
              expect(reference, same(group.members));
              return members;
            };
        await tester.pumpWidget(h.host(view: view, dock: dock));
        final header = find.byKey(
          const ValueKey('source-unit-header:cold-group'),
        );
        final workIndicator = find.descendant(
          of: header,
          matching: find.byType(TimelineActivityIndicator),
        );
        final workRotation = find.descendant(
          of: workIndicator,
          matching: find.byType(RotationTransition),
        );
        expect(find.text('工作未完成'), findsOneWidget);
        expect(tester.widget<TimelineActivityRow>(header).active, isFalse);
        expect(find.text('工作中'), findsNothing);
        expect(workIndicator, findsNothing);
        expect(workRotation, findsNothing);
        expect(find.byType(ComposerDockView), findsOneWidget);
        expect(memberOpens, 0);
        await tester.tap(header);
        await _flush(tester);
        expect(memberOpens, 1);
        await members.consumer!.applyBatch(
          ChatBatch(
            placement: ChatPlacement.set,
            entries: [
              ChatAtomEntry(
                ChatAtom(
                  id: 'saved-reasoning',
                  source: _source,
                  sourceOrder: 1,
                  kind: ChatAtomKind.reasoning,
                  delivery: ChatDeliveryKind.foreground,
                  lifecycle: const ActiveChatAtom(
                    started: null,
                    status: ChatActiveStatus.running,
                  ),
                  contents: [
                    ChatAtomContent(
                      role: ChatContentRole.body,
                      reference: _ref(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        await tester.pump();
        expect(members.scopes, isEmpty);
        await _flush(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(TimelineReasoningView),
            matching: find.byType(TimelineActivityRow),
          ),
        );
        await tester.pump();
        members.scopes.single.watches.single.add(_window('已保存的思考片段'));
        await tester.idle();
        await tester.pump();
        expect(find.text('已保存的思考片段'), findsOneWidget);
        final coldMeta = tester.widget<TimelineActivityRow>(header).meta;
        await tester.pump(const Duration(seconds: 12));
        expect(tester.widget<TimelineActivityRow>(header).meta, coldMeta);
        expect(coldMeta, '7 项');
        expect(workIndicator, findsNothing);
        expect(workRotation, findsNothing);
        expect(h.presentation.live.value.single.item, same(group));
        expect(group.summary, same(originalSummary));
        expect(originalSummary.activeCount, 2);
        expect(originalSummary.finishedAt, isNull);
        expect(group.admissionClosed, isFalse);

        await h.acceptCurrent(snapshot(true));
        await tester.pumpWidget(h.host(view: view, dock: dock));
        expect(tester.widget<TimelineActivityRow>(header).active, isTrue);
        expect(find.text('工作中'), findsOneWidget);
        expect(workIndicator, findsOneWidget);
        expect(
          tester.widget<TimelineActivityIndicator>(workIndicator).active,
          isTrue,
        );
        expect(workRotation, findsOneWidget);
        await h.acceptCurrent(snapshot(false));
        await tester.pumpWidget(h.host(view: view, dock: dock));
        expect(tester.widget<TimelineActivityRow>(header).active, isFalse);
        expect(workIndicator, findsNothing);
        expect(workRotation, findsNothing);
        expect(find.text('已保存的思考片段'), findsOneWidget);
        expect(
          memberOpens,
          1,
          reason: 'Execution qualification does not discard a readable member scope',
        );
        if (kind == InteractionKind.userInput) {
          await tester.enterText(
            find.byKey(StudioDriverKeys.userInputFirstText),
            '恢复后的回答',
          );
          await tester.tap(find.byKey(StudioDriverKeys.userInputSubmit));
          await tester.pump();
          expect(answers.single.answers.single.answers, ['恢复后的回答']);
        } else {
          await tester.tap(find.byKey(StudioDriverKeys.toolApprove));
          await tester.pump();
          expect(approvals, 1);
        }
        expect(h.current.executionPresent, isFalse);
        expect(h.current.items.single, same(group));
        expect(group.summary, same(originalSummary));
        await tester.pumpWidget(const SizedBox());
        await _flush(tester);
        expect(members.isClosed, isTrue);
      },
    );
  }

  testWidgets(
    'typed active compaction Status renders one production row; completion uses its original receipt',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      TimelineItem status({
        ChatTerminalOutcome? outcome,
        PayloadData? payload,
      }) => TimelineItem(
        id: 'compaction-status',
        kind: TimelineItemKind.status,
        source: const OperationChatSource(operationId: 'compaction-operation'),
        atomKind: ChatAtomKind.compaction,
        delivery: ChatDeliveryKind.independent,
        outcome: outcome,
        contents: const [],
        payload: payload,
        admissionClosed: true,
      );
      await h.accept([status()]);
      await tester.pumpWidget(h.host());
      final unit = find.byKey(const ValueKey('compaction-status'));
      final rows = find.descendant(
        of: unit,
        matching: find.byType(TimelineActivityRow),
      );
      expect(unit, findsOneWidget);
      expect(rows, findsOneWidget);
      final active = tester.widget<TimelineActivityRow>(rows);
      final l10n = AppLocalizations.of(tester.element(rows));
      expect(active.label, l10n.conversationActivityCompacting);
      expect(active.icon, Icons.compress_outlined);
      expect(active.active, isTrue);
      expect(active.expandable, isFalse);
      expect(find.byType(ConversationActivityStatus), findsNothing);
      expect(h.content.scopes, isEmpty);
      expect(h.controller.messages, isEmpty);

      await h.accept([
        status(
          outcome: ChatTerminalOutcome.completed,
          payload: chatEnvelope(
            'compaction-receipt',
            type: 'contextCompaction',
            data: const {},
          ).payload,
        ),
      ]);
      await tester.pumpWidget(h.host());
      expect(rows, findsOneWidget);
      final completed = tester.widget<TimelineActivityRow>(rows);
      expect(completed.label, l10n.timelineContextCompacted);
      expect(completed.active, isFalse);
      expect(completed.expandable, isFalse);
      expect(find.byType(ConversationActivityStatus), findsNothing);
      expect(h.content.scopes, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'saved compaction without an execution owner is unknown, not an active compaction row',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      final item = TimelineItem(
        id: 'saved-compaction',
        kind: TimelineItemKind.status,
        source: const OperationChatSource(operationId: 'saved-operation'),
        atomKind: ChatAtomKind.compaction,
        delivery: ChatDeliveryKind.independent,
        outcome: null,
        contents: const [],
        admissionClosed: true,
      );
      await h.acceptCurrent(
        CurrentProjection(
          sourceEffectSeq: 9,
          logicalStatus: ThreadStatusView.running,
          executionPresent: false,
          active: null,
          activeTurn: null,
          sources: const [],
          atoms: const [],
          items: [item],
          previews: const [],
          collections: const [],
        ),
      );
      await tester.pumpWidget(h.host());
      expect(find.text('内容状态未知'), findsOneWidget);
      expect(find.byType(TimelineActivityRow), findsNothing);
      expect(h.presentation.live.value.single.item, same(item));
      expect(item.outcome, isNull);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  for (final (kind, outcome) in [
    (ChatAtomKind.receipt, null),
    (ChatAtomKind.compaction, ChatTerminalOutcome.completed),
  ]) {
    testWidgets(
      'no-payload $kind / $outcome stays unknown despite a globally running current',
      (tester) async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.accept([
          TimelineItem(
            id: 'unknown-status',
            kind: TimelineItemKind.status,
            source: const OperationChatSource(operationId: 'unknown-operation'),
            atomKind: kind,
            outcome: outcome,
            delivery: ChatDeliveryKind.independent,
            contents: const [],
            admissionClosed: true,
          ),
        ]);
        await tester.pumpWidget(h.host());
        expect(find.text('内容状态未知'), findsOneWidget);
        expect(find.byType(TimelineActivityRow), findsNothing);
        expect(find.byType(ConversationActivityStatus), findsNothing);
        expect(h.content.scopes, isEmpty);
        await tester.pumpWidget(const SizedBox());
        await _flush(tester);
      },
    );
  }

  testWidgets(
    'real group members share the outer reading viewport and remain reachable when height shrinks',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      final members = _MemberContent();
      await h.accept([
        workItem('long-members', count: 30, active: 0, closed: false),
      ]);
      final unit = h.presentation.live.value.single;
      unit.expansion.expanded = true;
      unit.expansion.openMembers = (_, _) async => members;
      await tester.binding.setSurfaceSize(const Size(760, 210));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(h.host());
      await _flush(tester);
      await members.consumer!.applyBatch(
        ChatBatch(
          placement: ChatPlacement.set,
          entries: [
            for (var index = 0; index < 30; index++)
              ChatAtomEntry(
                chatEnvelope(
                  'member-$index',
                  type: 'tool',
                  data: {
                    'invocation': {
                      'toolCallId': 'call-$index',
                      'name': 'stat_path',
                      'presentationContract': 'builtin.stat_path@1',
                    },
                    'state': {
                      'kind': 'succeeded',
                      'completedAt': 1,
                      'output': {'attachments': []},
                    },
                  },
                  bodies: [
                    inlineBody(
                      'tool.arguments',
                      jsonEncode({'path': '文件-$index.txt'}),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
      await _flush(tester);
      expect(tester.takeException(), isNull);
      final scrolls = tester.stateList<ScrollableState>(
        find.byType(Scrollable),
      );
      expect(
        scrolls.where((scroll) => scroll.position.maxScrollExtent > 0),
        hasLength(1),
        reason: 'Only the outer group body scrolls',
      );
      final body = find.byType(SingleChildScrollView).first;
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: body, matching: find.byType(Scrollable)).first,
          )
          .position;
      expect(position.maxScrollExtent, greaterThan(320));
      await tester.drag(body, const Offset(0, -5000));
      await _flush(tester);
      final last = find.textContaining('文件-29.txt');
      expect(last.hitTestable(), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(760, 130));
      await tester.pumpWidget(h.host());
      await _flush(tester);
      await tester.drag(body, const Offset(0, -5000));
      await _flush(tester);
      expect(tester.takeException(), isNull);
      expect(last.hitTestable(), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('conversation-activity')))
            .height,
        lessThanOrEqualTo(130),
      );
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'an unfinished group does not hide a later response; folded group opens no body or member resource',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      var opens = 0;
      await h.accept([workItem('R', closed: true, active: 1), _textItem()]);
      h.presentation.live.value.first.expansion.openMembers = (_, _) async {
        opens++;
        throw StateError('must remain folded');
      };
      await tester.pumpWidget(h.host());
      expect(find.byType(TimelineDisplayUnitView), findsOneWidget);
      expect(opens, 0);
      expect(h.content.scopes, hasLength(1));
      h.content.scopes.single.watches.single.add(_window('后继正文仍可读'));
      await tester.idle();
      await tester.pump();
      expect(find.text('后继正文仍可读'), findsOneWidget);
      expect(h.presentation.live.value.map((unit) => unit.id), [
        'R',
        'response',
      ]);
      expect(h.controller.messages, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'same content ref retains its watch; revision replacement hides stale text and preserves IO failure',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.accept([_textItem()]);
      await tester.pumpWidget(h.host());
      final old = h.content.scopes.single;
      old.watches.single.add(_window('旧文档'));
      await tester.idle();
      await tester.pump();
      expect(find.text('旧文档'), findsOneWidget);
      final borrowed = h.display!.windows.single;
      final display = h.display;
      await tester.pumpWidget(h.host(view: null));
      expect(h.display, same(display));
      expect(h.display!.windows.single, same(borrowed));
      expect(h.content.scopes, [old]);
      expect(old.active, isTrue);
      expect(old.watches, hasLength(1));
      expect(find.byType(ConversationActivityBar), findsOneWidget);
      expect(find.byType(ConversationResponseView), findsOneWidget);
      expect(find.byType(ConversationActivityStatus), findsNothing);
      expect(find.text('旧文档'), findsOneWidget);
      await h.accept([_textItem()]);
      await tester.pumpWidget(h.host());
      expect(h.content.scopes, [old]);
      expect(old.watches, hasLength(1));
      expect(h.display!.windows.single, same(borrowed));
      old.watches.single.add(_window('整片替换'));
      // The stream is asynchronous: deliver its event before drawing the frame.
      await tester.idle();
      await tester.pump();
      expect(utf8.decode(borrowed.window!.bytes), '整片替换');
      expect(find.text('旧文档'), findsNothing);
      expect(find.text('整片替换'), findsOneWidget);
      old.cancelGate = Completer<void>();
      await h.accept([_textItem(revision: 2)]);
      expect(old.active, isFalse);
      expect(borrowed.window, isNull);
      expect(h.display!.windows, isEmpty);
      expect(h.content.scopes, [old]);
      await tester.pumpWidget(h.host());
      expect(find.text('整片替换'), findsNothing);
      old.cancelGate!.complete();
      await _flush(tester);
      expect(old.cancels, 1);
      expect(borrowed.window, isNull);
      expect(find.text('整片替换'), findsNothing);
      h.content.scopes.last.watches.single.addError(StateError('真实读取失败'));
      await tester.idle();
      await tester.pump();
      expect(find.textContaining('真实读取失败'), findsOneWidget);
      await h.accept([]);
      await tester.pumpWidget(h.host(view: null));
      expect(h.display, same(display));
      expect(h.display!.windows, isEmpty);
      expect(find.byType(ConversationActivityBar), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      expect(h.content.scopes.every((scope) => scope.closed), isTrue);
    },
  );

  for (final staleError in [false, true]) {
    testWidgets(
      'current Deferred ref replacement revokes range callbacks before layout and ignores late ${staleError ? 'error' : 'success'}',
      (tester) async {
        final h = _Harness();
        addTearDown(h.dispose);
        final oldRead = Completer<ContentWindow>();
        h.content.onRead = (_, _) => oldRead.future;
        TimelineItem deferred(int revision) => _textItem(
          revision: revision,
          payload: DeferredPayload(
            reference: _ref(revision: revision),
            byteLength: 100000,
          ),
        );
        await h.accept([deferred(1)]);
        await tester.pumpWidget(h.host());
        final open = find.text('按需查看原文 · 100000 字节');
        expect(h.content.scopes, isEmpty);
        await tester.tap(open);
        await tester.pump();
        final range = tester.widget<TimelineContentRangeConnector>(
          find.byType(TimelineContentRangeConnector),
        );
        final old = h.content.scopes.single;
        final borrowed = h.display!.windows.single;
        old.cancelGate = Completer<void>();
        await h.accept([deferred(2)]);
        expect(old.active, isFalse);
        expect(range.isDisplayActive!(), isFalse);
        expect(borrowed.window, isNull);
        expect(h.display!.windows, isEmpty);
        await expectLater(
          range.readContent!(
            range.reference,
            const ContentRange(offset: 0, maxBytes: 20),
          ),
          throwsA(isA<StaleConversationScope>()),
        );
        expect(old.reads, hasLength(1));
        if (staleError) {
          oldRead.completeError(StateError('旧范围失败'));
        } else {
          oldRead.complete(_window('旧范围正文'));
        }
        await tester.idle();
        await tester.pumpWidget(h.host());
        expect(find.text('旧范围正文'), findsNothing);
        expect(find.textContaining('旧范围失败'), findsNothing);
        expect(old.closed, isFalse);
        old.cancelGate!.complete();
        await tester.idle();
        expect(old.closed, isTrue);
        final freshRead = Completer<ContentWindow>();
        h.content.onRead = (_, _) => freshRead.future;
        await tester.tap(open);
        await tester.pump();
        final fresh = h.content.scopes.last;
        expect(fresh, isNot(same(old)));
        freshRead.complete(_window('新范围正文'));
        await tester.idle();
        await tester.pump();
        expect(find.text('新范围正文'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await _flush(tester);
      },
    );
  }

  testWidgets(
    'selection retirement revokes body callbacks before cancel/join completes',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.accept([_textItem()]);
      await tester.pumpWidget(h.host());
      final old = h.content.scopes.single;
      old.cancelGate = Completer<void>();
      old.watches.single.add(_window('旧值'));
      await tester.idle();
      await tester.pump();
      expect(find.text('旧值'), findsOneWidget);
      final previousIntent = h.presentation.live.value.single.expansion;
      final borrowed = h.display!.windows.single;
      await h.accept([]);
      expect(old.active, isFalse);
      expect(h.display!.windows, isEmpty);
      old.watches.single.add(_window('迟到值'));
      expect(borrowed.window, isNull);
      // Reappear with the same item ID before any intervening layout.
      await h.accept([_textItem(revision: 2)]);
      expect(
        h.presentation.live.value.single.expansion,
        isNot(same(previousIntent)),
      );
      await tester.pumpWidget(h.host());
      expect(find.text('迟到值'), findsNothing);
      expect(find.text('旧值'), findsNothing);
      final fresh = h.content.scopes.last;
      expect(fresh, isNot(same(old)));
      expect(old.closed, isFalse);
      old.cancelGate!.complete();
      await _flush(tester);
      fresh.watches.single.add(_window('新值'));
      await tester.idle();
      await tester.pump();
      expect(find.text('新值'), findsOneWidget);
      expect(old.closed, isTrue);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'reasoning reads only its summary while folded and revokes the body before the closing animation',
    (tester) async {
      final content = _Content();
      final images = TimelineImageResources(threadId: 'thread');
      addTearDown(images.release);
      const summaryRef = ContentRef(
        databaseId: 'database',
        target: BodyContentTarget(
          owner: CurrentContentOwner(
            domain: 'execution',
            id: 'reasoning',
            revision: 1,
          ),
          key: 'part.summaryText.0',
        ),
      );
      TimelineMemberDisplay? display;
      Widget scene({bool withBody = true}) => _host(
        TimelineMemberAtom(
          key: const ValueKey('reasoning-member'),
          atom: ChatAtom(
            id: 'reasoning-member',
            source: _source,
            sourceOrder: 1,
            kind: ChatAtomKind.reasoning,
            delivery: ChatDeliveryKind.foreground,
            lifecycle: const ActiveChatAtom(
              started: null,
              status: ChatActiveStatus.running,
            ),
            contents: [
              const ChatAtomContent(
                role: ChatContentRole.reasoningSummary,
                reference: summaryRef,
              ),
              if (withBody)
                ChatAtomContent(role: ChatContentRole.body, reference: _ref()),
            ],
          ),
          content: content,
          isActive: () => true,
          images: images,
          readAttachment: null,
          registerDisplay: (value) {
            display = value;
            return () => display = null;
          },
        ),
      );
      await tester.pumpWidget(scene());
      final original = content.scopes.single;
      expect(original.requests.single.$1, same(summaryRef));
      original.watches.single.add(_window('持续更新的思考概要'));
      await tester.idle();
      await tester.pump();
      expect(
        find.textContaining('持续更新的思考概要', findRichText: true),
        findsOneWidget,
      );
      expect(display!.windows, hasLength(1));
      final row = find.descendant(
        of: find.byType(TimelineReasoningView),
        matching: find.byType(TimelineActivityRow),
      );
      await tester.tap(row);
      await tester.pump();
      expect(original.requests, hasLength(2));
      original.watches.last.add(_window('按需读取的思考正文'));
      await tester.idle();
      await _flush(tester);
      expect(find.text('按需读取的思考正文'), findsOneWidget);
      original.cancelGate = Completer<void>();
      await tester.tap(row);
      expect(original.active, isFalse);
      expect(display!.windows, isEmpty);
      original.watches.last.add(_window('折叠后迟到正文'));
      await tester.idle();
      await tester.pump();
      expect(display!.windows, isEmpty);
      original.cancelGate!.complete();
      await _flush(tester);
      expect(content.scopes, hasLength(2));
      final fresh = content.scopes.last;
      expect(fresh.requests.single.$1, same(summaryRef));
      fresh.watches.single.add(_window('折叠后仍可更新概要'));
      await tester.idle();
      await _flush(tester);
      expect(
        find.textContaining('折叠后仍可更新概要', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('折叠后迟到正文'), findsNothing);
      expect(find.text('按需读取的思考正文'), findsNothing);
      await tester.pumpWidget(scene(withBody: false));
      expect(find.byType(ExpansionTile), findsNothing);
      expect(tester.widget<TimelineActivityRow>(row).expandable, isFalse);
      expect(fresh.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      expect(content.scopes.every((scope) => scope.closed), isTrue);
    },
  );

  testWidgets(
    'sealed reasoning revokes pending body reads immediately while retaining its summary',
    (tester) async {
      final content = _Content();
      final images = TimelineImageResources(threadId: 'thread');
      addTearDown(images.release);
      final pendingBody = Completer<ContentWindow>();
      content.onRead = (reference, _) =>
          (reference.target as BodyContentTarget).key.contains('summaryText')
          ? Future.value(_window('已保存的思考概要'))
          : pendingBody.future;
      Map<String, Object?> manifest(String key) => {
        'key': key,
        'byteLength': 100,
        'reference': {
          'databaseId': 'database',
          'target': {
            'kind': 'body',
            'owner': {'kind': 'item', 'itemId': 'sealed-reasoning'},
            'key': key,
          },
        },
      };
      TimelineMemberDisplay? display;
      await tester.pumpWidget(
        _host(
          TimelineMemberAtom(
            atom: ChatAtom(
              id: 'sealed-reasoning',
              source: _source,
              sourceOrder: 1,
              kind: ChatAtomKind.reasoning,
              delivery: ChatDeliveryKind.foreground,
              lifecycle: const TerminalChatAtom(
                started: null,
                ended: null,
                outcome: ChatTerminalOutcome.completed,
              ),
              contents: const [],
              payload: InlinePayload(
                bytes: utf8.encode(
                  jsonEncode({
                    'contract': 'anywork.chat/1',
                    'type': 'thinking',
                    'data': <String, Object?>{},
                    'bodies': [
                      manifest('part.summaryText.0'),
                      manifest('part.reasoningText.0'),
                    ],
                  }),
                ),
              ),
            ),
            content: content,
            isActive: () => true,
            images: images,
            readAttachment: null,
            registerDisplay: (value) {
              display = value;
              return () => display = null;
            },
          ),
        ),
      );
      await _flush(tester);
      expect(content.scopes.single.reads, hasLength(1));
      expect(
        find.textContaining('已保存的思考概要', findRichText: true),
        findsOneWidget,
      );
      final row = find.descendant(
        of: find.byType(TimelineReasoningView),
        matching: find.byType(TimelineActivityRow),
      );
      await tester.tap(row);
      await _flush(tester);
      final original = content.scopes.single;
      expect(original.reads, hasLength(2));
      expect(
        find.byType(ExpansionTile),
        findsOneWidget,
        reason: 'Opening the member is the only body disclosure',
      );
      final bodyConnector = tester
          .widgetList<TimelineContentRangeConnector>(
            find.byType(TimelineContentRangeConnector),
          )
          .singleWhere((view) => view.contentKey == 'part.reasoningText.0');
      expect(bodyConnector.isDisplayActive!(), isTrue);
      await tester.tap(row);
      expect(original.active, isFalse);
      expect(bodyConnector.isDisplayActive!(), isFalse);
      expect(display!.windows, isEmpty);
      await expectLater(
        bodyConnector.readContent!(
          bodyConnector.reference,
          const ContentRange(offset: 0, maxBytes: 20),
        ),
        throwsA(isA<StaleConversationScope>()),
      );
      expect(original.reads, hasLength(2));
      pendingBody.complete(_window('已经折叠的迟到思考正文'));
      await _flush(tester);
      expect(find.text('已经折叠的迟到思考正文'), findsNothing);
      expect(
        find.textContaining('已保存的思考概要', findRichText: true),
        findsOneWidget,
      );
      expect(content.scopes.last.reads, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      expect(content.scopes.every((scope) => scope.closed), isTrue);
    },
  );

  testWidgets(
    'typed wait uses member atom, never tool-name or generic Running inference',
    (tester) async {
      final content = _Content();
      final images = TimelineImageResources(threadId: 'thread');
      addTearDown(images.release);
      final waiting = ThreadWaitPresentationView(
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
      );
      ChatAtom member(ThreadWaitPresentationView? wait) => ChatAtom(
        id: 'wait-atom',
        source: _source,
        sourceOrder: 1,
        kind: ChatAtomKind.toolCall,
        delivery: ChatDeliveryKind.foreground,
        lifecycle: const ActiveChatAtom(
          started: null,
          status: ChatActiveStatus.running,
        ),
        tool: const ChatToolIdentity(callId: 'call', name: 'wait'),
        wait: wait,
        contents: const [],
      );
      Widget scene(ThreadWaitPresentationView? wait) => _host(
        TimelineMemberAtom(
          key: const ValueKey('wait-atom'),
          atom: member(wait),
          content: content,
          isActive: () => true,
          images: images,
          readAttachment: null,
        ),
      );
      await tester.pumpWidget(scene(null));
      expect(find.byType(TimelineWaitPanel), findsNothing);
      await tester.pumpWidget(scene(waiting));
      expect(find.byType(TimelineWaitPanel), findsOneWidget);
      expect(
        tester
            .widget<TimelineWaitPanel>(find.byType(TimelineWaitPanel))
            .presentation,
        same(waiting),
      );
      expect(content.scopes, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );
}

final class _MemberContent extends _Content {
  ConversationBatchConsumer? consumer;
  bool _closed = false;
  @override
  bool get isClosed => _closed;
  @override
  Observation attachConsumer(
    ConversationBatchConsumer consumer, {
    required ReadDemand demand,
  }) {
    this.consumer = consumer;
    return _MemberObservation();
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    for (final scope in scopes) {
      scope.retire();
      await scope.close(deadline: deadline);
    }
    _closed = true;
    return CloseReport();
  }
}

final class _MemberObservation extends Fake implements Observation {
  @override
  bool isCancelled = false;
  @override
  void cancel() => isCancelled = true;
}
