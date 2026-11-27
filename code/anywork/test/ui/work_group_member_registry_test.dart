import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/tools/tool_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/features/conversation/timeline/work_group/items/agent_member_item.dart';
import 'package:anywork/src/features/conversation/timeline/work_group/items/fallback_member_item.dart';
import 'package:anywork/src/features/conversation/timeline/work_group/items/file_change_member_item.dart';
import 'package:anywork/src/features/conversation/timeline/work_group/items/media_tool_member_item.dart';
import 'package:anywork/src/features/conversation/timeline/work_group/items/reasoning_member_item.dart';
import 'package:anywork/src/features/conversation/timeline/work_group/items/skill_member_item.dart';
import 'package:anywork/src/features/conversation/timeline/work_group/items/tool_member_item.dart';
import 'package:anywork/src/features/conversation/timeline/work_group/work_group_member_adapter.dart';
import 'package:anywork/src/features/conversation/timeline/work_group/work_group_member_registry.dart';
import 'package:anywork/src/features/conversation/timeline/work_group/work_group_member_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_badges.dart';
import 'package:anywork/src/shared/studio_code_block.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(Widget child, {Locale locale = const Locale('zh')}) => MaterialApp(
  theme: pureStudioTheme(),
  locale: locale,
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

String _showFilesEnvelope() => jsonEncode({
  'contract': 'anywork.event/1',
  'type': 'tool',
  'meta': {'presentationContract': 'builtin.show_files@1'},
  'data': {
    'invocation': {
      'toolCallId': 'call-media',
      'name': 'show_files',
      'presentationContract': 'builtin.show_files@1',
    },
    'state': {
      'kind': 'succeeded',
      'completedAt': 10,
      'output': {'attachments': []},
    },
  },
  'bodies': const [],
});

