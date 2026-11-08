import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/interaction_details_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/plan_document_connector.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/features/conversation/interactions/state/interaction_payload.dart';
import 'package:anywork/src/features/conversation/interactions/views/user_input_view.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/src/conversation/data/conversation_read_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart' show chatWorkspace;

ContentRef _plan(int revision) => ContentRef(
  databaseId: 'database',
  target: BodyContentTarget(
    owner: CurrentContentOwner(
      domain: 'plan',
      id: 'thread',
      revision: revision,
    ),
    key: 'plan.document',
  ),
);
CurrentCollectionRef _interactions(int revision) => CurrentCollectionRef(
  databaseId: 'database',
  collection: 'interactions',
  revision: revision,
);
ContentWindow _window(String text) => ContentWindow(
  offset: 0,
  bytes: utf8.encode(text),
  generation: 'original-resource',
  availableThrough: utf8.encode(text).length,
  sealed: true,
);
CurrentCollectionPage _page(
  int revision,
  String title, {
  String? next,
  Map<String, Object?>? request,
}) => CurrentCollectionPage(
  revision: revision,
  entries: [
    CurrentCollectionEntry(
      id: title,
      position: 0,
      payload: InlinePayload(
        bytes: utf8.encode(
          jsonEncode(
            request ??
                {
                  'interactionId': title,
                  'scope': {'threadId': 'thread', 'turnId': 'turn'},
                  'revision': revision,
                  'content': {
                    'kind': 'userInput',
                    'data': {
                      'questions': [
                        {
                          'id': 'public',
                          'header': title,
                          'question': '只读详情',
                          'isOther': true,
                          'isSecret': false,
                        },
                        {
                          'id': 'secret',
                          'header': '不可展示的原始字段',
                          'question': '不可展示的敏感问题',
                          'isSecret': true,
                        },
                      ],
                      'state': {
                        'kind': 'resolved',
                        'data': {
                          'operationId': 'resolved-question',
                          'answers': {
                            'secret': {
                              'answers': ['不可展示的敏感答案'],
                            },
                          },
                          'resolvedAt': 2,
                        },
                      },
                    },
                  },
                  'createdAt': 1,
                  'updatedAt': 2,
                },
          ),
        ),
      ),
    ),
  ],
  continuation: next,
);
Widget _host(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (context) => DecoratedBox(
        // Match the opaque composer footer between Scaffold and the details.
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
        child: SingleChildScrollView(child: child),
      ),
    ),
  ),
);
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

const _detailsRef = ContentRef(
  databaseId: 'database',
  target: BodyContentTarget(
    owner: CurrentContentOwner(
      domain: 'interactions',
      id: 'deferred',
      revision: 1,
    ),
    key: 'interaction',
  ),
);

CurrentCollectionPage _deferredPage(int byteLength) => CurrentCollectionPage(
  revision: 1,
  entries: [
    CurrentCollectionEntry(
      id: 'deferred',
      position: 0,
      payload: DeferredPayload(reference: _detailsRef, byteLength: byteLength),
    ),
  ],
);

ContentWindow _slice(
  List<int> bytes,
  int offset,
  int end, {
  String generation = 'request-v1',
  int? total,
  bool sealed = true,
}) => ContentWindow(
  offset: offset,
  bytes: bytes.sublist(offset, end),
  generation: generation,
  availableThrough: total ?? bytes.length,
  sealed: sealed,
);

Future<_Content> _openDeferred(WidgetTester tester, int byteLength) async {
  final content = _Content();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    for (final read in content.reader.reads) {
      if (!read.$2.isCompleted) {
        read.$2.completeError(StateError('retired test read'));
      }
    }
    for (final page in content.reader.pages) {
      if (!page.$3.isCompleted) {
        page.$3.completeError(StateError('retired test page'));
      }
    }
    await content.join();
  });
  await tester.pumpWidget(
    _host(
      InteractionDetailsConnector(
        content: content,
        reference: _interactions(1),
        isCurrent: () => true,
      ),
    ),
  );
  expect(tester.takeException(), isNull);
  await tester.tap(find.text('交互详情'));
  await _frames(tester);
  expect(tester.takeException(), isNull);
  content.reader.pages.single.$3.complete(_deferredPage(byteLength));
  await _frames(tester);
  await tester.tap(find.text('查看完整交互详情'));
  await _frames(tester);
  expect(tester.takeException(), isNull);
  return content;
}

