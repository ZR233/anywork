// 时间线公开文本与公开产物的渠道呈现契约（design/27 §27.6.1、design/29 §29.2–29.4）。
//
// 覆盖：呈现完整性（Full/Truncated）与平台结果（Accepted/Rejected/Unknown）分开显示，
// 文件永不被标成截断；公开产物的“已发布 / 历史已保存 / 本机已保存”与渠道送达是不同
// 事实。像素布局与截图由 Driver 人工证据覆盖。
import 'dart:typed_data';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/timeline/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/platform/public_artifact_platform.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/audience_fixture.dart';
import 'support/test_statistics_feed.dart';

final class _UnusedSaveTarget implements PublicArtifactPlatform {
  @override
  Future<String?> chooseSavePath(String suggestedName) async => null;

  @override
  Future<void> writeBytes(String destination, Uint8List bytes) async {}

  @override
  Future<bool> openFile(String destination) async => false;
}

StudioTimelineItem _textItem({
  int revision = 1,
  bool saved = true,
  String body = '完整答复',
}) => StudioTimelineItem(
  item: ThreadItemView(
    id: 'canonical-text',
    threadId: 'thread',
    turnId: 'turn',
    ordinal: 1,
    revision: revision,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: saved,
    state: ThreadTextItemStateView(
      channel: ThreadTextChannel.finalAnswer,
      text: body,
      attachments: const [],
      lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
    ),
  ),
  saved: saved,
  lifecycle: StudioTimelineLifecycle.terminal,
  omittedBytes: 0,
  details: const [],
);

StudioTimelineItem _artifactItem({
  int revision = 1,
  bool saved = false,
  int byteLen = 6,
}) => StudioTimelineItem(
  item: ThreadItemView(
    id: 'canonical-artifact',
    threadId: 'thread',
    turnId: 'turn',
    ordinal: 2,
    revision: revision,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: saved,
    state: ThreadPublicArtifactItemStateView(
      publicationId: 'publication-1',
      toolCallId: 'tool-call-1',
      displayName: '报告.未知后缀',
      resource: ThreadArtifactResource(
        id: 'resource-1',
        contentDigest: 'sha256:${'0' * 64}',
        byteLen: byteLen,
        mediaType: 'application/x-unknown',
      ),
      publishedAt: DateTime.utc(2026),
    ),
  ),
  saved: saved,
  lifecycle: StudioTimelineLifecycle.terminal,
  omittedBytes: 0,
  details: const [],
);

TimelineSessionViewState _viewState() => const TimelineSessionViewState(
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

ReadThreadAudienceItemsReply _reply(
  AudienceReadCall call, {
  required BotItemDelivery delivery,
  int summaryVersion = 1,
  int deliveryVersion = 1,
}) => ReadThreadAudienceItemsReply(
  threadId: call.request.threadId,
  authorization: call.request.authorization,
  result: BotAudienceItemsReadItems(
    authorization: BotAuthorizationRef(
      id: call.request.authorization,
      revision: 1,
    ),
    phase: BotAuthorizationPhase.active,
    summaryVersion: summaryVersion,
    deliveryVersion: deliveryVersion,
    items: [
      for (final id in call.request.itemIds)
        BotAudienceItemStatus(
          itemId: id,
          canonical: const BotAudienceCanonicalItemPresent(
            revision: 1,
            saved: true,
            eligibility: BotItemEligibilityText(
              channel: BotPublicTextChannel.finalAnswer,
            ),
          ),
          delivery: delivery,
        ),
    ],
  ),
);

Future<AppGraph> _graph(
  WidgetTester tester,
  AudienceTransport transport,
) async {
  final graph = AppGraph(
    transport: transport,
    statisticsFeed: const TestStatisticsFeedPort(),
    clientId: 'publication-blocks',
    artifactPlatform: _UnusedSaveTarget(),
  );
  addTearDown(() async {
    // The fixture statistics feed never acknowledges its close; the bounded
    // deadline keeps the render contract independent of that unrelated owner.
    await tester.runAsync(
      () =>
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 2))),
    );
  });
  return graph;
}

TimelineDisplayLease _leaseWith(
  ThreadAudienceScope scope,
  List<StudioTimelineItem> items,
) {
  final lease = TimelineDisplayLease(
    threadId: 'thread',
    generation: 1,
    openQueries: (_) => null,
    openAudience: () => scope,
  );
  lease.adoptBaseline(
    StudioTimelineBaseline(
      subscriptionId: 'test',
      version: 1,
      before: null,
      items: items,
      hasOlder: false,
    ),
  );
  return lease;
}

Future<void> _pumpTimeline(
  WidgetTester tester,
  AppGraph graph,
  TimelineDisplayLease lease,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appGraphProvider.overrideWithValue(graph)],
      child: MaterialApp(
        theme: pureStudioTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TimelineView(
            threadId: 'thread',
            view: _viewState(),
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
  await tester.pump();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TimelineView)));