void main() {
  test(
    'timelineMarkdownPlainText strips markdown markers and folds newlines',
    () {
      expect(
        timelineMarkdownPlainText(
          '**First** `__code__`\r\n*em* ~~old~~ [Docs](https://example.com)',
        ),
        'First code em old Docs',
      );
      expect(
        timelineMarkdownPlainText('**A****B** read_file'),
        'A B read_file',
      );
    },
  );

  test('workGroupMemberRegistry registers all adapters and rejects duplicate kinds', () {
    expect(workGroupMemberRegistry.adapters.length, 7);
    expect(
      workGroupMemberRegistry.exactKinds,
      containsAll(WorkGroupMemberKind.values),
    );
    expect(
      () => WorkGroupMemberRegistry(
        adapters: const [ReasoningMemberItem(), ReasoningMemberItem()],
      ),
      throwsArgumentError,
    );

    expect(
      workGroupMemberRegistry.resolveForMember(
        const WorkGroupReasoning(
          id: 'r1',
          seq: 1,
          text: '',
          summary: 'Plan',
          outcome: 'completed',
        ),
      ),
      isA<ReasoningMemberItem>(),
    );
    expect(
      workGroupMemberRegistry.resolveForMember(
        WorkGroupToolCall(
          id: 't1',
          seq: 2,
          callId: 'c1',
          toolName: 'exec',
          status: 'running',
          summary: 'exec',
          payloadJson: '{}',
          bodies: const [],
        ),
      ),
      isA<ToolMemberItem>(),
    );
    expect(
      workGroupMemberRegistry.resolveForMember(
        WorkGroupToolCall(
          id: 't2',
          seq: 3,
          callId: 'c2',
          toolName: 'show_files',
          presentationContract: 'builtin.show_files@1',
          status: 'succeeded',
          summary: 'show_files',
          payloadJson: _showFilesEnvelope(),
          bodies: const [],
        ),
      ),
      isA<MediaToolMemberItem>(),
    );
    expect(
      workGroupMemberRegistry.resolveForMember(
        const WorkGroupAgent(
          id: 'a1',
          seq: 4,
          agentId: 'thread-1',
          name: 'reviewer',
          status: 'running',
          summary: 'review diff',
          payloadJson: '{}',
        ),
      ),
      isA<AgentMemberItem>(),
    );
    expect(
      workGroupMemberRegistry.resolveForMember(
        WorkGroupFileChange(
          id: 'f1',
          seq: 5,
          summary: 'lib/main.dart',
          payloadJson: '{}',
          bodies: const [],
        ),
      ),
      isA<FileChangeMemberItem>(),
    );
    expect(
      workGroupMemberRegistry.resolveForMember(
        const WorkGroupSkill(
          id: 's1',
          seq: 6,
          name: 'add-tool',
          summary: 'add-tool',
          payloadJson: '{}',
        ),
      ),
      isA<SkillMemberItem>(),
    );
    expect(
      workGroupMemberRegistry.resolveForMember(
        const WorkGroupFallback(
          id: 'fb1',
          seq: 7,
          eventId: 'e1',
          eventKind: 'custom',
          reason: 'unsupported',
        ),
      ),
      isA<FallbackWorkGroupMemberItem>(),
    );
  });

  testWidgets(
    'ReasoningMemberItem renders markdown summary, duration, and clean tooltip',
    (tester) async {
      await tester.pumpWidget(
        _host(
          WorkGroupMemberView(
            isLive: true,
            member: const WorkGroupReasoning(
              id: 'r1',
              seq: 1,
              text: 'Body **details**',
              summary: '**Phase A****Phase B**',
              outcome: 'completed',
              startedAtMs: 1000,
              finishedAtMs: 3000,
            ),
            bodyBuilder: (id, text) => TimelineMarkdown(
              id: id,
              text: text,
              onLink: (_) {},
              isSafeLink: (_) => false,
              imageBuilder: (_, url) => Text(url),
            ),
          ),
        ),
      );

      expect(find.byType(TimelineReasoningView), findsOneWidget);
      expect(find.byType(TimelineReasoningSummary), findsOneWidget);
      expect(find.textContaining('思考 ·'), findsNothing);
      expect(find.byIcon(Icons.psychology_alt_outlined), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      expect(find.text('用时 2 秒'), findsOneWidget);

      final row = tester.widget<TimelineActivityRow>(
        find.byType(TimelineActivityRow),
      );
      expect(row.label, 'Phase A Phase B');
      expect(row.tooltip, isNull);
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'Phase A Phase B\n用时 2 秒');

      await tester.tap(find.byType(TimelineActivityRow));
      await tester.pumpAndSettle();
      expect(find.text('Body details', findRichText: true), findsOneWidget);
    },
  );

  testWidgets(
    'ToolMemberItem reuses TimelineToolItemView and shows live tail in body',
    (tester) async {
      await tester.pumpWidget(
        _host(
          WorkGroupMemberView(
            isLive: true,
            now: () => DateTime.fromMillisecondsSinceEpoch(3000, isUtc: true),
            member: WorkGroupToolCall(
              id: 'call:1',
              seq: 1,
              callId: '1',
              toolName: 'exec',
              presentationContract: 'builtin.exec@2',
              status: 'running',
              summary: 'exec',
              arguments: '{"command":"cargo test"}',
              resultPreview: '[stderr] compiling crate',
              payloadJson: '{}',
              bodies: const [],
              startedAtMs: 1000,
            ),
          ),
        ),
      );

      expect(find.byType(TimelineToolItemView), findsOneWidget);
      expect(find.text('正在运行 cargo test'), findsOneWidget);
      expect(find.text('用时 2 秒'), findsOneWidget);
      expect(find.textContaining('[stderr]'), findsNothing);

      await tester.tap(find.byType(TimelineActivityRow));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(StudioCodeBlock), findsOneWidget);
      expect(find.textContaining('[stderr] compiling crate'), findsOneWidget);
    },
  );

  testWidgets('MediaToolMemberItem routes to attachmentBuilder when provided', (
    tester,
  ) async {
    ChatItemPresentation? captured;
    await tester.pumpWidget(
      _host(
        WorkGroupMemberView(
          member: WorkGroupToolCall(
            id: 'call:media',
            seq: 1,
            callId: 'media',
            toolName: 'show_files',
            presentationContract: 'builtin.show_files@1',
            status: 'succeeded',
            summary: 'show_files',
            payloadJson: _showFilesEnvelope(),
            bodies: const [],
          ),
          attachmentBuilder: (item) {
            captured = item;
            return const Text('media-attachment-widget');
          },
        ),
      ),
    );

    expect(captured, isNotNull);
    expect(find.text('media-attachment-widget'), findsOneWidget);
  });

  testWidgets(
    'AgentMemberItem hides raw thread IDs and keeps category/issue icons',
    (tester) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              WorkGroupMemberView(
                member: WorkGroupAgent(
                  id: 'a1',
                  seq: 1,
                  agentId: 'thread-66137d7bee82c-14',
                  name: 'thread-66137d7bee82c-14',
                  status: 'completed',
                  summary: '审查阶段 B 变更',
                  payloadJson: jsonEncode({
                    'contract': 'anywork.event/1',
                    'type': 'agent',
                    'data': {
                      'identity': {
                        'role': 'reviewer',
                        'taskSummary': '审查阶段 B 变更',
                      },
                      'outcome': {'kind': 'completed'},
                    },
                  }),
                  startedAtMs: 1000,
                  finishedAtMs: 4000,
                ),
              ),
              const WorkGroupMemberView(
                member: WorkGroupAgent(
                  id: 'a2',
                  seq: 2,
                  agentId: 'thread-999999999999-1',
                  name: 'thread-999999999999-1',
                  status: 'failed',
                  summary: 'thread-999999999999-1',
                  payloadJson: '{}',
                ),
              ),
            ],
          ),
        ),
      );

      expect(find.byType(StudioCompactChip), findsOneWidget);
      expect(find.text('reviewer'), findsOneWidget);
      expect(find.text('审查阶段 B 变更'), findsOneWidget);
      expect(find.text('用时 3 秒'), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);

      expect(find.text('子智能体失败 · 子智能体'), findsOneWidget);
      expect(find.textContaining('thread-999999999999-1'), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    },
  );

  testWidgets('FileChange, Skill, and Fallback render clean single-line rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            WorkGroupMemberView(
              member: WorkGroupFileChange(
                id: 'f1',
                seq: 1,
                summary: 'lib/foo.dart',
                payloadJson: '{}',
                bodies: const [],
              ),
            ),
            const WorkGroupMemberView(
              member: WorkGroupSkill(
                id: 's1',
                seq: 2,
                name: 'add-tool',
                summary: 'add-tool',
                payloadJson: '{}',
              ),
            ),
            const WorkGroupMemberView(
              member: WorkGroupFallback(
                id: 'fb1',
                seq: 3,
                eventId: 'ev-1',
                eventKind: 'unknownEvent',
                reason: 'unrecognized payload',
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.text('修改文件 · lib/foo.dart'), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);

    expect(find.text('激活技能 · add-tool'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);

    expect(find.text('unknownEvent · unrecognized payload'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });
}
