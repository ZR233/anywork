import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_children_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_group_members_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_children_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart'
    show ChatOperation, InMemoryChatController;

import '../support/chat_fixtures.dart';
import '../support/pump_client_future.dart';

const _bodyRef = ContentRef(
  databaseId: 'database',
  target: BodyContentTarget(
    owner: CurrentContentOwner(domain: 'reasoning', id: 'R', revision: 1),
    key: 'body',
  ),
);
ChatAtom _reasoning({PayloadData? payload}) => ChatAtom(
  id: 'R',
  source: const ForegroundTurnChatSource(turnId: 'T'),
  sourceOrder: 1,
  kind: ChatAtomKind.reasoning,
  delivery: ChatDeliveryKind.foreground,
  lifecycle: const ActiveChatAtom(
    started: null,
    status: ChatActiveStatus.running,
  ),
  contents: const [
    ChatAtomContent(role: ChatContentRole.body, reference: _bodyRef),
  ],
  payload: payload,
);
Widget _host(TimelineDisplayUnit unit) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: TimelineDisplayUnitView(
      key: ValueKey(unit.id),
      unit: unit,
      executionPresent: false,
      childBuilder: (_) =>
          TimelineGroupMembersConnector(unit: unit, threadId: 'thread'),
    ),
  ),
);
Future<void> _frames(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

TimelineDisplayUnit _unit(
  String id,
  Future<ConversationContent> Function(TimelineMembersRef, ReadDemand) open,
) {
  final unit = TimelineDisplayUnit(item: workItem(id, count: 82), live: false);
  unit.expansion.current = unit;
  unit.expansion.openMembers = open;
  return unit;
}

void main() {
  testWidgets(
    'same item and projection version with a new opaque generation revoke the original member scope before layout',
    (tester) async {
      final opened = <_Content>[];
      final references = <TimelineMembersRef>[];
      TimelineGroupDisplay? display;
      final controller = InMemoryChatController();
      final mapper = TimelineMessageController(
        controller,
        generation: 1,
        onUnitCreated: (unit) {
          unit.expansion.expanded = true;
          unit.expansion.openMembers = (reference, demand) async {
            references.add(reference);
            final content = _Content();
            opened.add(content);
            return content;
          };
          unit.expansion.registerDisplay = (value) {
            display = value;
            return () {
              if (identical(display, value)) display = null;
            };
          };
        },
      );
      addTearDown(() {
        mapper.dispose();
        controller.dispose();
      });
      CurrentProjection current(String generation) => CurrentProjection(
        sourceEffectSeq: 1,
        logicalStatus: ThreadStatusView.running,
        executionPresent: true,
        sources: const [],
        atoms: const [],
        items: [
          workItem(
            'same-group',
            closed: false,
            active: 1,
            count: 82,
            projectionGeneration: generation,
          ),
        ],
        previews: const [],
        collections: const [],
      );
      await mapper.applyBatch(
        ChatBatch(
          placement: ChatPlacement.set,
          entries: const [],
          current: current('opaque/rebuild:甲'),
        ),
      );
      await tester.pumpWidget(
        ValueListenableBuilder<List<TimelineDisplayUnit>>(
          valueListenable: mapper.live,
          builder: (_, units, _) => _host(units.single),
        ),
      );
      await _frames(tester);
      final original = opened.single;
      await original.consumer!.applyBatch(
        ChatBatch(
          placement: ChatPlacement.set,
          entries: [ChatAtomEntry(_reasoning())],
        ),
      );
      await tester.pump();
      final oldDisplay = display!;
      final oldScope = original.scopes.single;
      original.closeGate = Completer<void>();
      await mapper.applyBatch(
        ChatBatch(
          placement: ChatPlacement.append,
          entries: const [],
          current: current('opaque/rebuild:乙'),
        ),
      );
      expect(oldDisplay.isCurrent, isFalse);
      expect(oldScope.isActive, isFalse);
      expect(mapper.live.value.single.expansion.expanded, isTrue);
      await _frames(tester);
      expect(opened, hasLength(2));
      expect(references.map((reference) => reference.projectionVersion), [
        1,
        1,
      ]);
      expect(references.map((reference) => reference.projectionGeneration), [
        'opaque/rebuild:甲',
        'opaque/rebuild:乙',
      ]);
      expect(original.closeCalls, 1);
      expect(original.closed, isFalse);
      await opened.last.consumer!.applyBatch(
        ChatBatch(
          placement: ChatPlacement.set,
          entries: [ChatAtomEntry(_reasoning())],
        ),
      );
      await tester.pump();
      oldScope.watch.add(
        ContentWindow(
          bytes: utf8.encode('迟到旧代内容'),
          offset: 0,
          generation: 'old-body',
          availableThrough: 18,
          sealed: true,
        ),
      );
      opened.last.scopes.single.watch.add(
        ContentWindow(
          bytes: utf8.encode('新代内容'),
          offset: 0,
          generation: 'new-body',
          availableThrough: 12,
          sealed: true,
        ),
      );
      await tester.pump();
      expect(find.text('迟到旧代内容'), findsNothing);
      expect(find.text('新代内容'), findsOneWidget);
      expect(display!.membersRef!.projectionGeneration, 'opaque/rebuild:乙');
      original.closeGate!.complete();
      await _frames(tester);
      expect(original.closed, isTrue);
      await tester.pumpWidget(const SizedBox());
      await _frames(tester);
    },
  );

  testWidgets(
    'opening member failure stays local and explicit retry opens only the same typed scope',
    (tester) async {
      var opens = 0;
      final content = _Content();
      final unit = _unit('retry', (reference, demand) async {
        expect(reference.itemId, 'retry');
        if (opens++ == 0) throw StateError('成员读取失败');
        return content;
      })..expansion.expanded = true;
      await tester.pumpWidget(_host(unit));
      await _frames(tester);
      expect(find.textContaining('成员读取失败'), findsOneWidget);
      expect(find.text('82 项'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('timeline-members-retry')));
      await _frames(tester);
      expect(opens, 2);
      await content.consumer!.applyBatch(
        ChatBatch(
          placement: ChatPlacement.set,
          entries: [ChatAtomEntry(chatAtomMessage('retried', body: '重试后的成员'))],
        ),
      );
      await tester.pump();
      expect(find.text('重试后的成员'), findsOneWidget);
      expect(find.textContaining('成员读取失败'), findsNothing);
      expect(find.text('82 项'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _frames(tester);
    },
  );

  testWidgets(
    'GroupMembers is lazy, thinking reads on first expansion, folding revokes and joins original resources',
    (tester) async {
      final opened = <_Content>[];
      final references = <TimelineMembersRef>[];
      TimelineGroupDisplay? display;
      final unit = _unit('group', (reference, demand) async {
        references.add(reference);
        expect(demand.maxItems, greaterThan(0));
        final content = _Content();
        opened.add(content);
        return content;
      });
      unit.expansion.registerDisplay = (value) {
        display = value;
        return () => display = null;
      };
      await tester.pumpWidget(_host(unit));
      expect(opened, isEmpty);
      await tester.tap(find.byKey(const ValueKey('source-unit-header:group')));
      await _frames(tester);
      final old = opened.single;
      expect(references.single, unit.item.members);
      await old.consumer!.applyBatch(
        ChatBatch(
          placement: ChatPlacement.set,
          entries: [ChatAtomEntry(_reasoning())],
          before: 'members-next',
        ),
      );
      await tester.pump();
      expect(old.scopes, hasLength(1));
      old.scopes.single.watch.add(
        ContentWindow(
          bytes: utf8.encode('展开直接可读'),
          offset: 0,
          generation: 'g',
          availableThrough: 24,
          sealed: false,
        ),
      );
      await tester.pump();
      expect(find.text('展开直接可读'), findsOneWidget);
      expect(find.text('82 项'), findsOneWidget);
      expect(display!.atoms.single.id, 'R');
      expect(display!.windows.single.window!.bytes, utf8.encode('展开直接可读'));
      old.closeGate = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('source-unit-header:group')));
      expect(display!.isCurrent, isFalse);
      expect(display!.windows, isEmpty);
      expect(old.scopes.single.isActive, isFalse);
      await _frames(tester);
      expect(old.closeCalls, 1);
      expect(old.closed, isFalse);
      await tester.tap(find.byKey(const ValueKey('source-unit-header:group')));
      await _frames(tester);
      expect(opened, hasLength(2));
      old.closeGate!.complete();
      await _frames(tester);
      expect(old.closed, isTrue);
      await tester.pumpWidget(const SizedBox());
      await _frames(tester);
      expect(opened.last.closeCalls, 1);
    },
  );

  testWidgets(
    'GroupMembers reports unadmitted Set as loading without replacing the original display',
    (tester) async {
      final content = _Content();
      final state = content.state as LatestValue<ChatUiState<bool>>;
      final references = <TimelineMembersRef>[];
      TimelineGroupDisplay? display;
      var registrations = 0;
      final unit = _unit('set-admission', (reference, _) async {
        references.add(reference);
        return content;
      });
      unit.expansion.registerDisplay = (value) {
        registrations++;
        display = value;
        return () => display = null;
      };
      StreamSubscription<ChatOperation>? observer;
      bool? loadingDuringSet;
      try {
        await tester.pumpWidget(_host(unit));
        expect(references, isEmpty);
        final header = find.byKey(
          const ValueKey('source-unit-header:set-admission'),
        );
        await tester.tap(header);
        await _frames(tester);
        final consumer = content.consumer!;
        final prefix = _reasoning();
        await pumpClientFuture(
          tester,
          consumer.applyBatch(
            ChatBatch(
              placement: ChatPlacement.set,
              entries: [ChatAtomEntry(prefix)],
            ),
          ),
          'admit initial GroupMembers prefix',
        );
        await tester.pump();
        final body = ContentWindow(
          bytes: utf8.encode('original member prefix'),
          offset: 0,
          generation: 'prefix-body',
          availableThrough: utf8.encode('original member prefix').length,
          sealed: false,
        );
        final oldScope = content.scopes.single;
        oldScope.watch.add(body);
        await tester.pump();
        expect(find.text('original member prefix'), findsOneWidget);
        expect(
          tester.getSize(find.text('original member prefix')).isEmpty,
          isFalse,
        );
        final original = display!;
        final reference = references.single;
        final owner = unit.expansion;
        final bodyGeneration = owner.bodyGeneration;
        final source = unit.item.source;
        final prefixReference = prefix.contents.single.reference;
        final child = tester.state(
          find.byType(TimelineChildrenConnector),
        ) as TimelineChildrenDisplay;
        final controller = tester
            .widget<TimelineChildrenView>(find.byType(TimelineChildrenView))
            .controller;
        final generation = child.generation;
        expect(child.ready && child.isCurrent, isTrue);
        expect(original.loading, isFalse);
        expect(original.atoms.single, same(prefix));
        expect(original.windows.single.reference, same(prefixReference));
        expect(prefix.source, source);
        final operations = <String>[];
        observer = controller.operationsStream.listen(
          (operation) => operations.add(operation.type.name),
        );
        final added = ChatAtom(
          id: 'S',
          completionItemId: 'S',
          source: source,
          sourceOrder: 2,
          kind: ChatAtomKind.text,
          delivery: ChatDeliveryKind.foreground,
          lifecycle: const TerminalChatAtom(
            started: null,
            ended: null,
            outcome: ChatTerminalOutcome.completed,
          ),
          contents: const [],
          payload: chatAtomMessage('S', body: 'new member').payload,
        );
        var completed = false;
        final admission = consumer.applyBatch(
          ChatBatch(
            placement: ChatPlacement.set,
            entries: [ChatAtomEntry(prefix), ChatAtomEntry(added)],
          ),
        );
        final completion = admission.then<void>((_) {
          completed = true;
        });
        // No pump, sleep or gate: borrow the real Set's synchronous await gap.
        loadingDuringSet = original.loading;
        expect(completed, isFalse);
        expect(display, same(original));
        expect(original.isCurrent && original.expanded, isTrue);
        expect(original.membersRef, same(reference));
        expect(unit.expansion, same(owner));
        expect(owner.current, same(unit));
        expect(owner.bodyGeneration, same(bodyGeneration));
        expect(unit.item.source, source);
        expect(content.consumer, same(consumer));
        expect(child.ready || child.isCurrent, isFalse);
        expect(child.generation, greaterThan(generation));
        expect(child.messages, isEmpty);
        expect(original.atoms, isEmpty, reason: 'The borrow is not admitted');
        expect(controller.messages.map((message) => message.id), contains('R'));
        expect(
          chatItemPresentationOf(controller.messages.first)!.atom,
          same(prefix),
        );
        debugPrintSynchronously(
          'GroupMembers pending Set: ${jsonEncode({'completed': completed, 'childReady': child.ready, 'controllerIds': controller.messages.map((message) => message.id).toList(), 'borrowedIds': original.atoms.map((atom) => atom.id).toList(), 'loading': loadingDuringSet})}',
        );
        await pumpClientFuture(tester, admission, 'admit original member Set');
        await pumpClientFuture(
          tester,
          completion,
          'observe original Set result',
        );
        await tester.pump();
        expect(completed, isTrue);
        expect(oldScope.isActive, isFalse);
        expect(display, same(original));
        expect(child.ready && child.isCurrent, isTrue);
        expect(original.loading, isFalse);
        expect(original.error, isNull);
        expect(original.membersRef, same(reference));
        expect(owner.bodyGeneration, same(bodyGeneration));
        expect(original.atoms, orderedEquals([prefix, added]));
        expect(
          tester
              .widget<TimelineChildrenView>(find.byType(TimelineChildrenView))
              .controller,
          same(controller),
        );
        expect(operations, ['set']);
        expect(content.scopes, hasLength(2));
        content.scopes.last.watch.add(body);
        await tester.pump();
        expect(original.windows.single.reference, same(prefixReference));
        expect(find.text('original member prefix'), findsOneWidget);
        expect(find.text('new member'), findsOneWidget);
        expect(tester.getSize(find.text('new member')).isEmpty, isFalse);
        expect(references, [unit.item.members]);
        expect(registrations, 1);
        debugPrintSynchronously(
          'GroupMembers admitted Set: ${jsonEncode({'operations': operations, 'memberIds': original.atoms.map((atom) => atom.id).toList(), 'controllerIds': controller.messages.map((message) => message.id).toList()})}',
        );
        content.closeGate = Completer<void>();
        await tester.tap(header);
        expect(original.isCurrent, isFalse);
        expect(original.atoms, isEmpty);
        expect(original.windows, isEmpty);
        expect(content.scopes.every((scope) => !scope.isActive), isTrue);
        await _frames(tester);
        expect(content.closeCalls, 1);
        expect(content.closed, isFalse);
        content.closeGate!.complete();
        await _frames(tester);
        expect(content.closed, isTrue);
        expect(state.observerCount, 0);
        expect(display, isNull);
        expect(references, hasLength(1));
        debugPrintSynchronously(
          'GroupMembers original resources closed: ${jsonEncode({'opens': references.length, 'closes': content.closeCalls, 'closed': content.closed})}',
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (observer != null) {
          await pumpClientFuture(
            tester,
            observer.cancel(),
            'cancel Set observer',
          );
        }
        final gate = content.closeGate;
        if (gate != null && !gate.isCompleted) gate.complete();
        await tester.pumpWidget(const SizedBox());
        await _frames(tester);
        for (final scope in content.scopes) {
          expect(scope.watch.hasListener, isFalse);
          // A read-only scope may never subscribe: its single-stream done
          // cannot complete without a listener. UI subscriptions are gone.
          unawaited(scope.watch.close());
        }
        state.close();
        unit.expansion.retirement.dispose();
        unit.expansion.dispose();
      }
      // Assert the captured gap only after joining the original UI resources.
      expect(
        loadingDuringSet,
        isTrue,
        reason: 'An unadmitted Set is loading, not a real zero-member window',
      );
    },
  );

  for (final lateFailure in [false, true]) {
    testWidgets(
      'retired member open ${lateFailure ? 'failure' : 'success'} cannot rebind into the next group',
      (tester) async {
        final pending = Completer<ConversationContent>();
        final a = _unit('A', (_, _) => pending.future)
          ..expansion.expanded = true;
        await tester.pumpWidget(_host(a));
        await tester.pump();
        a.expansion.retire();
        final current = _Content();
        final b = _unit('B', (_, _) async => current)
          ..expansion.expanded = true;
        await tester.pumpWidget(_host(b));
        await _frames(tester);
        await current.consumer!.applyBatch(
          ChatBatch(
            placement: ChatPlacement.set,
            entries: [ChatAtomEntry(chatAtomMessage('B-body', body: '当前组'))],
          ),
        );
        await tester.pump();
        expect(find.text('当前组'), findsOneWidget);
        final late = _Content();
        if (lateFailure) {
          pending.completeError(StateError('旧读取失败'));
        } else {
          pending.complete(late);
        }
        await _frames(tester);
        expect(find.text('当前组'), findsOneWidget);
        expect(find.textContaining('旧读取失败'), findsNothing);
        if (!lateFailure) {
          expect(late.consumer, isNull);
          expect(late.closed, isTrue);
        }
        expect(current.closeCalls, 0);
        await tester.pumpWidget(const SizedBox());
        await _frames(tester);
        expect(current.closed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final staleError in [false, true]) {
    testWidgets(
      'Deferred payload retired ${staleError ? 'error' : 'success'} cannot overwrite a reopened member request',
      (tester) async {
        final opened = <_Content>[];
        final unit = _unit('deferred', (_, _) async {
          final content = _Content();
          opened.add(content);
          return content;
        });
        unit.expansion.expanded = true;
        Future<void> deliver(_Content content) => content.consumer!.applyBatch(
          ChatBatch(
            placement: ChatPlacement.set,
            entries: [
              ChatAtomEntry(
                _reasoning(
                  payload: const DeferredPayload(
                    reference: ContentRef(
                      databaseId: 'database',
                      target: ItemPayloadTarget(itemId: 'original-payload'),
                    ),
                    byteLength: 100000,
                  ),
                ),
              ),
            ],
          ),
        );
        await tester.pumpWidget(_host(unit));
        await _frames(tester);
        await deliver(opened.single);
        await tester.pump();
        final open = find.text('按需查看原文 · 100000 字节');
        await tester.tap(open);
        await tester.pump();
        final old = opened.single.scopes.single;
        await tester.tap(
          find.byKey(const ValueKey('source-unit-header:deferred')),
        );
        await _frames(tester);
        await tester.tap(
          find.byKey(const ValueKey('source-unit-header:deferred')),
        );
        await _frames(tester);
        await deliver(opened.last);
        await tester.pump();
        await tester.tap(open);
        await tester.pump();
        final fresh = opened.last.scopes.single;
        if (staleError) {
          old.read.completeError(StateError('旧正文失败'));
        } else {
          old.read.complete(
            ContentWindow(
              bytes: utf8.encode('迟到正文'),
              offset: 0,
              generation: 'g',
              availableThrough: 12,
              sealed: true,
            ),
          );
        }
        await tester.pump();
        expect(find.text('迟到正文'), findsNothing);
        expect(find.textContaining('旧正文失败'), findsNothing);
        fresh.read.complete(
          ContentWindow(
            bytes: utf8.encode('新正文'),
            offset: 0,
            generation: 'g',
            availableThrough: 9,
            sealed: true,
          ),
        );
        await tester.pump();
        expect(find.text('新正文'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await _frames(tester);
      },
    );
  }
}

final class _Content extends Fake implements ConversationContent {
  @override
  final state = LatestValue<ChatUiState<bool>>(const ChatReady('thread', true));
  @override
  AttemptId get currentAttemptId => const AttemptId(1);
  ConversationBatchConsumer? consumer;
  final scopes = <_Scope>[];
  int closeCalls = 0;
  bool closed = false;
  @override
  bool get isClosed => closed;
  Completer<void>? closeGate;
  @override
  Observation attachConsumer(
    ConversationBatchConsumer consumer, {
    required ReadDemand demand,
  }) {
    this.consumer = consumer;
    return _Observation(() {});
  }

  @override
  ConversationQueryScope openScope({required int generation}) {
    final scope = _Scope();
    scopes.add(scope);
    return scope;
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    closeCalls++;
    for (final scope in scopes) {
      scope.retire();
    }
    await closeGate?.future;
    closed = true;
    return CloseReport();
  }
}

final class _Observation implements Observation {
  _Observation(this.onCancel);
  final VoidCallback onCancel;
  @override
  bool isCancelled = false;
  @override
  bool isPaused = false;
  @override
  void pause() => isPaused = true;
  @override
  void resume() => isPaused = false;
  @override
  void cancel() {
    if (!isCancelled) {
      isCancelled = true;
      onCancel();
    }
  }
}

final class _Scope extends Fake implements ConversationQueryScope {
  @override
  bool isActive = true;
  final watch = StreamController<ContentWindow>();
  final read = Completer<ContentWindow>();
  @override
  Stream<ContentWindow> watchContent({
    required ContentRef reference,
    required ContentRange range,
  }) => watch.stream;
  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) => read.future;
  @override
  void retire() => isActive = false;
  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    retire();
    return CloseReport();
  }
}
