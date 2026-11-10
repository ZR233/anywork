import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_content_range_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

Widget rowApp(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
ChatItemPresentation deferred(String database) => ChatItemPresentation.decode(
  fixtureAtom(
    id: 'same-row',
    payload: DeferredPayload(
      reference: ContentRef(
        databaseId: database,
        target: const ItemPayloadTarget(itemId: 'payload'),
      ),
      byteLength: 100000,
    ),
  ),
);
ContentWindow window(String value, {int offset = 0, int? available}) =>
    ContentWindow(
      offset: offset,
      bytes: utf8.encode(value),
      generation: 'g1',
      availableThrough: available ?? offset + utf8.encode(value).length,
      sealed: true,
    );
ChatContentRangeBuilder contentBuilder(ChatContentRead read) =>
    (itemId, contentKey, label, reference, witness) =>
        TimelineContentRangeConnector(
          itemId: itemId,
          contentKey: contentKey,
          label: label,
          reference: reference,
          witness: witness,
          readContent: read,
        );

void main() {
  testWidgets(
    'content window owns expansion across accepted-value rebuilds and uses official enabled',
    (tester) async {
      final changes = <bool>[];
      Widget build({
        bool loading = false,
        bool active = true,
        bool canRead = true,
        String text = 'accepted original',
      }) => rowApp(
        TimelineContentRangeView(
          itemId: 'pure-content',
          contentKey: 'payload',
          label: '合成内容窗口',
          loading: loading,
          active: active,
          canRead: canRead,
          window: window(text),
          onExpansionChanged: changes.add,
          onNext: null,
          onCopy: null,
          witness: (_, child) => child,
        ),
      );
      await tester.pumpWidget(build());
      final tile = find.byType(ExpansionTile);
      expect(tester.getSize(tile).height, greaterThanOrEqualTo(28));
      expect(find.text('accepted original'), findsNothing);
      expect(tester.widget<ExpansionTile>(tile).onExpansionChanged, isNotNull);
      await tester.tap(find.text('合成内容窗口'));
      await tester.pumpAndSettle();
      expect(changes, [true]);
      expect(find.text('accepted original'), findsOneWidget);
      for (final disabled in [
        build(loading: true),
        build(active: false),
        build(canRead: false),
      ]) {
        await tester.pumpWidget(disabled);
        expect(tester.widget<ExpansionTile>(tile).enabled, isFalse);
        await tester.tap(find.text('合成内容窗口'));
        await tester.pump();
        expect(changes, [
          true,
        ], reason: 'Disabled headers cannot change demand');
      }
      await tester.pumpWidget(build(text: 'accepted replacement'));
      await tester.pumpAndSettle();
      expect(tester.widget<ExpansionTile>(tile).enabled, isTrue);
      expect(find.text('accepted replacement'), findsOneWidget);
      expect(changes, [
        true,
      ], reason: 'Value rebuilds do not reset or re-expand UI');
      await tester.tap(find.text('合成内容窗口'));
      await tester.pumpAndSettle();
      expect(changes, [true, false]);
      expect(find.text('accepted replacement'), findsNothing);
    },
  );

  for (final type in ['thinking', 'plan']) {
    final reasoning = type == 'thinking';
    final body = reasoning ? 'completed reasoning' : 'approved plan';
    testWidgets(
      'unrelated Append keeps ${reasoning ? 'reasoning expansion' : 'plan expansion'} and immutable card identity',
      (tester) async {
        final controller = InMemoryChatController();
        final resources = TimelineImageResources(threadId: 'thread');
        final adapter = TimelineMessageController(controller, generation: 1);
        addTearDown(() {
          adapter.dispose();
          resources.release();
          controller.dispose();
        });
        await adapter.applyBatch(
          chatBatch([
            statusItem(
              chatEnvelope(
                type,
                type: type,
                data: reasoning ? const {} : const {'decision': 'approved'},
                bodies: [
                  inlineBody(
                    reasoning ? 'part.reasoningText.0' : 'plan.body',
                    body,
                  ),
                ],
              ),
            ),
          ]),
        );
        Widget build() => rowApp(
          Column(
            children: [
              for (final message in controller.messages)
                ChatItemView(
                  key: ValueKey(message.id),
                  item:
                      message.metadata![chatItemPresentationKey]
                          as ChatItemPresentation,
                ),
            ],
          ),
        );
        await tester.pumpWidget(build());
        expect(find.text(body), findsNothing);
        await tester.tap(find.byType(ExpansionTile).first);
        await tester.pumpAndSettle();
        expect(find.text(body), findsOneWidget);
        final old = controller.messages.single;
        final card = old.metadata![chatItemPresentationKey];
        await adapter.applyBatch(
          chatBatch([
            chatMessage('next', completionSeq: 2),
          ], placement: ChatPlacement.append),
        );
        await tester.pumpWidget(build());
        expect(controller.messages.first, same(old));
        expect(
          controller.messages.first.metadata![chatItemPresentationKey],
          same(card),
        );
        expect(find.text(body), findsOneWidget);
        if (reasoning) expect(find.byType(ExpansionTile), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'referenced reasoning summary reads immediately in one line, body waits for expansion',
    (tester) async {
      Map<String, Object?> body(String key) => {
        'key': key,
        'byteLength': 100,
        'reference': {
          'databaseId': 'database',
          'target': {
            'kind': 'body',
            'owner': {'kind': 'item', 'itemId': 'thinking'},
            'key': key,
          },
        },
      };
      final requests = <String>[];
      final item = ChatItemPresentation.decode(
        chatEnvelope(
          'thinking',
          type: 'thinking',
          data: const {},
          bodies: [body('part.summaryText.0'), body('part.reasoningText.0')],
        ),
      );
      await tester.pumpWidget(
        rowApp(
          ChatItemView(
            item: item,
            contentRangeBuilder: contentBuilder((reference, range) async {
              final key = (reference.target as BodyContentTarget).key;
              requests.add(key);
              expect(range.offset, 0);
              expect(range.maxBytes, lessThanOrEqualTo(64 * 1024));
              return window(
                key.contains('summaryText') ? '**有界读取的概要**' : '有界读取的思考正文',
              );
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, ['part.summaryText.0']);
      expect(
        find.textContaining('有界读取的概要', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(ExpansionTile), findsOneWidget);
      expect(find.textContaining('字节'), findsNothing);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(requests, ['part.summaryText.0', 'part.reasoningText.0']);
      expect(find.text('有界读取的思考正文'), findsOneWidget);
      expect(
        find.textContaining('有界读取的概要', findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Deferred is lazy, requests bounded original-reference windows, and Next advances byte offset',
    (tester) async {
      final requests = <(ContentRef, ContentRange)>[];
      final item = deferred('database');
      await tester.pumpWidget(
        rowApp(
          ChatItemView(
            item: item,
            contentRangeBuilder: contentBuilder((reference, range) async {
              requests.add((reference, range));
              return window(
                range.offset == 0 ? 'first' : 'last',
                offset: range.offset,
                available: 9,
              );
            }),
          ),
        ),
      );
      expect(requests, isEmpty);
      await tester.tap(find.text('按需查看原文 · 100000 字节'));
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);
      expect(requests.single.$1, same(item.reference));
      expect(requests.single.$2.offset, 0);
      expect(requests.single.$2.maxBytes, 65536);
      await tester.tap(find.text('下一段'));
      await tester.pumpAndSettle();
      expect(requests.last.$2.offset, 5);
      expect(find.text('last'), findsOneWidget);
      expect(
        find.text('first'),
        findsNothing,
        reason: 'only the requested window is retained, not an accumulated full body',
      );
      expect(find.text('下一段'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final failOld in [false, true]) {
    testWidgets(
      'reference A-B-A rejects late ${failOld ? 'error' : 'success'} and old finally cannot unlock new read',
      (tester) async {
        final old = Completer<ContentWindow>();
        final latest = Completer<ContentWindow>();
        var reads = 0;
        Widget build(String database) => rowApp(
          ChatItemView(
            key: const ValueKey('row'),
            item: deferred(database),
            contentRangeBuilder: contentBuilder(
              (_, _) => (++reads == 1 ? old : latest).future,
            ),
          ),
        );
        await tester.pumpWidget(build('a'));
        await tester.tap(find.text('按需查看原文 · 100000 字节'));
        await tester.pump();
        await tester.pumpWidget(build('b'));
        await tester.pumpWidget(build('a'));
        expect(
          reads,
          1,
          reason: 'A new reference identity retires UI state without reading',
        );
        await tester.tap(find.text('按需查看原文 · 100000 字节'));
        await tester.pump();
        expect(reads, 2);
        if (failOld) {
          old.completeError(StateError('old-error'));
        } else {
          old.complete(window('old-body'));
        }
        await tester.pump();
        expect(find.text('old-body'), findsNothing);
        expect(find.textContaining('old-error'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(
          tester.widget<ExpansionTile>(find.byType(ExpansionTile)).enabled,
          isFalse,
        );
        latest.complete(window('new-body'));
        await tester.pumpAndSettle();
        expect(find.text('new-body'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unmounted row ignores late read failure without an uncaught error',
    (tester) async {
      final reply = Completer<ContentWindow>();
      await tester.pumpWidget(
        rowApp(
          ChatItemView(
            item: deferred('database'),
            contentRangeBuilder: contentBuilder((_, _) => reply.future),
          ),
        ),
      );
      await tester.tap(find.text('按需查看原文 · 100000 字节'));
      await tester.pumpWidget(const SizedBox.shrink());
      reply.completeError(StateError('late-after-unmount'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
