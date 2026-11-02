import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_encoding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

const source = ForegroundTurnChatSource(turnId: 'T');
ChatAtom atom(
  String id,
  int order, {
  bool terminal = true,
  int? seq,
  String? completionItemId,
  ChatAtomKind kind = ChatAtomKind.reasoning,
  PayloadData? payload,
}) => ChatAtom(
  id: id,
  completionItemId: terminal ? completionItemId ?? id : null,
  completionSeq: terminal ? seq ?? order : null,
  source: source,
  sourceOrder: order,
  kind: kind,
  delivery: ChatDeliveryKind.foreground,
  lifecycle: terminal
      ? const TerminalChatAtom(
          started: null,
          ended: null,
          outcome: ChatTerminalOutcome.completed,
        )
      : const ActiveChatAtom(started: null, status: ChatActiveStatus.running),
  contents: const [],
  payload: payload,
);
ChatBatch page(
  List<ChatAtom> atoms, {
  ChatPlacement placement = ChatPlacement.append,
  bool ended = false,
  String? before,
}) => ChatBatch(
  placement: placement,
  before: before,
  entries: [
    if (atoms.isEmpty)
      ChatSourceEntry(
        ChatSourceState(
          source: source,
          lifecycle: ended
              ? const EndedChatSource(outcome: ChatTerminalOutcome.completed)
              : const ActiveChatSource(),
          started: null,
          ended: null,
        ),
      ),
    for (final a in atoms)
      ChatAtomEntry(
        ChatAtom(
          id: a.id,
          completionItemId: a.completionItemId,
          completionSeq: a.completionSeq,
          source: a.source,
          sourceOrder: a.sourceOrder,
          kind: a.kind,
          delivery: a.delivery,
          sourceState: ChatSourceState(
            source: a.source,
            lifecycle: ended
                ? const EndedChatSource(outcome: ChatTerminalOutcome.completed)
                : const ActiveChatSource(),
            started: null,
            ended: null,
          ),
          lifecycle: a.lifecycle,
          contents: a.contents,
          payload: a.payload,
        ),
      ),
  ],
);
TimelineDisplayUnit unit(Message message) =>
    message.metadata![timelineDisplayUnitKey] as TimelineDisplayUnit;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InMemoryChatController controller;
  late TimelineMessageController reducer;
  setUp(() {
    controller = InMemoryChatController();
    reducer = TimelineMessageController(
      controller,
      generation: 1,
      imageResources: TimelineImageResources(threadId: 'T'),
      displayDemand: const ReadDemand(maxItems: 2, maxBytes: 32768),
    );
  });
  tearDown(() {
    reducer.dispose();
    controller.dispose();
  });
  for (final lateError in [false, true]) {
    testWidgets(
      'R2 permanent merge revokes mounted body before late ${lateError ? 'failure' : 'success'}',
      (tester) async {
        ChatAtom reasoning(int order, int seq) => atom(
          'R$order',
          order,
          seq: seq,
          completionItemId: 'original-$order',
          payload: InlinePayload(
            bytes: utf8.encode(
              jsonEncode({
                'contract': 'anywork.chat/1',
                'type': 'thinking',
                'data': {},
                'bodies': [
                  {
                    'key': 'body',
                    'byteLength': 4,
                    'reference': {
                      'databaseId': 'db',
                      'target': {
                        'kind': 'body',
                        'owner': {'kind': 'item', 'itemId': 'original-$order'},
                        'key': 'body',
                      },
                    },
                  },
                ],
              }),
            ),
          ),
        );
        final batch = page(
          [reasoning(10, 1), reasoning(30, 2)],
          placement: ChatPlacement.set,
          before: 'unknown',
          ended: true,
        );
        final bytes = utf8
            .encode(
              jsonEncode({
                'placement': 'set',
                'entries': batch.entries.map(chatEntryToJson).toList(),
                'before': 'unknown',
                'current': null,
              }),
            )
            .length;
        expect(batch.entries, hasLength(2));
        expect(bytes, lessThanOrEqualTo(32768));
        await reducer.applyBatch(batch);
        final retained = unit(controller.messages.first);
        final retainedToken = Object();
        retained.expansion.setBodyVisible(retainedToken, true);
        final retainedGeneration = retained.expansion.bodyGeneration;
        final removed = unit(controller.messages.last);
        final intent = removed.expansion;
        intent.expanded = true;
        final borrows = <TimelineCurrentWindowDisplay>[];
        final pending = Completer<ContentWindow>();
        var reads = 0;
        var cleanups = 0;
        (bool, bool)? cleanupQualification;
        intent.retireBody = () {
          cleanups++;
          cleanupQualification = (intent.isRetired, intent.bodyActive);
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ChatItemView(
                item: ChatItemPresentation.forUnit(removed),
                isDisplayActive: () => true,
                contentRangeBuilder: (id, key, label, reference, witness) =>
                    TimelineContentRangeConnector(
                      itemId: id,
                      contentKey: key,
                      label: label,
                      reference: reference,
                      witness: witness,
                      isDisplayActive: () => true,
                      registerDisplay: (display) {
                        borrows.add(display);
                        return () => borrows.remove(display);
                      },
                      readContent: (reference, range) {
                        expect(
                          (reference.target as BodyContentTarget).owner,
                          isA<ItemContentOwner>().having(
                            (owner) => owner.itemId,
                            'payload identity',
                            'original-30',
                          ),
                        );
                        reads++;
                        return pending.future;
                      },
                    ),
              ),
            ),
          ),
        );
        await tester.pump();
        final old = borrows.single;
        final originalGeneration = intent.bodyGeneration;
        await reducer.applyBatch(
          page([], placement: ChatPlacement.prepend, ended: true),
        );
        final borrowedAfterRetire = borrows.length;
        final retiredSynchronously = intent.isRetired;
        final generationChanged = !identical(
          intent.bodyGeneration,
          originalGeneration,
        );
        final token = Object();
        intent.setBodyVisible(token, true);
        intent.setBodyVisible(token, false);
        intent.setBodyVisible(token, true);
        if (lateError) {
          pending.completeError(StateError('retired body failure'));
        } else {
          pending.complete(
            ContentWindow(
              offset: 0,
              bytes: utf8.encode('late'),
              generation: 'g',
              availableThrough: 4,
              sealed: true,
            ),
          );
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final staleResult = (old.window, old.error);
        intent.retire();
        await tester.pumpWidget(const SizedBox());
        expect(borrowedAfterRetire, 0);
        expect(retiredSynchronously, isTrue);
        expect(generationChanged, isTrue);
        expect(intent.bodyActive, isFalse);
        expect(intent.current, isNull);
        expect(staleResult, (null, null));
        expect(cleanups, 1);
        expect(cleanupQualification, (true, false));
        expect(
          reads,
          1,
          reason: 'Old tokens cannot reopen a permanently retired fragment',
        );
        final survivor = unit(controller.messages.single);
        expect(survivor.expansion, same(retained.expansion));
        expect(survivor.expansion.isRetired, isFalse);
        expect(survivor.expansion.bodyGeneration, same(retainedGeneration));
        expect(survivor.expansion.bodyActive, isTrue);
        expect(survivor.members.map((atom) => atom.id), ['R10', 'R30']);
      },
    );
  }
  test('R2 budget eviction permanently revokes its intent without revoking active survivors', () async {
    await reducer.applyBatch(
      page([], placement: ChatPlacement.set, before: 'H0'),
    );
    await reducer.applyBatch(page([atom('active', 1, terminal: false)]));
    final active = reducer.live.value.single;
    final activeToken = Object();
    active.expansion.setBodyVisible(activeToken, true);
    final activeGeneration = active.expansion.bodyGeneration;
    await reducer.applyBatch(
      page([atom('separator-10', 10, seq: 1, kind: ChatAtomKind.text)]),
    );
    await reducer.applyBatch(page([atom('work-20', 20, seq: 2)]));
    final evicted = reducer.live.value.singleWhere(
      (unit) => unit.members.any((a) => a.id == 'work-20'),
    );
    final intent = evicted.expansion;
    final token = Object();
    intent.setBodyVisible(token, true);
    final oldGeneration = intent.bodyGeneration;
    var cleanups = 0;
    intent.retireBody = () {
      expect(intent.isRetired, isTrue);
      expect(intent.bodyActive, isFalse);
      cleanups++;
    };
    await reducer.applyBatch(
      page([atom('separator-30', 30, seq: 3, kind: ChatAtomKind.text)]),
    );
    await reducer.applyBatch(page([atom('work-40', 40, seq: 4)]));
    expect(intent.current, isNull);
    expect(intent.isRetired, isTrue);
    expect(intent.bodyGeneration, isNot(same(oldGeneration)));
    intent.setBodyVisible(token, true);
    intent.retire();
    expect(intent.bodyActive, isFalse);
    expect(cleanups, 1);
    expect(active.expansion.isRetired, isFalse);
    expect(active.expansion.bodyGeneration, same(activeGeneration));
    expect(active.expansion.bodyActive, isTrue);
    expect(reducer.retainedCompletedBudget.$1, lessThanOrEqualTo(2));
  });
  test(
    'R2 permanent retirement preserves the original cleanup failure',
    () async {
      await reducer.applyBatch(
        page(
          [atom('R10', 10, seq: 1), atom('R30', 30, seq: 2)],
          placement: ChatPlacement.set,
          before: 'unknown',
          ended: true,
        ),
      );
      final retained = unit(controller.messages.first).expansion;
      final removed = unit(controller.messages.last).expansion;
      removed.setBodyVisible(Object(), true);
      final failure = StateError('original body close failure');
      void cleanup() {
        throw failure;
      }

      removed.retireBody = cleanup;
      await expectLater(
        reducer.applyBatch(
          page([], placement: ChatPlacement.prepend, ended: true),
        ),
        throwsA(same(failure)),
      );
      expect(removed.isRetired, isTrue);
      expect(removed.bodyActive, isFalse);
      expect(
        removed.retireBody,
        same(cleanup),
        reason: 'A failed cleanup is not erased as success',
      );
      expect(retained.isRetired, isFalse);
    },
  );
  test('unknown ordinary prefix is not adjacency even when source numbers differ by one', () async {
    await reducer.applyBatch(
      page(
        [
          atom('R', 10, seq: 2),
          atom('tool', 11, seq: 3, kind: ChatAtomKind.toolCall),
        ],
        placement: ChatPlacement.set,
        ended: true,
        before: 'unknown',
      ),
    );
    expect(controller.messages, hasLength(2));
    final survivor = controller.messages.first.id;
    await reducer.applyBatch(
      page([], placement: ChatPlacement.prepend, ended: true),
    );
    expect(controller.messages, hasLength(1));
    expect(controller.messages.single.id, survivor);
    expect(unit(controller.messages.single).members.map((a) => a.id), [
      'R',
      'tool',
    ]);
  });
  test('complete scope preserves real text separator even when it completes after work on both sides', () async {
    await reducer.applyBatch(
      page(
        [
          atom('R', 10, seq: 1),
          atom('tool', 30, seq: 2, kind: ChatAtomKind.toolCall),
          atom('text', 20, seq: 3, kind: ChatAtomKind.text),
        ],
        placement: ChatPlacement.set,
        ended: true,
      ),
    );
    expect(controller.messages.map((m) => unit(m).members.first.id), [
      'R',
      'text',
      'tool',
    ]);
  });
  test('reliable live admission connects sparse source positions without arithmetic assumptions', () async {
    await reducer.applyBatch(
      page([], placement: ChatPlacement.set, before: 'old'),
    );
    await reducer.applyBatch(page([atom('R', 10, terminal: false)]));
    final key = reducer.live.value.single.id;
    await reducer.applyBatch(
      page([atom('tool', 40, terminal: false, kind: ChatAtomKind.toolCall)]),
    );
    expect(reducer.live.value, hasLength(1));
    expect(reducer.live.value.single.id, key);
    expect(reducer.live.value.single.members.map((a) => a.id), ['R', 'tool']);
  });
  test(
    'window EOF never crosses an observed text boundary to an earlier work run',
    () async {
      await reducer.applyBatch(
        page(
          [atom('R', 30, seq: 4)],
          placement: ChatPlacement.set,
          ended: true,
          before: 'old',
        ),
      );
      final original = unit(controller.messages.single);
      await reducer.applyBatch(
        page(
          [
            atom('old-work', 10, seq: 1),
            atom('separator', 20, seq: 2, kind: ChatAtomKind.text),
            atom('same-work', 25, seq: 3),
          ],
          placement: ChatPlacement.prepend,
          ended: true,
        ),
        windowIntent: original.expansion,
      );
      expect(controller.messages, hasLength(3));
      expect(controller.messages.map((m) => unit(m).members.first.id), [
        'old-work',
        'separator',
        'same-work',
      ]);
      expect(unit(controller.messages.last).members.map((a) => a.id), [
        'same-work',
        'R',
      ]);
      expect(unit(controller.messages.last).lowerSeparator, 20);
    },
  );
  for (final hasSeparator in [false, true]) {
    test(
      'non-EOF detail accepts unknown fragments, then EOF resolves ${hasSeparator ? 'a real separator' : 'adjacency'} locally',
      () async {
        await reducer.applyBatch(
          page(
            [atom('R', 30, seq: 4)],
            placement: ChatPlacement.set,
            ended: true,
            before: 'unknown-prefix',
          ),
        );
        final message = controller.messages.single;
        final original = unit(message);
        original.expansion.expanded = true;
        original.expansion.before = 'old-window-cursor';
        await reducer.applyBatch(
          page(
            [atom('possibly-same-work', 10, seq: 3)],
            placement: ChatPlacement.prepend,
            ended: true,
            before: 'unread-older',
          ),
          windowIntent: original.expansion,
        );
        expect(controller.messages, hasLength(2));
        expect(controller.messages.last, same(message));
        expect(unit(controller.messages.last).members.map((a) => a.id), ['R']);
        expect(original.expansion.before, 'old-window-cursor');
        final firstKey = controller.messages.first.id;
        await reducer.applyBatch(
          page(
            [
              if (hasSeparator)
                atom('separator', 20, seq: 1, kind: ChatAtomKind.text),
            ],
            placement: ChatPlacement.prepend,
            ended: true,
          ),
          windowIntent: original.expansion,
        );
        expect(
          controller.messages.map((m) => m.id),
          hasSeparator ? [firstKey, 'separator', message.id] : [message.id],
        );
        expect(
          unit(controller.messages.last).members.map((a) => a.id),
          hasSeparator ? ['R'] : ['possibly-same-work', 'R'],
        );
        expect(
          unit(controller.messages.last).expansion,
          same(original.expansion),
        );
        expect(original.expansion.expanded, isTrue);
      },
    );
  }
  for (final staleError in [false, true]) {
    testWidgets(
      'historical fold/reopen rejects old body ${staleError ? 'error' : 'success'} before animation unmount',
      (tester) async {
        final payload = InlinePayload(
          bytes: utf8.encode(
            jsonEncode({
              'contract': 'anywork.chat/1',
              'type': 'thinking',
              'data': {},
              'bodies': [
                {
                  'key': 'body',
                  'label': '思考原文',
                  'byteLength': 16,
                  'reference': {
                    'databaseId': 'db',
                    'target': {
                      'kind': 'body',
                      'owner': {'kind': 'item', 'itemId': 'R'},
                      'key': 'body',
                    },
                  },
                },
              ],
            }),
          ),
        );
        await reducer.applyBatch(
          page(
            [atom('R', 10, payload: payload)],
            placement: ChatPlacement.set,
            ended: true,
          ),
        );
        final group = unit(controller.messages.single);
        group.expansion.expanded = true;
        final requests = <Completer<ContentWindow>>[];
        final borrows = <TimelineCurrentWindowDisplay>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ChatItemView(
                item: ChatItemPresentation.forUnit(group),
                isDisplayActive: () => true,
                contentRangeBuilder: (id, key, label, reference, witness) =>
                    TimelineContentRangeConnector(
                      itemId: id,
                      contentKey: key,
                      label: label,
                      reference: reference,
                      witness: witness,
                      isDisplayActive: () => true,
                      registerDisplay: (value) {
                        borrows.add(value);
                        return () => borrows.remove(value);
                      },
                      readContent: (reference, range) {
                        final request = Completer<ContentWindow>();
                        requests.add(request);
                        return request.future;
                      },
                    ),
              ),
            ),
          ),
        );
        await tester.pump();
        final old = borrows.single;
        final header = find.byKey(ValueKey('source-unit-header:${group.id}'));
        await tester.tap(header);
        expect(borrows, isEmpty);
        expect((old.window, old.error), (null, null));
        await tester.pump();
        await tester.tap(header);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(requests, hasLength(2));
        final fresh = borrows.single;
        if (staleError) {
          requests.first.completeError(StateError('old body failed'));
        } else {
          requests.first.complete(
            ContentWindow(
              offset: 0,
              bytes: utf8.encode('old body'),
              generation: 'old',
              availableThrough: 8,
              sealed: true,
            ),
          );
        }
        await tester.pump();
        expect((old.window, old.error), (null, null));
        expect((fresh.window, fresh.error), (null, null));
        expect(find.textContaining('old body'), findsNothing);
        requests.last.complete(
          ContentWindow(
            offset: 0,
            bytes: utf8.encode('fresh body'),
            generation: 'fresh',
            availableThrough: 10,
            sealed: true,
          ),
        );
        await tester.pump();
        expect(find.text('fresh body'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        expect(borrows, isEmpty);
      },
    );
  }
  test('complete EOF snapshot groups observed adjacent work despite sparse source order', () async {
    await reducer.applyBatch(
      page(
        [
          atom('R', 10, seq: 1),
          atom('tool', 20, seq: 2, kind: ChatAtomKind.toolCall),
        ],
        placement: ChatPlacement.set,
        ended: true,
      ),
    );
    expect(controller.messages, hasLength(1));
  });
  test('background B remains before later completed T work with an earlier segment of the same source', () async {
    final r = atom('R', 1, seq: 1);
    final text = atom('text', 2, seq: 2, kind: ChatAtomKind.text);
    final t = atom('T-tool', 3, seq: 4, kind: ChatAtomKind.toolCall);
    final b = ChatAtom(
      id: 'B',
      completionItemId: 'B',
      completionSeq: 3,
      source: const BackgroundResultChatSource(messageId: 'B'),
      sourceOrder: 1,
      kind: ChatAtomKind.toolCall,
      delivery: ChatDeliveryKind.independent,
      lifecycle: const TerminalChatAtom(
        started: null,
        ended: null,
        outcome: ChatTerminalOutcome.completed,
      ),
      contents: const [],
    );
    await reducer.applyBatch(page([r, text], placement: ChatPlacement.set));
    await reducer.applyBatch(
      page([atom('T-tool', 3, terminal: false, kind: ChatAtomKind.toolCall)]),
    );
    await reducer.applyBatch(page([b]));
    await reducer.applyBatch(page([t], ended: true));
    final liveOrder = controller.messages
        .map((m) => unit(m).members.first.id)
        .toList();
    reducer.dispose();
    reducer = TimelineMessageController(
      controller,
      generation: 2,
      imageResources: TimelineImageResources(threadId: 'T'),
      displayDemand: const ReadDemand(maxItems: 4, maxBytes: 32768),
    );
    await reducer.applyBatch(
      page([r, text, b, t], placement: ChatPlacement.set, ended: true),
    );
    final coldOrder = controller.messages
        .map((m) => unit(m).members.first.id)
        .toList();
    expect(liveOrder, coldOrder);
  });
  test('all known sparse group members are available to the ordinary detail selection', () async {
    await reducer.applyBatch(
      page(
        [atom('R', 10, seq: 2)],
        placement: ChatPlacement.set,
        ended: true,
        before: 'old',
      ),
    );
    final original = unit(controller.messages.single);
    await reducer.applyBatch(
      page(
        [atom('earlier', 5, seq: 1)],
        placement: ChatPlacement.prepend,
        ended: true,
      ),
      windowIntent: original.expansion,
    );
    expect(
      unit(controller.messages.single).members.map((a) => a.id),
      contains('earlier'),
    );
  });
  testWidgets(
    'historical group fold immediately revokes an already-mounted body window',
    (tester) async {
      final ref = ContentRef(
        databaseId: 'db',
        target: BodyContentTarget(
          owner: ItemContentOwner(itemId: 'R'),
          key: 'body',
        ),
      );
      final payload = InlinePayload(
        bytes: utf8.encode(
          jsonEncode({
            'contract': 'anywork.chat/1',
            'type': 'thinking',
            'data': {
              'outcome': {'kind': 'completed'},
            },
            'bodies': [
              {
                'key': 'body',
                'label': '思考原文',
                'byteLength': 16,
                'reference': {
                  'databaseId': 'db',
                  'target': {
                    'kind': 'body',
                    'owner': {'kind': 'item', 'itemId': 'R'},
                    'key': 'body',
                  },
                },
              },
            ],
          }),
        ),
      );
      final member = atom('R', 1, payload: payload);
      await reducer.applyBatch(
        page([member], placement: ChatPlacement.set, ended: true),
      );
      final group = unit(controller.messages.single);
      group.expansion.expanded = true;
      bool visible = true;
      group.expansion.onVisibilityChanged = (_, value) {
        visible = value;
      };
      TimelineCurrentWindowDisplay? display;
      final response = Completer<ContentWindow>();
      await tester.pumpWidget(
        MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatItemView(
              item: ChatItemPresentation.forUnit(group),
              isDisplayActive: () => true,
              contentRangeBuilder: (id, key, label, reference, witness) =>
                  TimelineContentRangeConnector(
                    itemId: id,
                    contentKey: key,
                    label: label,
                    reference: ref,
                    witness: witness,
                    isDisplayActive: () => true,
                    registerDisplay: (value) {
                      display = value;
                      return () {
                        display = null;
                      };
                    },
                    readContent: (reference, range) => response.future,
                  ),
            ),
          ),
        ),
      );
      await tester.pump();
      response.complete(
        ContentWindow(
          bytes: utf8.encode('body'),
          offset: 0,
          generation: 'g',
          availableThrough: 4,
          sealed: true,
        ),
      );
      await tester.pump();
      expect(display, isNotNull);
      expect(display!.window, isNotNull);
      await tester.tap(find.byKey(ValueKey('source-unit-header:${group.id}')));
      final afterFold = display?.window;
      await tester.pumpWidget(const SizedBox());
      expect(visible, isFalse);
      expect(afterFold, isNull);
    },
  );
}