void main() {
  testWidgets(
    'Deferred details never expose raw JSON clipboard or download controls',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final bytes =
          (_page(1, 'deferred').entries.single.payload as InlinePayload).bytes;
      final content = await _openDeferred(tester, bytes.length);
      content.reader.reads.single.$2.complete(_slice(bytes, 0, bytes.length));
      await _frames(tester);
      expect(find.text('deferred'), findsOneWidget);
      expect(find.textContaining('不可展示的'), findsNothing);
      expect(find.text('复制当前段'), findsNothing);
      expect(find.byType(TimelineContentRangeConnector), findsNothing);
      expect(find.byIcon(Icons.download), findsNothing);
      expect(copied, isEmpty);
      expect(
        tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((widget) => widget.data)
            .whereType<String>(),
        contains('只读详情'),
      );
    },
  );

  testWidgets(
    'A 70KiB canonical request spanning UTF8 bytes decodes once after all windows',
    (tester) async {
      final envelope = jsonDecode(
        utf8.decode(
          (_page(1, 'deferred').entries.single.payload as InlinePayload).bytes,
        ),
      ) as Map;
      final question =
          ((envelope['content'] as Map)['data'] as Map)['questions'][0] as Map;
      question['question'] = 'UTF8_MARK';
      final prefix = utf8
          .encode(jsonEncode(envelope).split('UTF8_MARK').first)
          .length;
      final prompt = '${'x' * (65535 - prefix)}🐱${'y' * 8000}';
      question['question'] = prompt;
      final bytes = utf8.encode(jsonEncode(envelope));
      expect(bytes.length, greaterThan(70 * 1024));
      expect(bytes[65535], 0xf0);
      final content = await _openDeferred(tester, bytes.length);
      expect(content.reader.ranges.single.offset, 0);
      expect(content.reader.ranges.single.maxBytes, 65536);
      content.reader.reads.single.$2.complete(_slice(bytes, 0, 65536));
      await _frames(tester);
      expect(find.text('交互详情格式无效'), findsNothing);
      expect(
        find.text('deferred'),
        findsNothing,
        reason: 'No partial JSON is presented',
      );
      expect(content.reader.ranges.last.offset, 65536);
      expect(
        content.scopes,
        hasLength(2),
        reason: 'Every chunk retains the original object query scope',
      );
      content.reader.reads.last.$2.complete(_slice(bytes, 65536, bytes.length));
      await _frames(tester);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == prompt,
        ),
        findsOneWidget,
      );
      expect(find.text('交互详情格式无效'), findsNothing);
      expect(find.textContaining('不可展示的'), findsNothing);
      expect(find.text('复制当前段'), findsNothing);
    },
  );

  testWidgets(
    'Interaction details reject over 1MiB before reading without reporting malformed JSON',
    (tester) async {
      final content = await _openDeferred(tester, 1024 * 1024 + 1);
      expect(content.reader.reads, isEmpty);
      expect(find.text('详情资源超出读取预算'), findsOneWidget);
      expect(find.text('交互详情格式无效'), findsNothing);
      expect(find.text('复制当前段'), findsNothing);
    },
  );

  for (final fault in [
    'generation',
    'offset',
    'length',
    'sealed',
    'progress',
    'budget',
  ]) {
    testWidgets(
      'Deferred interaction window $fault violation is explicit and never exposes raw bytes',
      (tester) async {
        final bytes =
            (_page(1, 'deferred').entries.single.payload as InlinePayload)
                .bytes;
        final content = await _openDeferred(tester, bytes.length);
        if (fault == 'progress') {
          content.reader.reads.single.$2.complete(_slice(bytes, 0, 0));
        } else {
          content.reader.reads.single.$2.complete(_slice(bytes, 0, 100));
          await _frames(tester);
          content.reader.reads.last.$2.complete(
            ContentWindow(
              offset: fault == 'offset' ? 101 : 100,
              bytes: bytes.sublist(100),
              generation: fault == 'generation' ? 'request-v2' : 'request-v1',
              availableThrough: fault == 'budget'
                  ? 1024 * 1024 + 1
                  : fault == 'length'
                  ? bytes.length + 1
                  : bytes.length,
              sealed: fault != 'sealed',
            ),
          );
        }
        await _frames(tester);
        expect(
          find.text(
            fault == 'budget'
                ? '详情资源超出读取预算'
                : fault == 'progress'
                ? '详情资源读取未取得进展'
                : '详情资源窗口不连续',
          ),
          findsOneWidget,
        );
        expect(find.text('交互详情格式无效'), findsNothing);
        expect(find.textContaining('不可展示的'), findsNothing);
        expect(find.text('复制当前段'), findsNothing);
      },
    );
  }

  for (final retirement in ['fold', 'ownFold', 'reference', 'unmount']) {
    testWidgets(
      'Deferred interaction $retirement retires and joins an in-flight later window',
      (tester) async {
        final bytes =
            (_page(1, 'deferred').entries.single.payload as InlinePayload)
                .bytes;
        final content = await _openDeferred(tester, bytes.length);
        content.reader.reads.single.$2.complete(_slice(bytes, 0, 100));
        await _frames(tester);
        final pending = content.reader.reads.last.$2;
        final scope = content.scopes.last;
        expect(scope.pendingQueries, 1);
        if (retirement == 'fold') {
          await tester.tap(find.text('交互详情'));
        } else if (retirement == 'ownFold') {
          await tester.tap(find.text('查看完整交互详情'));
        } else if (retirement == 'reference') {
          await tester.pumpWidget(
            _host(
              InteractionDetailsConnector(
                content: content,
                reference: _interactions(2),
                isCurrent: () => true,
              ),
            ),
          );
        } else {
          await tester.pumpWidget(const SizedBox());
        }
        expect(scope.isActive, isFalse);
        var joined = false;
        unawaited(scope.close().then((_) => joined = true));
        await _frames(tester);
        expect(
          joined,
          isFalse,
          reason: 'Cancellation must join the original native read',
        );
        final readCount = content.reader.reads.length;
        if (retirement == 'unmount') {
          pending.completeError(StateError('不可展示的迟到原始错误'));
        } else {
          pending.complete(_slice(bytes, 100, bytes.length));
        }
        await _frames(tester);
        expect(joined, isTrue);
        expect(scope.isSettled, isTrue);
        expect(
          content.reader.reads,
          hasLength(readCount),
          reason: 'A retired request cannot demand another chunk',
        );
        expect(find.text('deferred'), findsNothing);
        expect(find.text('交互详情格式无效'), findsNothing);
        expect(find.textContaining('不可展示的'), findsNothing);
        if (retirement == 'reference') {
          content.reader.pages.last.$3.complete(_page(2, '新引用公开问题'));
          await _frames(tester);
          expect(find.text('新引用公开问题'), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'Deferred canonical interaction details use the original bounded content reader',
    (tester) async {
      final content = _Content();
      const reference = ContentRef(
        databaseId: 'database',
        target: BodyContentTarget(
          owner: CurrentContentOwner(
            domain: 'interactions',
            id: 'deferred',
            revision: 1,
          ),
          key: 'interaction',
        ),
      );
      final bytes =
          (_page(1, 'deferred').entries.single.payload as InlinePayload).bytes;
      await tester.pumpWidget(
        _host(
          InteractionDetailsConnector(
            content: content,
            reference: _interactions(1),
            isCurrent: () => true,
          ),
        ),
      );
      await tester.tap(find.text('交互详情'));
      await _frames(tester);
      content.reader.pages.single.$3.complete(
        CurrentCollectionPage(
          revision: 1,
          entries: [
            CurrentCollectionEntry(
              id: 'deferred',
              position: 0,
              payload: DeferredPayload(
                reference: reference,
                byteLength: bytes.length,
              ),
            ),
          ],
        ),
      );
      await _frames(tester);
      expect(content.reader.reads, isEmpty);
      await tester.tap(find.text('查看完整交互详情'));
      await _frames(tester);
      expect(content.reader.reads.single.$1, reference);
      content.reader.reads.single.$2.complete(_window(utf8.decode(bytes)));
      await _frames(tester);
      expect(find.text('deferred'), findsOneWidget);
      expect(find.text('交互详情格式无效'), findsNothing);
      expect(find.textContaining('不可展示的'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await content.join();
    },
  );

  testWidgets(
    'State refs read canonical requests without acquiring State decision authority',
    (tester) async {
      final content = _Content();
      final refs = ThreadBusinessRefs(
        plan: null,
        interactions: _interactions(1),
      );
      final stateInteraction = PendingInteraction(
        id: 'state-question',
        threadId: 'thread',
        turnId: 'state-turn',
        kind: InteractionKind.userInput,
        title: 'State唯一问答',
        body: '',
        revision: 9,
        payload: const UserInputInteractionPayload(
          questions: [
            UserQuestionView(
              id: 'state-q',
              header: 'State唯一问答',
              question: 'State问题',
              isOther: false,
              isSecret: false,
              options: [
                UserQuestionOptionView(label: '允许', description: 'State选项'),
              ],
            ),
          ],
        ),
      );
      final state = chatWorkspace(
        'thread',
        businessRefs: refs,
      ).copyWith(interactions: [stateInteraction]);
      var decisions = 0;
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              UserInputView(
                payload: InteractionPayloadSnapshot.from(
                  state.interactions.single,
                ),
                enabled: true,
                onSubmit: (_) => decisions++,
              ),
              InteractionDetailsConnector(
                content: content,
                reference: state.businessRefs.interactions!,
                isCurrent: () => true,
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(content.activity.value, isNull);
      expect(content.reader.pages, isEmpty);
      await tester.ensureVisible(find.text('交互详情'));
      await tester.tap(find.text('交互详情'));
      await _frames(tester);
      expect(tester.takeException(), isNull);
      expect(content.reader.pages.single.$1, refs.interactions);
      content.reader.pages.single.$3.complete(_page(1, '查询的公开问题'));
      await _frames(tester);
      expect(find.text('查询的公开问题'), findsOneWidget);
      expect(find.text('交互详情格式无效'), findsNothing);
      expect(find.textContaining('不可展示的'), findsNothing);
      expect(find.text('敏感问题内容已隐藏'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((field) => field.enabled == false),
        isTrue,
      );
      expect(find.byKey(StudioDriverKeys.userInputSubmit), findsOneWidget);
      expect(state.interactions.single, same(stateInteraction));
      expect(state.interactions.single.revision, 9);
      expect(decisions, 0);
      await tester.ensureVisible(find.text('允许'));
      await tester.tap(find.text('允许'));
      await _frames(tester);
      final submit = find.byKey(StudioDriverKeys.userInputSubmit);
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await _frames(tester);
      expect(decisions, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await content.join();
    },
  );

  testWidgets(
    'Canonical approval details omit lifecycle secrets and reject legacy title/body shapes',
    (tester) async {
      final content = _Content();
      Widget view(int revision) => _host(
        InteractionDetailsConnector(
          content: content,
          reference: _interactions(revision),
          isCurrent: () => true,
        ),
      );
      await tester.pumpWidget(view(1));
      await tester.tap(find.text('交互详情'));
      await _frames(tester);
      content.reader.pages.single.$3.complete(
        _page(
          1,
          'approval',
          request: {
            'interactionId': 'approval',
            'scope': {'threadId': 'thread', 'turnId': 'turn'},
            'revision': 5,
            'createdAt': 1,
            'updatedAt': 2,
            'content': {
              'kind': 'toolApproval',
              'data': {
                'request': {
                  'name': 'read_file',
                  'arguments': {'path': 'public.txt'},
                  'workingDirectory': '/project',
                },
                'state': {
                  'kind': 'resolved',
                  'data': {
                    'operationId': 'resolved-approval',
                    'resolvedAt': 2,
                    'decision': 'approved',
                    'reason': '不可展示的审批决议',
                  },
                },
              },
            },
          },
        ),
      );
      await _frames(tester);
      expect(find.text('read_file'), findsOneWidget);
      expect(find.textContaining('public.txt'), findsOneWidget);
      expect(find.textContaining('不可展示的'), findsNothing);
      expect(find.byKey(StudioDriverKeys.toolApprove), findsNothing);
      expect(find.byKey(StudioDriverKeys.toolDeny), findsNothing);
      await tester.pumpWidget(view(2));
      await _frames(tester);
      content.reader.pages.last.$3.complete(
        _page(
          2,
          'legacy',
          request: {
            'interactionId': 'legacy',
            'title': '旧标题',
            'body': '旧结构不得兜底',
          },
        ),
      );
      await _frames(tester);
      expect(find.text('交互详情格式无效'), findsOneWidget);
      expect(find.text('旧标题'), findsNothing);
      expect(find.text('旧结构不得兜底'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await content.join();
    },
  );

  testWidgets(
    'B08/B09: an initial State Plan reference reads while activity is empty',
    (tester) async {
      final content = _Content();
      final reference = _plan(3);
      await tester.pumpWidget(
        _host(
          PlanDocumentConnector(
            key: ValueKey(reference),
            content: content,
            reference: reference,
            isCurrent: () => true,
            documentBuilder: Text.new,
          ),
        ),
      );
      await _frames(tester);
      expect(content.activity.value, isNull);
      expect(content.reader.reads.single.$1, reference);
      content.reader.reads.single.$2.complete(_window('冷会话的完整计划 v3'));
      await _frames(tester);
      expect(find.text('冷会话的完整计划 v3'), findsOneWidget);
      expect(
        content.reader.businessReads,
        0,
        reason: 'GUI consumes the supplied State reference',
      );
      await tester.pumpWidget(const SizedBox());
      await content.join();
    },
  );

  testWidgets(
    'B10/B16: token publications do not replace the Plan reader or Main',
    (tester) async {
      final content = _Content();
      final reference = _plan(3);
      final history = InMemoryChatController(
        messages: [const Message.custom(id: 'completed', authorId: 'user')],
      );
      final saved = history.messages.single;
      Widget view() => _host(
        PlanDocumentConnector(
          key: ValueKey(reference),
          content: content,
          reference: reference,
          isCurrent: () => true,
          documentBuilder: Text.new,
        ),
      );
      await tester.pumpWidget(view());
      await _frames(tester);
      final scope = content.scopes.single;
      for (var revision = 1; revision <= 5; revision++) {
        content.activity.publish(
          ActivitySnapshot(
            revision: revision,
            completedThrough: 0,
            executionPresent: true,
            entries: const [],
          ),
        );
        await tester.pumpWidget(view());
      }
      expect(content.scopes.single, same(scope));
      expect(content.reader.reads, hasLength(1));
      content.reader.reads.single.$2.complete(_window('独立于慢历史的计划'));
      await _frames(tester);
      expect(find.text('独立于慢历史的计划'), findsOneWidget);
      expect(history.messages.single, same(saved));
      await tester.pumpWidget(const SizedBox());
      await content.join();
      history.dispose();
    },
  );

  for (final failOld in [false, true]) {
    testWidgets(
      'B10/B15/B17: old Plan ${failOld ? 'error' : 'bytes'} cannot overwrite a new State reference',
      (tester) async {
        final content = _Content();
        var current = _plan(3);
        Widget view(ContentRef reference) => _host(
          PlanDocumentConnector(
            key: ValueKey(reference),
            content: content,
            reference: reference,
            isCurrent: () => current == reference,
            documentBuilder: Text.new,
          ),
        );
        await tester.pumpWidget(view(current));
        await _frames(tester);
        final old = content.reader.reads.single.$2;
        final oldScope = content.scopes.single;
        current = _plan(4);
        await tester.pumpWidget(view(current));
        await _frames(tester);
        expect(oldScope.isActive, isFalse);
        content.reader.reads.last.$2.complete(_window('计划 v4'));
        await _frames(tester);
        if (failOld) {
          old.completeError(StateError('旧文档失效'));
        } else {
          old.complete(_window('计划 v3'));
        }
        await _frames(tester);
        expect(find.text('计划 v4'), findsOneWidget);
        expect(find.text('计划 v3'), findsNothing);
        expect(find.textContaining('旧文档失效'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await content.join();
      },
    );
  }

  testWidgets(
    'B15: content failures remain visible and never fall back to history text',
    (tester) async {
      final content = _Content();
      final reference = _plan(3);
      await tester.pumpWidget(
        _host(
          PlanDocumentConnector(
            key: ValueKey(reference),
            content: content,
            reference: reference,
            isCurrent: () => true,
            documentBuilder: Text.new,
          ),
        ),
      );
      await _frames(tester);
      content.reader.reads.single.$2.completeError(StateError('缺少计划正文块'));
      await _frames(tester);
      expect(find.textContaining('缺少计划正文块'), findsOneWidget);
      expect(content.reader.businessReads, 0);
      await tester.pumpWidget(const SizedBox());
      await content.join();
    },
  );

  for (final failOldPage in [false, true]) {
    testWidgets(
      'B11/B18: changed interaction refs retire the old second page ${failOldPage ? 'failure' : 'bytes'}, leaving the Plan window intact',
      (tester) async {
        final content = _Content();
        var current = _interactions(1);
        final plan = _plan(3);
        Widget view() => _host(
          Column(
            children: [
              PlanDocumentConnector(
                key: ValueKey(plan),
                content: content,
                reference: plan,
                isCurrent: () => true,
                documentBuilder: Text.new,
              ),
              InteractionDetailsConnector(
                key: const ValueKey('details'),
                content: content,
                reference: current,
                isCurrent: () => true,
              ),
            ],
          ),
        );
        await tester.pumpWidget(view());
        await _frames(tester);
        expect(content.reader.pages, isEmpty);
        content.reader.reads.single.$2.complete(_window('保留的计划窗口'));
        await tester.tap(find.text('交互详情'));
        await _frames(tester);
        content.reader.pages.single.$3.complete(
          _page(1, '当前问题', next: 'page-2'),
        );
        await _frames(tester);
        expect(find.textContaining('不可展示的原始字段'), findsNothing);
        await tester.tap(find.text('下一页交互详情'));
        await _frames(tester);
        final oldPage = content.reader.pages.last;
        expect(oldPage.$2, 'page-2');
        current = _interactions(2);
        await tester.pumpWidget(view());
        await _frames(tester);
        expect(content.scopes[1].isActive, isFalse);
        content.reader.pages.last.$3.complete(_page(2, '新的问题切面'));
        if (failOldPage) {
          oldPage.$3.completeError(
            const StudioFailure(
              code: StudioFailureCode.staleRevision,
              message: '旧交互版本失效',
              retryable: false,
              correlationId: 'retired-interaction-page',
            ),
          );
        } else {
          oldPage.$3.complete(_page(1, '过期的第二页'));
        }
        await _frames(tester);
        expect(find.text('新的问题切面'), findsOneWidget);
        expect(find.text('过期的第二页'), findsNothing);
        expect(find.textContaining('旧交互版本失效'), findsNothing);
        expect(find.text('保留的计划窗口'), findsOneWidget);
        expect(content.scopes.first.isActive, isTrue);
        expect(content.reader.businessReads, 0);
        await tester.pumpWidget(const SizedBox());
        await content.join();
      },
    );
  }
}

final class _Content extends Fake implements ConversationContent {
  @override
  String get threadId => 'thread';
  final reader = _Reader();
  final scopes = <ConversationReadScope>[];
  @override
  final LatestValue<ActivitySnapshot?> activity = LatestValue(null);
  @override
  bool get isClosed => false;
  @override
  AttemptId get currentAttemptId => const AttemptId(1);
  @override
  ConversationQueryScope openScope({required int generation}) {
    final scope = ConversationReadScope(
      threadId: 'thread',
      generation: generation,
      reader: reader,
      isEligible: () => true,
      applyOlder: (_) async {},
    );
    scopes.add(scope);
    return scope;
  }

  Future<void> join() async {
    for (final scope in scopes) {
      scope.retire();
      expect((await scope.close()).complete, isTrue);
    }
    activity.close();
  }
}

final class _Reader extends Fake implements ConversationReader {
  final reads = <(ContentRef, Completer<ContentWindow>)>[];
  final ranges = <ContentRange>[];
  final pages =
      <(CurrentCollectionRef, String?, Completer<CurrentCollectionPage>)>[];
  int businessReads = 0;
  @override
  Future<ThreadBusinessRefs> readBusinessRefs() async {
    businessReads++;
    throw StateError('GUI must not query refs after State acceptance');
  }

  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    expect(range.maxBytes, lessThanOrEqualTo(64 * 1024));
    ranges.add(range);
    final result = Completer<ContentWindow>();
    reads.add((reference, result));
    return result.future;
  }

  @override
  Future<CurrentCollectionPage> pageCurrent({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) {
    final result = Completer<CurrentCollectionPage>();
    pages.add((reference, continuation, result));
    return result.future;
  }
}
