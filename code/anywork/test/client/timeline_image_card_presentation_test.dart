// 展示工具（`show_image`）图片卡片的呈现契约。
//
// 覆盖工具条目到呈现项类型的映射、与会话内其它块的分离、typed 附件与展示文案的传递，
// 以及没有图片附件时的错误态。像素、解码与布局细节由 Driver 人工证据覆盖
// （design/24 §24.1、design/19 §19.9、design/25 §25.6）。
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/domain/models/timeline_presentation.dart';
import 'package:anywork/src/features/timeline/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

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
          ThreadToolOutputView(
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
      threadId: 'thread',
      generation: 1,
      openQueries: (_) => null,
    );
    lease.adoptBaseline(
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

  Future<void> pumpTimeline(
    WidgetTester tester,
    TimelineDisplayLease lease, {
    AnyworkClient? client,
    Size size = const Size(900, 700),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (client != null) anyworkClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          theme: pureStudioTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TimelineView(
              threadId: 'thread',
              view: viewState(),
              lease: lease,
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

  AnyworkClient openClient() {
    final client = AnyworkClient(
      transport: RecordingDemoTransport(),
      clientId: 'image-card',
    );
    // close 会等待命令 owner 收束：这些等待需要真实事件循环，因此在 runAsync 内收尾。
    addTearDown(
      () => client.close(
        deadline: DateTime.now().add(const Duration(seconds: 1)),
      ),
    );
    client.selection.markOpened();
    return client;
  }

  /// 在真实事件循环内收尾展示客户端：命令 owner 的收束依赖真实异步，不能挤在
  /// fake-async 的帧预算里等待。
  Future<void> closeClient(WidgetTester tester, AnyworkClient client) async {
    final report = await tester.runAsync(
      () => client.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );
    expect(report!.complete, isTrue, reason: '展示客户端在用例内可完整收束');
  }

  group('展示工具的呈现分类', () {
    test('show_image 载荷独立成图片卡片组，不并入普通工具活动组', () {
      final lease = leaseWith([
        toolItem('call-before', ordinal: 1, name: 'stat_path'),
        cardItem('card', ordinal: 2),
        toolItem('call-after', ordinal: 3, name: 'stat_path'),
        toolItem('read-image', ordinal: 4, name: 'view_image'),
      ]);

      expect(
        lease.presentationFor('call-before')!.kind,
        TimelinePresentationKind.activity,
      );
      final card = lease.presentationFor('card')!;
      expect(card, isA<TimelineImageCardGroup>());
      expect(card.kind, TimelinePresentationKind.imageCard);
      expect(card.memberIds, ['card']);
      // 后续同一 Turn 的普通工具仍按既有规则成组，且不含卡片成员。
      final after = lease.presentationFor('call-after')!;
      expect(after.kind, TimelinePresentationKind.activity);
      expect(after.memberIds, ['call-after']);
      // 读取图片的工具仍走既有图集，不与展示卡片共用呈现项。
      expect(
        lease.presentationFor('read-image')!.kind,
        TimelinePresentationKind.images,
      );
    });

    test('同 Turn 的多条展示调用各自一张卡片，不合并成组', () {
      final lease = leaseWith([
        cardItem('card-a', ordinal: 1),
        cardItem('card-b', ordinal: 2, arguments: '{"caption":"第二张"}'),
      ]);
      final first = lease.presentationFor('card-a')!;
      final second = lease.presentationFor('card-b')!;
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
        lease.presentationFor('card-empty')!.kind,
        TimelinePresentationKind.imageCard,
      );
    });
  });

  group('展示工具的图片卡片', () {
    testWidgets('带 typed 图片附件与 caption 时渲染卡片', (tester) async {
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
      expect(find.text('雨后的天台'), findsOneWidget);
      expect(find.text('Image card'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await lease.retire();
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
      await lease.retire();
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
      await lease.retire();
      await closeClient(tester, client);
    });
  });
}
