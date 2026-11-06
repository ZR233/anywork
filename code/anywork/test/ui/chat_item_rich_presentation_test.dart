import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_children_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_payload_reading.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
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
}) => ChatItemPresentation.decodePayload(
  id,
  InlinePayload(
    bytes: utf8.encode(
      jsonEncode({
        'contract': 'anywork.chat/1',
        'type': type,
        'data': data,
        'bodies': bodies,
      }),
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
    'Main tool Status keeps its original unit and discloses Item-owned ranges in live and history',
    (tester) async {
      final tool = _tool('builtin.exec@2');
      for (final live in [true, false]) {
        final mode = live ? 'live' : 'history';
        final contentItemId = 'original-main-result-$mode';
        final owner = ItemContentOwner(itemId: contentItemId);
        final arguments = ContentRef(
          databaseId: 'main-status-db',
          target: BodyContentTarget(owner: owner, key: 'tool.arguments'),
        );
        final output = ContentRef(
          databaseId: 'main-status-db',
          target: BodyContentTarget(owner: owner, key: 'tool.result'),
        );
        final unit = TimelineDisplayUnit(
          live: live,
          item: TimelineItem(
            id: 'status:main-result-$mode',
            kind: TimelineItemKind.status,
            source: BackgroundResultChatSource(messageId: 'result-$mode'),
            atomKind: ChatAtomKind.toolCall,
            delivery: ChatDeliveryKind.independent,
            outcome: ChatTerminalOutcome.completed,
            turnId: 'original-turn',
            contentItemId: contentItemId,
            payload: InlinePayload(bytes: utf8.encode(tool.raw!)),
            contents: [
              ChatAtomContent(
                role: ChatContentRole.toolArguments,
                reference: arguments,
              ),
              ChatAtomContent(
                role: ChatContentRole.toolOutput,
                reference: output,
              ),
            ],
            admissionClosed: true,
          ),
        );
        final item = ChatItemPresentation.forUnit(unit);
        expect(item.displayUnit, same(unit));
        expect(item.atom, isNull);
        expect(item.compatibility, ChatItemCompatibility.current);
        expect(item.type, 'tool');
        final declared = {
          ChatContentRole.toolArguments.name: arguments,
          ChatContentRole.toolOutput.name: output,
        };
        final requests = <({String id, String key, ContentRef reference})>[];
        await tester.pumpWidget(
          _host(
            ChatItemView(
              key: ValueKey(unit.id),
              item: item,
              contentRangeBuilder: (id, key, label, reference, witness) {
                expect(id, unit.id);
                expect(declared, contains(key));
                expect(reference, same(declared[key]));
                // Observe renderer wiring only; this builder does not read IO.
                requests.add((id: id, key: key, reference: reference));
                return Text('declared:$key');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TimelineToolDetails), findsOneWidget);
        final rendered = tester.widget<TimelineToolDetails>(
          find.byType(TimelineToolDetails),
        );
        expect(rendered.item.toolCallId, 'call');
        expect(rendered.item.statusString, 'succeeded');
        for (final key in declared.keys) {
          expect(find.text('declared:$key'), findsNothing);
        }
        await tester.tap(_rowTap);
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(TimelineToolDetails)),
        );
        expect(
          find.textContaining(l10n.timelineToolExitCode(0)),
          findsOneWidget,
        );
        for (final key in declared.keys) {
          expect(find.text('declared:$key'), findsOneWidget);
        }
        expect(
          requests.map((request) => request.key).toSet(),
          declared.keys.toSet(),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        unit.expansion.retirement.dispose();
        unit.expansion.dispose();
      }
    },
  );

  testWidgets(
    'declared tool bodies preserve diagnostics and successful workflow payload hiding',
    (tester) async {
      for (final hidden in [false, true]) {
        final item = _tool(
          hidden ? 'builtin.workflow_transition@1' : 'builtin.exec@2',
          name: hidden ? 'workflow_transition' : 'exec',
        );
        await tester.pumpWidget(
          _host(
            TimelineToolDetails(
              key: ValueKey(hidden),
              item: (item.toolCard as DecodedToolCard).value,
              initiallyExpanded: true,
              declaredContents: const [Text('declared internal body')],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('declared internal body'),
          hidden ? findsNothing : findsOneWidget,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(TimelineToolDetails)),
        );
        expect(
          find.textContaining(l10n.timelineToolExitCode(0)),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'Turn completion, failure and stop preserve distinct semantics without invented meta',
    (tester) async {
      for (final (outcome, icon) in [
        ('completed', Icons.account_tree_outlined),
        ('failed', Icons.error_outline),
        ('cancelled', Icons.stop_circle_outlined),
        ('interrupted', Icons.stop_circle_outlined),
      ]) {
        await _show(
          tester,
          _item('terminal-$outcome', 'turn', {
            'outcome': {'kind': outcome},
          }),
        );
        expect(find.byIcon(icon), findsOneWidget, reason: outcome);
        final row = tester.widget<TimelineActivityRow>(
          find.byType(TimelineActivityRow),
        );
        expect(row.meta, isNull);
        expect(find.text('0s'), findsNothing);
        expect(find.byType(Card), findsNothing);
        expect(
          tester
              .widget<ExpansionTile>(find.byType(ExpansionTile))
              .showTrailingIcon,
          isFalse,
        );
      }
    },
  );

  testWidgets(
    'collapsed history processes keep the compact row height and grow with text scale',
    (tester) async {
      final cases = [
        (_item('compact-thinking', 'thinking', {}), 28.0),
        // One call has one semantic disclosure, including all public details.
        (_tool('builtin.exec@2'), 28.0),
        (
          _item('compact-plan', 'plan', {
            'decision': 'approved',
            'documentVersion': 3,
          }),
          28.0,
        ),
      ];
      for (final (item, compactHeight) in cases) {
        for (final scale in [1.0, 2.5]) {
          await tester.pumpWidget(
            _host(
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: ChatItemView(key: ValueKey(item.id), item: item),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final height = tester
              .getSize(find.byKey(ValueKey('chat-item:${item.id}')))
              .height;
          expect(
            height,
            scale == 1
                ? closeTo(compactHeight, .01)
                : greaterThan(compactHeight),
            reason: '${item.type} at text scale $scale',
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'only exact current marker enables specialized command parsing; generic and unknown preserve public original',
    (tester) async {
      await _show(tester, _tool('builtin.exec@2', name: 'untrusted name'));
      expect(find.byType(TimelineToolDetails), findsOneWidget);
      final row = tester.widget<TimelineActivityRow>(
        find.descendant(
          of: find.byType(TimelineToolDetails),
          matching: find.byType(TimelineActivityRow),
        ),
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
            find.descendant(
              of: find.byType(TimelineToolDetails),
              matching: find.byType(TimelineActivityRow),
            ),
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
          find.descendant(
            of: find.byType(TimelineToolDetails),
            matching: find.byType(TimelineActivityRow),
          ),
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
            .widget<TimelineActivityRow>(find.byType(TimelineActivityRow).first)
            .label,
        isNotEmpty,
      );
      expect(find.textContaining('bounded summary'), findsOneWidget);
      expect(find.text('reasoning proof'), findsOneWidget);
      expect(
        tester
            .widget<TimelineActivityRow>(find.byType(TimelineActivityRow).first)
            .expandable,
        isFalse,
        reason: 'Opening the parent group already exposes the thinking content',
      );
      final cases = <(String, Map<String, Object?>, IconData)>[
        (
          'skill',
          {
            'activation': {'name': 'test skill', 'source': 'project'},
          },
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
      expect(find.byType(Card), findsNothing);
      expect(find.text('计划已批准'), findsOneWidget);
      expect(find.text('plan proof'), findsNothing);
      await tester.tap(find.text('计划已批准'));
      await tester.pumpAndSettle();
      expect(find.text('plan proof'), findsOneWidget);
    },
  );

  testWidgets(
    'completed compaction is a static single-line receipt, not another process disclosure',
    (tester) async {
      await _show(
        tester,
        _item('compaction', 'contextCompaction', {
          'beforeTokens': 50,
          'afterTokens': 20,
        }),
      );
      expect(find.text('已完成压缩'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      final row = tester.widget<TimelineActivityRow>(
        find.byType(TimelineActivityRow),
      );
      expect(row.active, isFalse);
      expect(row.meta, isNull);
      expect(find.textContaining('tokens'), findsNothing);
    },
  );

  testWidgets('Turn receipt never opens an entire Turn as a work group', (
    tester,
  ) async {
    final turn = _item('turn', 'turn', {
      'outcome': {'kind': 'failed'},
      'childrenParentId': 'opaque-parent',
    });
    await tester.pumpWidget(_host(ChatItemView(item: turn)));
    await tester.pumpAndSettle();
    expect(find.byType(TimelineChildrenConnector), findsNothing);
    await tester.tap(_rowTap);
    await tester.pumpAndSettle();
    expect(find.byType(TimelineChildrenConnector), findsNothing);
    await tester.tap(_rowTap);
    await tester.pumpAndSettle();
    expect(find.byType(TimelineChildrenConnector), findsNothing);
  });

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
                {'id': 'public', 'isSecret': false, 'optionCount': 2},
                {'id': 'secret', 'isSecret': true, 'optionCount': 0},
              ],
              'state': {
                'kind': 'resolved',
                'answers': [
                  {'questionId': 'secret', 'redacted': true, 'answerCount': 1},
                  {'questionId': 'public', 'redacted': false, 'answerCount': 2},
                ],
              },
            },
          },
          bodies: [
            _body('tool.arguments', '{}'),
            _body('tool.user-input.answer.0.0', 'public answer'),
            _body(
              'tool.user-input.question.0.option.1.description',
              'second detail',
            ),
            _body('tool.user-input.question.0.option.0.label', 'first option'),
            _body('tool.user-input.question.0.body', 'public prompt'),
            _body('tool.user-input.answer.0.1', 'second answer'),
            _body('tool.user-input.question.0.header', 'public question'),
            _body('tool.user-input.question.0.option.1.label', 'second option'),
            _body(
              'tool.user-input.question.0.option.0.description',
              'first detail',
            ),
            _body('tool.user-input.answer.1.0', 'SECRET'),
          ],
        ),
      );
      expect(find.text('public question'), findsNothing);
      await tester.tap(
        find.byKey(StudioDriverKeys.timelineUserInput('tool:generic@1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('public question'), findsOneWidget);
      expect(find.text('public answer'), findsOneWidget);
      final ordered = [
        'public question',
        'public prompt',
        '可选项',
        'first option',
        'first detail',
        'second option',
        'second detail',
        '实际回答',
        'public answer',
        'second answer',
      ];
      for (var index = 1; index < ordered.length; index++) {
        expect(
          tester.getTopLeft(find.text(ordered[index])).dy,
          greaterThan(tester.getTopLeft(find.text(ordered[index - 1])).dy),
        );
      }
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
