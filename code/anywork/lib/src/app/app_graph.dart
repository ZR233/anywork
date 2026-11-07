import 'dart:async';

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

import '../platform/clipboard_image_reader.dart';
import '../platform/error_log.dart';
import '../presentation/view_models/timeline_session_owner.dart';
import 'studio_startup_host.dart';

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
    StudioStartupHost? startupHost,
    ClipboardImageStager? clipboardImageStager,
  }) : startupHost = startupHost ?? ImmediateStudioStartupHost() {
    final staged = <String, StagedClipboardImage>{};
    final stager = clipboardImageStager ?? const SystemClipboardImageStager();
    final instanceId = clientId ?? 'app-${identityHashCode(this)}';
    final mutations = MutationBoard(clientId: instanceId);
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
      owner: instanceId,
    );
    client = AnyworkClient(
      transport: transport,
      clientId: instanceId,
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
      owner: client.clientId,
    );
    client.updates.attach();
    timeline = TimelineSessionOwner(client: client);
    _conversationObservation = client.conversations.visibleThreadId.watch(
      _observeVisibleConversation,
    );
    _observeVisibleConversation(client.conversations.visibleThreadId.value);
    final selection = client.selection.source.watchLatest((_) {
      _syncVisibleConversation();
    });
    _selectionObservation = selection.observation;
  }

  final StudioStartupHost startupHost;
  ValueListenable<StudioStartupPhase> get startupProgress =>
      startupHost.progress;
  ValueListenable<StartupRecoveryReport?> get startupRecovery =>
      startupHost.recovery;
  void dismissStartupRecovery() => startupHost.dismissRecovery();

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
    startupHost.prepareRetry();
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
  Observation? _conversationObservation;
  Observation? _workspaceObservation;
  bool _conversationPageVisible = false;
  String? _routeThreadId;
  bool _hostVisible = true;
  bool _closed = false;
  Future<CloseReport>? _closing;

  /// Navigation, not a selected ID or a mounted offstage route, owns demand.
  /// Bot routes supply their own target; the studio follows canonical selection.
  void setConversationPageVisible(bool visible, {String? threadId}) {
    if (_closed) return;
    _conversationPageVisible = visible;
    _routeThreadId = threadId;
    _syncVisibleConversation();
  }

  /// Losing focus alone does not hide the conversation; minimizing does.
  void setHostVisible(bool visible) {
    if (_closed || _hostVisible == visible) return;
    _hostVisible = visible;
    _syncVisibleConversation();
  }

  String? get _conversationTarget {
    if (_closed || !_conversationPageVisible || !_hostVisible) return null;
    final selection = client.selection.state;
    return _routeThreadId ??
        (selection.needsOpen ? null : selection.selectedThreadId);
  }

  void _observeVisibleConversation(String? id) {
    _workspaceObservation?.cancel();
    _workspaceObservation = null;
    timeline.select(id);
    if (_closed ||
        id == null ||
        client.conversations.visibleThreadId.value != id) {
      return;
    }
    final session = client.conversations.existingSession(id)!;
    void admitDraft() {
      if (_conversationTarget == id &&
          session.state.workspace != null &&
          client.drafts.existingComposer(id) == null) {
        _syncVisibleConversation();
      }
    }

    _workspaceObservation = session.source.watch((_) => admitDraft());
    admitDraft();
  }

  void _syncVisibleConversation() {
    if (_closed) return;
    final target = _conversationTarget;
    timeline.noteVisibleSelection(target);
    final conversations = client.conversations;
    if (target != conversations.visibleThreadId.value) {
      conversations.setVisibleThread(null);
    }
    if (target == null) {
      timeline.select(null);
      return;
    }
    if (target != _conversationTarget) return;
    // A valid destination borrows its logical draft across route changes.
    if (conversations.existingSession(target)?.state.workspace != null) {
      client.drafts.composer(target);
    }
    if (target == _conversationTarget) conversations.setVisibleThread(target);
  }

  Future<CloseReport> close({required DateTime deadline}) {
    final existing = _closing;
    if (existing != null) return existing;
    final completion = Completer<CloseReport>();
    _closing = completion.future;
    completion.complete(Future<CloseReport>.sync(() => _close(deadline)));
    return completion.future;
  }

  /// 先同步封闭 Client 准入，并在首次 await 前发布「无展示」促使 Chat 子树卸载。
  ///
  /// `timeline.close` 在首次 await 之前同步清空展示元数据；视图卸载后其真实 `dispose`
  /// 才允许 lease 销毁 controller 并观察 stock stream done。树仍借用 controller 时不会
  /// 提前 ACK，重复 close 得到同一个释放结果（design/26 §26.8）。
  Future<CloseReport> _close(DateTime deadline) async {
    _closed = true;
    _selectionObservation?.cancel();
    _selectionObservation = null;
    _conversationObservation?.cancel();
    _conversationObservation = null;
    _workspaceObservation?.cancel();
    _workspaceObservation = null;
    final clientClose = client.close(deadline: deadline);
    final timelineClose = timeline.close(deadline: deadline);
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
