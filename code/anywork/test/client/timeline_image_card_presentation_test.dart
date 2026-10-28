import 'support/conversation_fixtures.dart';

import 'dart:async';
import 'dart:typed_data';

// 展示工具（`show_image`）图片卡片的呈现契约。
//
// 覆盖工具条目到呈现项类型的映射、与会话内其它块的分离、typed 附件与展示文案的传递，
// 以及没有图片附件时的错误态。像素、解码与布局细节由 Driver 人工证据覆盖
// （design/24 §24.1、design/19 §19.9、design/25 §25.6）。
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_entry.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_detail_connector.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';
import 'support/pump_client_future.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final timestamp = DateTime.utc(2026, 1, 2, 3, 4, 5);

  const cardImage = ThreadAttachmentView(
    id: 'card-image',
    modality: AttachmentModalityView.image,
    mediaType: 'image/png',
    byteSize: 1024,
    filename: 'terrace.png',
    width: 800,
    height: 450,
  );

  ConversationItem toolItem(
    String id, {
    required int ordinal,
    required String name,
    String arguments = '{}',
    List<ThreadAttachmentView> attachments = const [],
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: ordinal,
    revision: 1,
    createdAt: timestamp,
    updatedAt: timestamp,
    saved: true,
    lifecycle: ConversationLifecycle.terminal,
    descriptor: ConversationToolDescriptor(
      invocation: ConversationToolInvocation(
        toolCallId: 'call-$id',
        callId: 'call-$id',
        name: name,
      ),
      state: ConversationToolSucceeded(
        completedAt: timestamp,
        output: ConversationToolOutputDescriptor(attachments: attachments),
      ),
    ),
    fields: {
      const ThreadToolArgumentsFieldView(): arguments,
      const ThreadToolResultFieldView(): 'ok',
    },
  );

  /// 一条展示工具卡片条目：参数只带 canonical 展示文案。
  ConversationItem cardItem(
    String id, {
    required int ordinal,
    String arguments = '{"caption":"雨后的天台"}',
    List<ThreadAttachmentView> attachments = const [cardImage],
  }) => toolItem(
    id,
    ordinal: ordinal,
    name: 'show_image',
    arguments: arguments,
    attachments: attachments,
  );

  Future<void> unmountTimeline(
    WidgetTester tester,
    TimelineDisplayLease lease,
  ) async {
    if (lease.isReleased) return;
    final close = find.byKey(StudioDriverKeys.timelineDetailClose);
    if (close.evaluate().isNotEmpty) {
      await tester.tap(close);
      await pumpClientUntil(
        tester,
        () => find
            .byKey(StudioDriverKeys.timelineDetailDialog)
            .evaluate()
            .isEmpty,
        'image detail actual close',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      lease.retire(),
      'image timeline stock operations done',
    );
    expect(lease.isReleased, isTrue, reason: '卸载后等待真实 stock operations done');
  }

  TimelineDisplayLease leaseWith(
    List<ConversationItem> items, {
    WidgetTester? tester,
  }) {
    final lease = TimelineDisplayLease(
      threadId: 'thread',
      generation: 1,
      content: conversationContentFixture(tester: tester),
    );
    lease.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'test',
        version: 0,
        items: items,
        before: null,
        hasOlder: false,
      ),
    );
    addTearDown(
      tester == null ? lease.retire : () => unmountTimeline(tester, lease),
    );
    return lease;
  }

  TimelineSessionViewState viewState() => TimelineSessionViewState(
    threadId: 'thread',
    generation: 1,
    mode: TimelineDisplayMode.live,
    connection: TimelineConnectionPhase.ready,
    connectionError: null,
    olderCursor: null,
    hasOlder: false,
    isLoadingOlder: false,
    olderError: null,
    hasNewOutput: false,
    isPreparingLive: false,
  );

  AnyworkClient openClient(WidgetTester tester) {
    final client = AnyworkClient(
      transport: RecordingDemoTransport(),
      clientId: 'image-card',
    );
    // close 的原 Future 可能同时依赖真实队列和 FakeAsync；驱动两者后再校验报告。
    addTearDown(() async {
      final report = await pumpClientFuture(
        tester,
        client.close(deadline: DateTime.now().add(const Duration(seconds: 1))),
        'image-card media client teardown close',
      );
      expect(report.complete, isTrue, reason: '展示客户端 teardown 必须真实关闭');
    });
    client.selection.markOpened();
    return client;
  }

  Future<void> pumpTimeline(
    WidgetTester tester,
    TimelineDisplayLease lease, {
    AnyworkClient? client,
    Size size = const Size(900, 700),
  }) async {
    final mediaClient = client ?? openClient(tester);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [anyworkClientProvider.overrideWithValue(mediaClient)],
        child: MaterialApp(
          theme: pureStudioTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final threadId = lease.threadId;
              Future<Uint8List> readAttachment(String id) =>
                  mediaClient.readAttachmentBytes(threadId, id);
              void detail(String itemId, ThreadContentFieldView field) {
                if (lease.isRetired || !context.mounted) return;
                unawaited(
                  openTimelineDetail(
                    context,
                    lease: lease,
                    itemId: itemId,
                    field: field,
                  ).catchError((Object error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error.toString())));
                    }
                  }),
                );
              }

              return Scaffold(
                body: TimelineView(
                  threadId: 'thread',
                  view: viewState(),
                  controls: lease,
                  onLoadOlder: () async {},
                  onRetryOlder: () async {},
                  onReturnLive: () async {},
                  onEnterHistory: () {},
                  onRetryConnection: () async {},
                  onDetail: detail,
                  onLink: (_) {},
                  isSafeLink: (_) => false,
                  imageBuilder: (_, message, index) => TimelineImageConnector(
                    message: message,
                    index: index,
                    item: timelineEntryOf(message)!.first,
                    resources: lease.imageResources,
                    readBytes: () => readAttachment(
                      (message.metadata!['attachment'] as ThreadAttachmentView)
                          .id,
                    ),
                    isActive: () => !lease.isRetired,
                    onDetail: detail,
                  ),
                  remoteImageBuilder: (_, _) => const SizedBox.shrink(),
                  groupMediaBuilder: (item) => TimelineGroupMediaConnector(
                    item: item,
                    resources: lease.imageResources,
                    readAttachment: readAttachment,
                    isActive: () => !lease.isRetired,
                    onDetail: detail,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    // 卡片图片区是异步读取：给首帧与读取回调留出帧预算，不等待无限加载动画。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 汇合原关闭 Future：同时驱动真实与 FakeAsync 队列，断言留在 helper 返回之后。
  Future<void> closeClient(WidgetTester tester, AnyworkClient client) async {
    final report = await pumpClientFuture(
      tester,
      client.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'image-card media client body close',
    );
    expect(report.complete, isTrue, reason: '展示客户端在用例内可完整收束');
  }

  group('展示工具的呈现分类', () {
    test('show_image 载荷独立成图片卡片组，不并入普通工具活动组', () {
      final lease = leaseWith([
        toolItem('call-before', ordinal: 1, name: 'read_file'),
        cardItem('card', ordinal: 2),
        toolItem('call-after', ordinal: 3, name: 'read_file'),
        toolItem('read-image', ordinal: 4, name: 'view_image'),
      ]);

      expect(
        lease.presentationFor('call-before')!.kind,
        TimelineEntryKind.activity,
      );
      final card = lease.presentationFor('card')!;
      expect(card, isA<TimelineEntry>());
      expect(card.kind, TimelineEntryKind.single);
      expect(card.memberIds, ['card']);
      final image = lease.controller.messages.whereType<ImageMessage>().single;
      expect(identical(timelineEntryOf(image), card), isTrue);
      expect(image.metadata!['attachment'], same(cardImage));
      // 后续同一 Turn 的普通工具仍按既有规则成组，且不含卡片成员。
      final after = lease.presentationFor('call-after')!;
      expect(after.kind, TimelineEntryKind.activity);
      expect(after.memberIds, ['call-after']);
      // 读取图片的工具仍走既有图集，不与展示卡片共用呈现项。
      expect(
        lease.presentationFor('read-image')!.kind,
        TimelineEntryKind.images,
      );
    });

    test('同 Turn 的多条展示调用各自一张卡片，不合并成组', () {
      final lease = leaseWith([
        cardItem('card-a', ordinal: 1),
        cardItem('card-b', ordinal: 2, arguments: '{"caption":"第二张"}'),
      ]);
      final first = lease.presentationFor('card-a')!;
      final second = lease.presentationFor('card-b')!;
      expect(first, isA<TimelineEntry>());
      expect(second, isA<TimelineEntry>());
      expect(identical(first, second), isFalse);
      expect(first.memberIds, ['card-a']);
      expect(second.memberIds, ['card-b']);
    });

    test('没有图片附件的展示调用仍是卡片，不退回普通工具活动组', () {
      final lease = leaseWith([
        cardItem('card-empty', ordinal: 1, attachments: const []),
      ]);
      expect(
        lease.presentationFor('card-empty')!.kind,
        TimelineEntryKind.single,
      );
    });
  });

  group('展示工具的图片卡片', () {
    testWidgets('带 typed 图片附件与 caption 时渲染卡片', (tester) async {
      final client = openClient(tester);
      final lease = leaseWith([cardItem('card', ordinal: 1)], tester: tester);
      await pumpTimeline(tester, lease, client: client);

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TimelineImageConnector &&
              widget.message.id == 'card:attachment:card-image',
        ),
        findsOneWidget,
        reason: '卡片身份由 owning 调用与附件身份合成',
      );
      expect(find.text('雨后的天台'), findsOneWidget);
      expect(find.text('Image card'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountTimeline(tester, lease);
      await closeClient(tester, client);
    });

    testWidgets('caption 非字符串或超长时按容错规则处理', (tester) async {
      final client = openClient(tester);
      final lease = leaseWith([
        cardItem('card-bad', ordinal: 1, arguments: '{"caption":42}'),
      ], tester: tester);
      await pumpTimeline(tester, lease, client: client);

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TimelineImageConnector &&
              widget.message.id == 'card-bad:attachment:card-image',
        ),
        findsOneWidget,
      );
      expect(find.text('42'), findsNothing, reason: '只有字符串才作为展示文案');
      expect(tester.takeException(), isNull);
      await unmountTimeline(tester, lease);
      await closeClient(tester, client);
    });

    testWidgets('没有图片附件时渲染卡片错误态', (tester) async {
      final client = openClient(tester);
      final lease = leaseWith([
        cardItem('card-empty', ordinal: 1, attachments: const []),
      ], tester: tester);
      await pumpTimeline(tester, lease, client: client);

      expect(
        find.text('This image is unavailable'),
        findsOneWidget,
        reason: '无 typed 图片附件时是错误态，不抛异常',
      );
      expect(find.text('Image card'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountTimeline(tester, lease);
      await closeClient(tester, client);
    });
  });
}
