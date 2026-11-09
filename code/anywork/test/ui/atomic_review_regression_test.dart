import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/completion_run_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/display_fixtures.dart';

const _bodyRef = ContentRef(
  databaseId: 'database',
  target: BodyContentTarget(
    owner: ItemContentOwner(itemId: 'R'),
    key: 'body',
  ),
);
ChatAtom _reasoning({PayloadData? payload}) => ChatAtom(
  id: 'R',
  source: const ForegroundTurnChatSource(turnId: 'turn'),
  sourceOrder: 71,
  kind: ChatAtomKind.reasoning,
  delivery: ChatDeliveryKind.foreground,
  completionItemId: 'R',
  completionSeq: 71,
  lifecycle: const TerminalChatAtom(
    started: null,
    ended: null,
    outcome: ChatTerminalOutcome.completed,
  ),
  contents: const [
    ChatAtomContent(role: ChatContentRole.body, reference: _bodyRef),
  ],
  payload: payload,
);

Widget _host(TimelineDisplayUnit unit, _Content content) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: TimelineDisplayUnitView(
      key: ValueKey(unit.id),
      unit: unit,
      childBuilder: (_) => CompletionRunConnector(
        unit: unit,
        threadId: 'thread',
        content: content,
        images: content.images,
      ),
    ),
  ),
);

TimelineDisplayUnit _unit(
  String id,
  Future<DisplayMembers> Function(
    DisplayBlockRef,
    DisplayMemberWindow,
    ReadDemand,
  )
  open,
) {
  final unit = TimelineDisplayUnit.live(
    block: LiveDisplayBlock(
      id: id,
      blockOrder: 1,
      closing: false,
      body: WorkDisplayBlock(
        summary: displaySummary(82, terminal: 1, running: 81),
        members: DisplayBlockRef(databaseId: 'database', blockId: id),
      ),
    ),
    executionPresent: true,
    expansion: TimelineExpansionIntent(),
  );
  unit.expansion.current = unit;
  unit.expansion.openDisplayMembers = open;
  return unit;
}

DisplayMemberPage _page(
  TimelineDisplayUnit unit,
  List<ChatAtom> atoms, {
  int revision = 1,
}) => DisplayMemberPage(
  block: unit.memberReference!,
  revision: revision,
  sealed: false,
  before: 70,
  entries: [
    for (var i = 0; i < atoms.length; i++)
      DisplayMemberHead(
        memberKey: atoms[i].id,
        memberOrder: 71 + i,
        atom: atoms[i],
        completionId: atoms[i].completionItemId,
      ),
  ],
);

