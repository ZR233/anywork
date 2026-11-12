import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/plan_detail_connector.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/plan_document_view_model.dart';
import 'package:anywork/src/features/conversation/timeline/views/plan_detail_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/chat_fixtures.dart';
import '../support/plan_document_transport.dart';
import '../support/pump_client_future.dart';
import '../support/test_statistics_feed.dart';

void main() {
  testWidgets('计划先于 ready 挂载，离页返回、A-B-A 与新 attempt 自动恢复', (tester) async {
    final initialGate = Completer<void>();
    final h = await _Harness.open(
      tester,
      PlanDocumentTransport()..nextInitialGate = initialGate,
    );
    await h.publish(1, 'First plan body');
    await h.mount();
    final element = tester.element(find.byType(PlanDetailConnector));
    final panel = tester.state(find.byType(PlanDetailView));
    expect(h.session.content.state.value, isA<ChatOpening<bool>>());
    expect(h.transport.reads, isEmpty);
    initialGate.complete();
    await h.body('First plan body');
    expect(h.transport.reads.single.range.maxBytes, 64 * 1024);
    expect(
      find.byKey(
        StudioDriverKeys.timelineContentCopyWindow(
          'plan-document',
          'plan.document',
        ),
      ),
      findsOneWidget,
    );
    final firstAttempt = h.session.content.currentAttemptId;

    h.graph.setConversationPageVisible(false);
    await tester.pump();
    expect(find.byKey(StudioDriverKeys.planDetailsMarkdown), findsNothing);
    h.graph.setConversationPageVisible(true);
    await h.body('First plan body');
    expect(h.session.content.currentAttemptId, isNot(firstAttempt));
    expect(h.transport.reads, hasLength(2));
    expect(tester.element(find.byType(PlanDetailConnector)), same(element));
    expect(tester.state(find.byType(PlanDetailView)), same(panel));

    h.graph.setConversationPageVisible(true, threadId: 'thread-alt');
    await pumpClientUntil(
      tester,
      () => h.graph.client.conversations.visibleThreadId.value == 'thread-alt',
      'B visible',
    );
    expect(find.byKey(StudioDriverKeys.planDetailsMarkdown), findsNothing);
    h.graph.setConversationPageVisible(true, threadId: 'thread-main');
    await h.body('First plan body');
    expect(h.transport.reads, hasLength(3));

    h.session.content.refresh();
    await h.body('First plan body');
    expect(h.transport.reads, hasLength(4));
    // An unrelated state publication with the same reference is not a read.
    await h.publish(1, 'First plan body');
    await tester.pump();
    expect(h.transport.reads, hasLength(4));

    h.transport.failNextInitial = StateError('temporary connection loss');
    h.session.content.refresh();
    await pumpClientUntil(
      tester,
      () => h.session.content.state.value is ChatReconnecting<bool>,
      'reconnecting',
    );
    expect(h.document.error, isNull, reason: '重连期间显示等待，而非局部失败');
    expect(h.document.window, isNull);
    await tester.pump(const Duration(seconds: 1));
    await h.body('First plan body');
    expect(h.transport.reads, hasLength(5));
    await h.close();
  });

  testWidgets('旧读取迟到不清新 loading，文档换版隔离旧错误，局部失败显式重试', (tester) async {
    final h = await _Harness.open(tester, PlanDocumentTransport());
    await h.publish(1, 'Old version body');
    final oldGate = Completer<void>();
    h.transport.nextReadGate = oldGate;
    await h.mount();
    await h.reads(1);
    final oldRead = h.transport.reads.single;

    final newGate = Completer<void>();
    h.transport.nextReadGate = newGate;
    h.session.content.refresh();
    await h.reads(2);
    oldGate.complete();
    await pumpClientUntil(tester, () => oldRead.delivered, 'late old success');
    expect(h.document.loading, isTrue);
    expect(h.document.window, isNull);
    newGate.complete();
    await h.body('Old version body');

    final oldErrorGate = Completer<void>();
    h.transport
      ..nextReadGate = oldErrorGate
      ..nextReadError = StateError('obsolete version failure');
    await h.publish(2, 'Second version body');
    await h.reads(3);
    final oldError = h.transport.reads.last;
    await h.publish(3, 'Current version body');
    await h.body('Current version body');
    oldErrorGate.complete();
    await pumpClientUntil(tester, () => oldError.delivered, 'late old failure');
    expect(find.textContaining('obsolete version failure'), findsNothing);
    expect(h.document.error, isNull);
    expect(h.document.loading, isFalse);

    h.transport.nextReadError = StateError('document disk unavailable');
    await h.publish(4, 'Retry version body');
    await pumpClientUntil(
      tester,
      () => h.document.error != null,
      'local failure',
    );
    expect(find.textContaining('document disk unavailable'), findsOneWidget);
    final feeds = h.transport.timelineFeeds.length;
    final reads = h.transport.reads.length;
    await tester.pump(const Duration(seconds: 2));
    expect(h.transport.reads, hasLength(reads), reason: '没有自动重试循环');
    await tester.tap(find.byKey(const ValueKey('plan-document-retry')));
    await h.body('Retry version body');
    expect(h.transport.reads, hasLength(reads + 1));
    expect(h.transport.timelineFeeds, hasLength(feeds), reason: '局部失败不重开连接');

    final disposedGate = Completer<void>();
    h.transport
      ..nextReadGate = disposedGate
      ..nextReadError = StateError('disposed document failure');
    await h.publish(5, 'Disposed version body');
    await h.reads(reads + 2);
    final disposedRead = h.transport.reads.last;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    disposedGate.complete();
    await pumpClientUntil(
      tester,
      () => disposedRead.delivered,
      'disposed read',
    );
    expect(tester.takeException(), isNull);
    await h.close();
  });

  testWidgets('真实连接失败显示原因，显式重试刷新连接后自动读正文', (tester) async {
    final h = await _Harness.open(
      tester,
      PlanDocumentTransport()
        ..failNextInitial = const StudioFailure(
          code: StudioFailureCode.protocol,
          message: 'plan connection rejected',
          retryable: false,
          correlationId: 'plan-connection',
          reason: StudioFailureReason.protocolVersionMismatch,
        ),
    );
    await h.publish(1, 'Recovered connection body');
    await h.mount();
    await pumpClientUntil(
      tester,
      () => h.document.error != null,
      'connection failure',
    );
    expect(find.textContaining('plan connection rejected'), findsOneWidget);
    expect(h.transport.reads, isEmpty);
    final feeds = h.transport.timelineFeeds.length;
    await tester.tap(find.byKey(const ValueKey('plan-document-retry')));
    await h.body('Recovered connection body');
    expect(h.transport.timelineFeeds, hasLength(feeds + 1));
    await h.close();
  });

  testWidgets('计划正文保留有界翻页与只复制当前窗口', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    final h = await _Harness.open(
      tester,
      PlanDocumentTransport()..responseMaxBytes = 32,
    );
    const markdown =
        'First bounded paragraph for the plan.\n\n'
        'Second bounded paragraph keeps a different body visible.';
    await h.publish(1, markdown);
    await h.mount();
    await pumpClientUntil(
      tester,
      () => h.document.window != null && !h.document.loading,
      'first bounded window',
    );
    final copy = find.byKey(
      StudioDriverKeys.timelineContentCopyWindow(
        'plan-document',
        'plan.document',
      ),
    );
    final next = find.byKey(
      StudioDriverKeys.timelineContentNextWindow(
        'plan-document',
        'plan.document',
      ),
    );
    await tester.tap(copy);
    await tester.pump();
    expect(copied, markdown.substring(0, 32));
    await tester.tap(next);
    await pumpClientUntil(
      tester,
      () => h.document.window?.offset == 32 && !h.document.loading,
      'next bounded window',
    );
    expect(h.transport.reads, hasLength(2));
    expect(h.transport.reads.last.range.offset, 32);
    expect(
      h.transport.reads.map((read) => read.range.maxBytes),
      everyElement(65536),
    );
    await tester.tap(copy);
    await tester.pump();
    expect(copied, utf8.decode(h.document.window!.bytes));
    expect(copied, markdown.substring(32, 64));
    await h.close();
  });
}

