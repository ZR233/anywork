import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/app/theme/studio_tokens.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_ui_controllers.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_view_state.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

ContentRef _bodyRef(String id) => ContentRef(
  databaseId: 'parent-db',
  target: BodyContentTarget(
    owner: ItemContentOwner(itemId: id),
    key: 'body',
  ),
);

InlinePayload _payload(
  String id,
  String text, {
  bool bodyDeferred = false,
  bool user = false,
}) => InlinePayload(
  bytes: utf8.encode(
    jsonEncode({
      'contract': 'anywork.chat/1',
      'type': 'text',
      // This is deliberately also present in untrusted Inbox fixtures.
      'data': {'channel': user ? 'user' : 'parentAgent', 'attachments': []},
      'bodies': [
        {
          'key': 'body',
          'byteLength': utf8.encode(text).length,
          if (!bodyDeferred) 'inline': utf8.encode(text),
          if (bodyDeferred)
            'reference': {
              'databaseId': 'parent-db',
              'target': {
                'kind': 'body',
                'owner': {'kind': 'item', 'itemId': id},
                'key': 'body',
              },
            },
        },
        {
          'key': 'accepted.payload',
          'byteLength': 8,
          'inline': utf8.encode('RETAINED'),
        },
      ],
    }),
  ),
);

ChatAtom _atom(
  String id, {
  String text = '请完成当前任务。',
  ThreadTextChannel? channel = ThreadTextChannel.parentAgent,
  bool user = false,
  bool bodyDeferred = false,
  bool payloadDeferred = false,
  bool payloadMissing = false,
}) => ChatAtom(
  id: id,
  completionItemId: id,
  source: user
      ? InputChatSource(inputId: id)
      : InboxMessageChatSource(sourceId: 'agent:direct-parent', messageId: id),
  sourceOrder: null,
  kind: user ? ChatAtomKind.input : ChatAtomKind.text,
  delivery: ChatDeliveryKind.independent,
  textChannel: user ? ThreadTextChannel.user : channel,
  lifecycle: const TerminalChatAtom(
    started: null,
    ended: null,
    outcome: ChatTerminalOutcome.completed,
  ),
  contents: [
    ChatAtomContent(role: ChatContentRole.body, reference: _bodyRef(id)),
  ],
  payload: payloadMissing
      ? null
      : payloadDeferred
      ? DeferredPayload(
          reference: ContentRef(
            databaseId: 'parent-db',
            target: ItemPayloadTarget(itemId: id),
          ),
          byteLength: 9000,
        )
      : _payload(id, text, bodyDeferred: bodyDeferred, user: user),
);

DisplayBlock _block(ChatAtom atom, {int order = 1}) => DisplayBlock(
  id: atom.id,
  blockOrder: order,
  body: SingleDisplayBlock(
    visibility: HistorySingleVisibility.content,
    record: DisplayRecord(
      atom: atom,
      contentSource: CompletedOriginal(completionId: atom.id),
    ),
  ),
);

