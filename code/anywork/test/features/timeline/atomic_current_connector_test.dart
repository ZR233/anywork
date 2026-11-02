import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/src/contracts/stamps.dart';
import 'package:anywork_client/src/lifecycle/resource_budget.dart';
import 'package:anywork_client/src/observation/latest_value.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = ForegroundTurnChatSource(turnId: 'T');
ContentRef _ref({int revision = 1}) => ContentRef(
  databaseId: 'database',
  target: BodyContentTarget(
    owner: CurrentContentOwner(
      domain: 'execution',
      id: 'reasoning',
      revision: revision,
    ),
    key: 'body',
  ),
);

ChatAtom _atom(
  String id,
  int order, {
  ChatAtomKind kind = ChatAtomKind.reasoning,
  ContentRef? reference,
  PayloadData? payload,
}) => ChatAtom(
  id: id,
  source: _source,
  sourceOrder: order,
  kind: kind,
  delivery: ChatDeliveryKind.foreground,
  payload: payload,
  lifecycle: const ActiveChatAtom(
    started: null,
    status: ChatActiveStatus.running,
  ),
  contents: [
    if (reference != null)
      ChatAtomContent(role: ChatContentRole.body, reference: reference),
  ],
);

CurrentProjection _current(
  List<ChatAtom> atoms, {
  CurrentActivityHead? activity,
  StudioTurnActivity phase = StudioTurnActivity.thinking,
  List<CurrentContentPreview> previews = const [],
}) => CurrentProjection(
  sourceEffectSeq: 1,
  logicalStatus: ThreadStatusView.running,
  executionPresent: true,
  active: activity,
  activeTurn: CurrentTurnHead(id: 'T', phase: phase),
  sources: const [
    ChatSourceState(
      source: _source,
      lifecycle: ActiveChatSource(),
      started: null,
      ended: null,
    ),
  ],
  atoms: atoms,
  previews: previews,
  collections: const [],
);

ContentWindow _window(String text, {int offset = 0}) => ContentWindow(
  bytes: utf8.encode(text),
  offset: offset,
  generation: 'g',
  availableThrough: 100000,
  sealed: false,
);

Future<void> _flush(WidgetTester tester) async {
  // Live indicators continuously animate. Drain only the disclosure animation
  // and original scope cancellation chain, not all future animation frames.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

final class _Harness {
  final content = _Content();
  final controller = InMemoryChatController();
  final images = TimelineImageResources(threadId: 'thread');
  late final presentation = TimelineMessageController(
    controller,
    generation: 1,
    imageResources: images,
  );
  CurrentProjection current = _current([]);
  TimelineCurrentDisplay? display;

  Future<void> accept(List<ChatAtom> atoms) async {
    current = _current(atoms);
    await presentation.applyBatch(
      ChatBatch(
        placement: ChatPlacement.append,
        entries: const [],
        current: current,
      ),
    );
  }

  Widget host({
    ConversationActivityView? view,
    ValueListenable<({bool hasMore, bool loading, Object? error})>? activity,
    Future<void> Function()? loadActivity,
  }) => MaterialApp(
    theme: pureStudioTheme(),
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ConversationCurrentConnector(
        key: ObjectKey(content),
        current: current,
        content: content,
        view:
            view ??
            const ConversationActivityView(
              identity: 'active',
              kind: ConversationActivityKind.thinking,
              summary: '思考中',
              expandable: true,
            ),
        units: presentation.live,
        images: images,
        activity: activity,
        loadActivity: loadActivity,
        readAttachment: (_) async => Uint8List(0),
        isDisplayActive: () => true,
        registerDisplay: (value) {
          display = value;
          return () => display = null;
        },
      ),
    ),
  );
  Finder get header => find.byKey(
    ValueKey('source-unit-header:${presentation.live.value.first.id}'),
  );
  void dispose() {
    presentation.dispose();
    images.release();
    controller.dispose();
  }
}

