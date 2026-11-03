import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/src/contracts/stamps.dart';
import 'package:anywork_client/src/lifecycle/resource_budget.dart';
import 'package:anywork_client/src/observation/latest_value.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';


import '../support/chat_fixtures.dart';
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


CurrentProjection _current(List<TimelineItem> items) => CurrentProjection(
  sourceEffectSeq: 1, logicalStatus: ThreadStatusView.running, executionPresent: true,
  activeTurn: const CurrentTurnHead(id: 'T', phase: StudioTurnActivity.thinking),
  sources: const [], atoms: const [], items: items, previews: const [], collections: const [],
);
TimelineItem _textItem({int revision = 1}) => TimelineItem(
  id: 'response', kind: TimelineItemKind.text, source: _source,
  delivery: ChatDeliveryKind.foreground, textChannel: ThreadTextChannel.finalAnswer,
  contents: [ChatAtomContent(role: ChatContentRole.body, reference: _ref(revision: revision))],
  admissionClosed: false,
);
Widget _host(Widget child) => MaterialApp(
  theme: pureStudioTheme(), locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);
final class _Harness {
  final content = _Content();
  final controller = InMemoryChatController();
  final images = TimelineImageResources(threadId: 'thread');
  late final presentation = TimelineMessageController(controller, generation: 1);
  CurrentProjection current = _current([]);
  TimelineCurrentDisplay? display;
  Future<void> accept(List<TimelineItem> items) async {
    current = _current(items);
    await presentation.applyBatch(ChatBatch(placement: ChatPlacement.append, entries: const [], current: current));
  }
  Widget host() => _host(ConversationCurrentConnector(
    key: ObjectKey(content), current: current, content: content,
    view: const ConversationActivityView(identity: 'active', kind: ConversationActivityKind.thinking, summary: '思考中', expandable: true),
    units: presentation.live, images: images, readAttachment: (_) async => Uint8List(0),
    isDisplayActive: () => true,
    registerDisplay: (value) { display = value; return () => display = null; },
  ));
  void dispose() { presentation.dispose(); images.release(); controller.dispose(); }
}

void main() {
  testWidgets('an unfinished group does not hide a later response; folded group opens no body or member resource', (tester) async {
    final h = _Harness(); addTearDown(h.dispose);
    var opens = 0;
    await h.accept([workItem('R', closed: true, active: 1), _textItem()]);
    h.presentation.live.value.first.expansion.openMembers = (_, _) async { opens++; throw StateError('must remain folded'); };
    await tester.pumpWidget(h.host());
    expect(find.byType(TimelineDisplayUnitView), findsOneWidget);
    expect(opens, 0);
    expect(h.content.scopes, hasLength(1));
    h.content.scopes.single.watches.single.add(_window('后继正文仍可读'));
    await tester.pump();
    expect(find.text('后继正文仍可读'), findsOneWidget);
    expect(h.presentation.live.value.map((unit) => unit.id), ['R', 'response']);
    expect(h.controller.messages, isEmpty);
    await tester.pumpWidget(const SizedBox()); await _flush(tester);
  });

  testWidgets('same content ref retains its watch; revision replacement hides stale text and preserves IO failure', (tester) async {
    final h = _Harness(); addTearDown(h.dispose);
    await h.accept([_textItem()]); await tester.pumpWidget(h.host());
    final old = h.content.scopes.single;
    old.watches.single.add(_window('旧文档')); await tester.pump();
    final borrowed = h.display!.windows.single;
    await h.accept([_textItem()]); await tester.pumpWidget(h.host());
    expect(h.content.scopes, [old]); expect(old.watches, hasLength(1));
    old.watches.single.add(_window('整片替换')); await tester.pump();
    expect(find.text('旧文档'), findsNothing); expect(find.text('整片替换'), findsOneWidget);
    await h.accept([_textItem(revision: 2)]); await tester.pumpWidget(h.host()); await _flush(tester);
    expect(old.cancels, 1); expect(borrowed.window, isNull);
    expect(find.text('整片替换'), findsNothing);
    h.content.scopes.last.watches.single.addError(StateError('真实读取失败')); await tester.pump();
    expect(find.textContaining('真实读取失败'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); await _flush(tester);
    expect(h.content.scopes.every((scope) => scope.closed), isTrue);
  });

  testWidgets('selection retirement revokes body callbacks before cancel/join completes', (tester) async {
    final h = _Harness(); addTearDown(h.dispose);
    await h.accept([_textItem()]); await tester.pumpWidget(h.host());
    final old = h.content.scopes.single;
    old.cancelGate = Completer<void>();
    old.watches.single.add(_window('旧值')); await tester.pump();
    final borrowed = h.display!.windows.single;
    await h.accept([]);
    expect(old.active, isFalse); expect(h.display!.windows, isEmpty);
    old.watches.single.add(_window('迟到值')); await tester.pump();
    expect(find.text('迟到值'), findsNothing); expect(borrowed.window, isNull);
    await h.accept([_textItem(revision: 2)]); await tester.pumpWidget(h.host());
    old.cancelGate!.complete(); await _flush(tester);
    final fresh = h.content.scopes.last;
    fresh.watches.single.add(_window('新值')); await tester.pump();
    expect(find.text('新值'), findsOneWidget); expect(old.closed, isTrue);
    await tester.pumpWidget(const SizedBox()); await _flush(tester);
  });

  testWidgets('typed wait uses member atom, never tool-name or generic Running inference', (tester) async {
    final content = _Content(); final images = TimelineImageResources(threadId: 'thread');
    addTearDown(images.release);
    final waiting = ThreadWaitPresentationView(
      intent: ThreadWaitEventsIntentView(targets: const [ThreadWaitTargetView(taskId: 'task:timer', toolName: 'sleep', status: ThreadWaitTargetStatusView.running)], timeoutMs: 120000),
      state: ThreadWaitStateView.waiting,
    );
    ChatAtom member(ThreadWaitPresentationView? wait) => ChatAtom(
      id: 'wait-atom', source: _source, sourceOrder: 1, kind: ChatAtomKind.toolCall,
      delivery: ChatDeliveryKind.foreground,
      lifecycle: const ActiveChatAtom(started: null, status: ChatActiveStatus.running),
      tool: const ChatToolIdentity(callId: 'call', name: 'wait'), wait: wait, contents: const [],
    );
    Widget scene(ThreadWaitPresentationView? wait) => _host(TimelineMemberAtom(
      key: const ValueKey('wait-atom'), atom: member(wait), content: content,
      isActive: () => true, images: images, readAttachment: null,
    ));
    await tester.pumpWidget(scene(null)); expect(find.byType(TimelineWaitPanel), findsNothing);
    await tester.pumpWidget(scene(waiting));
    expect(find.byType(TimelineWaitPanel), findsOneWidget);
    expect(tester.widget<TimelineWaitPanel>(find.byType(TimelineWaitPanel)).presentation, same(waiting));
    expect(content.scopes, isEmpty);
    await tester.pumpWidget(const SizedBox()); await _flush(tester);
  });
}
