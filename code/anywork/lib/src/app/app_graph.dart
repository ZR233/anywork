import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/statistics.dart';
import 'package:anywork_client/statistics_ports.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/acp_ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../infrastructure/frb/studio_api.dart';
import '../infrastructure/frb/studio_update_api.dart';
import '../infrastructure/frb/statistics/frb_statistics_feed.dart';
import '../infrastructure/demo/statistics/demo_statistics_feed.dart';
import '../platform/clipboard_image_reader.dart';
import '../platform/studio_platform.dart';
import '../platform/error_log.dart';
import '../presentation/view_models/timeline_session_owner.dart';

/// The application composition root is the only place that knows both the
/// transport implementation and the SDK-only Client.
class AppGraph {
  AppGraph({
    required StudioTransport transport,
    required StatisticsFeedPort statisticsFeed,
    String? clientId,
    StudioUpdateApi? updateApi,
    bool updatesEnabled = false,
    AccountFeedPort? accountFeed,
    AccountConfigurationPort? accountConfiguration,
    AccountModelsPort? accountModels,
    AccountUsagePort? accountUsage,
    AcpPort? acpPort,
  }) {
    final staged = <String, StagedClipboardImage>{};
    final stager = const SystemClipboardImageStager();
    final instanceId = clientId ?? 'app-${identityHashCode(this)}';
    final budget = ResourceBudget();
    final mutations = MutationBoard(clientId: instanceId, budget: budget);
    final settingsWrites = SettingsWriteCoordinator();
    accountDomains = AccountDomainResources(
      feed: accountFeed ?? transport as AccountFeedPort,
      configuration:
          accountConfiguration ?? transport as AccountConfigurationPort,
      modelPort: accountModels ?? transport as AccountModelsPort,
      usagePort: accountUsage ?? transport as AccountUsagePort,
      acpPort: acpPort ?? transport as AcpPort,
      coordinator: settingsWrites,
      mutations: mutations,
      budget: budget,
      owner: instanceId,
    );
    client = AnyworkClient(
      transport: transport,
      clientId: instanceId,
      budget: budget,
      mutationBoard: mutations,
      settingsWrites: settingsWrites,
      accountDomains: accountDomains,
      updateApi: updateApi,
      updatesEnabled: updatesEnabled,
      clipboardImageStager: (Uint8List bytes) async {
        final image = await stager.stage(bytes);
        staged[image.path] = image;
        return image.path;
      },
      clipboardImageCleanup: (path) async {
        final image = staged[path];
        if (image == null) return;
        await image.dispose();
        staged.remove(path);
      },
    );
    accountDomains.onSettings = client.acceptSettingsSnapshot;
    accountDomains.attachDirectoryDemand(
      () => _ModelDirectoryDemand(
        client.channels.acquireTopic(const ModelCatalogTopic()),
      ),
    );
    statisticsRepository = createStatisticsRepository(
      feed: statisticsFeed,
      budget: client.budget,
      owner: client.clientId,
    );
    client.updates.attach();
    timeline = TimelineSessionOwner(client: client);
    final selection = client.selection.source.watchLatest((_) {
      _syncVisibleConversation();
    });
    _selectionObservation = selection.observation;
  }

  factory AppGraph.production() => AppGraph(
    transport: FrbStudioTransport(),
    statisticsFeed: const FrbStatisticsFeedPort(),
    updateApi: const FrbStudioUpdateApi(),
    updatesEnabled:
        isWindowsPlatform &&
        (const bool.fromEnvironment('dart.vm.product') ||
            const bool.fromEnvironment('ANYWORK_DRIVER')) &&
        !const bool.fromEnvironment('ANYWORK_DEMO'),
  );
  factory AppGraph.demo({bool driver = false}) => AppGraph(
    transport: driver
        ? DriverDemoStudioTransport(lspActivityLoop: true)
        : DemoStudioTransport(lspActivityLoop: true),
    statisticsFeed: DemoStatisticsFeedPort(),
  );

  ValueListenable<StudioStartupPhase> get startupProgress =>
      FrbStudioTransport.startupProgress;
  ValueListenable<StartupRecoveryReport?> get startupRecovery =>
      FrbStudioTransport.startupRecovery;
  void dismissStartupRecovery() =>
      FrbStudioTransport.startupRecovery.value = null;