class _Harness {
  _Harness(this.tester, this.transport, this.graph);
  final WidgetTester tester;
  final PlanDocumentTransport transport;
  final AppGraph graph;
  late ProviderContainer container;
  ConversationSession get session =>
      graph.client.conversations.session('thread-main');
  PlanDocumentState get document =>
      container.read(planDocumentViewModelProvider('thread-main'));

  static Future<_Harness> open(
    WidgetTester tester,
    PlanDocumentTransport transport,
  ) async {
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'plan-recovery',
    );
    final h = _Harness(tester, transport, graph);
    await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
    graph
      ..timeline.updateReadDemand(chatDemand)
      ..setConversationPageVisible(true);
    await pumpClientFuture(
      tester,
      graph.client.directoryCommands.selectThread('thread-main'),
      'select thread',
    );
    await pumpClientUntil(
      tester,
      () => h.session.state.hasSnapshot,
      'state before content ready',
    );
    return h;
  }

  Future<void> publish(int revision, String markdown) async {
    transport.seedConversationState(
      'thread-main',
      ThreadRuntimeUpdate(
        runtime: session.state.workspace!.runtime.copyWith(
          plan: PlanRuntimeView(
            revision: revision,
            state: PlanRuntimePhase.awaitingConfirmation,
            updatedAt: DateTime.utc(2026, 3, 18),
            document: PlanDocumentView(
              version: revision,
              markdown: markdown,
              contentHash: 'plan-$revision',
            ),
          ),
        ),
        todo: null,
        modelRoute: session.state.modelRoute,
      ),
    );
    await pumpClientUntil(
      tester,
      () => session.state.businessRefs?.plan?.revision == revision,
      'plan reference $revision',
    );
  }

  Future<void> mount() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appGraphProvider.overrideWithValue(graph)],
        child: MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PlanDetailConnector(
              threadId: 'thread-main',
              identity: 'pending-plan',
              status: PlanDetailStatus.awaitingConfirmation,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(PlanDetailConnector)),
    );
    await tester.pump();
  }

  Future<void> reads(int count) => pumpClientUntil(
    tester,
    () => transport.reads.length >= count,
    'read $count',
  );

  Future<void> body(String text) => pumpClientUntil(
    tester,
    () =>
        document.window != null &&
        !document.loading &&
        find.textContaining(text, findRichText: true).evaluate().isNotEmpty,
    'body $text',
  );

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    final report = await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'close graph',
    );
    expect(report.complete, isTrue);
  }
}
