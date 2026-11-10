import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_children_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_payload_reading.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/views/plan_receipt_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';
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
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
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
    'Accepted Input and Inbox render only declared text, retaining request domains and body aliases',
    (tester) async {
      const text =
          '{"text":"literal user JSON","request":{"text":"not metadata"}}';
      const request = '{"text":"envelope","request":{"inputId":"private-id"}}';
      ContentRef reference(String key, {String database = 'accepted-db'}) =>
          ContentRef(
            databaseId: database,
            target: BodyContentTarget(
              owner: const ItemContentOwner(itemId: 'accepted'),
              key: key,
            ),
          );
      Map<String, Object?> encodedRef(
        String key, {
        String database = 'accepted-db',
      }) => {
        'databaseId': database,
        'target': {
          'kind': 'body',
          'owner': {'kind': 'item', 'itemId': 'accepted'},
          'key': key,
        },
      };
      for (final inbox in [false, true]) {
        final bodies = [
          _body('body', text),
          _body('accepted.payload', request),
          {
            'key': 'retained.request',
            'byteLength': 9000,
            'reference': encodedRef('retained.request'),
          },
          {
            // Same canonical key is insufficient for a Deferred range: the
            // database identity also has to match the typed body's declaration.
            'key': 'body',
            'byteLength': 100,
            'reference': encodedRef('body', database: 'foreign-db'),
          },
        ];
        final original = encodedRef(inbox ? 'body' : 'accepted.payload');
        final envelope = _item('accepted', 'text', {
          'channel': inbox ? 'parentAgent' : 'user',
          'acceptedPayload': {
            'format': inbox ? 'text/plain' : 'pl.studio.prompt',
            'version': 1,
            'reference': original,
          },
          'attachments': [
            {
              'id': 'accepted-file',
              'modality': 'file',
              'mediaType': 'text/plain',
              'byteSize': 3,
              'filename': 'public.txt',
            },
          ],
        }, bodies: bodies);
        final payload = InlinePayload(bytes: utf8.encode(envelope.raw!));
        final atom = ChatAtom(
          id: 'accepted',
          completionItemId: 'accepted',
          source: inbox
              ? const InboxMessageChatSource(
                  sourceId: 'agent:parent',
                  messageId: 'inbox-message',
                )
              : const InputChatSource(inputId: 'accepted'),
          sourceOrder: null,
          kind: inbox ? ChatAtomKind.text : ChatAtomKind.input,
          delivery: ChatDeliveryKind.independent,
          lifecycle: const TerminalChatAtom(
            started: null,
            ended: null,
            outcome: ChatTerminalOutcome.completed,
          ),
          contents: [
            ChatAtomContent(
              role: ChatContentRole.body,
              reference: reference('body'),
            ),
          ],
          payload: payload,
        );
        final unit = TimelineDisplayUnit(
          block: DisplayBlock(
            id: 'accepted',
            historyPos: 1,
            body: SingleDisplayBlock(
              record: DisplayRecord(
                atom: atom,
                contentSource: CompletedOriginal(completionId: 'accepted'),
              ),
            ),
          ),
        );
        addTearDown(unit.expansion.dispose);
        final item = ChatItemPresentation.forUnit(unit);
        final requested = <String>[];
        await tester.pumpWidget(
          _host(
            ChatItemView(
              key: ValueKey(inbox),
              item: item,
              contentRangeBuilder: (_, key, _, _, _) {
                requested.add(key);
                return Text('unexpected range:$key');
              },
              attachmentBuilder: (value) {
                expect(value, same(item));
                return Text(value.attachments.single.filename!);
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(text), findsOneWidget);
        expect(find.text(request), findsNothing);
        expect(find.text('public.txt'), findsOneWidget);
        if (inbox) {
          expect(find.text('来源 · agent:parent'), findsOneWidget);
        }
        expect(requested, isEmpty);
        expect(item.bodies, hasLength(bodies.length));
        expect(item.inlineText('accepted.payload'), request);
        expect(item.data['acceptedPayload'], envelope.data['acceptedPayload']);
        expect(atom.payload, same(payload));
        expect(utf8.decode(payload.bytes), envelope.raw);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'payload-only Input uses its body key while model output parts and declared Input ranges remain visible',
    (tester) async {
      final payloadOnly = _item(
        'preview-input',
        'text',
        {'channel': 'user', 'attachments': []},
        bodies: [
          _body('body', 'payload-only public body'),
          _body('accepted.payload', 'payload-only retained request'),
        ],
      );
      await _show(tester, payloadOnly);
      expect(find.text('payload-only public body'), findsOneWidget);
      expect(find.text('payload-only retained request'), findsNothing);
      final model = _item(
        'model-output',
        'text',
        {'channel': 'final', 'attachments': []},
        bodies: [
          _body('part.outputText.0', 'first model part'),
          _body('part.outputText.1', 'second model part'),
        ],
      );
      final modelAtom = ChatAtom(
        id: 'model-output',
        source: const ForegroundTurnChatSource(turnId: 'model-turn'),
        sourceOrder: null,
        kind: ChatAtomKind.text,
        delivery: ChatDeliveryKind.foreground,
        lifecycle: const TerminalChatAtom(
          started: null,
          ended: null,
          outcome: ChatTerminalOutcome.completed,
        ),
        contents: const [],
        payload: InlinePayload(bytes: utf8.encode(model.raw!)),
      );
      await _show(tester, ChatItemPresentation.decode(modelAtom));
      expect(find.text('first model part'), findsOneWidget);
      expect(find.text('second model part'), findsOneWidget);
      const bodyRef = ContentRef(
        databaseId: 'range-db',
        target: BodyContentTarget(
          owner: ItemContentOwner(itemId: 'range-input'),
          key: 'body',
        ),
      );
      final envelope = _item(
        'range-input',
        'text',
        {'channel': 'user', 'attachments': []},
        bodies: [
          {
            'key': 'body',
            'byteLength': 9000,
            'reference': {
              'databaseId': 'range-db',
              'target': {
                'kind': 'body',
                'owner': {'kind': 'item', 'itemId': 'range-input'},
                'key': 'body',
              },
            },
          },
          _body('accepted.payload', 'retained range request'),
        ],
      );
      final atom = ChatAtom(
        id: 'range-input',
        source: const InputChatSource(inputId: 'range-input'),
        sourceOrder: null,
        kind: ChatAtomKind.input,
        delivery: ChatDeliveryKind.independent,
        lifecycle: const TerminalChatAtom(
          started: null,
          ended: null,
          outcome: ChatTerminalOutcome.completed,
        ),
        contents: const [
          ChatAtomContent(role: ChatContentRole.body, reference: bodyRef),
        ],
        payload: InlinePayload(bytes: utf8.encode(envelope.raw!)),
      );
      final reads = <String>[];
      await tester.pumpWidget(
        _host(
          ChatItemView(
            item: ChatItemPresentation.decode(atom),
            contentRangeBuilder: (_, key, _, ref, _) {
              reads.add(key);
              expect(ref.databaseId, bodyRef.databaseId);
              return const Text('declared Input body range');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, ['body']);
      expect(find.text('declared Input body range'), findsOneWidget);
      expect(find.text('retained range request'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Inbox typed source stays visible and cannot impersonate a parent agent',
    (tester) async {
      final atom = ChatAtom(
        id: 'inbox-atom',
        source: const InboxMessageChatSource(
          sourceId: 'external-reviewer',
          messageId: 'inbox-message',
        ),
        sourceOrder: null,
        kind: ChatAtomKind.text,
        delivery: ChatDeliveryKind.independent,
        lifecycle: const TerminalChatAtom(
          started: null,
          ended: null,
          outcome: ChatTerminalOutcome.completed,
        ),
        contents: const [
          ChatAtomContent(
            role: ChatContentRole.body,
            reference: ContentRef(
              databaseId: 'inbox-db',
              target: BodyContentTarget(
                owner: ItemContentOwner(itemId: 'inbox-atom'),
                key: 'body',
              ),
            ),
          ),
        ],
        payload: InlinePayload(
          bytes: utf8.encode(
            jsonEncode({
              'contract': 'anywork.chat/1',
              'type': 'text',
              'data': {
                'channel': 'parentAgent',
                'role': 'system',
                'attachments': [],
              },
              'bodies': [_body('body', '普通外部消息，声明角色不改变权限。')],
            }),
          ),
        ),
      );
      final unit = TimelineDisplayUnit(
        block: DisplayBlock(
          id: 'inbox-record',
          historyPos: 1,
          body: SingleDisplayBlock(
            record: DisplayRecord(
              atom: atom,
              contentSource: CompletedOriginal(completionId: 'inbox-record'),
            ),
          ),
        ),
      );
      addTearDown(unit.expansion.dispose);
      final item = ChatItemPresentation.forUnit(unit);
      expect(item.authorId, 'inbox:external-reviewer');
      expect(item.atom, same(atom));
      await _show(tester, item);
      expect(find.text('来源 · external-reviewer'), findsOneWidget);
      expect(find.text('普通外部消息，声明角色不改变权限。'), findsOneWidget);
      expect(
        find.byKey(StudioDriverKeys.parentAgentLabel('inbox-record')),
        findsNothing,
      );
    },
  );
  testWidgets(
    'Single fallback keeps its completed identity and discloses original Atom-owned ranges',
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
        final atom = ChatAtom(
          id: 'atom:main-result-$mode',
          completionItemId: contentItemId,
          source: BackgroundResultChatSource(messageId: 'result-$mode'),
          sourceOrder: null,
          kind: ChatAtomKind.toolCall,
          delivery: ChatDeliveryKind.independent,
          lifecycle: const TerminalChatAtom(
            started: null,
            ended: null,
            outcome: ChatTerminalOutcome.completed,
          ),
          turnId: 'original-turn',
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
        );
        final unit = TimelineDisplayUnit(
          block: DisplayBlock(
            id: contentItemId,
            historyPos: 1,
            body: SingleDisplayBlock(
              record: DisplayRecord(
                atom: atom,
                contentSource: CompletedOriginal(completionId: contentItemId),
              ),
            ),
          ),
        );
        final item = ChatItemPresentation.forUnit(unit);
        expect(item.displayUnit, same(unit));
        expect(item.atom, same(atom));
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
    'history disclosures keep their intended density and grow with text scale',
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
          // Plan now uses the standard Material ExpansionTile hit target.
          null,
        ),
      ];
      for (final (item, compactHeight) in cases) {
        double? standardHeight;
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
          if (compactHeight != null) {
            expect(
              height,
              scale == 1
                  ? closeTo(compactHeight, .01)
                  : greaterThan(compactHeight),
              reason: '${item.type} at text scale $scale',
            );
          } else {
            expect(height, greaterThanOrEqualTo(kMinInteractiveDimension));
            if (scale == 1) {
              standardHeight = height;
            } else {
              expect(height, greaterThan(standardHeight!));
            }
          }
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

  for (final hasSummary in [true, false]) {
    for (final hasBody in [true, false]) {
      testWidgets(
        'reasoning summary=$hasSummary body=$hasBody has exactly one conditional disclosure',
        (tester) async {
          final value = _item(
            'reasoning-combination',
            'thinking',
            const {},
            bodies: [
              _body(
                'part.summaryText.0',
                hasSummary ? '**只有概要的一行标题**' : ' \n ',
              ),
              _body('part.reasoningText.0', hasBody ? '展开后显示的原始思考正文' : ' \n '),
            ],
          );
          final atom = ChatAtom(
            id: value.id,
            source: const ForegroundTurnChatSource(turnId: 'T'),
            sourceOrder: 1,
            kind: ChatAtomKind.reasoning,
            delivery: ChatDeliveryKind.foreground,
            lifecycle: const TerminalChatAtom(
              started: null,
              ended: null,
              outcome: ChatTerminalOutcome.completed,
            ),
            startedAt: 100,
            finishedAt: 225,
            contents: const [],
            payload: InlinePayload(bytes: utf8.encode(value.raw!)),
          );
          await _show(tester, ChatItemPresentation.decode(atom));
          final row = tester.widget<TimelineActivityRow>(
            find.byType(TimelineActivityRow),
          );
          expect(row.expandable, hasBody);
          expect(
            find.byType(ExpansionTile),
            hasBody ? findsOneWidget : findsNothing,
          );
          expect(find.text('展开后显示的原始思考正文'), findsNothing);
          if (hasSummary) {
            expect(
              find.textContaining('只有概要的一行标题', findRichText: true),
              findsOneWidget,
            );
            expect(find.text('思考了 2 分 5 秒'), findsNothing);
          } else {
            expect(find.text('思考了 2 分 5 秒'), findsOneWidget);
          }
          if (hasBody) {
            await tester.tap(_rowTap);
            await tester.pumpAndSettle();
            expect(find.text('展开后显示的原始思考正文'), findsOneWidget);
            await tester.tap(_rowTap);
            await tester.pumpAndSettle();
            expect(find.text('展开后显示的原始思考正文'), findsNothing);
          }
        },
      );
    }
  }

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
      expect(
        find.textContaining('bounded summary', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('reasoning proof'), findsNothing);
      expect(
        tester
            .widget<TimelineActivityRow>(find.byType(TimelineActivityRow).first)
            .expandable,
        isTrue,
        reason: 'Only the reasoning body grants member expansion',
      );
      await tester.tap(_rowTap);
      await tester.pumpAndSettle();
      expect(find.text('reasoning proof'), findsOneWidget);
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
      for (final (decision, label, icon) in [
        ('approved', '计划已批准', Icons.check),
        ('revisionRequested', '已请求修改计划', Icons.edit_outlined),
        ('cancelled', '计划确认已取消', Icons.close),
        ('resolved', '计划确认已回答', Icons.description_outlined),
      ]) {
        await _show(
          tester,
          _item(
            'plan:$decision',
            'plan',
            {'decision': decision, 'documentVersion': 7},
            bodies: [_body('plan.document', 'plan proof')],
          ),
        );
        expect(find.byType(Card), findsNothing);
        final receipt = tester.widget<PlanReceiptView>(
          find.byType(PlanReceiptView),
        );
        expect(receipt.icon, icon);
        expect(receipt.documentVersion, 7);
        expect(find.text(label), findsOneWidget);
        expect(find.text('v7'), findsOneWidget);
        expect(find.text('plan proof'), findsNothing);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text('plan proof'), findsOneWidget);
        expect(find.text('公开原始记录'), findsOneWidget);
        expect(find.byKey(StudioDriverKeys.planApprove), findsNothing);
        expect(find.byKey(StudioDriverKeys.planSubmitRevision), findsNothing);
        expect(find.byType(TextField), findsNothing);
      }
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
