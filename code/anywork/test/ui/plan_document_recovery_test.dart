import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/features/conversation/timeline/connectors/plan_detail_connector.dart';
import 'package:anywork/src/features/conversation/timeline/views/plan_detail_view.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/display_fixtures.dart';
import '../support/plan_document_harness.dart';
import '../support/plan_document_transport.dart';
import '../support/pump_client_future.dart';

void main() {
  testWidgets('计划先于 ready 挂载，离页返回、A-B-A 与新 attempt 自动恢复', (tester) async {
    final initialGate = Completer<void>();
    final h = await PlanDocumentHarness.open(
      tester,
      PlanDocumentTransport()..nextInitialGate = initialGate,
    );
    await h.publish(1, 'First plan body');
    await h.mount();
    final element = tester.element(find.byType(PlanDetailConnector));
    final panel = tester.state(find.byType(PlanDetailView));
    expect(h.session.content.state.value, isA<ChatOpening<bool>>());
    expect(h.transport.reads, isEmpty);
    expect(h.session.content.activity.value, isNull);
    initialGate.complete();
    await h.body('First plan body');
    expect(h.session.content.activity.value, isNull);
    expect(
      h.transport.reads.single.reference,
      h.session.state.businessRefs!.plan!.document,
    );
    expect(h.transport.businessReads, 0);
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
    final window = h.document.window;
    final lease = h.graph.timeline.lease('thread-main')!;
    final main = lease.controller;
    final history = main.messages.toList();
    expect(history, isNotEmpty);
    final feed = h.transport.timelineFeeds.single;
    for (var update = 0; update < 5; update++) {
      final previous = lease.live.value!;
      final live = LiveDisplayWindow(
        revision: previous.revision + 1,
        historyThrough: previous.historyThrough,
        currentWorkId: null,
        executionPresent: true,
        blocks: const [],
      );
      feed.emitTimeline(
        displayBatch(
          const [],
          placement: ChatPlacement.append,
          from: live.historyThrough,
          through: live.historyThrough,
          live: live,
        ),
      );
      await pumpClientUntil(
        tester,
        () => lease.live.value?.revision == live.revision,
        'live update ${live.revision} accepted by Client',
      );
      expect(h.document.window, same(window));
      expect(h.transport.reads, hasLength(1));
      expect(h.session.content.currentAttemptId, firstAttempt);
      expect(h.graph.timeline.lease('thread-main'), same(lease));
      expect(lease.controller, same(main));
      expect(main.messages, hasLength(history.length));
      for (var index = 0; index < history.length; index++) {
        expect(main.messages[index], same(history[index]));
      }
    }

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
    final h = await PlanDocumentHarness.open(tester, PlanDocumentTransport());
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

    // Both stale bytes and errors must be isolated after a document revision,
    // not just after reconnecting the same document on a new attempt.
    for (final failOld in [false, true]) {
      final revision = failOld ? 4 : 2;
      final obsoleteGate = Completer<void>();
      h.transport
        ..nextReadGate = obsoleteGate
        ..nextReadError = failOld
            ? StateError('obsolete version failure')
            : null;
      final reads = h.transport.reads.length;
      await h.publish(revision, 'Obsolete version $revision');
      await h.reads(reads + 1);
      final obsolete = h.transport.reads.last;
      await h.publish(revision + 1, 'Current version ${revision + 1}');
      await h.body('Current version ${revision + 1}');
      final window = h.document.window;
      obsoleteGate.complete();
      await pumpClientUntil(
        tester,
        () => obsolete.delivered,
        'late old ${failOld ? 'failure' : 'bytes'}',
      );
      expect(h.document.window, same(window));
      expect(find.textContaining('Obsolete version'), findsNothing);
      expect(find.textContaining('obsolete version failure'), findsNothing);
      expect(h.document.error, isNull);
      expect(h.document.loading, isFalse);
    }

    final completedReads = h.transport.completedReads;
    final olderReads = h.transport.olderReads;
    h.transport.nextReadError = StateError('document disk unavailable');
    await h.publish(6, 'Retry version body');
    await pumpClientUntil(
      tester,
      () => h.document.error != null,
      'local failure',
    );
    expect(find.textContaining('document disk unavailable'), findsOneWidget);
    expect(h.document.window, isNull);
    expect(find.byKey(StudioDriverKeys.planDetailsMarkdown), findsNothing);
    expect(
      find.textContaining('Retry version body', findRichText: true),
      findsNothing,
    );
    expect(h.transport.businessReads, 0);
    expect(h.transport.completedReads, completedReads);
    expect(h.transport.olderReads, olderReads);
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
    await h.publish(7, 'Disposed version body');
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
    final h = await PlanDocumentHarness.open(
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
    final h = await PlanDocumentHarness.open(
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