final class _Content extends Fake implements ConversationContent {
  final source = LatestValue<ChatUiState<bool>>(
    const ChatReady('thread', true),
  );
  final scopes = <_Scope>[];
  Future<ContentWindow> Function(ContentRef, ContentRange)? onRead;
  @override
  bool get isClosed => false;
  @override
  ValueObservation<ChatUiState<bool>> get state => source;
  @override
  AttemptId get currentAttemptId => const AttemptId(1);
  @override
  ConversationQueryScope openScope({required int generation}) {
    final scope = _Scope()..onRead = onRead;
    scopes.add(scope);
    return scope;
  }
}

final class _Scope extends Fake implements ConversationQueryScope {
  final watches = <StreamController<ContentWindow>>[];
  final requests = <(ContentRef, ContentRange)>[];
  bool active = true;
  bool closed = false;
  int cancels = 0;
  Completer<void>? cancelGate;
  Object? closeFailure;
  Future<ContentWindow> Function(ContentRef, ContentRange)? onRead;
  final reads = <(ContentRef, ContentRange)>[];
  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    reads.add((reference, range));
    return onRead!(reference, range);
  }

  @override
  bool get isActive => active;
  @override
  Stream<ContentWindow> watchContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    requests.add((reference, range));
    final watch = StreamController<ContentWindow>(
      onCancel: () {
        cancels++;
        return cancelGate?.future;
      },
    );
    watches.add(watch);
    return watch.stream;
  }

  @override
  void retire() {
    active = false;
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    await cancelGate?.future;
    if (closeFailure case final failure?) {
      return CloseReport(
        unresolved: [
          UnresolvedResource(
            owner: 'scope',
            attemptId: const AttemptId(1),
            reason: failure,
          ),
        ],
      );
    }
    closed = true;
    return CloseReport();
  }
}

