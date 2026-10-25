// 展示工具（`show_image`）图片卡片的呈现契约。
//
// 覆盖工具条目到呈现项类型的映射、与会话内其它块的分离、typed 附件与展示文案的传递，
// 以及没有图片附件时的错误态。像素、解码与布局细节由 Driver 人工证据覆盖
// （design/24 §24.1、design/19 §19.9、design/25 §25.6）。
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/state/timeline_view_state.dart';
import 'package:anywork/src/features/conversation/timeline/presentation_item.dart';
import 'package:anywork/src/features/conversation/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/connectors/timeline_row_connector.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/features/conversation/timeline/display_lease.dart';
import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/timeline_drafts_environment.dart';

import 'support/timeline_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TimelineTestEnvironment environment;
  setUp(() {
    environment = TimelineTestEnvironment(
      timeline: const UnscriptedTimelineTransport(),
    );
  });
  tearDown(() => environment.close());
  TestWidgetsFlutterBinding.ensureInitialized();
  final timestamp =
      (DateTime.utc(2026, 1, 2, 3, 4, 5).millisecondsSinceEpoch ~/ 1000);

  const cardImage = ThreadAttachmentView(
    id: 'card-image',
    modality: AttachmentModality.image,
    mediaType: 'image/png',
    byteSize: 1024,
    filename: 'terrace.png',
    width: 800,
    height: 450,
  );

  StudioTimelineItem toolItem(
    String id, {
    required int ordinal,
    required String name,
    String arguments = '{}',
    List<ThreadAttachmentView> attachments = const [],
  }) => StudioTimelineItem(
    item: ThreadItemView(
      id: id,
      threadId: 'thread',
      turnId: 'turn',
      ordinal: ordinal,
      revision: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
      state: ThreadToolItemStateView(
        invocation: ThreadToolInvocationView(
          toolCallId: 'call-$id',
          callId: 'call-$id',
          name: name,
          arguments: arguments,
        ),
        lifecycle: SucceededThreadToolView(
          timestamp,
          ThreadToolOutput(
            result: 'ok',
            attachments: attachments,
            outputArtifacts: const [],
          ),
        ),
      ),
    ),
    saved: true,
    lifecycle: StudioTimelineLifecycle.terminal,
    omittedBytes: 0,
    details: const [],
  );

  /// 一条展示工具卡片条目：参数只带 canonical 展示文案。
  StudioTimelineItem cardItem(
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

  TimelineDisplayLease leaseWith(List<StudioTimelineItem> items) {
    final lease = TimelineDisplayLease(
      session: environment.conversations.session('thread'),
      generation: 1,
    );
    lease.content.adoptBaseline(
      StudioTimelineBaseline(
        subscriptionId: 'test',
        version: 0,
        items: items,
        before: null,
        hasOlder: false,
      ),
    );
    return lease;
  }

  TimelineViewState viewState() => TimelineViewState(
    threadId: 'thread',
    generation: 1,
    displayMode: TimelineDisplayMode.live,
    connectionPhase: TimelineConnectionPhase.ready,
    connectionError: null,
    olderCursor: null,
    hasOlder: false,
    olderLoading: false,
    olderError: null,
    hasNewOutput: false,
    preparingLive: false,
  );

  Future<void> pumpTimeline(
    WidgetTester tester,
    TimelineDisplayLease lease, {
    TimelineDraftsEnvironment? client,
    Size size = const Size(900, 700),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (client != null)
            draftsRepositoryProvider.overrideWithValue(client.repository),
        ],
        child: MaterialApp(
          theme: pureStudioTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TimelineView(
              threadId: 'thread',
              state: viewState(),
              binding: lease.canvas,
              messageBuilder: (context, message) => TimelineRowConnector(
                message: message,
                display: lease.binding,
              ),
              onLoadOlder: () async {},
              onRetryOlder: () async {},
              onReturnLive: () async {},
              onEnterHistory: () {},
              onRetryConnection: () async {},
            ),
          ),
        ),
      ),
    );
    // 卡片图片区是异步读取：给首帧与读取回调留出帧预算，不等待无限加载动画。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  TimelineDraftsEnvironment openClient() =>
      TimelineDraftsEnvironment(clientId: 'image-card');

  /// 在真实事件循环内收尾展示客户端：命令 owner 的收束依赖真实异步，不能挤在
  /// fake-async 的帧预算里等待。
  Future<void> closeClient(
    WidgetTester tester,
    TimelineDraftsEnvironment client,
  ) async {
    // A requested image is still Unknown until its original binary source
    // replies. Settle that exact opening, then let the real repository join it.
    for (final opening in client.binary.opens.values) {
      if (!opening.reply.isCompleted) {
        opening.reply.completeError(
          const StudioFailure(
            code: StudioFailureCode.cancelled,
            message: 'Test image source closed',
            retryable: false,
            correlationId: 'image-card-test-close',
          ),
        );
      }
    }
    await tester.runAsync(client.close);
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
        lease.content.presentationFor('call-before')!.kind,
        TimelinePresentationKind.activity,
      );
      final card = lease.content.presentationFor('card')!;
      expect(card, isA<TimelineImageCardGroup>());
      expect(card.kind, TimelinePresentationKind.imageCard);
      expect(card.memberIds, ['card']);
      // 后续同一 Turn 的普通工具仍按既有规则成组，且不含卡片成员。
      final after = lease.content.presentationFor('call-after')!;
      expect(after.kind, TimelinePresentationKind.activity);
      expect(after.memberIds, ['call-after']);
      // 读取图片的工具仍走既有图集，不与展示卡片共用呈现项。
      expect(
        lease.content.presentationFor('read-image')!.kind,
        TimelinePresentationKind.images,
      );
    });

    test('同 Turn 的多条展示调用各自一张卡片，不合并成组', () {
      final lease = leaseWith([
        cardItem('card-a', ordinal: 1),
        cardItem('card-b', ordinal: 2, arguments: '{"caption":"第二张"}'),
      ]);
      final first = lease.content.presentationFor('card-a')!;
      final second = lease.content.presentationFor('card-b')!;
      expect(first, isA<TimelineImageCardGroup>());
      expect(second, isA<TimelineImageCardGroup>());
      expect(identical(first, second), isFalse);
      expect(first.memberIds, ['card-a']);
      expect(second.memberIds, ['card-b']);
    });

    test('没有图片附件的展示调用仍是卡片，不退回普通工具活动组', () {
      final lease = leaseWith([
        cardItem('card-empty', ordinal: 1, attachments: const []),
      ]);
      expect(
        lease.content.presentationFor('card-empty')!.kind,
        TimelinePresentationKind.imageCard,
      );
    });
  });

  group('展示工具的图片卡片', () {
    testWidgets('typed 图片附件渲染独立卡片，未发布的 caption 和 previewReady 保持 Unknown', (
      tester,
    ) async {
      final client = openClient();
      final lease = leaseWith([cardItem('card', ordinal: 1)]);
      final entryId = StudioDriverKeys.toolImageEntryId(
        'call-card',
        'card-image',
      );
      await pumpTimeline(tester, lease, client: client);

      expect(
        find.byKey(StudioDriverKeys.imageCard(entryId)),
        findsOneWidget,
        reason: '卡片身份由 owning 调用与附件身份合成',
      );
      expect(
        find.text('雨后的天台'),
        findsNothing,
        reason: 'opaque arguments 不是 typed caption，禁止解析补造',
      );
      expect(
        find.text('This image is unavailable'),
        findsNothing,
        reason: '在途读取不是已知空图片',
      );
      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: '原 source 尚未发布结果，不能伪造 previewReady',
      );
      expect(find.text('Image card'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await lease.close();
      await closeClient(tester, client);
    });

    testWidgets('caption 非字符串或超长时按容错规则处理', (tester) async {
      final client = openClient();
      final lease = leaseWith([
        cardItem('card-bad', ordinal: 1, arguments: '{"caption":42}'),
      ]);
      final entryId = StudioDriverKeys.toolImageEntryId(
        'call-card-bad',
        'card-image',
      );
      await pumpTimeline(tester, lease, client: client);

      expect(find.byKey(StudioDriverKeys.imageCard(entryId)), findsOneWidget);
      expect(find.text('42'), findsNothing, reason: '只有字符串才作为展示文案');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await lease.close();
      await closeClient(tester, client);
    });

    testWidgets('没有图片附件时渲染卡片错误态', (tester) async {
      final client = openClient();
      final lease = leaseWith([
        cardItem('card-empty', ordinal: 1, attachments: const []),
      ]);
      await pumpTimeline(tester, lease, client: client);

      expect(
        find.text('This image is unavailable'),
        findsOneWidget,
        reason: '无 typed 图片附件时是错误态，不抛异常',
      );
      expect(find.text('Image card'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await lease.close();
      await closeClient(tester, client);
    });
  });
}
