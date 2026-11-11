import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/completion_run_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/state/conversation_realtime_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_resting_cat.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_writing_indicator.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/src/contracts/stamps.dart';
import 'package:anywork_client/src/lifecycle/close_report.dart';
import 'package:anywork_client/src/observation/latest_value.dart';
import 'package:material_ui/material_ui.dart';
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

final class _Content extends Fake implements ConversationContent {
  final source = LatestValue<ChatUiState<bool>>(
    const ChatReady('thread', true),
  );
  final scopes = <_Scope>[];
  @override
  final LatestValue<ActivitySnapshot?> activity = LatestValue(null);
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
  int completedReads = 0;
  @override
  Future<CompletedEntry> readCompleted({
    required String recordId,
    required ReadDemand demand,
  }) {
    completedReads++;
    throw StateError('A frozen observation must not read a future completion');
  }

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

final class _FreezeMembers implements DisplayMembers {
  final _pages = <DisplayMemberPage>[];
  Completer<DisplayMemberPage?>? _pending;
  bool _closing = false;
  bool closed = false;
  void send(DisplayMemberPage page) {
    final pending = _pending;
    _pending = null;
    if (pending == null) {
      _pages.add(page);
    } else {
      pending.complete(page);
    }
  }

  @override
  Future<DisplayMemberPage?> next() {
    if (_closing) return Future.value();
    if (_pages.isNotEmpty) return Future.value(_pages.removeAt(0));
    return (_pending = Completer<DisplayMemberPage?>()).future;
  }

  @override
  void requestClose() {
    _closing = true;
    _pending?.complete(null);
    _pending = null;
  }

  @override
  Future<void> close() async {
    requestClose();
    closed = true;
  }
}

Widget _host(
  Widget child, {
  bool disableAnimations = false,
  bool tickersEnabled = true,
}) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: TickerMode(enabled: tickersEnabled, child: child!),
  ),
  home: Scaffold(body: child),
);

ChatAtom _textItem({int revision = 1, PayloadData? payload}) => ChatAtom(
  id: 'response',
  source: _source,
  sourceOrder: 1,
  kind: ChatAtomKind.text,
  delivery: ChatDeliveryKind.foreground,
  textChannel: ThreadTextChannel.finalAnswer,
  lifecycle: const ActiveChatAtom(
    started: null,
    status: ChatActiveStatus.running,
  ),
  payload: payload,
  contents: [
    ChatAtomContent(
      role: ChatContentRole.body,
      reference: _ref(revision: revision),
    ),
  ],
);

final class _Harness {
  final content = _Content();
  final images = TimelineImageResources(threadId: 'thread');
  TimelineCurrentDisplay? display;
  int revision = 0;
  bool active = true;
  final live = ValueNotifier<LiveDisplayWindow?>(null);
  Future<LiveDisplayWindow> Function(String)? loadLiveOlder;
  void accept(List<ActivityEntry> entries) => live.value = LiveDisplayWindow(
    revision: ++revision,
    historyThrough: 0,
    executionPresent: true,
    blocks: [
      for (final (index, entry) in entries.indexed)
        LiveDisplayBlock(
          id: entry.atom.id,
          blockOrder: index + 1,
          state: DisplayBlockState.open,
          body: SingleDisplayBlock(
            record: DisplayRecord(
              atom: entry.atom,
              contentSource: const CurrentAtom(),
            ),
          ),
        ),
    ],
  );
  Widget host({bool disableAnimations = false, bool tickersEnabled = true}) =>
      _host(
        ConversationCurrentConnector(
          section: ConversationLiveSection.output,
          key: ObjectKey(content),
          session: const ThreadSessionState(threadId: 'thread'),
          content: content,
          region: ContentRealtimeRegion(live: live.value, notices: []),
          live: live,
          loadLiveOlder: loadLiveOlder,
          liveUnit: (block, executionPresent) => TimelineDisplayUnit.live(
            block: block,
            executionPresent: executionPresent,
            expansion: TimelineExpansionIntent(),
          ),
          images: images,
          readAttachment: (_) async => Uint8List(0),
          isDisplayActive: () => active,
          registerDisplay: (value) {
            display = value;
            return () => display = null;
          },
        ),
        disableAnimations: disableAnimations,
        tickersEnabled: tickersEnabled,
      );
  void dispose() {
    active = false;
    images.release();
    content.activity.close();
    live.dispose();
  }
}

ActivityEntry _part(ChatAtom atom) => ActivityEntry(
  identity: ModelPartActivityIdentity(atomId: atom.id),
  atom: atom,
);

