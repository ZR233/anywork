import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _body(String key, String text) => {
  'key': key,
  'byteLength': utf8.encode(text).length,
  'inline': utf8.encode(text),
};
ChatItemPresentation _item(
  String id,
  String type,
  Map<String, Object?> data, {
  List<Map<String, Object?>> bodies = const [],
}) => ChatItemPresentation.decode(
  ChatMessage(
    id: id,
    payload: InlinePayload(
      bytes: utf8.encode(
        jsonEncode({
          'contract': 'anywork.chat/1',
          'type': type,
          'data': data,
          'bodies': bodies,
        }),
      ),
    ),
  ),
);
ChatItemPresentation _tool(
  String? marker, {
  String arguments = '{"command":"printf proof"}',
  String name = 'exec',
  Map<String, Object?> extra = const {},
  List<Map<String, Object?>>? bodies,
}) => _item(
  'tool:$marker',
  'tool',
  {
    'invocation': {
      'toolCallId': 'call',
      'name': name,
      'presentationContract': marker,
    },
    'state': {
      'kind': 'succeeded',
      'completedAt': 12,
      'output': {'exitCode': 0, 'attachments': []},
    },
    ...extra,
  },
  bodies:
      bodies ??
      [
        _body('tool.arguments', arguments),
        _body('tool.result', 'public result'),
      ],
);
Widget _host(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
Future<void> _show(WidgetTester tester, ChatItemPresentation item) async {
  await tester.pumpWidget(
    _host(ChatItemView(key: ValueKey(item.id), item: item)),
  );
  await tester.pumpAndSettle();
}

Finder get _rowTap => find
    .ancestor(
      of: find.byType(TimelineActivityRow),
      matching: find.byType(InkWell),
    )
    .first;

void main() {
  testWidgets(
    'only exact current marker enables specialized command parsing; generic and unknown preserve public original',
    (tester) async {
      await _show(tester, _tool('builtin.exec@2', name: 'untrusted name'));
      expect(find.byType(TimelineToolDetails), findsOneWidget);
      final row = tester.widget<TimelineActivityRow>(
        find.byType(TimelineActivityRow),
      );
      expect(row.icon, Icons.terminal);
      expect(row.label, contains('printf proof'));
      for (final marker in [
        'generic@1',
        null,
        'builtin.exec@1',
        'builtin.exec@99',
        'arbitrary',
      ]) {
        await _show(tester, _tool(marker));
        if (marker == 'generic@1') {
          final generic = tester.widget<TimelineActivityRow>(
            find.byType(TimelineActivityRow),
          );
          expect(generic.icon, Icons.build_outlined);
          expect(generic.label, isNot(contains('printf proof')));
          await tester.tap(_rowTap);
        } else {
          expect(find.byType(TimelineToolDetails), findsNothing);
          await tester.tap(find.text('exec · 未知展示格式'));
        }
        await tester.pumpAndSettle();
        expect(find.textContaining('printf proof'), findsWidgets);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'tool families reuse existing semantic cards and disclose current argument/result fields',
    (tester) async {
      final cases = <(String, String, IconData)>[
        ('stat_path', '{"path":"src/proof.dart"}', Icons.menu_book_outlined),
        (
          'write_file',
          '{"path":"src/proof.dart","content":"proof"}',
          Icons.edit_outlined,
        ),
        ('search_session_note', '{"query":"needle"}', Icons.search),
        ('copy_path', '{"from":"a","to":"b"}', Icons.content_copy_outlined),
        (
          'send_message',
          '{"agentId":"child","message":"proof"}',
          Icons.send_outlined,
        ),
        (
          'lsp_query',
          '{"languageId":"dart","filePath":"proof.dart","operation":"hover"}',
          Icons.code,
        ),
        ('plan_current', '{}', Icons.checklist_rtl),
        ('workflow_current', '{}', Icons.route_outlined),
      ];
      for (final (name, arguments, icon) in cases) {
        await _show(
          tester,
          _tool('builtin.$name@1', arguments: arguments, name: name),
        );
        expect(find.byType(TimelineToolDetails), findsOneWidget, reason: name);
        final row = tester.widget<TimelineActivityRow>(
          find.byType(TimelineActivityRow),
        );
        expect(row.icon, icon, reason: name);
        await tester.tap(_rowTap);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('public result'),
          findsWidgets,
          reason: name,
        );
        expect(tester.takeException(), isNull, reason: name);
      }
      await _show(
        tester,
        _tool(
          'builtin.web_search@1',
          arguments: '{"search_query":[{"q":"actual query"}]}',
        ),
      );
      expect(find.byType(TimelineWebSearchToolCard), findsOneWidget);
      await tester.tap(_rowTap);
      await tester.pumpAndSettle();
      expect(find.textContaining('actual query'), findsWidgets);
      await _show(
        tester,
        _tool(
          'builtin.sleep@1',
          arguments: '{"durationMs":20}',
          extra: {
            'wait': {
              'state': 'elapsed',
              'intent': {
                'kind': 'timer',
                'data': {'durationMs': 20},
              },
            },
          },
        ),
      );
      expect(find.byType(TimelineWaitPanel), findsOneWidget);
    },
  );

  testWidgets(
    'malformed known tool stays local and reveals legitimate original; missing arguments is not a specialized card',
    (tester) async {
      final bad = _tool('builtin.exec@2', arguments: 'not json');
      final neighbor = _item(
        'neighbor',
        'text',
        {'channel': 'final'},
        bodies: [_body('body', 'neighbor proof')],
      );
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              ChatItemView(item: bad),
              ChatItemView(item: neighbor),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('exec · 内容格式错误'), findsOneWidget);
      expect(find.byType(TimelineToolDetails), findsNothing);
      expect(find.text('neighbor proof'), findsOneWidget);
      await tester.tap(find.text('exec · 内容格式错误'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not json'), findsWidgets);
      await _show(tester, _tool('builtin.exec@2', bodies: []));
      expect(find.byType(TimelineToolDetails), findsNothing);
      expect(find.text('exec · 内容格式错误'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'thinking summary, plan receipt and every non-tool kind retain semantic presentation without item grouping',
    (tester) async {
      await _show(
        tester,
        _item(
          'thinking',
          'thinking',
          {
            'outcome': {'kind': 'completed'},
          },
          bodies: [
            _body('part.summaryText.0', '**bounded summary**'),
            _body('part.reasoningText.0', 'reasoning proof'),
          ],
        ),
      );
      expect(
        tester
            .widget<TimelineActivityRow>(find.byType(TimelineActivityRow))
            .label,
        contains('bounded summary'),
      );
      expect(find.text('reasoning proof'), findsNothing);
      await tester.tap(_rowTap);
      await tester.pumpAndSettle();
      expect(find.text('reasoning proof'), findsOneWidget);
      final cases = <(String, Map<String, Object?>, IconData)>[
        (
          'skill',
          {'name': 'test skill', 'source': 'project'},
          Icons.auto_awesome_outlined,
        ),
        ('file', {'path': 'test.dart'}, Icons.description_outlined),
        (
          'agent',
          {
            'identity': {'role': 'executor'},
            'outcome': {
              'kind': 'failed',
              'data': {'message': 'agent diagnostic'},
            },
          },
          Icons.smart_toy_outlined,
        ),
        (
          'inference',
          {
            'model': 'model',
            'outcome': {'kind': 'cancelled'},
          },
          Icons.model_training_outlined,
        ),
        (
          'contextCompaction',
          {'beforeTokens': 50, 'afterTokens': 20},
          Icons.compress_outlined,
        ),
        ('raw', {'notice': 'raw diagnostic'}, Icons.data_object_outlined),
      ];
      for (final (type, data, icon) in cases) {
        await _show(
          tester,
          _item(type, type, data, bodies: [_body('body', 'public $type')]),
        );
        expect(
          tester
              .widget<TimelineActivityRow>(find.byType(TimelineActivityRow))
              .icon,
          icon,
        );
        await tester.tap(_rowTap);
        await tester.pumpAndSettle();
        expect(find.text('公开原始记录'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: type);
      }
      await _show(
        tester,
        _item(
          'plan',
          'plan',
          {'decision': 'approved'},
          bodies: [_body('plan.document', 'plan proof')],
        ),
      );
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('plan proof'), findsOneWidget);
    },
  );

  testWidgets(
    'terminal children mount only while expanded and use the real opaque parent',
    (tester) async {
      final turn = _item('turn', 'turn', {
        'outcome': {'kind': 'failed'},
        'childrenParentId': 'opaque-parent',
      });
      var mounts = 0;
      var disposes = 0;
      await tester.pumpWidget(
        _host(
          ChatItemView(
            item: turn,
            childrenBuilder: (parent) {
              expect(parent, 'opaque-parent');
              return _Mount(
                onMount: () => mounts++,
                onDispose: () => disposes++,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(mounts, 0);
      await tester.tap(_rowTap);
      await tester.pumpAndSettle();
      expect(mounts, 1);
      await tester.tap(_rowTap);
      await tester.pumpAndSettle();
      expect(disposes, 1);
    },
  );

  testWidgets(
    'user-input receipt uses public manifest and suppresses secret/redacted answers',
    (tester) async {
      await _show(
        tester,
        _tool(
          'generic@1',
          extra: {
            'userInput': {
              'questions': [
                {'id': 'public', 'isSecret': false},
                {'id': 'secret', 'isSecret': true},
              ],
              'state': {
                'kind': 'resolved',
                'answers': [
                  {'questionId': 'secret', 'redacted': true},
                ],
              },
            },
          },
          bodies: [
            _body('tool.arguments', '{}'),
            _body('tool.user-input.question.0.header', 'public question'),
            _body('tool.user-input.answer.0.0', 'public answer'),
            _body('tool.user-input.answer.1.0', 'SECRET'),
          ],
        ),
      );
      expect(find.text('public question'), findsOneWidget);
      expect(find.text('public answer'), findsOneWidget);
      expect(find.text('敏感内容已隐藏'), findsOneWidget);
      expect(find.text('SECRET'), findsNothing);
      await tester.ensureVisible(find.text('公开原始记录'));
      await tester.tap(find.text('公开原始记录'));
      await tester.pumpAndSettle();
      expect(find.text('SECRET'), findsNothing);
      expect(find.text('敏感字段已隐藏，仅展示公开 metadata'), findsOneWidget);
    },
  );

  testWidgets(
    'image attachment remains inside custom row, reads once, opens original and exposes real failures',
    (tester) async {
      final resources = TimelineImageResources(threadId: 'thread');
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      );
      final item = _item(
        'image',
        'text',
        {
          'channel': 'user',
          'attachments': [
            {
              'id': 'image',
              'modality': 'image',
              'mediaType': 'image/png',
              'byteSize': png.length,
              'filename': 'proof.png',
            },
            {
              'id': 'file',
              'modality': 'file',
              'mediaType': 'text/plain',
              'byteSize': 3,
              'filename': 'proof.txt',
            },
          ],
        },
        bodies: [_body('body', '**markdown proof**')],
      );
      var reads = 0;
      var active = true;
      Widget row() => _host(
        ChatItemView(
          item: item,
          bodyBuilder: (id, text) => TimelineMarkdown(
            id: id,
            text: text,
            onLink: (_) {},
            isSafeLink: (_) => false,
            imageBuilder: (_, url) => Text(url),
          ),
          attachmentBuilder: (item) => TimelineAttachmentsConnector(
            item: item,
            resources: resources,
            isActive: () => active,
            readAttachment: (id) async {
              reads++;
              return png;
            },
          ),
        ),
      );
      await tester.pumpWidget(row());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('proof.txt'), findsOneWidget);
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(reads, 1);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      active = false;
      await tester.pumpWidget(const SizedBox());
      resources.release();
      expect(tester.takeException(), isNull);

      final failedResources = TimelineImageResources(threadId: 'failed');
      await tester.pumpWidget(
        _host(
          TimelineAttachmentsConnector(
            item: item,
            resources: failedResources,
            isActive: () => true,
            readAttachment: (id) async =>
                throw StateError('attachment database missing'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('attachment database missing'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      failedResources.release();
    },
  );
}

class _Mount extends StatefulWidget {
  const _Mount({required this.onMount, required this.onDispose});
  final VoidCallback onMount, onDispose;
  @override
  State<_Mount> createState() => _MountState();
}

class _MountState extends State<_Mount> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('children');
}