  /// Client publishes success/failure before this application-level handler
  /// records diagnostics. A route never owns a separate startup Future or flag.
  Future<void> initialize() =>
      client.bootstrap().catchError((Object error, StackTrace stack) {
        recordDartError(
          error,
          stack,
          stage: 'bootstrap',
          correlationId: client.bootstrapState.value.failure?.correlationId,
        );
      });

  Future<void> retryStartup() {
    FrbStudioTransport.retryInitialization();
    return initialize();
  }

  late final AnyworkClient client;
  late final StatisticsRepository statisticsRepository;
  late final TimelineSessionOwner timeline;
  late final AccountDomainResources accountDomains;
  AccountsRepository get accounts => accountDomains.accounts;
  ModelsRepository get models => accountDomains.models;
  AccountUsageRepository get accountUsage => accountDomains.usage;
  AcpService get acp => accountDomains.acp;
  Observation? _selectionObservation;
  bool _conversationPageVisible = false;
  String? _expectedConversationThreadId;
  bool _hostVisible = true;
  bool _closed = false;
  String? _visibleThreadId;
  Future<CloseReport>? _closing;

  /// Navigation, not a selected ID or a mounted offstage route, owns demand.
  /// A resource-bound destination may restrict demand to its expected selection;
  /// that restriction never supplies a second selection or opens another thread.
  void setConversationPageVisible(bool visible, {String? expectedThreadId}) {
    if (_closed ||
        (_conversationPageVisible == visible &&
            _expectedConversationThreadId == expectedThreadId)) {
      return;
    }
    _conversationPageVisible = visible;
    _expectedConversationThreadId = expectedThreadId;
    _syncVisibleConversation();
  }

  /// Losing focus alone does not hide the conversation; minimizing does.
  void setHostVisible(bool visible) {
    if (_closed || _hostVisible == visible) return;
    _hostVisible = visible;
    _syncVisibleConversation();
  }

  void _syncVisibleConversation() {
    if (_closed) return;
    final selection = client.selection.state;
    final target =
        _conversationPageVisible &&
            _hostVisible &&
            !selection.needsOpen &&
            (_expectedConversationThreadId == null ||
                selection.selectedThreadId == _expectedConversationThreadId)
        ? selection.selectedThreadId
        : null;
    if (_visibleThreadId == target) return;
    _visibleThreadId = target;
    // Revoke the old presentation before retiring the feed. A -> B -> A
    // never gives a late callback permission to publish into the new lease.
    timeline.select(null);
    client.conversations.setVisibleThread(target);
    if (target != null) timeline.select(target);
  }

  Future<CloseReport> close({required DateTime deadline}) =>
      _closing ??= _close(deadline);

  /// 关闭顺序：先同步发布「无展示」促使现存 Chat 子树卸载，再同时收束 Client。
  ///
  /// `timeline.close` 在首次 await 之前同步清空展示元数据；视图卸载后其真实 `dispose`
  /// 才允许 lease 销毁 controller 并观察 stock stream done。树仍借用 controller 时不会
  /// 提前 ACK，重复 close 得到同一个释放结果（design/26 §26.8）。
  Future<CloseReport> _close(DateTime deadline) async {
    _closed = true;
    _selectionObservation?.cancel();
    _selectionObservation = null;
    final timelineClose = timeline.close(deadline: deadline);
    final clientClose = client.close(deadline: deadline);
    final statisticsClose = statisticsRepository.close(deadline: deadline);
    final accountClose = accountDomains.close(deadline: deadline);
    final reports = await Future.wait([
      timelineClose,
      clientClose,
      statisticsClose,
      accountClose,
    ]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }
}

final class _ModelDirectoryDemand implements AccountDemand {
  _ModelDirectoryDemand(this.lease);
  final BridgeTopicLease lease;
  @override
  Future<void> release() => lease.release();
}

/// Borrowed instance. ProviderScope owns observations, never the application.
final appGraphProvider = Provider<AppGraph>((ref) {
  throw StateError('The application must inject its AppGraph');
});