/// The strip shows one line in place and keeps the full item detail in its
/// tooltip, so both surfaces are part of the contract.
String _channelDetail(WidgetTester tester, AppLocalizations l10n) {
  final matches = tester
      .widgetList<Tooltip>(find.byType(Tooltip))
      .map((tooltip) => tooltip.message ?? '')
      .where((message) => message.startsWith(l10n.audienceCurrentContext))
      .toList();
  expect(matches, hasLength(1), reason: 'one strip per mounted public row');
  return matches.single;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a public text row separates channel integrity from the platform result',
    (tester) async {
      final transport = AudienceTransport();
      final graph = await _graph(tester, transport);
      graph.client
          .session('thread')
          .applySnapshot(audienceWorkspace(knownAudience()));
      final scope = graph.client.audienceQueries.openScope('thread', 1);
      final lease = _leaseWith(scope, [_textItem()]);
      await _pumpTimeline(tester, graph, lease);
      final read = await transport.nextRead();
      expect(read.request.itemIds, [
        'canonical-text',
      ], reason: 'demand is the canonical member, never a presentation id');
      read.result.complete(
        _reply(
          read,
          delivery: const BotItemDeliveryKnown(
            ledger: BotItemLedgerSummary(
              observedRevision: 1,
              projected: BotItemPresentationText(
                revision: 1,
                integrity: BotTextIntegrity.truncated,
                saved: true,
              ),
              accepted: BotItemPresentationText(
                revision: 1,
                integrity: BotTextIntegrity.truncated,
                saved: true,
              ),
              platform: BotItemPlatformCard(
                latestOperation: BotCardOperationSummary(
                  operationId: 'card-op',
                  contentRevision: 1,
                  action: BotCardOperationKind.content,
                  result: BotPlatformResultAccepted(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final l10n = _l10n(tester);
      final detail = _channelDetail(tester, l10n);
      expect(
        detail,
        contains(l10n.audienceCurrentAccepted),
        reason: 'the accepted revision matches this canonical revision',
      );
      expect(detail, contains(l10n.audienceProjected));
      expect(
        find.text(l10n.audienceTruncated),
        findsOneWidget,
        reason: 'the host states the presentation was truncated',
      );
      expect(
        detail,
        isNot(contains(l10n.audienceFull)),
        reason: 'truncated content is never labelled complete',
      );
      expect(
        find.textContaining(l10n.audiencePlatformAccepted),
        findsOneWidget,
      );
      expect(detail, contains(l10n.audiencePlatformAccepted));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'a public artifact keeps local save, history saving and channel delivery apart',
    (tester) async {
      final transport = AudienceTransport();
      final graph = await _graph(tester, transport);
      graph.client
          .session('thread')
          .applySnapshot(audienceWorkspace(knownAudience()));
      final scope = graph.client.audienceQueries.openScope('thread', 1);
      final lease = _leaseWith(scope, [_artifactItem()]);
      await _pumpTimeline(tester, graph, lease);
      final read = await transport.nextRead();
      expect(read.request.itemIds, ['canonical-artifact']);
      read.result.complete(
        _reply(
          read,
          delivery: const BotItemDeliveryKnown(
            ledger: BotItemLedgerSummary(
              observedRevision: 1,
              projected: BotItemPresentationFile(revision: 1),
              accepted: BotItemPresentationNone(),
              platform: BotItemPlatformFile(
                operationId: 'file-op',
                contentRevision: 1,
                upload: BotPlatformResultAccepted(),
                message: BotPlatformResultRejected(
                  diagnostic: BotDiagnostic(
                    code: 'platform-rejected',
                    message: 'rejected',
                    retryable: false,
                  ),
                ),
                outcome: BotFileOutcome.partial,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final l10n = _l10n(tester);
      final detail = _channelDetail(tester, l10n);
      // The typed artifact block: identity, size and save actions only.
      expect(find.text(l10n.artifactPublished), findsOneWidget);
      expect(find.text('报告.未知后缀'), findsOneWidget);
      expect(
        find.text(l10n.artifactHistoryPending),
        findsOneWidget,
        reason: 'a committed item does not imply its history revision is saved',
      );
      expect(find.text(l10n.artifactSave), findsOneWidget);
      expect(find.text(l10n.artifactSaveOpen), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // Channel facts stay independent: upload accepted, message rejected means
      // partial, and a file is never described as truncated.
      expect(
        find.text(l10n.audiencePartial),
        findsOneWidget,
        reason: 'the in-place line states a partial platform outcome',
      );
      expect(detail, contains(l10n.audienceUpload));
      expect(detail, contains(l10n.audienceMessage));
      expect(detail, contains(l10n.audiencePlatformRejected));
      expect(find.text(l10n.audienceTruncated), findsNothing);
      expect(
        detail,
        isNot(contains(l10n.audienceTruncated)),
        reason: 'files have no presentation truncation',
      );
      expect(
        detail,
        isNot(contains(l10n.audienceFull)),
        reason: 'a file is never described with text integrity at all',
      );
      expect(
        detail,
        isNot(contains(l10n.audienceCurrentAccepted)),
        reason: 'nothing in this ledger proves the file was delivered',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