Future<void> _frames(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

Finder _header(TimelineDisplayUnit unit) =>
    find.byKey(ValueKey('completion-run-header:${unit.id}'));
Future<void> _toggle(WidgetTester tester, TimelineDisplayUnit unit) => tester
    .tap(find.descendant(of: _header(unit), matching: find.byType(Text)).first);
Future<void> _expandReasoning(WidgetTester tester) async {
  await _frames(tester);
  final header = find.descendant(
    of: find.byType(TimelineReasoningView),
    matching: find.byType(TimelineActivityRow),
  );
  final label = find.descendant(of: header, matching: find.byType(Text)).first;
  await tester.ensureVisible(label);
  expect(label.hitTestable(), findsOneWidget);
  await tester.tap(label);
  await tester.pump();
}

ContentWindow _window(String text) => ContentWindow(
  bytes: utf8.encode(text),
  offset: 0,
  generation: 'body',
  availableThrough: utf8.encode(text).length,
  sealed: true,
);
Future<void> _dispose(
  WidgetTester tester,
  TimelineDisplayUnit unit,
  _Content content,
) async {
  unit.expansion.retire();
  await tester.pumpWidget(const SizedBox());
  await _frames(tester);
  expect(
    content.scopes.every(
      (scope) => !scope.isActive && !scope.watch.hasListener,
    ),
    isTrue,
  );
  content.images.release();
  content.state.close();
  unit.expansion.retirement.dispose();
  unit.expansion.dispose();
  expect(tester.takeException(), isNull);
}

void _expectCount(WidgetTester tester) {
  final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
  expect(
    find.text(
      '${l10n.timelineGroupRecord} · ${l10n.timelineGroupMemberCount(82)}',
    ),
    findsOneWidget,
  );
}

void main() {
  testWidgets(
    'member open failure stays local; explicit retry uses the same block/window',
    (tester) async {
      var opens = 0;
      final content = _Content();
      final members = _Members();
      final unit = _unit('retry', (reference, window, demand) async {
        expect(reference.blockId, 'retry');
        expect(window, isA<LatestDisplayMembers>());
        expect(demand.maxItems, 12);
        if (opens++ == 0) throw StateError('成员读取失败');
        return members;
      })..expansion.expanded = true;
      await tester.pumpWidget(_host(unit, content));
      await _frames(tester);
      expect(find.textContaining('成员读取失败'), findsOneWidget);
      _expectCount(tester);
      await tester.tap(find.widgetWithText(TextButton, '重试'));
      await _frames(tester);
      expect(opens, 2);
      members.deliver(_page(unit, [_message('retried', '重试后的成员')]));
      await tester.pump();
      expect(find.text('重试后的成员'), findsOneWidget);
      expect(find.textContaining('成员读取失败'), findsNothing);
      _expectCount(tester);
      await _dispose(tester, unit, content);
      expect(members.closed, isTrue);
    },
  );

  testWidgets(
    'Work/member bodies are lazy; folding revokes immediately and joins original handles',
    (tester) async {
      final content = _Content();
      final opened = <_Members>[];
      final references = <DisplayBlockRef>[];
      TimelineGroupDisplay? display;
      final unit = _unit('group', (reference, window, demand) async {
        references.add(reference);
        expect(window, isA<LatestDisplayMembers>());
        expect(demand.maxItems, 12);
        final members = _Members();
        opened.add(members);
        return members;
      });
      unit.expansion.registerDisplay = (value) {
        display = value;
        return () => display = null;
      };
      await tester.pumpWidget(_host(unit, content));
      expect(opened, isEmpty);
      expect(content.scopes, isEmpty);
      await _toggle(tester, unit);
      await _frames(tester);
      final old = opened.single;
      expect(references.single, unit.memberReference);
      old.deliver(_page(unit, [_reasoning()]));
      await tester.pump();
      expect(content.scopes, isEmpty, reason: 'Reasoning body remains folded');
      await _expandReasoning(tester);
      expect(content.scopes, hasLength(1));
      content.scopes.single.watch.add(_window('展开直接可读'));
      await tester.pump();
      expect(find.text('展开直接可读'), findsOneWidget);
      expect(display!.atoms.single.id, 'R');
      expect(display!.windows.single.window!.bytes, utf8.encode('展开直接可读'));
      final original = display!;
      old.closeGate = Completer<void>();
      await _toggle(tester, unit);
      expect(original.isCurrent, isFalse);
      expect(original.atoms, isEmpty);
      expect(original.windows, isEmpty);
      expect(content.scopes.single.isActive, isFalse);
      expect(old.closeRequested, isTrue);
      await _frames(tester);
      expect(old.closeCalls, 1);
      expect(old.closed, isFalse);
      await _toggle(tester, unit);
      await _frames(tester);
      expect(opened, hasLength(2));
      old.closeGate!.complete();
      await _frames(tester);
      expect(old.closed, isTrue);
      await _dispose(tester, unit, content);
      expect(opened.last.closed, isTrue);
    },
  );

  testWidgets(
    'first member next is loading; complete structural pages replace atomically without resetting the display/body',
    (tester) async {
      final content = _Content();
      final members = _Members();
      var opens = 0;
      var registrations = 0;
      TimelineGroupDisplay? display;
      final unit = _unit('page-admission', (_, _, _) async {
        opens++;
        return members;
      })..expansion.expanded = true;
      unit.expansion.registerDisplay = (value) {
        registrations++;
        display = value;
        return () => display = null;
      };
      await tester.pumpWidget(_host(unit, content));
      await _frames(tester);
      final original = display!;
      final owner = unit.expansion;
      final bodyGeneration = owner.bodyGeneration;
      expect(
        original.loading,
        isTrue,
        reason: 'Unreturned first page is not a zero-member result',
      );
      expect(original.atoms, isEmpty);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final prefix = _reasoning();
      members.deliver(_page(unit, [prefix]));
      await tester.pump();
      await _expandReasoning(tester);
      final scope = content.scopes.single;
      scope.watch.add(_window('original member prefix'));
      await tester.pump();
      final memberState = tester.state(find.byType(TimelineMemberAtom));
      expect(find.text('original member prefix'), findsOneWidget);
      expect(original.loading, isFalse);
      expect(
        members.nextCalls,
        2,
        reason: 'One current page, one next structural update in flight',
      );
      // Awaiting a later page leaves the previously accepted page readable.
      expect(original.atoms.single, same(prefix));
      expect(original.windows.single.reference, _bodyRef);
      final added = _message('S', 'new member');
      members.deliver(_page(unit, [prefix, added], revision: 2));
      expect(original.atoms, [
        same(prefix),
      ], reason: 'No partial page leaks before next completes');
      await tester.pump();
      expect(display, same(original));
      expect(original.isCurrent && original.expanded, isTrue);
      expect(original.loading, isFalse);
      expect(original.error, isNull);
      expect(original.blockReference, unit.memberReference);
      expect(owner.bodyGeneration, same(bodyGeneration));
      expect(original.atoms, orderedEquals([prefix, added]));
      expect(
        tester.state(find.byType(TimelineMemberAtom).first),
        same(memberState),
      );
      expect(content.scopes, [scope]);
      expect(scope.isActive, isTrue);
      expect(original.windows.single.reference, _bodyRef);
      expect(find.text('original member prefix'), findsOneWidget);
      expect(find.text('new member'), findsOneWidget);
      expect(tester.getSize(find.text('new member')).isEmpty, isFalse);
      expect(opens, 1);
      expect(registrations, 1);
      _expectCount(tester);
      await _dispose(tester, unit, content);
      expect(members.closed, isTrue);
    },
  );

  for (final lateFailure in [false, true]) {
    testWidgets(
      'retired member open ${lateFailure ? 'failure' : 'success'} cannot rebind into the next group',
      (tester) async {
        final content = _Content();
        final pending = Completer<DisplayMembers>();
        final a = _unit('A', (_, _, _) => pending.future)
          ..expansion.expanded = true;
        await tester.pumpWidget(_host(a, content));
        await _frames(tester);
        a.expansion.retire();
        final current = _Members();
        final b = _unit('B', (_, _, _) async => current)
          ..expansion.expanded = true;
        await tester.pumpWidget(_host(b, content));
        await _frames(tester);
        current.deliver(_page(b, [_message('B-body', '当前组')]));
        await tester.pump();
        expect(find.text('当前组'), findsOneWidget);
        final late = _Members();
        if (lateFailure) {
          pending.completeError(StateError('旧读取失败'));
        } else {
          pending.complete(late);
        }
        await _frames(tester);
        expect(find.text('当前组'), findsOneWidget);
        expect(find.textContaining('旧读取失败'), findsNothing);
        if (!lateFailure) {
          expect(late.nextCalls, 0);
          expect(late.closeRequested && late.closed, isTrue);
        }
        expect(current.closeCalls, 0);
        await _dispose(tester, b, content);
        expect(current.closed, isTrue);
        a.expansion.retirement.dispose();
        a.expansion.dispose();
      },
    );
  }

  for (final staleError in [false, true]) {
    testWidgets(
      'Deferred payload retired ${staleError ? 'error' : 'success'} cannot overwrite a reopened member request',
      (tester) async {
        final content = _Content();
        final opened = <_Members>[];
        final unit = _unit('deferred', (_, _, _) async {
          final members = _Members();
          opened.add(members);
          return members;
        })..expansion.expanded = true;
        void deliver(_Members members) => members.deliver(
          _page(unit, [
            _reasoning(
              payload: const DeferredPayload(
                reference: ContentRef(
                  databaseId: 'database',
                  target: ItemPayloadTarget(itemId: 'R'),
                ),
                byteLength: 100000,
              ),
            ),
          ]),
        );
        await tester.pumpWidget(_host(unit, content));
        await _frames(tester);
        deliver(opened.single);
        await tester.pump();
        final old = content.scopes.single;
        await _toggle(tester, unit);
        expect(old.isActive, isFalse);
        await _frames(tester);
        await _toggle(tester, unit);
        await _frames(tester);
        deliver(opened.last);
        await tester.pump();
        final fresh = content.scopes.last;
        expect(fresh, isNot(same(old)));
        if (staleError) {
          old.completed.completeError(StateError('旧正文失败'));
        } else {
          old.completed.complete(_completedReasoning('迟到正文'));
        }
        await tester.pump();
        expect(find.text('迟到正文'), findsNothing);
        expect(find.textContaining('旧正文失败'), findsNothing);
        fresh.completed.complete(_completedReasoning('新正文'));
        await tester.pump();
        expect(find.text('新正文'), findsOneWidget);
        await _dispose(tester, unit, content);
        expect(opened.every((members) => members.closed), isTrue);
      },
    );
  }
}

/// Only the external handle's next/close timing. No projection or UI reduction.
final class _Members implements DisplayMembers {
  Completer<DisplayMemberPage?>? _next;
  Completer<void>? closeGate;
  int nextCalls = 0;
  int closeCalls = 0;
  bool closeRequested = false;
  bool closed = false;
  @override
  Future<DisplayMemberPage?> next() {
    nextCalls++;
    if (closeRequested) return Future.value(null);
    expect(_next, isNull, reason: 'At most one next is outstanding');
    return (_next = Completer<DisplayMemberPage?>()).future;
  }

  void deliver(DisplayMemberPage page) {
    final pending = _next!;
    _next = null;
    pending.complete(page);
  }

  @override
  void requestClose() {
    closeRequested = true;
    final pending = _next;
    _next = null;
    pending?.complete(null);
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    await closeGate?.future;
    closed = true;
  }
}

final class _Content extends Fake implements ConversationContent {
  @override
  final LatestValue<ChatUiState<bool>> state = LatestValue<ChatUiState<bool>>(
    const ChatReady('thread', true),
  );
  @override
  AttemptId get currentAttemptId => const AttemptId(1);
  @override
  bool get isClosed => false;
  final images = TimelineImageResources(threadId: 'thread');
  final scopes = <_Scope>[];
  @override
  ConversationQueryScope openScope({required int generation}) {
    final scope = _Scope();
    scopes.add(scope);
    return scope;
  }
}

final class _Scope extends Fake implements ConversationQueryScope {
  @override
  bool isActive = true;
  final watch = StreamController<ContentWindow>.broadcast();
  final read = Completer<ContentWindow>();
  final completed = Completer<CompletedEntry>();
  @override
  Future<CompletedEntry> readCompleted({
    required String recordId,
    required ReadDemand demand,
  }) {
    expect(recordId, 'R');
    expect(demand.maxItems, 1);
    expect(demand.maxBytes, 64 * 1024);
    return completed.future;
  }

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
    await watch.close();
    return CloseReport();
  }
}

CompletedEntry _completedReasoning(String text) => CompletedEntry(
  recordId: 'R',
  completionSeq: 71,
  run: null,
  mainPresentation: MainPresentation.foregroundWork,
  atom: _reasoning(payload: _message('R', text).payload),
);

ChatAtom _message(String id, String summary) => ChatAtom(
  id: id,
  completionItemId: id,
  completionSeq: 72,
  source: const ForegroundTurnChatSource(turnId: 'turn'),
  sourceOrder: 72,
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
        'data': {
          'outcome': {'kind': 'completed'},
        },
        'bodies': [
          {
            'key': 'part.summaryText.0',
            'byteLength': utf8.encode(summary).length,
            'inline': utf8.encode(summary),
          },
        ],
      }),
    ),
  ),
);