Widget _host(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Finder _label(String id) => find.byKey(StudioDriverKeys.parentAgentLabel(id));

void main() {
  for (final decode in [false, true]) {
    for (final storage in ['inline', 'body range', 'payload range']) {
      testWidgets(
        'trusted parent keeps identity via ${decode ? 'decode' : 'forUnit'} ($storage)',
        (tester) async {
          final id = 'parent-$storage';
          final atom = _atom(
            id,
            bodyDeferred: storage == 'body range',
            payloadDeferred: storage == 'payload range',
          );
          final unit = TimelineDisplayUnit(block: _block(atom));
          addTearDown(unit.expansion.dispose);
          var item = decode
              ? ChatItemPresentation.decode(atom)
              : ChatItemPresentation.forUnit(unit);
          expect(item.authorId, 'parentAgent');
          expect(item.atom, same(atom));
          final reads = <String>[];
          Widget view() => ChatItemView(
            key: ValueKey(id),
            item: item,
            contentRangeBuilder: (itemId, key, label, reference, witness) {
              expect(itemId, id);
              expect(reference.databaseId, 'parent-db');
              if (key == 'body') {
                expect(reference.target, isA<BodyContentTarget>());
                final target = reference.target as BodyContentTarget;
                expect(target.key, 'body');
                expect((target.owner as ItemContentOwner).itemId, id);
              } else {
                expect(key, 'payload');
                expect((reference.target as ItemPayloadTarget).itemId, id);
              }
              reads.add(key);
              return Text('range:$key');
            },
          );
          await tester.pumpWidget(_host(view()));
          await tester.pumpAndSettle();
          expect(_label(id), findsOneWidget);
          final label = tester.widget<Text>(_label(id));
          expect(
            label.data,
            AppLocalizations.of(tester.element(_label(id))).timelineParentAgent,
          );
          expect(find.text('来源 · agent:direct-parent'), findsNothing);
          expect(find.text('RETAINED'), findsNothing);
          if (storage == 'inline') {
            expect(find.text('请完成当前任务。'), findsOneWidget);
            expect(reads, isEmpty);
          } else {
            final key = storage == 'body range' ? 'body' : 'payload';
            expect(reads, [key]);
            expect(find.text('range:$key'), findsOneWidget);
          }
          if (storage == 'payload range') {
            item = item.resolvePayload(_payload(id, '元数据已到达。'));
            expect(item.authorId, 'parentAgent');
            expect(item.atom, same(atom));
            await tester.pumpWidget(_host(view()));
            await tester.pumpAndSettle();
            expect(_label(id), findsOneWidget);
            expect(find.text('元数据已到达。'), findsOneWidget);
            expect(find.text('RETAINED'), findsNothing);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'pending parent metadata keeps typed identity and declared ranges',
    (tester) async {
      final atom = _atom('pending-parent', payloadMissing: true);
      final unit = TimelineDisplayUnit(block: _block(atom));
      addTearDown(unit.expansion.dispose);
      final item = ChatItemPresentation.forUnit(unit);
      expect(item.atom, same(atom));
      expect(item.authorId, 'parentAgent');
      final reads = <ContentRef>[];
      await tester.pumpWidget(
        _host(
          ChatItemView(
            item: item,
            contentRangeBuilder: (id, key, label, reference, witness) {
              expect(id, unit.id);
              reads.add(reference);
              return const Text('独立正文范围');
            },
          ),
        ),
      );
      expect(_label(unit.id), findsOneWidget);
      expect(reads, [same(atom.contents.single.reference)]);
      expect(find.text('独立正文范围'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Inbox source prefix and payload cannot grant parent identity', (
    tester,
  ) async {
    for (final channel in [null, ThreadTextChannel.user]) {
      final atom = _atom('untrusted-$channel', channel: channel);
      final unit = TimelineDisplayUnit(block: _block(atom));
      addTearDown(unit.expansion.dispose);
      for (final item in [
        ChatItemPresentation.forUnit(unit),
        ChatItemPresentation.decode(atom),
      ]) {
        expect(item.authorId, 'inbox:agent:direct-parent');
        await tester.pumpWidget(_host(ChatItemView(item: item)));
        expect(_label(item.id), findsNothing);
        expect(find.text('来源 · agent:direct-parent'), findsOneWidget);
      }
    }
  });

  for (final width in [1000.0, 320.0]) {
    testWidgets(
      'parent and user share production prompt bubbles at width $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controls = _Controls();
        const longText =
            '请先核对已有实现，再完成范围内的修复并验证结果。'
            '长消息需要在窄窗口中自然换行，不能越过气泡的左右边界。'
            '保持正文可读，不把额外保留的接收数据当作正文展示。';
        await controls.adapter.applyBlocks([
          _block(_atom('user', user: true, text: longText)),
          _block(_atom('initial', text: '初始任务'), order: 2),
        ], ChatPlacement.set);
        await tester.pumpWidget(_host(_timeline(controls)));
        await tester.pumpAndSettle();
        expect(_label('initial'), findsOneWidget);
        // A later parent message takes the same real adapter and TimelineView path.
        await controls.adapter.applyBlocks([
          _block(_atom('follow-up', text: longText), order: 3),
          _block(_atom('external', channel: null, text: '外部消息'), order: 4),
          _block(_atom('pending', payloadMissing: true), order: 5),
          _block(_atom('deferred', payloadDeferred: true), order: 6),
        ], ChatPlacement.append);
        await tester.pumpAndSettle();

        // The decorated prompt container is inside ChatMessage, around ChatItemView.
        Finder prompt(String id) => find.descendant(
          of: find.byKey(StudioDriverKeys.timelineRow(id)),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is BoxDecoration,
          ),
        );
        final user = tester.widget<Container>(prompt('user'));
        final userRect = tester.getRect(prompt('user'));
        final userRow = tester.widget<ChatMessage>(
          find.byKey(StudioDriverKeys.timelineRow('user')),
        );
        for (final id in ['initial', 'follow-up', 'pending', 'deferred']) {
          expect(_label(id), findsOneWidget);
          final parent = tester.widget<Container>(prompt(id));
          final rect = tester.getRect(prompt(id));
          expect(parent.constraints, user.constraints);
          expect(parent.padding, user.padding);
          expect(parent.decoration, user.decoration);
          expect(
            rect.width,
            lessThanOrEqualTo(StudioLayout.conversationPromptWidth),
          );
          expect(rect.right, closeTo(userRect.right, 0.01));
          expect(rect.left, greaterThanOrEqualTo(24));
          final row = tester.widget<ChatMessage>(
            find.byKey(StudioDriverKeys.timelineRow(id)),
          );
          expect(row.horizontalPadding, userRow.horizontalPadding);
          expect(row.verticalPadding, userRow.verticalPadding);
          expect(row.verticalGroupedPadding, userRow.verticalGroupedPadding);
        }
        expect(tester.getSize(prompt('follow-up')).width, userRect.width);
        expect(_label('external'), findsNothing);
        expect(prompt('external'), findsNothing);
        expect(find.text('来源 · agent:direct-parent'), findsOneWidget);
        if (width == 320) {
          expect(tester.getSize(prompt('follow-up')).height, greaterThan(100));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await controls.dispose();
      },
    );
  }
}

Widget _timeline(_Controls controls) => TimelineView(
  threadId: 'child-thread',
  view: const TimelineSessionViewState(
    threadId: 'child-thread',
    generation: 1,
    mode: TimelineDisplayMode.live,
    connection: TimelineConnectionPhase.ready,
  ),
  controls: controls,
  onLoadOlder: () async {},
  onRetryOlder: () async {},
  onReturnLive: () async {},
  onEnterHistory: () {},
  onRetryConnection: () {},
  onLink: (_) {},
  isSafeLink: (_) => false,
  remoteImageBuilder: (_, _) => const SizedBox.shrink(),
  contentRangeBuilder: (_, _, _, _, _) => const Text('待读取正文'),
);

final class _Controls implements TimelineUiControllers {
  @override
  final InMemoryChatController controller = InMemoryChatController();
  @override
  final scrollController = ScrollController();
  late final adapter = TimelineMessageController(controller, generation: 1);
  @override
  Key get chatKey => const ValueKey('parent-chat');
  @override
  bool get isRetired => false;
  @override
  void bind() {}
  @override
  Future<void> unbind() async {}
  Future<void> dispose() async {
    adapter.dispose();
    controller.dispose();
    scrollController.dispose();
  }
}