void main() {
  testWidgets(
    'after-text projects thinking without a phantom group, then admits real text and new work',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      const coarse = CurrentActivityHead(
        id: 'attempt',
        kind: ThreadActivityKind.responding,
        summary: '原始粗阶段',
        toolCount: 0,
        backgroundToolCount: 0,
      );
      ContentRef body(String id) => ContentRef(
        databaseId: 'database',
        target: BodyContentTarget(
          owner: ItemContentOwner(itemId: id),
          key: 'body',
        ),
      );
      CurrentProjection current(
        List<ChatAtom> atoms, {
        bool oldPreview = false,
      }) => _current(
        atoms,
        activity: coarse,
        phase: StudioTurnActivity.responding,
        previews: [
          if (oldPreview)
            CurrentContentPreview(
              id: 'text-A',
              role: CurrentContentRole.response,
              text: '正文A',
              reference: body('text-A'),
            ),
        ],
      );
      ChatAtom completed(
        String id,
        int order,
        int seq,
        ChatAtomKind kind,
        String text, {
        bool input = false,
      }) => ChatAtom(
        id: id,
        completionItemId: 'payload-$id',
        completionSeq: seq,
        source: input ? const InputChatSource(inputId: 'user') : _source,
        sourceOrder: order,
        kind: kind,
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
              'type': kind == ChatAtomKind.reasoning ? 'thinking' : 'text',
              'data': {'channel': input ? 'user' : 'final'},
              'bodies': [
                {
                  'key': 'body',
                  'byteLength': utf8.encode(text).length,
                  'inline': utf8.encode(text),
                },
              ],
            }),
          ),
        ),
      );
      Future<ConversationActivityView> accept(
        List<ChatAtom> atoms, {
        List<ChatEntry> entries = const [],
        ChatPlacement placement = ChatPlacement.append,
        bool oldPreview = false,
      }) async {
        h.current = current(atoms, oldPreview: oldPreview);
        await h.presentation.applyBatch(
          ChatBatch(placement: placement, entries: entries, current: h.current),
        );
        final view = projectConversationActivity(current: h.current)!;
        await tester.pumpWidget(h.host(view: view));
        await _flush(tester);
        expect(
          h.current.active,
          same(coarse),
          reason: 'The coarse Runtime fact is not rewritten',
        );
        expect(
          h.current.atoms.every((atom) => atom.lifecycle is ActiveChatAtom),
          isTrue,
        );
        return view;
      }

      List<String> mainMembers() => [
        for (final message in h.controller.messages)
          ...(message.metadata![timelineDisplayUnitKey] as TimelineDisplayUnit)
              .members
              .map((atom) => atom.id),
      ];
      await accept(
        [],
        placement: ChatPlacement.set,
        entries: [
          ChatAtomEntry(
            completed('user', 1, 1, ChatAtomKind.input, '用户输入', input: true),
          ),
        ],
      );
      expect(find.text('思考中'), findsOneWidget);
      expect(h.presentation.live.value, isEmpty);
      expect(h.content.scopes, isEmpty);
      await accept([_atom('G1', 10)]);
      final groupKey = h.presentation.live.value.single.id;
      await accept(
        [],
        entries: [
          ChatAtomEntry(completed('G1', 10, 2, ChatAtomKind.reasoning, '思考记录')),
        ],
      );
      expect(mainMembers(), ['user']);
      expect(h.presentation.live.value.single.id, groupKey);
      final textA = _atom(
        'text-A',
        20,
        kind: ChatAtomKind.text,
        reference: body('text-A'),
      );
      expect((await accept([textA])).kind, ConversationActivityKind.responding);
      expect(mainMembers(), ['user', 'G1']);
      expect(h.presentation.live.value.single.members.single, same(textA));
      final aScope = h.content.scopes.single;
      expect(aScope.requests.single.$1, same(textA.contents.single.reference));
      aScope.watches.single.add(_window('正文A'));
      await tester.pump();
      expect(find.text('正文A'), findsOneWidget);
      final afterText = await accept(
        [],
        entries: [
          ChatAtomEntry(completed('text-A', 20, 3, ChatAtomKind.text, '正文A')),
        ],
      );
      expect(afterText.kind, ConversationActivityKind.thinking);
      expect(mainMembers(), ['user', 'G1', 'text-A']);
      final originalHistory = List.of(h.controller.messages);
      expect(h.presentation.live.value, isEmpty);
      expect(find.text('思考中'), findsOneWidget);
      expect(find.text('正文A'), findsNothing);
      expect(h.display!.windows, isEmpty);
      expect(aScope.closed, isTrue);
      final readsAfterText = h.content.scopes.length;
      final stalePreview = await accept([], oldPreview: true);
      expect(stalePreview.kind, ConversationActivityKind.thinking);
      expect(
        stalePreview.responseParts.single.text,
        '正文A',
        reason: 'Preview metadata is preserved, not live admission',
      );
      expect(h.presentation.live.value, isEmpty);
      expect(find.text('思考中'), findsOneWidget);
      expect(find.text('正文A'), findsNothing);
      expect(
        h.content.scopes.length,
        readsAfterText,
        reason: 'Placeholder and stale preview do not open detail IO',
      );
      expect(h.controller.messages, originalHistory);
      final textB = _atom(
        'text-B',
        30,
        kind: ChatAtomKind.text,
        reference: body('text-B'),
      );
      expect((await accept([textB])).kind, ConversationActivityKind.responding);
      final bScope = h.content.scopes.last;
      bScope.watches.single.add(_window('正文B'));
      await tester.pump();
      expect(find.text('正文B'), findsOneWidget);
      expect(mainMembers(), ['user', 'G1', 'text-A']);
      await accept(
        [],
        entries: [
          ChatAtomEntry(completed('text-B', 30, 4, ChatAtomKind.text, '正文B')),
        ],
      );
      expect(h.current.atoms, isEmpty);
      expect(h.presentation.live.value, isEmpty);
      expect(mainMembers(), ['user', 'G1', 'text-A', 'text-B']);
      expect(find.text('思考中'), findsOneWidget);
      expect(find.text('正文B'), findsNothing);
      final next = _atom('next-work', 40);
      await accept([next]);
      expect(h.presentation.live.value.single.kind, TimelineUnitKind.work);
      expect(h.presentation.live.value.single.id, isNot(groupKey));
      expect(h.presentation.live.value.single.members.single, same(next));
      expect(mainMembers(), ['user', 'G1', 'text-A', 'text-B']);
      expect(
        h.content.scopes.length,
        readsAfterText + 1,
        reason: 'Only the next real text opened another content scope',
      );
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  test('responding projection defensively rejects terminal text without admitting it as legal current', () {
    // This deliberately malformed helper input is never sent to the presenter,
    // SDK current owner, or transport. Legal current contains unfinished atoms only.
    final terminal = ChatAtom(
      id: 'ended',
      completionItemId: 'payload-ended',
      completionSeq: 9,
      source: _source,
      sourceOrder: 20,
      kind: ChatAtomKind.text,
      delivery: ChatDeliveryKind.foreground,
      lifecycle: const TerminalChatAtom(
        started: null,
        ended: null,
        outcome: ChatTerminalOutcome.completed,
      ),
      contents: const [],
    );
    final value = _current(
      [terminal],
      activity: const CurrentActivityHead(
        id: 'retained-attempt',
        kind: ThreadActivityKind.responding,
        summary: ' 原始摘要 ',
        thinkingSummary: '保留思考摘要',
        thinkingSeconds: 7,
        toolCount: 2,
        backgroundToolCount: 1,
      ),
    );
    final view = projectConversationActivity(current: value)!;
    expect(view.kind, ConversationActivityKind.thinking);
    expect(view.identity, 'retained-attempt');
    expect(
      (view.turnId, view.summary, view.thinkingSummary, view.thinkingSeconds),
      ('T', '原始摘要', '保留思考摘要', 7),
    );
    expect((view.activeToolCount, view.backgroundToolCount), (2, 1));
    expect(value.atoms.single, same(terminal));
    expect(value.active!.kind, ThreadActivityKind.responding);
    expect(projectConversationActivity(current: null), isNull);
  });
  testWidgets(
    'unmaterialized activity uses the compact load and retry entry without hidden body IO',
    (tester) async {
      final h = _Harness();
      final activity =
          ValueNotifier<({bool hasMore, bool loading, Object? error})>((
            hasMore: true,
            loading: false,
            error: null,
          ));
      var loads = 0;
      await tester.pumpWidget(
        h.host(
          activity: activity,
          loadActivity: () async {
            loads++;
            activity.value = (hasMore: true, loading: true, error: null);
          },
        ),
      );
      expect(find.text('尚有活动未载入'), findsOneWidget);
      expect(h.content.scopes, isEmpty);
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(loads, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      activity.value = (
        hasMore: true,
        loading: false,
        error: StateError('ordinary page failed'),
      );
      await tester.pump();
      expect(find.textContaining('ordinary page failed'), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(loads, 2);
      activity.value = (hasMore: false, loading: false, error: null);
      await tester.pump();
      expect(find.text('尚有活动未载入'), findsNothing);
      expect(h.content.scopes, isEmpty);
      await tester.pumpWidget(const SizedBox());
      activity.dispose();
      h.dispose();
    },
  );
  testWidgets(
    'typed live tool observes only its declared body after explicit expansion and cancels on fold',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      final reference = _ref();
      await h.accept([
        _atom(
          'opaque-tool-id',
          1,
          kind: ChatAtomKind.toolCall,
          reference: reference,
        ),
      ]);
      await tester.pumpWidget(h.host());
      expect(h.content.scopes, isEmpty);
      expect(h.display!.windows, isEmpty);
      await tester.tap(find.text('工具调用'));
      await _flush(tester);
      final scope = h.content.scopes.single;
      expect(scope.requests.single.$1, same(reference));
      expect(scope.requests.single.$2.maxBytes, 32 * 1024);
      scope.watches.single.add(_window('明确声明的工具输出'));
      await tester.pump();
      expect(find.text('明确声明的工具输出'), findsOneWidget);
      await tester.tap(find.text('工具调用'));
      expect(h.display!.windows, isEmpty);
      expect(scope.active, isFalse);
      await _flush(tester);
      expect(scope.closed, isTrue);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'activity, previews, Plan and collections cannot invent a live unit or implicit read',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.accept([]);
      h.current = CurrentProjection(
        sourceEffectSeq: 2,
        logicalStatus: ThreadStatusView.running,
        executionPresent: true,
        sources: const [],
        atoms: const [],
        active: const CurrentActivityHead(
          id: 'activity',
          kind: ThreadActivityKind.responding,
          summary: 'responding',
          toolCount: 2,
          backgroundToolCount: 1,
        ),
        activeTurn: const CurrentTurnHead(
          id: 'T',
          phase: StudioTurnActivity.responding,
        ),
        plan: CurrentPlanHead(
          revision: 1,
          phase: PlanRuntimePhase.drafting,
          document: _ref(),
        ),
        previews: [
          CurrentContentPreview(
            id: 'old',
            role: CurrentContentRole.response,
            text: '旧预览不属于真实片段',
            reference: _ref(),
          ),
        ],
        collections: [
          CurrentCollectionRef(
            databaseId: 'database',
            collection: 'old',
            revision: 1,
          ),
        ],
      );
      final projected = projectConversationActivity(current: h.current)!;
      await tester.pumpWidget(h.host(view: projected));
      expect(projected.kind, ConversationActivityKind.thinking);
      expect(find.text('思考中'), findsOneWidget);
      expect(h.presentation.live.value, isEmpty);
      expect(h.content.scopes, isEmpty);
      expect(h.display!.windows, isEmpty);
      expect(h.display!.collections, isEmpty);
      expect(find.text('旧预览不属于真实片段'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A-B-A and late original close failure do not publish into replacement State',
    (tester) async {
      final a = _Harness();
      final b = _Harness();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await a.accept([_atom('R', 1, reference: _ref())]);
      await b.accept([_atom('R', 1, reference: _ref())]);
      await tester.pumpWidget(a.host());
      final retired = a.content.scopes.single;
      retired.cancelGate = Completer<void>();
      await tester.pumpWidget(b.host());
      b.content.scopes.single.watches.single.add(_window('B内容'));
      await tester.pump();
      expect(find.text('B内容'), findsOneWidget);
      await tester.pumpWidget(a.host());
      final current = a.content.scopes.last;
      expect(current, isNot(same(retired)));
      current.watches.single.add(_window('新A内容'));
      retired.closeFailure = StateError('旧A关闭失败');
      retired.cancelGate!.complete();
      await _flush(tester);
      expect(find.text('新A内容'), findsOneWidget);
      expect(find.textContaining('旧A关闭失败'), findsNothing);
      expect(retired.closed, isFalse);
      expect(current.active, isTrue);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Deferred borrows only the actual expanded window and keeps original byte identity',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      final reference = ContentRef(
        databaseId: 'database',
        target: const ItemPayloadTarget(itemId: 'original-payload'),
      );
      final requests = <Completer<ContentWindow>>[];
      h.content.onRead = (ref, range) {
        expect(ref, same(reference));
        expect((range.offset, range.maxBytes), (0, 64 * 1024));
        final result = Completer<ContentWindow>();
        requests.add(result);
        return result.future;
      };
      await h.accept([
        _atom(
          'deferred',
          1,
          payload: DeferredPayload(reference: reference, byteLength: 100000),
        ),
      ]);
      await tester.pumpWidget(h.host());
      expect(h.content.scopes, isEmpty);
      expect(h.display!.windows, isEmpty);
      final open = find.text('按需查看原文 · 100000 字节');
      await tester.tap(open);
      await tester.pump();
      final observed = h.display!.windows.single;
      expect((observed.window, observed.error), (null, null));
      final admitted = _window('已接纳的工具原文');
      requests.single.complete(admitted);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        expect(h.display!.windows.single, same(observed));
        expect(observed.reference, same(reference));
        expect(observed.window, same(admitted));
        expect(observed.window!.bytes, same(admitted.bytes));
      }
      expect(h.content.scopes.single.reads.length, 1);
      await tester.tap(open);
      expect(h.display!.windows, isEmpty);
      expect((observed.window, observed.error), (null, null));
      await tester.pump();
      await tester.tap(open);
      await tester.pump();
      final reopened = h.display!.windows.single;
      final failure = StateError('explicit payload read failed');
      requests.last.completeError(failure);
      await tester.pump();
      expect(reopened.error, same(failure));
      expect(find.text(failure.toString()), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      expect(h.display, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final staleError in [false, true]) {
    testWidgets(
      'Deferred retired ${staleError ? 'error' : 'success'} cannot publish or clear a reopened request',
      (tester) async {
        final h = _Harness();
        addTearDown(h.dispose);
        final requests = <Completer<ContentWindow>>[];
        h.content.onRead = (_, _) {
          final result = Completer<ContentWindow>();
          requests.add(result);
          return result.future;
        };
        await h.accept([
          _atom(
            'deferred',
            1,
            payload: DeferredPayload(
              reference: ContentRef(
                databaseId: 'database',
                target: const ItemPayloadTarget(itemId: 'original-payload'),
              ),
              byteLength: 100000,
            ),
          ),
        ]);
        await tester.pumpWidget(h.host());
        final open = find.text('按需查看原文 · 100000 字节');
        await tester.tap(open);
        await tester.pump();
        final old = h.display!.windows.single;
        await tester.tap(h.header);
        expect(h.display!.windows, isEmpty);
        await _flush(tester);
        await tester.tap(h.header);
        await _flush(tester);
        await tester.tap(open);
        await tester.pump();
        final replacement = h.display!.windows.single;
        if (staleError) {
          requests.first.completeError(StateError('retired read failed'));
        } else {
          requests.first.complete(_window('retired value'));
        }
        await tester.pump();
        expect((old.window, old.error), (null, null));
        expect((replacement.window, replacement.error), (null, null));
        expect(find.text('retired value'), findsNothing);
        expect(find.textContaining('retired read failed'), findsNothing);
        expect(requests.length, 2);
        requests.last.complete(_window('replacement value'));
        await tester.pump();
        expect(find.text('replacement value'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await _flush(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'folded work reads nothing; expanding reads original thinking ref without a second click',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      final reference = _ref();
      await h.accept([_atom('R', 1, reference: reference)]);
      h.presentation.live.value.single.expansion.expanded = false;
      await tester.pumpWidget(h.host());
      expect(h.content.scopes, isEmpty);
      await tester.tap(h.header);
      await _flush(tester);
      final scope = h.content.scopes.single;
      expect(scope.requests.single.$1, same(reference));
      expect(scope.requests.single.$2.maxBytes, 32 * 1024);
      scope.watches.single.add(_window('真实思考窗口'));
      await tester.pump();
      expect(find.text('真实思考窗口'), findsOneWidget);
      expect(h.display!.windows.single.window!.bytes, utf8.encode('真实思考窗口'));
      expect(h.display!.collections, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      expect((scope.active, scope.closed, scope.cancels), (false, true, 1));
      expect(h.display, isNull);
    },
  );

  testWidgets(
    'same semantic ref keeps watch; replacement range releases the borrowed old window',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.accept([_atom('R', 1, reference: _ref())]);
      await tester.pumpWidget(h.host());
      final scope = h.content.scopes.single;
      final original = _window('第一片');
      scope.watches.single.add(original);
      await tester.pump();
      final borrowed = h.display!.windows.single;
      expect(borrowed.window, same(original));
      await h.accept([_atom('R', 1, reference: _ref())]);
      await tester.pumpWidget(h.host());
      expect(h.content.scopes, [scope]);
      expect(scope.watches.length, 1);
      scope.watches.single.add(_window('整片替换'));
      await tester.pump();
      expect(find.text('第一片'), findsNothing);
      expect(find.text('整片替换'), findsOneWidget);
      await tester.tap(find.text('下一段'));
      expect(borrowed.window, isNull);
      await _flush(tester);
      final next = h.content.scopes.last;
      expect(scope.cancels, 1);
      expect(next.requests.single.$2.offset, utf8.encode('整片替换').length);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'fold revokes old callbacks immediately, rapid reopen can observe again',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.accept([_atom('R', 1, reference: _ref())]);
      await tester.pumpWidget(h.host());
      final old = h.content.scopes.single;
      old.cancelGate = Completer<void>();
      old.watches.single.add(_window('旧窗口'));
      await tester.pump();
      await tester.tap(h.header);
      expect(old.active, isFalse);
      expect(h.display!.windows, isEmpty);
      await tester.pump();
      await tester.tap(h.header);
      await _flush(tester);
      old.cancelGate!.complete();
      await _flush(tester);
      expect(h.content.scopes.length, 2);
      final fresh = h.content.scopes.last;
      fresh.watches.single.add(_window('新窗口'));
      await tester.pump();
      expect(find.text('新窗口'), findsOneWidget);
      expect(find.text('旧窗口'), findsNothing);
      expect(old.closed, isTrue);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'revision replacement hides stale text and preserves real IO errors',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.accept([_atom('R', 1, reference: _ref())]);
      await tester.pumpWidget(h.host());
      final old = h.content.scopes.single;
      old.watches.single.add(_window('旧文档'));
      await tester.pump();
      await h.accept([_atom('R', 1, reference: _ref(revision: 2))]);
      await tester.pumpWidget(h.host());
      await _flush(tester);
      expect(old.cancels, 1);
      expect(find.text('旧文档'), findsNothing);
      final fresh = h.content.scopes.last;
      fresh.watches.single.addError(
        StateError('StaleContent: owner revision retired'),
      );
      await tester.pump();
      expect(find.textContaining('StaleContent'), findsOneWidget);
      fresh.watches.single.addError(StateError('真实读取失败'));
      await tester.pump();
      expect(find.textContaining('真实读取失败'), findsOneWidget);
      expect(fresh.requests.single.$1.target, isA<BodyContentTarget>());
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'text start does not erase unfinished reasoning or borrow old previews',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.accept([
        _atom('R', 1, reference: _ref()),
        _atom(
          'text',
          2,
          kind: ChatAtomKind.text,
          reference: ContentRef(
            databaseId: 'database',
            target: const BodyContentTarget(
              owner: CurrentContentOwner(
                domain: 'text',
                id: 'text',
                revision: 1,
              ),
              key: 'body',
            ),
          ),
        ),
      ]);
      await tester.pumpWidget(h.host());
      expect(h.presentation.live.value.length, 2);
      expect(h.controller.messages, isEmpty);
      expect(h.content.scopes.length, 2);
      h.content.scopes.first.watches.single.add(_window('未结束思考'));
      h.content.scopes.last.watches.single.add(_window('流式正文'));
      await tester.pump();
      expect(find.text('未结束思考'), findsOneWidget);
      expect(find.text('流式正文'), findsOneWidget);
      expect(h.display!.windows.length, 2);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      expect(h.content.scopes.every((scope) => scope.closed), isTrue);
    },
  );
}