void main() {
  for (final pageFirst in [true, false]) {
    for (final available in [true, false]) {
      testWidgets(
        'freeze handoff ${pageFirst ? "member-first" : "head-first"} available=$available keeps row demand and rejects late current IO',
        (tester) async {
          final content = _Content();
          final images = TimelineImageResources(threadId: 'thread');
          final handle = _FreezeMembers();
          final cancellation = Completer<void>();
          final expansion = TimelineExpansionIntent()..expanded = true;
          const reference = DisplayBlockRef(
            databaseId: 'database',
            blockId: 'work',
          );
          expansion.openDisplayMembers = (_, _, _) async => handle;
          addTearDown(() {
            if (!cancellation.isCompleted) cancellation.complete();
            expansion.retire();
            images.release();
          });
          ContentRef bodyRef(String key, bool frozen) => ContentRef(
            databaseId: 'database',
            target: BodyContentTarget(
              owner: frozen
                  ? const DisplayObservationContentOwner(
                      blockId: 'work',
                      memberKey: 'row',
                    )
                  : const CurrentContentOwner(
                      domain: 'execution',
                      id: 'reasoning',
                      revision: 1,
                    ),
              key: key,
            ),
          );
          DisplayMemberPage page(bool frozen) => DisplayMemberPage(
            block: reference,
            revision: frozen ? 2 : 1,
            sealed: frozen,
            entries: [
              DisplayMemberHead(
                memberKey: 'row',
                memberOrder: 1,
                record: DisplayRecord(
                  startFact: const ChatFactPosition(effectSeq: 1, suborder: 0),
                  contentSource: frozen
                      ? FrozenObservation(capturedAt: 50, available: available)
                      : const CurrentAtom(),
                  atom: ChatAtom(
                    id: 'same-reasoning',
                    source: _source,
                    sourceOrder: 1,
                    kind: ChatAtomKind.reasoning,
                    delivery: ChatDeliveryKind.foreground,
                    lifecycle: const ActiveChatAtom(
                      started: null,
                      status: ChatActiveStatus.running,
                    ),
                    startedAt: 1,
                    contents: [
                      ChatAtomContent(
                        role: ChatContentRole.reasoningSummary,
                        reference: bodyRef('summary', frozen),
                      ),
                      ChatAtomContent(
                        role: ChatContentRole.body,
                        reference: bodyRef('body', frozen),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
          content.onRead = (ref, range) async {
            final target = ref.target as BodyContentTarget;
            expect(
              target.owner,
              const DisplayObservationContentOwner(
                blockId: 'work',
                memberKey: 'row',
              ),
            );
            final bytes = utf8.encode('frozen-${target.key}');
            return ContentWindow(
              bytes: bytes,
              offset: 0,
              generation: 'frozen',
              availableThrough: bytes.length,
              sealed: true,
            );
          };
          Widget scene(DisplayBlockState state) => _host(
            CompletionRunConnector(
              key: const ValueKey('stable-block'),
              unit: TimelineDisplayUnit.live(
                block: LiveDisplayBlock(
                  id: 'work',
                  blockOrder: 1,
                  state: state,
                  body: const WorkDisplayBlock(
                    members: reference,
                    summary: WorkSummary(
                      total: 1,
                      terminal: 0,
                      running: 1,
                      waiting: 0,
                      failed: 0,
                      cancelled: 0,
                      transferred: 0,
                      unavailable: 0,
                    ),
                  ),
                ),
                executionPresent: true,
                expansion: expansion,
              ),
              threadId: 'thread',
              content: content,
              images: images,
            ),
          );
          await tester.pumpWidget(scene(DisplayBlockState.open));
          expansion.members!.disclosure('row').expanded = true;
          handle.send(page(false));
          await _flush(tester);
          final original = content.scopes.single..cancelGate = cancellation;
          expect(original.requests, hasLength(2));
          for (var i = 0; i < original.requests.length; i++) {
            final key =
                (original.requests[i].$1.target as BodyContentTarget).key;
            original.watches[i].add(_window('live-$key'));
          }
          await _flush(tester);
          expect(find.text('live-summary'), findsOneWidget);
          expect(find.text('live-body'), findsOneWidget);
          final originalState = tester.state(find.byType(TimelineMemberAtom));
          final originalDisclosure = expansion.members!.disclosure('row');
          if (pageFirst) {
            handle.send(page(true));
            await _flush(tester);
            expect(
              tester.state(find.byType(TimelineMemberAtom)),
              same(originalState),
            );
            expect(
              expansion.members!.disclosure('row'),
              same(originalDisclosure),
            );
          } else {
            await tester.pumpWidget(scene(DisplayBlockState.sealed));
            await _flush(tester);
            expect(originalDisclosure.retired, isTrue);
            expect(original.active, isFalse);
            expect(find.text('正在读取封存观察…'), findsOneWidget);
            handle.send(page(true));
            await _flush(tester);
          }
          expect(original.active, isFalse);
          expect(
            original.closed,
            isFalse,
            reason: 'Original cancellation/join is still outstanding',
          );
          expect(expansion.members!.disclosure('row').expanded, isTrue);
          expect(
            content.scopes.expand((s) => s.reads),
            hasLength(available ? 2 : 0),
          );
          if (available) {
            expect(find.text('frozen-summary'), findsOneWidget);
            expect(find.text('frozen-body'), findsOneWidget);
          } else {
            expect(find.text('旧边界观察不可用 · 封存时尚未结束'), findsOneWidget);
          }
          final admittedScopes = content.scopes.length;
          for (final watch in original.watches) {
            watch.add(_window('late-current-success'));
            watch.addError(StateError('late-current-error'));
          }
          cancellation.complete();
          await _flush(tester);
          await tester.pumpWidget(scene(DisplayBlockState.sealed));
          await _flush(tester);
          expect(original.closed, isTrue);
          expect(content.scopes, hasLength(admittedScopes));
          expect(content.scopes.skip(1).expand((s) => s.requests), isEmpty);
          expect(content.scopes.fold(0, (n, s) => n + s.completedReads), 0);
          expect(find.text('late-current-success'), findsNothing);
          expect(find.textContaining('late-current-error'), findsNothing);
          if (available) {
            expect(find.text('frozen-summary'), findsOneWidget);
            expect(find.text('frozen-body'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          expansion.retire();
          await _flush(tester);
          await handle.close();
          expect(content.scopes.every((scope) => scope.closed), isTrue);
          expect(handle.closed, isTrue);
        },
        timeout: const Timeout(Duration(seconds: 20)),
      );
    }
  }

  testWidgets(
    'frozen deferred metadata uses only its sealed observation, never a future completion',
    (tester) async {
      final content = _Content();
      final images = TimelineImageResources(threadId: 'thread');
      addTearDown(images.release);
      const reference = ContentRef(
        databaseId: 'database',
        target: BodyContentTarget(
          owner: DisplayObservationContentOwner(
            blockId: 'old-block',
            memberKey: 'old-row',
          ),
          key: 'payload',
        ),
      );
      final bytes = utf8.encode(
        jsonEncode({
          'contract': 'anywork.chat/1',
          'type': 'text',
          'data': {'channel': 'final', 'attachments': []},
          'bodies': [
            {
              'key': 'body',
              'byteLength': 13,
              'inline': utf8.encode('frozen-prefix'),
            },
          ],
        }),
      );
      content.onRead = (ref, range) async {
        expect(ref, reference);
        expect(range.offset, 0);
        expect(range.maxBytes, 64 * 1024);
        return ContentWindow(
          bytes: bytes,
          offset: 0,
          generation: 'snapshot',
          availableThrough: bytes.length,
          sealed: true,
        );
      };
      await tester.pumpWidget(
        _host(
          TimelineMemberAtom(
            displayId: 'old-row',
            record: DisplayRecord(
              atom: ChatAtom(
                id: 'same-atom',
                completionItemId: 'future-completion',
                source: _source,
                sourceOrder: 1,
                kind: ChatAtomKind.text,
                delivery: ChatDeliveryKind.foreground,
                lifecycle: const ActiveChatAtom(
                  started: null,
                  status: ChatActiveStatus.running,
                ),
                contents: const [],
                payload: DeferredPayload(
                  reference: reference,
                  byteLength: bytes.length,
                ),
              ),
              startFact: const ChatFactPosition(effectSeq: 1, suborder: 0),
              contentSource: const FrozenObservation(
                capturedAt: 50,
                available: true,
              ),
            ),
            content: content,
            isActive: () => true,
            images: images,
            readAttachment: null,
          ),
        ),
      );
      await _flush(tester);
      expect(find.text('frozen-prefix'), findsOneWidget);
      expect(find.byType(TimelineWritingIndicator), findsNothing);
      expect(content.scopes, hasLength(1));
      expect(content.scopes.single.reads, hasLength(1));
      expect(content.scopes.single.completedReads, 0);
      expect(content.scopes.single.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      expect(content.scopes.single.closed, isTrue);
    },
  );

  testWidgets(
    'same atom in two frozen rows reads independent sealed snapshots without watch or completion',
    (tester) async {
      final content = _Content();
      final images = TimelineImageResources(threadId: 'thread');
      addTearDown(images.release);
      content.onRead = (reference, range) async {
        final owner =
            (reference.target as BodyContentTarget).owner
                as DisplayObservationContentOwner;
        final bytes = utf8.encode('snapshot-${owner.memberKey}');
        return ContentWindow(
          bytes: bytes,
          offset: 0,
          generation: owner.memberKey,
          availableThrough: bytes.length,
          sealed: true,
        );
      };
      Widget row(String block, String member) => TimelineMemberAtom(
        key: ValueKey((block, member)),
        displayId: member,
        record: DisplayRecord(
          startFact: const ChatFactPosition(effectSeq: 1, suborder: 0),
          contentSource: const FrozenObservation(
            capturedAt: 50,
            available: true,
          ),
          atom: ChatAtom(
            id: 'same-execution-object',
            source: _source,
            sourceOrder: 1,
            kind: ChatAtomKind.reasoning,
            delivery: ChatDeliveryKind.foreground,
            lifecycle: const ActiveChatAtom(
              started: null,
              status: ChatActiveStatus.running,
            ),
            startedAt: 1,
            contents: [
              ChatAtomContent(
                role: ChatContentRole.reasoningSummary,
                reference: ContentRef(
                  databaseId: 'database',
                  target: BodyContentTarget(
                    owner: DisplayObservationContentOwner(
                      blockId: block,
                      memberKey: member,
                    ),
                    key: 'summary',
                  ),
                ),
              ),
            ],
          ),
        ),
        content: content,
        isActive: () => true,
        images: images,
        readAttachment: null,
      );
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              row('first-block', 'first-row'),
              row('second-block', 'second-row'),
            ],
          ),
        ),
      );
      await _flush(tester);
      expect(find.text('snapshot-first-row'), findsOneWidget);
      expect(find.text('snapshot-second-row'), findsOneWidget);
      expect(find.text('封存时尚未结束'), findsNWidgets(2));
      expect(content.scopes.expand((s) => s.requests), isEmpty);
      expect(content.scopes.fold(0, (n, s) => n + s.completedReads), 0);
      expect(
        tester
            .widgetList<TimelineReasoningView>(
              find.byType(TimelineReasoningView),
            )
            .every((v) => !v.running),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      expect(content.scopes.every((s) => s.closed), isTrue);
    },
  );

  testWidgets(
    'unavailable boundary never displays latest summary or opens details',
    (tester) async {
      final content = _Content();
      final images = TimelineImageResources(threadId: 'thread');
      addTearDown(images.release);
      await tester.pumpWidget(
        _host(
          TimelineMemberAtom(
            displayId: 'old-row',
            record: DisplayRecord(
              startFact: const ChatFactPosition(effectSeq: 1, suborder: 0),
              contentSource: const FrozenObservation(available: false),
              atom: ChatAtom(
                id: 'same-execution-object',
                source: _source,
                sourceOrder: 1,
                kind: ChatAtomKind.reasoning,
                delivery: ChatDeliveryKind.foreground,
                lifecycle: const ActiveChatAtom(
                  started: null,
                  status: ChatActiveStatus.waiting,
                ),
                contents: const [],
              ),
            ),
            content: content,
            isActive: () => true,
            images: images,
            readAttachment: null,
          ),
        ),
      );
      await _flush(tester);
      expect(find.text('旧边界观察不可用 · 封存时尚未结束'), findsOneWidget);
      expect(find.text('上次思考尚未恢复'), findsNothing);
      expect(find.byType(TimelineReasoningView), findsNothing);
      expect(content.scopes, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final handoffWithoutRevisionChange in [false, true]) {
    testWidgets(
      'same-revision older page retains Single IO until ${handoffWithoutRevisionChange ? 'history handoff' : 'structural revision'} invalidates it',
      (tester) async {
        final h = _Harness();
        addTearDown(h.dispose);
        final latestBlock = LiveDisplayBlock(
          id: 'latest',
          blockOrder: 2,
          state: DisplayBlockState.open,
          body: SingleDisplayBlock(
            record: DisplayRecord(
              atom: _textItem(revision: 2),
              contentSource: const CurrentAtom(),
            ),
          ),
        );
        LiveDisplayWindow latest({int revision = 7, int through = 0}) =>
            LiveDisplayWindow(
              revision: revision,
              historyThrough: through,
              executionPresent: true,
              blocks: [latestBlock],
              older: 'older-cursor',
            );
        final page = LiveDisplayWindow(
          revision: 7,
          historyThrough: 0,
          executionPresent: true,
          blocks: [
            LiveDisplayBlock(
              id: 'older',
              blockOrder: 1,
              state: DisplayBlockState.open,
              body: SingleDisplayBlock(
                record: DisplayRecord(
                  atom: _textItem(),
                  contentSource: const CurrentAtom(),
                ),
              ),
            ),
          ],
        );
        var reads = 0;
        h.loadLiveOlder = (before) async {
          expect(before, 'older-cursor');
          reads++;
          return page;
        };
        h.live.value = latest();
        await tester.pumpWidget(h.host());
        await tester.tap(find.widgetWithText(TextButton, '更早实时片段'));
        await _flush(tester);
        final scope = h.content.scopes.last;
        scope.watches.single.add(_window('older text'));
        await _flush(tester);
        final borrowed = h.display!.windows.single;
        final memberState = tester.state(find.byType(TimelineMemberAtom));
        final scopes = h.content.scopes.length;
        expect(find.text('older text'), findsOneWidget);
        h.live.value = latest(); // Different DTO identity, same structural cut.
        await tester.pumpWidget(h.host());
        expect(find.widgetWithText(TextButton, '最新实时片段'), findsOneWidget);
        expect(find.text('older text'), findsOneWidget);
        expect(
          tester.state(find.byType(TimelineMemberAtom)),
          same(memberState),
        );
        expect(h.display!.windows.single, same(borrowed));
        expect(h.content.scopes.length, scopes);
        expect(scope.active, isTrue);
        expect(scope.requests, hasLength(1));
        expect(reads, 1);
        h.live.value = latest(
          revision: handoffWithoutRevisionChange ? 7 : 8,
          through: handoffWithoutRevisionChange ? 1 : 0,
        );
        expect(scope.active, isFalse);
        await tester.pumpWidget(h.host());
        await _flush(tester);
        expect(find.widgetWithText(TextButton, '最新实时片段'), findsNothing);
        expect(find.text('older text'), findsNothing);
        expect(scope.closed, isTrue);
        expect(h.content.scopes.length, scopes + 1);
        await tester.pumpWidget(const SizedBox());
        await _flush(tester);
      },
    );
  }

  testWidgets(
    'real Activity animates thinking and writing, pauses accessibly, and retires tickers with identity',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      final thinking = _part(
        ChatAtom(
          id: 'thinking',
          source: _source,
          sourceOrder: null,
          kind: ChatAtomKind.reasoning,
          delivery: ChatDeliveryKind.foreground,
          lifecycle: const ActiveChatAtom(
            started: null,
            status: ChatActiveStatus.running,
          ),
          contents: const [],
        ),
      );
      h.accept([thinking, _part(_textItem())]);
      await tester.pumpWidget(h.host());
      final scope = h.content.scopes.single;
      scope.watches.single.add(_window('实际活动正文'));
      await _flush(tester);
      expect(find.text('实际活动正文'), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(
        tester.widget<TimelineMarkdown>(find.byType(TimelineMarkdown)).style,
        isNull,
        reason: '文本活动沿用普通正文样式，工具和思考窗口仍由原样式呈现',
      );
      final tail = tester
          .widget<TimelineRestingCat>(find.byType(TimelineRestingCat))
          .progress;
      final pen = tester
          .widget<TimelineWritingIndicator>(
            find.byType(TimelineWritingIndicator),
          )
          .position;
      final tailBefore = tail.value;
      final penBefore = pen.value;
      await tester.pump(const Duration(milliseconds: 170));
      expect(tail.value, isNot(tailBefore));
      expect(pen.value, isNot(penBefore));

      for (final reducedMotion in [true, false]) {
        await tester.pumpWidget(
          h.host(
            disableAnimations: reducedMotion,
            tickersEnabled: reducedMotion,
          ),
        );
        final stoppedTail = tail.value;
        final stoppedPen = pen.value;
        await tester.pump(const Duration(milliseconds: 170));
        expect(tail.value, stoppedTail);
        expect(pen.value, stoppedPen);
        expect(find.text('实际活动正文'), findsOneWidget);
        expect(h.content.scopes.single, same(scope));
        expect(scope.requests, hasLength(1));
      }
      await tester.pumpWidget(h.host());
      final resumedTail = tail.value;
      final resumedPen = pen.value;
      await tester.pump(const Duration(milliseconds: 170));
      expect(tail.value, isNot(resumedTail));
      expect(pen.value, isNot(resumedPen));

      h.accept([thinking]);
      await tester.pump();
      await _flush(tester);
      expect(find.byType(TimelineWritingIndicator), findsNothing);
      expect(find.text('实际活动正文'), findsNothing);
      expect(scope.closed, isTrue);
      expect(find.byType(TimelineRestingCat), findsOneWidget);
      h.accept([]);
      await tester.pump();
      expect(find.byType(TimelineRestingCat), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'active inline and deferred text use one writing shell without pre-reading deferred detail',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      final inline = InlinePayload(
        bytes: utf8.encode(
          jsonEncode({
            'contract': 'anywork.chat/1',
            'type': 'text',
            'data': {'channel': 'final', 'attachments': []},
            'bodies': [
              {
                'key': 'body',
                'byteLength': utf8.encode('内联正文').length,
                'inline': utf8.encode('内联正文'),
              },
            ],
          }),
        ),
      );
      h.accept([_part(_textItem(payload: inline))]);
      await tester.pumpWidget(h.host());
      expect(find.byType(TimelineWritingIndicator), findsOneWidget);
      expect(find.text('内联正文'), findsOneWidget);
      expect(h.content.scopes, isEmpty);
      h.accept([
        _part(
          _textItem(
            payload: DeferredPayload(reference: _ref(), byteLength: 100),
          ),
        ),
      ]);
      await tester.pumpWidget(h.host());
      expect(find.byType(TimelineWritingIndicator), findsOneWidget);
      expect(find.text('内联正文'), findsNothing);
      expect(h.content.scopes, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'Activity retirement revokes bodies synchronously and a new qualification cannot reuse old IO',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.accept([_part(_textItem())]);
      await tester.pumpWidget(h.host());
      final old = h.content.scopes.single;
      old.cancelGate = Completer<void>();
      old.watches.single.add(_window('旧值'));
      await tester.idle();
      await tester.pump();
      expect(find.text('旧值'), findsOneWidget);
      final borrowed = h.display!.windows.single;
      h.accept([]);
      expect(old.active, isFalse);
      expect(h.display!.windows, isEmpty);
      expect(borrowed.window, isNull);
      old.watches.single.add(_window('迟到值'));
      h.accept([_part(_textItem(revision: 2))]);
      await tester.pumpWidget(h.host());
      expect(find.text('迟到值'), findsNothing);
      expect(find.text('旧值'), findsNothing);
      final fresh = h.content.scopes.last;
      expect(fresh, isNot(same(old)));
      old.cancelGate!.complete();
      await _flush(tester);
      fresh.watches.single.add(_window('新值'));
      await tester.idle();
      await tester.pump();
      expect(find.text('新值'), findsOneWidget);
      expect(old.closed, isTrue);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'same activity ref retains its watch while a new resource revision hides stale text',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.accept([_part(_textItem())]);
      await tester.pumpWidget(h.host());
      final original = h.content.scopes.single;
      original.watches.single.add(_window('v1'));
      await _flush(tester);
      h.accept([_part(_textItem())]);
      await tester.pumpWidget(h.host());
      expect(h.content.scopes.single, same(original));
      expect(original.requests, hasLength(1));
      h.accept([_part(_textItem(revision: 2))]);
      await tester.pumpWidget(h.host());
      await _flush(tester);
      expect(find.text('v1'), findsNothing);
      final next = h.content.scopes.last;
      expect(next, isNot(same(original)));
      next.watches.single.addError(StateError('真实范围读取失败'));
      await _flush(tester);
      expect(find.textContaining('真实范围读取失败'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'only typed unfinished compaction is rendered; empty Activity removes it without a fake completion',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.accept([
        ActivityEntry(
          identity: const OtherActivityIdentity(
            domain: 'operation',
            id: 'compact',
          ),
          atom: ChatAtom(
            id: 'compact',
            source: const OperationChatSource(operationId: 'compact'),
            sourceOrder: null,
            kind: ChatAtomKind.compaction,
            delivery: ChatDeliveryKind.independent,
            lifecycle: const ActiveChatAtom(
              started: null,
              status: ChatActiveStatus.running,
            ),
            contents: const [],
          ),
        ),
      ]);
      await tester.pumpWidget(h.host());
      final row = tester.widget<TimelineActivityRow>(
        find.byType(TimelineActivityRow),
      );
      expect(
        row.label,
        AppLocalizations.of(tester.element(find.byType(TimelineActivityRow)))
            .conversationActivityCompacting,
      );
      expect(row.active, isTrue);
      expect(h.content.scopes, isEmpty);
      h.accept([]);
      await tester.pump();
      expect(find.byType(TimelineActivityRow), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );

  testWidgets(
    'reasoning reads only its summary while folded and revokes the body before the closing animation',
    (tester) async {
      final content = _Content();
      final images = TimelineImageResources(threadId: 'thread');
      addTearDown(images.release);
      const summaryRef = ContentRef(
        databaseId: 'database',
        target: BodyContentTarget(
          owner: CurrentContentOwner(
            domain: 'execution',
            id: 'reasoning',
            revision: 1,
          ),
          key: 'part.summaryText.0',
        ),
      );
      TimelineMemberDisplay? display;
      Widget scene({bool withBody = true}) => _host(
        TimelineMemberAtom(
          key: const ValueKey('reasoning-member'),
          content: content,
          isActive: () => true,
          images: images,
          readAttachment: null,
          registerDisplay: (value) {
            display = value;
            return () => display = null;
          },
          record: DisplayRecord(
            atom: ChatAtom(
              id: 'reasoning-member',
              source: _source,
              sourceOrder: 1,
              kind: ChatAtomKind.reasoning,
              delivery: ChatDeliveryKind.foreground,
              lifecycle: const ActiveChatAtom(
                started: null,
                status: ChatActiveStatus.running,
              ),
              contents: [
                const ChatAtomContent(
                  role: ChatContentRole.reasoningSummary,
                  reference: summaryRef,
                ),
                if (withBody)
                  ChatAtomContent(
                    role: ChatContentRole.body,
                    reference: _ref(),
                  ),
              ],
            ),
            contentSource: const CurrentAtom(),
          ),
          displayId: "fixture-current",
        ),
      );
      await tester.pumpWidget(scene());
      final original = content.scopes.single;
      expect(original.requests.single.$1, same(summaryRef));
      original.watches.single.add(_window('持续更新的思考概要'));
      await tester.idle();
      await tester.pump();
      expect(
        find.textContaining('持续更新的思考概要', findRichText: true),
        findsOneWidget,
      );
      expect(display!.windows, hasLength(1));
      final row = find.descendant(
        of: find.byType(TimelineReasoningView),
        matching: find.byType(TimelineActivityRow),
      );
      await tester.tap(row);
      await tester.pump();
      expect(original.requests, hasLength(2));
      original.watches.last.add(_window('按需读取的思考正文'));
      await tester.idle();
      await _flush(tester);
      expect(find.text('按需读取的思考正文'), findsOneWidget);
      original.cancelGate = Completer<void>();
      await tester.tap(row);
      expect(original.active, isFalse);
      expect(display!.windows, isEmpty);
      original.watches.last.add(_window('折叠后迟到正文'));
      await tester.idle();
      await tester.pump();
      expect(display!.windows, isEmpty);
      original.cancelGate!.complete();
      await _flush(tester);
      expect(content.scopes, hasLength(2));
      final fresh = content.scopes.last;
      expect(fresh.requests.single.$1, same(summaryRef));
      fresh.watches.single.add(_window('折叠后仍可更新概要'));
      await tester.idle();
      await _flush(tester);
      expect(
        find.textContaining('折叠后仍可更新概要', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('折叠后迟到正文'), findsNothing);
      expect(find.text('按需读取的思考正文'), findsNothing);
      await tester.pumpWidget(scene(withBody: false));
      expect(find.byType(ExpansionTile), findsNothing);
      expect(tester.widget<TimelineActivityRow>(row).expandable, isFalse);
      expect(fresh.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      expect(content.scopes.every((scope) => scope.closed), isTrue);
    },
  );

  testWidgets(
    'sealed reasoning revokes pending body reads immediately while retaining its summary',
    (tester) async {
      final content = _Content();
      final images = TimelineImageResources(threadId: 'thread');
      addTearDown(images.release);
      final pendingBody = Completer<ContentWindow>();
      content.onRead = (reference, _) =>
          (reference.target as BodyContentTarget).key.contains('summaryText')
          ? Future.value(_window('已保存的思考概要'))
          : pendingBody.future;
      Map<String, Object?> manifest(String key) => {
        'key': key,
        'byteLength': 100,
        'reference': {
          'databaseId': 'database',
          'target': {
            'kind': 'body',
            'owner': {'kind': 'item', 'itemId': 'sealed-reasoning'},
            'key': key,
          },
        },
      };
      TimelineMemberDisplay? display;
      await tester.pumpWidget(
        _host(
          TimelineMemberAtom(
            content: content,
            isActive: () => true,
            images: images,
            readAttachment: null,
            registerDisplay: (value) {
              display = value;
              return () => display = null;
            },
            record: DisplayRecord(
              atom: ChatAtom(
                id: 'sealed-reasoning',
                source: _source,
                sourceOrder: 1,
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
                      'data': <String, Object?>{},
                      'bodies': [
                        manifest('part.summaryText.0'),
                        manifest('part.reasoningText.0'),
                      ],
                    }),
                  ),
                ),
              ),
              contentSource: const CurrentAtom(),
            ),
            displayId: "fixture-current",
          ),
        ),
      );
      await _flush(tester);
      expect(content.scopes.single.reads, hasLength(1));
      expect(
        find.textContaining('已保存的思考概要', findRichText: true),
        findsOneWidget,
      );
      final row = find.descendant(
        of: find.byType(TimelineReasoningView),
        matching: find.byType(TimelineActivityRow),
      );
      await tester.tap(row);
      await _flush(tester);
      final original = content.scopes.single;
      expect(original.reads, hasLength(2));
      expect(
        find.byType(ExpansionTile),
        findsOneWidget,
        reason: 'Opening the member is the only body disclosure',
      );
      final bodyConnector = tester
          .widgetList<TimelineContentRangeConnector>(
            find.byType(TimelineContentRangeConnector),
          )
          .singleWhere((view) => view.contentKey == 'part.reasoningText.0');
      expect(bodyConnector.isDisplayActive!(), isTrue);
      await tester.tap(row);
      expect(original.active, isFalse);
      expect(bodyConnector.isDisplayActive!(), isFalse);
      expect(display!.windows, isEmpty);
      await expectLater(
        bodyConnector.readContent!(
          bodyConnector.reference,
          const ContentRange(offset: 0, maxBytes: 20),
        ),
        throwsA(isA<StaleConversationScope>()),
      );
      expect(original.reads, hasLength(2));
      pendingBody.complete(_window('已经折叠的迟到思考正文'));
      await _flush(tester);
      expect(find.text('已经折叠的迟到思考正文'), findsNothing);
      expect(
        find.textContaining('已保存的思考概要', findRichText: true),
        findsOneWidget,
      );
      expect(content.scopes.last.reads, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
      expect(content.scopes.every((scope) => scope.closed), isTrue);
    },
  );

  testWidgets(
    'restored interrupted reasoning renders cancelled without opening content',
    (tester) async {
      final content = _Content();
      final images = TimelineImageResources(threadId: 'thread');
      addTearDown(images.release);
      await tester.pumpWidget(
        _host(
          TimelineMemberAtom(
            content: content,
            isActive: () => true,
            images: images,
            readAttachment: null,
            record: DisplayRecord(
              atom: ChatAtom(
                id: 'restored-interrupted-reasoning',
                source: _source,
                sourceOrder: 1,
                kind: ChatAtomKind.reasoning,
                delivery: ChatDeliveryKind.foreground,
                lifecycle: const TerminalChatAtom(
                  started: ChatFactPosition(effectSeq: 2, suborder: 0),
                  ended: ChatFactPosition(effectSeq: 8, suborder: 0),
                  outcome: ChatTerminalOutcome.cancelled,
                ),
                contents: const [],
              ),
              contentSource: const CurrentAtom(),
            ),
            displayId: "fixture-current",
          ),
        ),
      );

      final reasoning = find.byType(TimelineReasoningView);
      final row = tester.widget<TimelineActivityRow>(
        find.descendant(
          of: reasoning,
          matching: find.byType(TimelineActivityRow),
        ),
      );
      expect(reasoning, findsOneWidget);
      expect(row.label, '思考已取消');
      expect(row.active, isFalse);
      expect(row.icon, Icons.stop_circle_outlined);
      expect(row.expandable, isFalse);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(content.scopes, isEmpty);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(content.scopes, isEmpty);
    },
  );

  testWidgets(
    'typed wait uses member atom, never tool-name or generic Running inference',
    (tester) async {
      final content = _Content();
      final images = TimelineImageResources(threadId: 'thread');
      addTearDown(images.release);
      final waiting = ThreadWaitPresentationView(
        intent: ThreadWaitEventsIntentView(
          targets: const [
            ThreadWaitTargetView(
              taskId: 'task:timer',
              toolName: 'sleep',
              status: ThreadWaitTargetStatusView.running,
            ),
          ],
          timeoutMs: 120000,
        ),
        state: ThreadWaitStateView.waiting,
      );
      ChatAtom member(ThreadWaitPresentationView? wait) => ChatAtom(
        id: 'wait-atom',
        source: _source,
        sourceOrder: 1,
        kind: ChatAtomKind.toolCall,
        delivery: ChatDeliveryKind.foreground,
        lifecycle: const ActiveChatAtom(
          started: null,
          status: ChatActiveStatus.running,
        ),
        tool: const ChatToolIdentity(callId: 'call', name: 'wait'),
        wait: wait,
        contents: const [],
      );
      Widget scene(ThreadWaitPresentationView? wait) => _host(
        TimelineMemberAtom(
          key: const ValueKey('wait-atom'),
          content: content,
          isActive: () => true,
          images: images,
          readAttachment: null,
          record: DisplayRecord(
            atom: member(wait),
            contentSource: const CurrentAtom(),
          ),
          displayId: "fixture-current",
        ),
      );
      await tester.pumpWidget(scene(null));
      expect(find.byType(TimelineWaitPanel), findsNothing);
      await tester.pumpWidget(scene(waiting));
      expect(find.byType(TimelineWaitPanel), findsOneWidget);
      expect(
        tester
            .widget<TimelineWaitPanel>(find.byType(TimelineWaitPanel))
            .presentation,
        same(waiting),
      );
      expect(content.scopes, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await _flush(tester);
    },
  );
}
