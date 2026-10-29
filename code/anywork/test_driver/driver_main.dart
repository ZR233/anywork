// Driver-only 故障注入复用既有 @visibleForTesting 初始化 override，不新增生产 fault API。
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywork/main.dart' as studio;
import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/statistics.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/state/account_view_state.dart';
import 'package:anywork/src/features/settings/accounts/views/accounts_list_view.dart';
import 'package:anywork/src/features/settings/accounts/views/account_details_view.dart';
import 'package:anywork/src/features/settings/accounts/views/native_account_editor_view.dart';
import 'package:anywork/src/features/settings/accounts/views/acp_account_editor_view.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_details_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_editor_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_editor_session_view_model.dart';
import 'package:anywork/src/features/settings/accounts/views/account_model_details_view.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:go_router/go_router.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_models_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/acp_account_view_model.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_plain_text.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/studio_host_lifecycle.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/l10n/studio_l10n.dart';

import 'package:anywork/src/platform/error_log.dart';
import 'package:anywork/src/shared/studio_driver_key_values.dart';
import 'package:anywork/src/shared/studio_driver_projection.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'raw_tap_extension.dart';
import 'pointer_scroll_extension.dart';
import 'pointer_drag_extension.dart';
import 'scrollbar_drag_extension.dart';
import 'key_press_extension.dart';
import 'tool_probe_extension.dart';
import 'runtime_event_evidence.dart';
import 'conversation_credit_probe.dart';
import 'page_switch_extension.dart';
import 'pointer_hover_extension.dart';

/// Native-only Driver entrypoint. Product and release builds use lib/main.dart.
void main() {
  if (const bool.fromEnvironment('dart.vm.product')) {
    throw StateError('Flutter Driver mode is unavailable in product builds');
  }
  enableFlutterDriverExtension(
    handler: _handleDriverData,
    commands: <CommandExtension>[
      RawTapCommandExtension(),
      PointerHoverCommandExtension(),
      PageSwitchCommandExtension(
        client: () => _client,
        owner: () => _container.read(appGraphProvider).timeline,
      ),
      PointerScrollCommandExtension(),
      PointerDragCommandExtension(),
      ScrollbarDragCommandExtension(),
      KeyPressCommandExtension(),
      ToolProbeExtension(
        owner: () => _container.read(appGraphProvider).timeline,
      ),
    ],
  );
  SchedulerBinding.instance.addTimingsCallback(_recordFrameTimings);
  final graph = const bool.fromEnvironment('ANYWORK_DEMO')
      ? AppGraph.demo(driver: true)
      : AppGraph.production();
  _container = ProviderContainer(
    overrides: [
      appGraphProvider.overrideWithValue(graph),
      statisticsRepositoryProvider.overrideWithValue(
        graph.statisticsRepository,
      ),
    ],
  );
  // Driver 只借用当前 AppGraph 的 Client 与展示 owner；绑定不建立内容订阅。
  bindStudioDriver(
    graph.client,
    timeline: graph.timeline,
    accountsRepository: graph.accounts,
    modelsRepository: graph.models,
    usageRepository: graph.accountUsage,
    acpService: graph.acp,
    observedAccountDetails: _observedAccountDetails,
  );
  _applyShutdownFaultOverride();
  studio.bootstrapStudio(container: _container);
  // 生产 widget（`_StudioLifecycleCoordinator.initState`）会在**首帧构建时**安装它
  // 自己的协调器（同一 `graph.close`），覆盖任何更早的安装。Driver 取证必须观察
  // 实际 active 的那一次收束，因此把同一 graph / 同一预算 / 同一进度接口的 Driver
  // 绑定放到首帧之后安装一次：不循环抢 active、不改生产入口、不新增 production getter。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _installDriverExitCoordinator(graph);
  });
}

/// 只安装一次 Driver 专用的退出协调器绑定（同一 AppGraph、同一 shutdown 进度接口）。
///
/// 与托盘退出共用同一条 `StudioExitCoordinator`：native -> Dart 的 requestExit 也进入它。
void _installDriverExitCoordinator(AppGraph graph) {
  StudioExitCoordinator.install(
    StudioExitCoordinator(
      graph.client.transport,
      _container.read(studioShutdownProgressStateProvider.notifier).update,
      readyUpdateVersion: () =>
          graph.client.updates.state is ReadyUpdaterStateSnapshot
          ? graph.client.updates.state.update?.version
          : null,
      onBeginExit: _container
          .read(studioShutdownProgressStateProvider.notifier)
          .beginExit,
      // 退出（含失败取消）在 `graph.close` 之前取消 runtime 取证观察：共享 Session／
      // Client 仍由既有 owner 关闭，记录器不改变任何 business demand。
      closeClient: (deadline) async {
        _runtimeEvidence?.cancelForShutdown();
        // 只**观察**既有 close 的结果：等这一次 memoized close，投影其
        // CloseReport.unresolved 供验收定位，然后原样返回同一报告。
        // 不重复 close / 不 retryCleanup / 不改清理与 Degraded 语义。
        final report = await graph.close(deadline: deadline);
        _clientCloseObserved = true;
        _clientCloseResources = _clientCloseResourcesJson(report);
        return report;
      },
    ),
  );
}

/// Driver-only 初始化故障注入：`ANYWORK_DRIVER_SHUTDOWN_FAULT` 取值
/// `pending-init`（初始化永久挂住）或 `bridge-load-error`（初始化显式抛错）。
///
/// 复用既有 [FrbStudioTransport.debugOverrideInitialization]，不新增生产 fault 接口；订阅
/// 故障由验收侧独立 Driver 入口/装饰器提供（见 ui-handoff-r3.txt）。
void _applyShutdownFaultOverride() {
  final fault = Platform.environment['ANYWORK_DRIVER_SHUTDOWN_FAULT'];
  if (fault == 'pending-init') {
    FrbStudioTransport.debugOverrideInitialization(
      () => Completer<void>().future,
    );
  } else if (fault == 'bridge-load-error') {
    FrbStudioTransport.debugOverrideInitialization(() async {
      throw StateError('driver-injected bridge load failure');
    });
  }
}

late final ProviderContainer _container;
AnyworkClient get _client => _container.read(appGraphProvider).client;
Future<StudioShutdownReport>? _shutdownTask;
ConversationCreditProbe? _conversationCreditProbe;

Future<StatisticsSnapshot> _awaitStatisticsSnapshot() async {
  final repository = _container.read(appGraphProvider).statisticsRepository;
  final demand = repository.acquireVisibleDemand();
  try {
    final current = repository.state;
    if (current.snapshot != null &&
        current.connection.phase == StatisticsConnectionPhase.ready) {
      return current.snapshot!;
    }

    final ready = Completer<StatisticsSnapshot>();
    void consider(StatisticsRepositoryState state) {
      final snapshot = state.snapshot;
      if (snapshot != null &&
          state.connection.phase == StatisticsConnectionPhase.ready) {
        if (!ready.isCompleted) ready.complete(snapshot);
      } else if (snapshot == null &&
          state.connection.phase == StatisticsConnectionPhase.failed) {
        if (!ready.isCompleted) {
          ready.completeError(
            StateError(
              'statistics repository failed before a complete owner snapshot',
            ),
          );
        }
      }
    }

    final observation = repository.observe(consider);
    consider(observation.initialState);
    try {
      return await ready.future.timeout(const Duration(seconds: 30));
    } finally {
      observation.cancel();
    }
  } finally {
    demand.release();
  }
}

/// Driver-only 只读证据：既有 `graph.close` 报告是否真的观察到，及其 unresolved
/// 资源投影。未观察时 `clientCloseObserved=false` 且资源为 `null`（**不**用空集合
/// 冒充“没有资源”）。
bool _clientCloseObserved = false;
List<Map<String, Object?>>? _clientCloseResources;
Future<void>? _driverFixtureClipboardImageTask;

/// Driver-only runtime 发布取证记录器：借用当前 Client 已存在的 Session 观察公开
/// runtime read-model 发布，不创建 Session、不建立 transport 订阅、不改变 demand。
RuntimeEventEvidenceRecorder? _runtimeEvidence;
bool _recordingFrames = false;
int _frameCount = 0;
int _slowFrames = 0;
int _verySlowFrames = 0;
int _maxFrameMicros = 0;
final List<Map<String, num>> _frameSamples = [];

void _recordFrameTimings(List<FrameTiming> timings) {
  if (!_recordingFrames) return;
  final completedAt = DateTime.now().millisecondsSinceEpoch;
  for (final timing in timings) {
    final elapsed = timing.totalSpan.inMicroseconds;
    _frameCount++;
    if (elapsed > 16667) _slowFrames++;
    if (elapsed > 33333) _verySlowFrames++;
    if (elapsed > _maxFrameMicros) _maxFrameMicros = elapsed;
    _frameSamples.add({
      'completedUnixMillis': completedAt,
      'totalMillis': elapsed / 1000,
      'vsyncOverheadMillis': timing.vsyncOverhead.inMicroseconds / 1000,
      'buildMillis': timing.buildDuration.inMicroseconds / 1000,
      'rasterMillis': timing.rasterDuration.inMicroseconds / 1000,
    });
  }
  if (_frameSamples.length > 8192) _frameSamples.removeRange(0, 4096);
}

Future<String> _handleDriverData(String? message) async {
  // JSON 命令限定在 Driver 入口：几何观察不参与产品布局；credit probe
  // 只持有额外的正式 transport feed，不能改变正常 SDK consumer 的 ACK。
  final raw = message?.trim() ?? '';
  if (raw.startsWith('{')) {
    return _handleJsonDriverCommand(raw);
  }
  switch (message) {
    case 'frame-start':
      _frameCount = 0;
      _slowFrames = 0;
      _verySlowFrames = 0;
      _maxFrameMicros = 0;
      _frameSamples.clear();
      _recordingFrames = true;
      return jsonEncode({'recording': true});
    case 'frame-stop':
      _recordingFrames = false;
      return jsonEncode({
        'frames': _frameCount,
        'over16Millis': _slowFrames,
        'over33Millis': _verySlowFrames,
        'maxFrameMillis': _maxFrameMicros / 1000,
        'samples': _frameSamples,
      });
    case 'snapshot':
      return _driverSnapshotJson();
    case 'updater-state':
      // Read-only Client/canonical facts, including the request that survives routes.
      final updater = _client.updates.state;
      final request = _client.updates.request.value;
      return jsonEncode({
        'state': updater.runtimeType.toString(),
        'revision': updater.revision,
        'version': updater.update?.version,
        'request': request.phase.name,
        'pending': request.pending,
        if (updater is DownloadingUpdaterStateSnapshot)
          'downloaded': updater.downloaded,
        if (updater is DownloadingUpdaterStateSnapshot) 'total': updater.total,
        if (updater is InstallFailedUpdaterStateSnapshot)
          'error': updater.error.code,
      });
    case 'mode-editor-state':
      final editor = _client.modeEditor.state;
      final catalog = _client.modeCatalog.state;
      final threadId = _client.selection.state.selectedThreadId;
      final session = threadId == null
          ? null
          : _client.conversations.sessionState(threadId);
      final run = session?.runtime?.workflow?.currentRun;
      return jsonEncode({
        'document': editor.document?.toJson(),
        'jsonText': editor.jsonText,
        'dirty': editor.dirty,
        'readOnly': editor.readOnly,
        'busy': editor.busy,
        'canUndo': editor.canUndo,
        'canRedo': editor.canRedo,
        'error': editor.error,
        'issues': [for (final issue in editor.issues) issue.toJson()],
        'preview': editor.preview?.toJson(),
        'catalogRevision': catalog.revision,
        'catalog': [
          for (final mode
              in catalog.value?.modes ?? <ThreadModeDescriptorView>[])
            {
              'id': mode.id,
              'displayName': mode.displayName,
              'readOnly': mode.readOnly,
            },
        ],
        'threadId': threadId,
        'run': run == null
            ? null
            : {
                'runId': run.runId,
                'lineageId': run.lineageId,
                'graphHash': run.graphHash,
                'currentStateId': run.currentStateId,
                'currentStateTitle': run.currentStateTitle,
                'modeDisplayName': run.modeDisplayName,
                'modeDeleted': run.modeDeleted,
              },
      });
    case 'driver-diagnostics':
      return jsonEncode(_driverDiagnostics());
    case 'driver-fixture-clipboard-image':
      // This is deliberately not a system clipboard operation. There is no
      // Driver-only ClipboardImageReader override in the current app, so the
      // deterministic fixture hook starts the same controller admission path
      // without awaiting its preview continuation. The follow-up
      // `driver-fixture-clipboard-image-preview` request awaits that typed
      // Driver-only stage.
      return _startDriverFixtureClipboardImage();
    case 'driver-fixture-clipboard-image-preview':
      return _finishDriverFixtureClipboardImage();
    case 'pid':
      // Acceptance locates the X11 window by `_NET_WM_PID`, so the driver must
      // expose its own process id. Product builds use lib/main.dart, so this
      // stays inside the Driver-only entrypoint.
      return jsonEncode({'pid': pid});
    case 'statistics':
      final performance = await _awaitStatisticsSnapshot();
      return jsonEncode({
        'ownerEpoch': performance.ownerEpoch,
        'feedId': performance.feedId,
        'revision': performance.publicationRevision,
        'summariesRevision': performance.summariesRevision,
        'historyRevision': performance.historyRevision,
        'statisticsPending': performance.statisticsPending,
        'statisticsGap': performance.statisticsGap,
        'readFailed': performance.readFailed,
        'summaries': [
          for (final summary in performance.summaries)
            {
              'accountId': summary.accountId,
              'accountDisplayName': summary.accountDisplayName,
              'modelId': summary.modelId,
              'samples': summary.sampleCount,
              'tokens': summary.completionTokens,
              'tokensPerSecond': summary.tokensPerSecond,
              'ttftSampleCount': summary.ttftSampleCount,
              'averageTtftMillis': summary.averageTtftMillis,
              'effortBreakdowns': [
                for (final effort in summary.effortBreakdowns)
                  {
                    'effort': effort.effort,
                    'samples': effort.sampleCount,
                    'tokens': effort.completionTokens,
                    'tokensPerSecond': effort.tokensPerSecond,
                    'ttftSampleCount': effort.ttftSampleCount,
                    'averageTtftMillis': effort.averageTtftMillis,
                  },
              ],
            },
        ],
        'history': [
          for (final sample in performance.history)
            {
              'accountId': sample.accountId,
              'accountDisplayName': sample.accountDisplayName,
              'modelId': sample.modelId,
              'sentModel': sample.sentModel,
              'reportedModel': sample.reportedModel,
              'matchState': sample.modelMatchState.name,
              'effort': sample.effort,
              'tokens': sample.completionTokens,
              'ttftMillis': sample.ttftMillis,
              'decodeMillis': sample.decodeMillis,
              'responseMillis': sample.totalResponseMillis,
              'tokensPerSecond': sample.tokensPerSecond,
            },
        ],
      });
    case 'thread-current':
      final threadId = _client.selection.state.selectedThreadId;
      if (threadId == null) return jsonEncode({'outputTokens': null});
      final snapshot = _client.conversations.sessionState(threadId)?.workspace;
      return jsonEncode({
        'outputTokens': snapshot?.runtime.completionTokens,
        'revision': snapshot?.revision,
      });
    case 'persistence-queue':
      // Driver 通过显式 topic lease 读取事件缓存，避免恢复已删除的 GUI 周期查询。
      final queue = _client.persistence.state.queue?.queue;
      return jsonEncode({
        'pendingOperations': queue?.pendingOperations,
        'threads': [
          for (final thread in queue?.threads ?? const [])
            {
              'fault': thread.fault,
              'generation': thread.faultGeneration,
              'stateDirty': thread.stateDirtyRevision,
              'stateDurable': thread.stateDurableRevision,
              'historyAdmitted': thread.historyAdmittedSequence,
              'historyDurable': thread.historyDurableSequence,
              'pending': thread.pendingOperations,
              'error': thread.lastError,
            },
        ],
      });
    // Timeline 展示意图：与界面按钮共用同一个 owner 动作，没有旧 window/focus 入口。
    // 这些命令只转发真实用户动作，不代替滚轮产生阅读意图（进入 History 只由真实
    // 用户滚动触发）。
    case 'load-older':
      final threadId = _client.selection.state.selectedThreadId;
      if (threadId == null) return jsonEncode({'loaded': false});
      final owner = _container.read(appGraphProvider).timeline;
      await owner.loadOlder(
        threadId,
        generation: owner.lease(threadId)?.generation ?? 0,
      );
      return jsonEncode({'loaded': true});
    case 'timeline-retry-older':
      final threadId = _client.selection.state.selectedThreadId;
      if (threadId == null) return jsonEncode({'loaded': false});
      final owner = _container.read(appGraphProvider).timeline;
      await owner.retryOlder(
        threadId,
        generation: owner.lease(threadId)?.generation ?? 0,
      );
      return jsonEncode({'loaded': true});
    case 'timeline-return-live':
      final threadId = _client.selection.state.selectedThreadId;
      if (threadId == null) return jsonEncode({'switched': false});
      await _container.read(appGraphProvider).timeline.returnToLive(threadId);
      return jsonEncode({'switched': true});
    case 'selection-body':
      // Read-only: the rendered split of the long assistant body.
      return jsonEncode(<String, Object?>{'ok': true, ...?_renderedLongBody()});
    case 'body-layout':
      return jsonEncode(_longBodyLayout());
    case 'selection-select-all':
      return _handleSelectAll();
    case 'selection-copy':
      return _handleCopySelected();
    case 'selection-state':
      return _handleSelectionState();
    case 'search-settings':
      return _handleSearchSettings();
    case 'search-mcp-state':
      return _handleSearchMcpState();
    case 'account-usage-state':
      return _accountUsageStateJson();
    case 'shutdown':
      try {
        final report = await (_shutdownTask ??= _runShutdown());
        // typed 清理 ack：成功才返 completed；degraded 如实上报，绝不伪 Stopped。
        return jsonEncode({
          'shutdown': report.allowsCleanExit ? 'completed' : 'degraded',
          ..._shutdownReportJson(report),
        });
      } on Object catch (error, stackTrace) {
        // 失败与堆栈不能只 debugPrint：落盘到 canonical 诊断日志。
        recordDartError(error, stackTrace);
        _shutdownTask = null;
        return jsonEncode({'shutdown': 'failed'});
      }
    case 'request-app-exit':
      // 先回复 exit_requested，再调度同一中央退出（arm deadline + 有界清理 + finishExit）。
      StudioDriverState.markExitRequested();
      Timer.run(() {
        unawaited(
          StudioExitCoordinator.requestExit().catchError((Object _) {}),
        );
      });
      return jsonEncode({'exit': 'exit_requested'});
    case 'arm-exit':
      // Driver-only：只固定 native 首次期限（beginExit），不清理、不退出。用于第一次
      // arm 后隔 5s 再 begin/repeat 再 hang，核对第一次 deadline 未被刷新。
      final armExitRemainingMs = await StudioHostLifecycle.beginExit();
      return jsonEncode({
        'armed': true,
        'remainingMs': armExitRemainingMs,
        'pid': pid,
      });
    case 'request-app-exit-twice':
      // 先武装 native 单期限并回报剩余，再间隔触发两次同一中央退出请求：第一次锚定
      // Dart 期限，第二次只复用同一 shared future；remaining 只减不增即证明不刷新。
      final twiceArmedRemainingMs = await StudioHostLifecycle.beginExit();
      StudioDriverState.markExitRequested();
      unawaited(StudioExitCoordinator.requestExit().catchError((Object _) {}));
      Timer(const Duration(milliseconds: 500), () {
        StudioDriverState.markExitRequested();
        unawaited(
          StudioExitCoordinator.requestExit().catchError((Object _) {}),
        );
      });
      return jsonEncode({
        'exit': 'exit_requested_twice',
        'armedRemainingMs': twiceArmedRemainingMs,
      });
    case 'shutdown-hang':
      // 仅 Driver 构建：先 arm deadline 并更新阶段，再阻塞 Dart isolate 并不返回 ack，
      // 验证 native 期限线程不依赖 Dart/bridge/mainloop 也能在到期强制结束本进程。
      // 验收以 OS pid 在 ~30s 内消失为证据，不依赖 requestData 是否拿到回复。
      await StudioHostLifecycle.beginExit();
      await StudioHostLifecycle.updateExitDiagnostics(stage: 'driver-hang');
      await StudioHostLifecycle.updateExitDiagnostics(
        stage: 'driver-hang-blocked',
      );
      sleep(const Duration(minutes: 5));
      return jsonEncode({'shutdown': 'hang-finished-unexpectedly'});
    case 'exit-status':
      // Driver-only 只读：暴露 native 剩余期限/清理预算/退出请求次数、typed 报告与
      // 已观察阶段、typed startup 状态/失败 code/correlation，供验收对齐 remaining/stage
      // 与 second-instance busy 判定，不触发任何退出动作。
      final diagnostics = StudioDriverState.exitDiagnosticsJson();
      final startup = diagnostics['startup'];
      return jsonEncode({
        ...diagnostics,
        'clientResources': [
          for (final resource in _client.budget.usage)
            {
              'kind': resource.kind.name,
              'owner': resource.owner,
              'phase': resource.phase.name,
            },
        ],
        'unresolvedClientResources': [
          for (final resource in _client.unresolvedResources)
            {'owner': resource.owner, 'reason': resource.reason.toString()},
        ],
        'startup': {
          if (startup is Map<String, Object?>) ...startup,
          'phase': FrbStudioTransport.startupProgress.value.name,
          'ownerPresent': FrbStudioTransport.runtimeOwnerPresent,
        },
      });
    default:
      return jsonEncode({'error': 'unsupported driver request'});
  }
}

/// 一次几何请求最多观察的行数：只读诊断，不值得让一次命令遍历整棵树。
const _timelineGeometryRowLimit = 64;

/// 产品分页小页上限（条）：一次 `load-older` 必须真实增长 1..32 条。
///
/// 20k 条历史下 `hasOlder` 在首页之后仍为真，因此“没有增长但还报 hasOlder”或
/// 空页/假 EOF 都不能算成功；growth 从实际 controller 与独立快照读取，不按请求值填。
const _timelinePageSizeLimit = 32;

/// JSON 命令入口（当前只有 `timeline-geometry`）。
///
/// 一切读取都在请求时发生：没有每帧采集、没有全局行测量表，也不向产品写回任何值。
Future<String> _handleJsonDriverCommand(String raw) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'error': 'invalidJson',
      'detail': error.message,
    });
  }
  if (decoded is! Map) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'error': 'commandMustBeJsonObject',
    });
  }
  final command = decoded['cmd'];
  switch (command) {
    case 'conversation-credit-open':
      if (_client.transport is! FrbStudioTransport) {
        throw StateError(
          'credit evidence requires the real native FRB transport',
        );
      }
      if (_conversationCreditProbe != null) {
        throw StateError('this Driver run already owns its credit probe');
      }
      final threadId = decoded['threadId'];
      if (threadId is! String ||
          threadId != _client.selection.state.selectedThreadId) {
        throw StateError('credit probe requires the selected real Thread');
      }
      final probe = ConversationCreditProbe(
        await _client.transport.openConversationFeed(threadId),
      );
      _conversationCreditProbe = probe;
      return jsonEncode(await probe.holdTwo());
    case 'conversation-credit-query':
      final probe = _conversationCreditProbe;
      if (probe == null) throw StateError('credit probe is not open');
      return jsonEncode(await probe.query(_client.transport));
    case 'conversation-credit-ack-one':
      final probe = _conversationCreditProbe;
      if (probe == null) throw StateError('credit probe is not open');
      return jsonEncode(await probe.acknowledgeOne());
    case 'conversation-credit-close':
      final probe = _conversationCreditProbe;
      if (probe == null) throw StateError('credit probe is not open');
      return jsonEncode(await probe.close());
    case 'timeline-geometry':
      final rowIds = decoded['rowIds'];
      if (rowIds != null && rowIds is! List) {
        return jsonEncode(<String, Object?>{
          'ok': false,
          'error': 'rowIdsMustBeList',
        });
      }
      return jsonEncode(
        _timelineGeometry(
          rowIds: rowIds == null
              ? null
              : <String>[for (final id in rowIds) '$id'],
        ),
      );
    case 'timeline-detail-text':
      // 打开着的详情查看器实际已加载到的正文：只读当前挂载子树，不触发读取、
      // 不改变查看器状态。用于证明逐块读取累计与关闭后停止。
      return jsonEncode(_timelineDetailText());
    case 'load-older-overlap':
      // 分页在途 + 滚轮交叠：在**同一个 Driver 操作**里调用产品自己的分页动作、
      // 直接读取应用发布的真实 loading 事实，再经标准指针信号路由派发输入，
      // 并 await 同一个真实分页 Future 收束。宿主命令往返不再被当作交叠证据。
      return jsonEncode(
        await _loadOlderOverlap(
          threadId: decoded['threadId'] is String
              ? decoded['threadId'] as String
              : null,
          generation: decoded['generation'] is num
              ? (decoded['generation'] as num).toInt()
              : null,
          inputs: decoded['inputs'] is num
              ? (decoded['inputs'] as num).toInt()
              : 8,
          dy: decoded['dy'] is num ? (decoded['dy'] as num).toDouble() : -60,
        ),
      );
    case 'clipboard-text':
      // 只读平台剪贴板当前内容（产品自己的复制动作已写入）；不修改剪贴板。
      // `full: true` 时额外返回原文，供验收与 fixture 推出的期望原文/结构比较。
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      return jsonEncode(<String, Object?>{
        'ok': true,
        'characters': text.length,
        'bytes': utf8.encode(text).length,
        'hash': _fnv1a64Hex(text),
        'head': _headOf(text),
        'tail': _tailOf(text),
        if (decoded['full'] == true) 'text': text,
      });
    case 'runtime-evidence-start':
      // Driver-only：在**已存在**的 Client Session 上登记 runtime 发布观察。命令只接受
      // 精确身份（threadId／turnId），不创建 Session、不新建 transport 订阅、不改 demand。
      final threadId = decoded['threadId'];
      final turnId = decoded['turnId'];
      if (threadId is! String || turnId is! String) {
        return jsonEncode(<String, Object?>{
          'ok': false,
          'cmd': 'runtime-evidence-start',
          'error': 'targetMustBeStrings',
        });
      }
      _runtimeEvidence ??= RuntimeEventEvidenceRecorder(_client);
      return jsonEncode(
        _runtimeEvidence!.start(threadId: threadId, turnId: turnId),
      );
    case 'runtime-evidence-stop':
      // 同步取消本记录器自己的观察并返回不可变结果；未开始或重复停止明确失败。
      final recorder = _runtimeEvidence;
      if (recorder == null) {
        return jsonEncode(<String, Object?>{
          'ok': false,
          'cmd': 'runtime-evidence-stop',
          'source': RuntimeEventEvidenceRecorder.source,
          'error': 'notStarted',
        });
      }
      return jsonEncode(recorder.stop());
    default:
      return jsonEncode(<String, Object?>{
        'ok': false,
        'error': 'unknownCommand',
        'command': command,
      });
  }
}

/// 只读行几何：视口 rect + 与视口真实相交的行 rect（同一坐标系）。
///
/// 按 canonical row key 现场遍历挂载的 element/render tree，因此它观察的是真实可见
/// 位置，而不是另存一份布局状态。指定 [rowIds] 时逐个给出终态；没有对应 Element 的
/// id 进入 `missing`，Element 存在但不可测则在行里给出 `reason`。
Map<String, Object?> _timelineGeometry({List<String>? rowIds}) {
  if (rowIds != null && rowIds.length > _timelineGeometryRowLimit) {
    return <String, Object?>{
      'ok': false,
      'error': 'tooManyRowIds',
      'limit': _timelineGeometryRowLimit,
    };
  }
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) {
    return <String, Object?>{'ok': false, 'error': 'noRootElement'};
  }
  final viewportKey = StudioDriverKeyValues.timelineScrollable;
  final rowPrefix = StudioDriverKeyValues.timelineRow('');
  RenderBox? viewport;
  _visitElements(root, (element) {
    if (viewport != null) return;
    final key = element.widget.key;
    if (key is ValueKey<String> && key.value == viewportKey) {
      final box = element.renderObject;
      if (box is RenderBox) viewport = box;
    }
  });
  final viewportBox = viewport;
  if (viewportBox == null || !viewportBox.attached || !viewportBox.hasSize) {
    return <String, Object?>{'ok': false, 'error': 'viewportNotMounted'};
  }
  final globalOrigin = viewportBox.localToGlobal(Offset.zero);
  final size = viewportBox.size;
  final bounds = Offset.zero & size;
  final requested = rowIds?.toSet();
  final rows = <Map<String, Object?>>[];
  final found = <String>{};

  _visitElements(root, (element) {
    final key = element.widget.key;
    if (key is! ValueKey<String> || !key.value.startsWith(rowPrefix)) return;
    final id = key.value.substring(rowPrefix.length);
    if (requested != null && !requested.contains(id)) return;
    found.add(id);
    final render = element.renderObject;
    if (render is! RenderBox) {
      rows.add(<String, Object?>{
        'id': id,
        'mounted': true,
        'painted': false,
        'intersects': false,
        'reason': 'noRenderBox',
      });
      return;
    }
    if (!render.attached) {
      rows.add(<String, Object?>{
        'id': id,
        'mounted': true,
        'painted': false,
        'intersects': false,
        'reason': 'detachedRenderBox',
      });
      return;
    }
    if (!render.hasSize || !render.size.isFinite || render.size.isEmpty) {
      rows.add(<String, Object?>{
        'id': id,
        'mounted': true,
        'painted': false,
        'intersects': false,
        'reason': 'notLaidOut',
      });
      return;
    }
    final local = render.localToGlobal(Offset.zero, ancestor: viewportBox);
    final rect = local & render.size;
    if (!rect.isFinite) {
      rows.add(<String, Object?>{
        'id': id,
        'mounted': true,
        'painted': false,
        'intersects': false,
        'reason': 'nonFiniteRect',
      });
      return;
    }
    final intersects =
        rect.top < bounds.bottom &&
        rect.bottom > bounds.top &&
        rect.left < bounds.right &&
        rect.right > bounds.left;
    rows.add(<String, Object?>{
      'id': id,
      'mounted': true,
      'painted': intersects,
      'intersects': intersects,
      'rect': <String, Object?>{
        'left': rect.left,
        'top': rect.top,
        'width': rect.width,
        'height': rect.height,
      },
    });
  });

  // 默认只返回真正可见（相交且可测）的行；指定 rowIds 时逐个给终态。
  final List<Map<String, Object?>> visible;
  if (requested == null) {
    visible =
        <Map<String, Object?>>[
          for (final row in rows)
            if (row['intersects'] == true) row,
        ]..sort(
          (left, right) => ((left['rect']! as Map)['top']! as num).compareTo(
            (right['rect']! as Map)['top']! as num,
          ),
        );
  } else {
    visible = rows;
  }
  return <String, Object?>{
    'ok': true,
    'frame': 'viewport',
    'viewport': <String, Object?>{
      'left': 0.0,
      'top': 0.0,
      'width': size.width,
      'height': size.height,
    },
    'viewportGlobal': <String, Object?>{
      'left': globalOrigin.dx,
      'top': globalOrigin.dy,
      'width': size.width,
      'height': size.height,
    },
    'rows': visible,
    'missing': <String>[
      if (requested != null)
        for (final id in requested)
          if (!found.contains(id)) id,
    ],
    'requested': requested?.length,
  };
}

/// `timeline-scrollable` 当前挂载的视口 RenderBox；未挂载或不可测时返回 null。
RenderBox? _timelineScrollableBox() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;
  final key = StudioDriverKeyValues.timelineScrollable;
  RenderBox? box;
  _visitElements(root, (element) {
    if (box != null) return;
    final widgetKey = element.widget.key;
    if (widgetKey is! ValueKey<String> || widgetKey.value != key) return;
    final render = element.renderObject;
    if (render is RenderBox && render.attached && render.hasSize) box = render;
  });
  return box;
}

/// 分页在途 + 滚轮交叠的复合 Driver 场景（只在验收侧使用，不进入产品）。
///
/// 事实来源全部是应用自身：`TimelineSessionOwner.source`（真实发布状态）与当前
/// `TimelineDisplayLease`（同一个 controller 的已加载条目数、标准 `ScrollController`
/// 几何）。只有应用真的受理了分页（同步发布 `isLoadingOlder == true`）才经标准
/// 指针信号路由派发输入；所有接受的 Future 都 await 到终态，错误只记录为证据，
/// 不抛未处理异步异常。宿主命令往返与 future 先后不再参与交叠判定。
/// 输入有效性用同一同步块内标准 `ScrollController` 的 pixels 变化证明（不靠 frame
/// 之后的页插入），页增长必须是 1..32 条真实小页（`hasOlder` 只作诊断）。
Future<Map<String, Object?>> _loadOlderOverlap({
  required String? threadId,
  required int? generation,
  required int inputs,
  required double dy,
}) async {
  final owner = _container.read(appGraphProvider).timeline;
  final selected = _client.selection.state.selectedThreadId;
  final target = threadId ?? selected;
  final evidence = <String, Object?>{
    'inputs': inputs,
    'dy': dy,
    'selectedThreadId': selected,
    'requestedThreadId': threadId,
  };
  Map<String, Object?> failure(
    String reason, [
    Map<String, Object?> extra = const <String, Object?>{},
  ]) => <String, Object?>{'ok': false, 'reason': reason, ...evidence, ...extra};
  if (inputs <= 0) return failure('inputsMustBePositive');
  if (target == null) return failure('noSelectedThread');
  if (selected != target) return failure('selectedThreadMismatch');
  final view = owner.source.value;
  final lease = owner.lease(target);
  if (view == null || view.threadId != target) {
    return failure('noCurrentDisplay', <String, Object?>{
      'viewThreadId': view?.threadId,
    });
  }
  if (lease == null) return failure('noCurrentLease');
  evidence['connectionBefore'] = view.connection.name;
  if (view.mode.name != 'history') {
    return failure('modeIsNotHistory', <String, Object?>{
      'mode': view.mode.name,
    });
  }
  if (generation != null && lease.generation != generation) {
    return failure('generationMismatch', <String, Object?>{
      'generation': lease.generation,
    });
  }
  if (!lease.hasOlder) {
    return failure('noOlderPage', <String, Object?>{
      'generation': lease.generation,
    });
  }
  if (view.isLoadingOlder) return failure('alreadyLoadingOlder');
  final box = _timelineScrollableBox();
  if (box == null) return failure('scrollableNotMounted');
  final center = box.localToGlobal(box.size.center(Offset.zero));
  final geometryBefore = _timelineGeometry();
  final generationBefore = lease.generation;
  final countBefore = lease.controller.messages.length;
  var dispatchedInputs = 0;
  var completedAfterInputs = -1;
  Object? pageError;

  Map<String, Object?> read({required int index, required bool afterInput}) {
    final nowView = owner.source.value;
    final nowLease = owner.lease(target);
    final position = nowLease != null && nowLease.scrollController.hasClients
        ? nowLease.scrollController.position
        : null;
    return <String, Object?>{
      'index': index,
      'afterInput': afterInput,
      'loadingOlder': nowView?.isLoadingOlder,
      'mode': nowView?.mode.name,
      'generation': nowLease?.generation,
      'hasOlder': nowView?.hasOlder,
      'olderCursor': nowView?.olderCursor,
      'olderError': nowView?.olderError?.toString(),
      'itemCount': nowLease?.controller.messages.length,
      'loadedCount': nowLease?.loadedCount,
      'pixels': position?.pixels,
      'minScrollExtent': position?.minScrollExtent,
      'maxScrollExtent': position?.maxScrollExtent,
      'viewportDimension': position?.viewportDimension,
      'pageCompleted': completedAfterInputs >= 0,
      'pageCompletedAfterInputs': completedAfterInputs,
    };
  }

  // 产品自己的分页动作：同步发布 loading 后 await 真实查询。
  final page = owner.loadOlder(
    target,
    generation: owner.lease(target)?.generation ?? 0,
  );
  final tracked = page.then<void>(
    (_) {
      if (completedAfterInputs < 0) completedAfterInputs = dispatchedInputs;
    },
    onError: (Object error, StackTrace stack) {
      pageError ??= error;
      if (completedAfterInputs < 0) completedAfterInputs = dispatchedInputs;
    },
  );
  // 只认应用真实发布的受理事实：host future 先后不能证明在途。
  final loadingAfterAction = owner.source.value?.isLoadingOlder;
  evidence['loadingOlderAfterAction'] = loadingAfterAction;
  // 从 `tracked` 成立起，本次已受理的分页必须在**所有**出口真正收束：正常完成、
  // 提前 return、输入/几何/框架异常都走同一 join。`tracked` 已用 onError 归一页
  // 错误；join 这里再兜一层只记录、不覆盖 primary 错误，也不放任 raw future 后台运行。
  var pageJoined = false;
  Future<void> joinPage() async {
    if (pageJoined) return;
    pageJoined = true;
    try {
      await tracked;
    } on Object catch (error) {
      pageError ??= error;
    }
  }

  try {
    if (loadingAfterAction != true) {
      await joinPage();
      return failure('loadOlderNotAccepted', <String, Object?>{
        'pageError': pageError?.toString(),
        'pageCompletedAfterInputs': completedAfterInputs,
        'olderError': owner.source.value?.olderError?.toString(),
        'hasOlder': owner.source.value?.hasOlder,
      });
    }
    final inputsLog = <Map<String, Object?>>[];
    for (var index = 0; index < inputs; index++) {
      final sample = read(index: index, afterInput: false);
      inputsLog.add(sample);
      // 标准指针信号路由：与 `PointerScrollCommandExtension` 同一事件类型与通道。
      GestureBinding.instance.handlePointerEvent(
        PointerScrollEvent(
          position: center,
          scrollDelta: Offset(0, dy),
          kind: PointerDeviceKind.mouse,
        ),
      );
      dispatchedInputs = index + 1;
      // 指针信号在同一个事件派发内同步解析：这里在任何 await/endOfFrame 之前读取标准
      // `ScrollController` 的实际 pixels，证明这次输入真的作用到了外层列表，而不是
      // 只 dispatch 过。frame 之后的页插入/几何变化不参与这条证据。
      final afterDispatch = read(index: index, afterInput: true);
      sample['afterDispatch'] = afterDispatch;
      final beforePixels = sample['pixels'] as double?;
      final dispatchPixels = afterDispatch['pixels'] as double?;
      final minExtent = sample['minScrollExtent'] as double?;
      final maxExtent = sample['maxScrollExtent'] as double?;
      // 负 dy 是向更早内容滚动（offset 增大），正 dy 反向；可用余量按方向取。
      final room = beforePixels == null
          ? null
          : dy < 0
          ? (maxExtent == null ? null : maxExtent - beforePixels)
          : (minExtent == null ? null : beforePixels - minExtent);
      final delta = beforePixels == null || dispatchPixels == null
          ? null
          : dispatchPixels - beforePixels;
      final moved =
          room != null &&
          room > 0.5 &&
          delta != null &&
          delta.abs() > 0.5 &&
          (dy < 0 ? delta > 0 : delta < 0);
      sample['outerScroll'] = <String, Object?>{
        'beforePixels': beforePixels,
        'afterDispatchPixels': dispatchPixels,
        'minScrollExtent': minExtent,
        'maxScrollExtent': maxExtent,
        'room': room,
        'delta': delta,
        'moved': moved,
      };
      SchedulerBinding.instance.scheduleFrame();
      await SchedulerBinding.instance.endOfFrame;
      sample['afterFrame'] = read(index: index, afterInput: true);
    }
    // 正常路径：先真正等待本次分页收束，再读取发布后的终态。
    await joinPage();
    SchedulerBinding.instance.scheduleFrame();
    await SchedulerBinding.instance.endOfFrame;
    final finalFacts = read(index: inputs, afterInput: true);
    final geometryAfter = _timelineGeometry();
    final countAfter = finalFacts['itemCount'] as int? ?? countBefore;
    final pageDelta = countAfter - countBefore;
    final generationAfter =
        finalFacts['generation'] as int? ?? generationBefore;
    final hasOlderAfter = finalFacts['hasOlder'] == true;
    final outerScrollMoves = <Map<String, Object?>>[
      for (final sample in inputsLog)
        if ((sample['outerScroll'] as Map?)?['moved'] == true) sample,
    ];
    final checks = <String, bool>{
      'loadAccepted': true,
      'historyMode': true,
      'generationStable': generationAfter == generationBefore,
      'pageCompleted': completedAfterInputs >= 0,
      'pageNoError': pageError == null,
      // 真实小页增长：一次请求必须增长 1..32 条（空页/假 EOF/多页合并都不绿）。
      'pagePublished': pageDelta > 0 && pageDelta <= _timelinePageSizeLimit,
      'loadingCleared': finalFacts['loadingOlder'] == false,
      'noOlderError': finalFacts['olderError'] == null,
      'inputDispatchedWhileInFlight': inputsLog.any(
        (sample) => sample['loadingOlder'] == true,
      ),
      // 至少一格输入在有可用余量时真的改变了外层 pixels（首帧之前读取）。
      'inputMovedOuterList': outerScrollMoves.isNotEmpty,
      'pagePublishedAfterAnInput': completedAfterInputs >= 1,
      'inputCountMatched': inputsLog.length == inputs,
    };
    return <String, Object?>{
      'ok': true,
      ...evidence,
      'threadId': target,
      'generationBefore': generationBefore,
      'generationAfter': generationAfter,
      'modeBefore': 'history',
      'hasOlderBefore': true,
      'countBefore': countBefore,
      'countAfter': countAfter,
      'pageDelta': pageDelta,
      'pageSizeLimit': _timelinePageSizeLimit,
      'hasOlderAfter': hasOlderAfter,
      'outerScrollMoves': outerScrollMoves.length,
      'loadingOlderAfterAction': loadingAfterAction,
      'pageCompletedAfterInputs': completedAfterInputs,
      'pageError': pageError?.toString(),
      'inputsLog': inputsLog,
      'final': finalFacts,
      'geometryBefore': geometryBefore,
      'geometryAfter': geometryAfter,
      'checks': checks,
      'pass': checks.values.every((value) => value),
    };
  } finally {
    // 输入 loop、几何读取或框架等待抛错时也必须收束同一个已受理 Future，不把它
    // 留在后台；join 已归一错误，不覆盖 primary 错误与 stack。
    await joinPage();
  }
}

/// 只读取挂载的 `timeline-detail-text`（`SelectableText`）与其所在对话框，不触发任何
/// 读取、不缓存正文；关闭后自然返回 `{open: false}`。
Map<String, Object?> _timelineDetailText() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return <String, Object?>{'ok': false, 'error': 'noRoot'};
  final dialogKey = StudioDriverKeyValues.timelineDetailDialog;
  final textKey = StudioDriverKeyValues.timelineDetailText;
  var dialog = false;
  String? text;
  _visitElements(root, (element) {
    final key = element.widget.key;
    if (key is! ValueKey<String>) return;
    if (key.value == dialogKey) dialog = true;
    if (key.value == textKey && element.widget is SelectableText) {
      text = (element.widget as SelectableText).data;
    }
  });
  if (!dialog) return <String, Object?>{'ok': true, 'open': false};
  final body = text ?? '';
  return <String, Object?>{
    'ok': true,
    'open': true,
    'characters': body.length,
    'bytes': utf8.encode(body).length,
    'hash': _fnv1a64Hex(body),
    'head': _headOf(body),
    'tail': _tailOf(body),
  };
}

Future<StudioShutdownReport> _runShutdown() async {
  // arm native 首次期限并执行 typed 清理，返回真实报告；不结束进程。
  return StudioExitCoordinator.cleanupActive();
}

/// 既有 `CloseReport.unresolved` 的稳定公开投影。
///
/// 只保留 owner 名字、attempt 的公开值和安全 reason 分类；不输出
/// `reason.toString()`、异常消息或任何凭据/路径细节，未知类型只给 runtimeType 名。
List<Map<String, Object?>> _clientCloseResourcesJson(CloseReport report) => [
  for (final resource in report.unresolved)
    {
      'owner': resource.owner,
      'attemptId': resource.attemptId.value,
      'reasonKind': _clientCloseReasonKind(resource.reason),
    },
];

String _clientCloseReasonKind(Object reason) => switch (reason) {
  TimeoutException() => 'timeout',
  StateError() => 'stateError',
  StudioFailure(:final code) => 'studioFailure:${code.name}',
  _ => 'unknown:${reason.runtimeType}',
};

Map<String, Object?> _shutdownReportJson(StudioShutdownReport report) {
  return {
    // Driver-only：同一次既有 close 是否观察到，以及其 unresolved 资源
    // （owner / attempt 公开值 / 安全 reasonKind）。未观察到即 null，不是空集合。
    'clientCloseObserved': _clientCloseObserved,
    'clientCloseResources': _clientCloseResources,
    'outcome': report.outcome.name,
    'persistence': switch (report.persistence) {
      UnknownStudioPendingPersistence() => 'unknown',
      PendingStudioPendingPersistence(:final count) => 'pending:$count',
      DrainedStudioPendingPersistence() => 'drained',
    },
    'issues': [
      for (final issue in report.issues)
        {
          'stage': issue.stage,
          'code': issue.code,
          'message': issue.message,
          'retryable': issue.retryable,
          'correlationId': issue.correlationId,
        },
    ],
  };
}

/// Extends the existing Driver snapshot without changing any of its legacy
/// keys. The legacy snapshot shape is a deliberate backward-compatibility
/// exception for existing manual-gui consumers. `driverDiagnostics` is the new
/// acceptance-only surface and exposes only typed, de-identified fields; it is
/// assembled in this Driver entrypoint rather than in the production snapshot
/// owner and is not part of the production protocol.
String _driverSnapshotJson() {
  final facts = StudioDriverState.readFacts();
  final decoded = jsonDecode(StudioDriverState.snapshotJson(observed: facts));
  if (decoded is! Map) {
    throw const FormatException('driver snapshot must be a JSON object');
  }
  final snapshot = decoded.cast<String, dynamic>();
  snapshot['driverDiagnostics'] = _driverDiagnostics(observed: facts);
  snapshot['delegation'] = _delegationSnapshot(facts);
  return jsonEncode(snapshot);
}

AccountsViewState? _existingAccountsView() =>
    _container.exists(accountsViewModelProvider)
    ? _container.read(accountsViewModelProvider).asData?.value
    : null;

AccountIdentity _domainIdentity(AccountDisplayKey key) =>
    key.kind == AccountKind.native
    ? NativeAccountIdentity(key.id)
    : AcpAccountIdentity(key.id);

/// Read the existing sole Router at request time. No retained navigation
/// mirror, URI parser, provider creation or business demand is involved.
AccountRouteIdentity? _accountNavigation() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;
  GoRouter? router;
  _visitElements(root, (element) {
    router ??= GoRouter.maybeOf(element);
  });
  return router == null ? null : readAccountRouteIdentity(router!);
}

AccountEditorSessionOwner? _existingEditorOwner(
  AccountRouteIdentity? navigation,
) {
  final entry = navigation?.entry;
  if (entry == null) return null;
  final provider = accountEditorSessionViewModelProvider(entry);
  if (!_container.exists(provider)) return null;
  final slot = _container.read(provider.notifier);
  final session = slot.currentOwner();
  if (session == null || !slot.isCurrentOwner(session) || !session.isActive) {
    return null;
  }
  final projection = _container.read(provider).asData?.value;
  if (projection == null ||
      projection.ownerId != session.ownerId ||
      projection.editor != session.currentEditor) {
    return null;
  }
  return session;
}

Map<AccountIdentity, AccountResource<AccountDetails>>
_observedAccountDetails() {
  final navigation = _accountNavigation();
  final result = <AccountIdentity, AccountResource<AccountDetails>>{};
  final account = navigation?.account;
  if (account != null) {
    final provider = accountDetailsViewModelProvider(account);
    if (_container.exists(provider)) {
      result[_domainIdentity(account)] = _container
          .read(provider.notifier)
          .readObservedDetails();
    }
  }
  final editor = _existingEditorOwner(navigation)?.currentEditor;
  if (editor != null) {
    final provider = accountEditorViewModelProvider(editor);
    if (_container.exists(provider)) {
      final resource = _container.read(provider.notifier).readObservedDetails();
      if (resource != null) result[_domainIdentity(editor.target)] = resource;
    }
  }
  return result;
}

Iterable<AccountDisplayKey> _existingModelKeys([
  AccountRouteIdentity? navigation,
]) sync* {
  final actual = navigation ?? _accountNavigation();
  final keys = <AccountDisplayKey>{
    ?actual?.account,
    ?_existingEditorOwner(actual)?.currentEditor?.target,
  };
  for (final key in keys) {
    if (key.kind == AccountKind.native &&
        _container.exists(accountModelsViewModelProvider(key))) {
      yield key;
    }
  }
}

AccountModelPresentation? _observedModel(String accountId, String modelId) {
  final key = AccountDisplayKey(kind: AccountKind.native, id: accountId);
  final provider = accountModelsViewModelProvider(key);
  if (!_container.exists(provider)) return null;
  return _container
      .read(provider)
      .asData
      ?.value
      .catalog
      .models
      .where((model) => model.key.modelId == modelId)
      .firstOrNull;
}

Map<String, Object?> _accountsPresentation() {
  final navigation = _accountNavigation();
  final view = _existingAccountsView();
  Map<String, Object?>? identity(AccountDisplayKey? key) =>
      key == null ? null : {'kind': key.kind.name, 'id': key.id};
  Map<String, Object?>? entryIdentity(AccountEditorEntryKey? entry) =>
      switch (entry) {
        CreatingAccountEditorEntryKey(:final routeEntryId) => {
          'kind': 'creating',
          'routeEntryId': routeEntryId,
        },
        EditingAccountEditorEntryKey(:final routeEntryId, :final account) => {
          'kind': 'editing',
          'routeEntryId': routeEntryId,
          'target': identity(account),
        },
        null => null,
      };
  final account = navigation?.account;
  final session = _existingEditorOwner(navigation);
  final editorKey = session?.currentEditor;
  final modelKeys = _existingModelKeys(navigation).toList(growable: false);
  AccountDetailsViewState? details;
  AccountEditorViewState? editor;
  if (account != null) {
    final provider = accountDetailsViewModelProvider(account);
    if (_container.exists(provider)) {
      details = _container.read(provider).asData?.value;
    }
  }
  if (editorKey != null) {
    final provider = accountEditorViewModelProvider(editorKey);
    if (_container.exists(provider)) {
      editor = _container.read(provider).asData?.value;
    }
  }
  final acpKey = editor?.acpKey ?? details?.acpKey;
  AccountAcpViewState? acp;
  if (acpKey != null) {
    final provider = acpAccountViewModelProvider(acpKey);
    if (_container.exists(provider)) {
      acp = _container.read(provider).asData?.value;
    }
  }
  return {
    'schemaVersion': 3,
    'navigation': navigation == null
        ? null
        : {
            'source': 'goRouter',
            'location': navigation.location,
            'page': navigation.page.name,
            'account': identity(account),
            'modelId': navigation.model?.modelId,
            'tab': navigation.tab?.name,
            'entry': entryIdentity(navigation.entry),
          },
    'resourceStatus': {
      'list': view != null ? 'observed' : 'absent',
      'editorSession': navigation == null
          ? 'unknown'
          : session == null
          ? 'absent'
          : 'active',
      'editor': navigation == null
          ? 'unknown'
          : editor == null
          ? 'absent'
          : 'observed',
      'details': navigation == null
          ? 'unknown'
          : details == null
          ? 'absent'
          : 'observed',
      'models': navigation == null
          ? 'unknown'
          : modelKeys.isEmpty
          ? 'absent'
          : 'observed',
    },
    'observed': view != null,
    'mountedViews': _mountedAccountsViews(navigation, editorKey),
    'search': view?.list.search,
    'list': view == null
        ? null
        : {
            'phase': view.list.phase.name,
            'search': view.list.search,
            'refreshing': view.list.refreshing,
            'rowTargets': [for (final row in view.list.rows) identity(row.key)],
          },
    'actions': view == null
        ? null
        : [
            for (final action in view.actions.entries)
              {
                'target': identity(action.key),
                'pending': action.value.pending,
                'ownerEpoch': action.value.ownerEpoch,
                'acpConnectionRevision': action.value.acpConnectionRevision,
              },
          ],
    'details': details == null
        ? null
        : {
            'target': identity(account),
            'observed': details.observed,
            'stale': details.stale,
          },
    'editor': editor == null
        ? null
        : {
            'ownerId': session!.ownerId,
            'editorId': editor.key.editorId,
            'target': identity(editor.key.target),
            'creating': editor.key.creating,
            'dirty': editor.dirty,
            'saving': editor.saving,
            'canSave': editor.canSave,
            'draftRevision': editor.draftRevision,
            'stale': editor.stale,
            'confirmedAccount': identity(
              editor.native?.accountKey ?? editor.acp?.accountKey,
            ),
          },
    'models': [
      for (final key in modelKeys)
        {
          'target': identity(key),
          'stale': _container
              .read(accountModelsViewModelProvider(key))
              .asData
              ?.value
              .stale,
          'readouts': {
            for (final entry
                in _container
                        .read(accountModelsViewModelProvider(key))
                        .asData
                        ?.value
                        .readouts
                        .entries ??
                    const <MapEntry<String, AccountReadoutState>>[])
              entry.key: {'phase': entry.value.phase.name},
          },
        },
    ],
    'acp': acpKey == null
        ? null
        : {
            'target': identity(acpKey.target),
            'providerId': acpKey.providerId,
            'connectionRevision': acpKey.connectionRevision,
            'editorId': acpKey.editorId,
            'creating': acpKey.creating,
            'phase': acp?.panel.phase.name,
            'actions': acp?.panel.availableActions
                .map((value) => value.name)
                .toList(),
            'progress': acp?.panel.progress,
            'status': acp?.panel.status,
            'progressLabel': acp?.panel.progressLabel,
            'preparedForEditor': acp?.preparedForEditor,
            'claimedOperationId': acp?.claimedOperationId,
            'preparationGeneration': acp?.preparationGeneration,
          },
  };
}

/// Explicit safe props of mounted production views, with visibility derived
/// from the committed typed destination. Mounted/covered is not absent.
Map<String, Object?> _mountedAccountsViews(
  AccountRouteIdentity? navigation,
  AccountEditorKey? editor,
) {
  final result = <String, Object?>{};
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return result;
  void record(
    String kind,
    Element element,
    bool matchesRoute,
    Map<String, Object?> fields,
  ) {
    var offstage = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget case Offstage(offstage: true)) offstage = true;
      return !offstage;
    });
    final data = <String, Object?>{
      'mounted': true,
      'visible': navigation == null ? null : matchesRoute && !offstage,
      ...fields,
    };
    final previous = result[kind] as Map<String, Object?>?;
    if (previous == null || data['visible'] == true) result[kind] = data;
  }

  _visitElements(root, (element) {
    switch (element.widget) {
      case AccountsListView():
        record('list', element, navigation?.page == AccountRoutePage.list, {});
      case AccountDetailsView(:final value):
        record(
          'details',
          element,
          navigation?.page == AccountRoutePage.details &&
              navigation?.account == value.key,
          {
            'target': {'kind': value.key.kind.name, 'id': value.key.id},
          },
        );
      case NativeAccountEditorView(:final value):
        record(
          'nativeEditor',
          element,
          navigation?.entry != null && editor?.editorId == value.editorId,
          {
            'editorId': value.editorId,
            'compactModelIds': [
              for (final model in value.declaredModels)
                if (model.compact != null) model.key.modelId,
            ],
          },
        );
      case AcpAccountEditorView(:final value):
        record(
          'acpEditor',
          element,
          navigation?.entry != null && editor?.editorId == value.editorId,
          {'editorId': value.editorId},
        );
      case AccountModelDetailsView(:final value, :final tab):
        record(
          'model',
          element,
          navigation?.page == AccountRoutePage.model &&
              navigation?.model == value.key,
          {
            'target': {
              'kind': value.key.account.kind.name,
              'id': value.key.account.id,
            },
            'modelId': value.key.modelId,
            'tab': tab.name,
          },
        );
    }
  });
  return result;
}

/// Read-only Client facts for delegation acceptance; no hidden UI-bypassing writes.
Map<String, Object?> _delegationSnapshot(StudioDriverFacts facts) {
  final store = _client.settings.state;
  final defaults = store.configLoaded ? store.canonical?.delegation : null;
  final drafts = _client.drafts.startDraft.state;
  final directory = _client.threadDirectory.state;
  final threads = <String, StudioThread>{
    for (final thread in [
      ...directory.window.threads,
      ...directory.overlayThreads,
    ])
      thread.id: thread,
    for (final workspace in facts.workspacesByThread.values)
      workspace.thread.id: workspace.thread,
  };
  Map<String, Object?>? route(NewThreadModelRoute? value) => value == null
      ? null
      : {
          'accountId': value.accountId,
          'modelId': value.modelId,
          'effort': value.effort,
        };
  return {
    'defaults': defaults == null
        ? null
        : {'mode': defaults.mode.name, 'preference': defaults.preference.name},
    'settingsRevision': store.settingsRevision,
    'catalogs': [
      for (final entry
          in facts.modelDirectory?.accounts.entries ??
              const <
                MapEntry<
                  NativeAccountIdentity,
                  AccountResource<AccountModelCatalog>
                >
              >[])
        {
          'accountId': entry.key.accountId,
          ...studioDriverResourceJson(entry.value),
        },
    ],
    'accountModels': [
      for (final account in facts.accounts)
        for (final model in account.models)
          {
            'accountId': account.id,
            'modelId': model.modelId,
            'enabled': model.enabled,
            'textEligible': model.matchesType(ModelType.text),
            'pending': _observedModel(account.id, model.modelId)?.saving,
            'failed': switch (_observedModel(account.id, model.modelId)) {
              null => null,
              final presentation => presentation.error != null,
            },
            'billingKind': account.billingKind?.name,
            'billingKindOverride': facts.accountSummaries
                ?.account(NativeAccountIdentity(account.id))
                ?.billingKindOverride
                ?.name,
          },
    ],
    'drafts': [
      for (final id in {
        ...drafts.projects.keys,
        if (facts.selectedProjectId != null) facts.selectedProjectId!,
      })
        {
          'projectId': id,
          'modeOverride': drafts.forProject(id).delegationModeOverride?.name,
          'preferenceOverride': drafts
              .forProject(id)
              .delegationPreferenceOverride
              ?.name,
          'effectiveMode': defaults == null
              ? null
              : drafts.forProject(id).resolveDelegation(defaults).mode.name,
          'effectivePreference': defaults == null
              ? null
              : drafts
                    .forProject(id)
                    .resolveDelegation(defaults)
                    .preference
                    .name,
          'workspaceMode': drafts.forProject(id).workspaceMode.id,
          'submitting': drafts.submitting,
        },
    ],
    'threads': [
      for (final thread in threads.values)
        {
          'threadId': thread.id,
          'mode': thread.delegationMode.name,
          'preference': thread.delegationPreference.name,
          'frozenModel': route(thread.frozenModel),
        },
    ],
    'agents': [
      for (final agent
          in _client.project.state.agents?.values ?? const <StudioAgentView>[])
        {
          'threadId': agent.threadId,
          'taskSummary': agent.task,
          'role': agent.role,
          'state': agent.status,
          'mode': agent.delegationMode.name,
          'preference': agent.delegationPreference.name,
          'frozenModel': route(agent.frozenModel),
        },
    ],
    // Both an in-flight/failed readout and its last finite result are retained.
    'modelDetails': _delegationModelDetails(),
  };
}

List<Map<String, Object?>> _delegationModelDetails() => [
  for (final key in _existingModelKeys()) ..._observedReadouts(key),
];

Iterable<Map<String, Object?>> _observedReadouts(AccountDisplayKey key) sync* {
  final provider = accountModelsViewModelProvider(key);
  if (!_container.exists(provider)) return;
  final view = _container.read(provider).asData?.value;
  final performance = _container
      .read(provider.notifier)
      .readObservedPerformance();
  for (final entry
      in view?.readouts.entries ??
          const <MapEntry<String, AccountReadoutState>>[]) {
    final detail = performance[entry.key];
    yield {
      'accountId': key.id,
      'modelId': entry.key,
      'phase': entry.value.phase.name,
      'loading': entry.value.phase == AccountReadoutPhase.loading,
      'failed': entry.value.phase == AccountReadoutPhase.failed,
      'available': detail?.available,
      'evaluationCount': detail?.recentEvaluations.length,
      'evaluations': detail == null
          ? null
          : [
              for (final evaluation in detail.recentEvaluations)
                {
                  'agentId': evaluation.agentId,
                  'turnId': evaluation.turnId,
                  'revision': evaluation.revision,
                  'model': {
                    'accountId': evaluation.model.accountId,
                    'modelId': evaluation.model.modelId,
                    'effort': evaluation.model.effort,
                  },
                  'outcome': evaluation.outcome.name,
                  'comment': evaluation.comment,
                  'updatedAt': evaluation.updatedAt,
                },
            ],
    };
  }
}

Map<String, Object?> _driverDiagnostics({StudioDriverFacts? observed}) {
  final facts = observed ?? StudioDriverState.readFacts();
  final workspace = facts.workspace;
  final session = workspace == null
      ? null
      : _client.conversations.existingSession(workspace.thread.id)?.state;
  final runtime = workspace?.runtime;
  final liveUsage = runtime?.liveUsage;
  final observedUsage =
      liveUsage != null &&
          liveUsage.turnId.isNotEmpty &&
          liveUsage.attemptId.isNotEmpty &&
          liveUsage.observationSequence >= 0
      ? liveUsage
      : null;
  final usageState = observedUsage?.state.name ?? 'unknown';
  final metricsAvailable =
      observedUsage != null &&
      (usageState == 'live' || usageState == 'authoritative');

  // ThreadRuntimeView stores these counters as non-nullable ints, while its
  // default constructor and FRB's unavailable context window both use zero.
  // That schema cannot distinguish an explicit zero from the default, so a
  // zero from those fields is conservatively unknown/null. The nullable live
  // usage fields do carry presence provenance; their explicit zero is kept.
  int? defaultProneCount(int? value) =>
      !metricsAvailable || value == null || value <= 0 ? null : value;
  int? explicitUsageCount(int? value) => metricsAvailable ? value : null;
  final contextTokens =
      explicitUsageCount(observedUsage?.latestContextTokens) ??
      defaultProneCount(runtime?.contextTokens);
  final contextWindow = defaultProneCount(runtime?.contextWindow);
  final totalTokens = defaultProneCount(runtime?.totalTokens);
  final inputTokens = defaultProneCount(runtime?.promptTokens);
  final outputTokens = defaultProneCount(runtime?.completionTokens);
  final reasoningTokens = defaultProneCount(runtime?.reasoningTokens);
  final liveOutputTokens = explicitUsageCount(observedUsage?.completionTokens);
  final liveResponseMillis = explicitUsageCount(observedUsage?.responseMillis);
  final throughputSource = runtime == null
      ? null
      : ModelRouteQueries.throughputSource(runtime);
  // Preserve source counters for diagnostics, but only derive throughput from
  // a complete output/response pair chosen by the canonical Client query.
  final turnOutputTokens = throughputSource?.outputTokens;
  final responseMillis = throughputSource?.responseMillis;
  final tokensPerSecond = throughputSource?.tokensPerSecond;
  return <String, Object?>{
    'schemaVersion': 1,
    'runtime': <String, Object?>{
      'availability': workspace == null ? 'unavailable' : 'available',
      // Null is an unknown/unavailable value. It is never replaced with a
      // zero-valued ThreadRuntimeView default merely to make the JSON shape
      // convenient. A usage state without a complete identity is downgraded
      // to unknown and all usage counters remain null.
      'usageState': usageState,
      'turnId': metricsAvailable ? observedUsage.turnId : null,
      'attemptId': metricsAvailable ? observedUsage.attemptId : null,
      'observationSequence': metricsAvailable
          ? observedUsage.observationSequence
          : null,
      // 当前展示代次已完成的 append 水位；没有 lease/cursor 时保持未知。
      'timelineEpoch': facts.timeline?.timelineEpoch,
      'completedThrough': facts.timeline?.completedThrough,
      'contextTokens': contextTokens,
      'contextWindow': contextWindow,
      'totalTokens': totalTokens,
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
      'reasoningTokens': reasoningTokens,
      'liveOutputTokens': liveOutputTokens,
      'liveResponseMillis': liveResponseMillis,
      'turnOutputTokens': turnOutputTokens,
      'responseMillis': responseMillis,
      'tokensPerSecond': tokensPerSecond,
      // 当前 Thread runtime 快照声明的技能激活列表：直接读 Client runtime
      // read-model 的 typed 字段，不另建 Driver 状态，也不从历史 Skill 条目推断。
      // 没有选中 Thread 的 workspace 时为 null，与其它 runtime 事实一致。
      'activeSkills': runtime?.activeSkills,
      // Keep throughput as an explicit typed group only when both source
      // counters are known; an unknown group is represented by null.
      'throughput': tokensPerSecond == null
          ? null
          : <String, Object?>{
              'outputTokens': turnOutputTokens,
              'responseMillis': responseMillis,
              'tokensPerSecond': tokensPerSecond,
            },
    },
    'stateStream': {
      'threadId': session?.threadId,
      'hasSnapshot': session?.hasSnapshot ?? false,
      'epoch': session?.streamEpoch,
      'baseRevision': session?.baseRevision,
      'revision': session?.revision,
    },
    'skills': _driverSkillsDiagnostics(),
    'composer': <String, Object?>{
      'newThread': _driverComposerDiagnostics(facts.newThreadComposer),
      'thread': _driverComposerDiagnostics(facts.threadComposer),
    },
    'accounts': _driverProviderDiagnostics(facts),
    'accountsPresentation': _accountsPresentation(),
    'topics': studioDriverTopicDiagnostics(
      _client,
      timeline: _container.read(appGraphProvider).timeline,
      accountsRepository: _container.read(appGraphProvider).accounts,
      modelsRepository: _container.read(appGraphProvider).models,
      usageRepository: _container.read(appGraphProvider).accountUsage,
      acpService: _container.read(appGraphProvider).acp,
    ),
    'seams': <String, Object?>{
      // No production ClipboardImageReader override/fixture is present in this
      // Driver entrypoint. The fixture request below therefore does not claim
      // to prove a real OS paste operation.
      'clipboardImageReaderOverride': false,
      'pasteObservation': 'unavailable',
      'fixtureHook': 'driver-fixture-clipboard-image',
      'fixtureAdmissionHook': 'driver-fixture-clipboard-image',
      'fixturePreviewHook': 'driver-fixture-clipboard-image-preview',
      'fixturePreviewStage': 'typed-driver-only-follow-up',
      'fixtureAwaitsPreviewInAdmissionHook': false,
      'runtimeEventEndpoint': 'unsupported',
      'systemClipboardTouched': false,
    },
  };
}

/// Project Skill discovery as the GUI's own Client read-model reports it.
///
/// The native acceptance seeds synthetic Skills into the isolated home, so this
/// Driver-only group carries the canonical discovered names, warnings and typed
/// state. Its `config` member is the read-only projection of the canonical Skill
/// directories the runtime was configured with; nothing here reads a file or a
/// Skill body, and no second Driver-side fact source is introduced.
Map<String, Object?> _driverSkillsDiagnostics() {
  final projectId = _client.selection.state.selectedProjectId;
  final snapshot = projectId == null
      ? null
      : _client.existingSkills(projectId)?.state.value;
  if (projectId == null || snapshot == null) {
    return <String, Object?>{
      'projectId': projectId,
      'status': null,
      'catalogRevision': null,
      'skills': null,
      'warnings': null,
      'error': null,
    };
  }
  final resource = snapshot.state;
  return <String, Object?>{
    'projectId': projectId,
    'status': switch (resource) {
      UninitializedObservedResource() => 'uninitialized',
      LoadingObservedResource() => 'loading',
      ReadyObservedResource() => 'ready',
      RefreshingObservedResource() => 'refreshing',
      StaleObservedResource() => 'stale',
      DegradedObservedResource() => 'degraded',
      FailedObservedResource() => 'failed',
      StoppedObservedResource() => 'stopped',
    },
    'catalogRevision': resource.value?.catalogRevision,
    'skills': List<String>.of(snapshot.skills),
    'warnings': List<String>.of(snapshot.warnings),
    'error': switch (resource) {
      DegradedObservedResource(:final error) => error.message,
      FailedObservedResource(:final error) => error.message,
      _ => null,
    },
    'config': _driverSkillsConfigDiagnostics(),
  };
}

/// The Skill directories the runtime is configured to scan.
///
/// Discovery can only find a seeded Skill when this configuration points at the
/// isolated user directory, so the acceptance records it next to the discovered
/// names instead of inferring the cause from an empty list.
Map<String, Object?> _driverSkillsConfigDiagnostics() {
  final skills = _client.settings.state.canonical?.skills;
  if (skills == null) {
    return <String, Object?>{'availability': 'unavailable'};
  }
  return <String, Object?>{
    'availability': 'available',
    'enabled': skills.enabled,
    'systemEnabled': skills.systemEnabled,
    'projectDir': skills.projectDir,
    'userDir': skills.userDir,
    'externalDirs': List<String>.of(skills.externalDirs),
    'disabledCount': skills.disabled.length,
  };
}

Map<String, Object?>? _driverComposerDiagnostics(
  ComposerThreadState? composer,
) {
  if (composer == null) return null;
  final attachments = composer.attachments;
  return <String, Object?>{
    'present': attachments.isNotEmpty,
    'previewReady':
        attachments.isNotEmpty &&
        attachments.every(
          (attachment) => attachment.previewBytes?.isNotEmpty == true,
        ),
    'attachmentGeneration': composer.attachmentGeneration,
    'submissionPending': composer.isSubmissionPending,
    // Do not expose the error text: it can contain account/path details. The
    // typed failure fact is sufficient for a Driver regression assertion.
    'failed': composer.error != null,
    'attachments': [
      for (final attachment in attachments)
        <String, Object?>{
          'id': attachment.id,
          'name': attachment.filename,
          'filename': attachment.filename,
          'modality': attachment.modality.name,
          'byteSize': attachment.byteSize,
          'previewReady': attachment.previewBytes?.isNotEmpty == true,
        },
    ],
  };
}

Map<String, Object?> _driverProviderDiagnostics(StudioDriverFacts facts) {
  final summaries = facts.accountSummaries;
  return <String, Object?>{
    'availability': summaries?.loaded == true ? 'available' : 'unavailable',
    'list': summaries?.loaded != true
        ? null
        : [
            for (final account in summaries!.accounts)
              {
                'kind': account.identity is NativeAccountIdentity
                    ? 'native'
                    : 'acp',
                'id': account.identity.accountId,
                'isDefault': account.isDefault,
                'credentialReady': account.credentialReady,
                'billingKind': account.billingKind?.name,
              },
          ],
    'details': [
      for (final account in facts.accounts)
        <String, Object?>{
          'kind': 'native',
          'id': account.id,
          ...studioDriverResourceJson(
            facts.modelDirectory?.accounts[NativeAccountIdentity(account.id)],
          ),
          'models':
              facts
                      .modelDirectory
                      ?.accounts[NativeAccountIdentity(account.id)]
                      ?.value ==
                  null
              ? null
              : [
                  for (final model
                      in facts
                          .modelDirectory!
                          .accounts[NativeAccountIdentity(account.id)]!
                          .value!
                          .models)
                    <String, Object?>{
                      'modelId': model.modelId,
                      'name': model.displayName,
                      'origin': model.origin.name,
                      'contextWindow': model.contextWindow,
                      'maxOutputTokens': model.maxOutputTokens,
                      'reasoningEfforts': model.reasoningEfforts,
                      'inputCapabilities': [
                        for (final capability in model.inputCapabilities)
                          capability.modality.name,
                      ],
                    },
                ],
        },
    ],
  };
}

Future<String> _startDriverFixtureClipboardImage() async {
  final fixtureCandidates = [
    File('test_driver/fixtures/tool-image.png'),
    File('code/anywork/test_driver/fixtures/tool-image.png'),
  ];
  File? fixture;
  for (final candidate in fixtureCandidates) {
    if (await candidate.exists()) {
      fixture = candidate;
      break;
    }
  }
  if (fixture == null) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'hook': 'driver-fixture-clipboard-image',
      'pasteSeam': 'unavailable',
      'systemClipboardTouched': false,
      'reason': 'fixture-not-found',
    });
  }

  final selection = _client.selection.state;
  final projectId = selection.selectedProjectId;
  final threadId = selection.selectedThreadId;
  if (projectId == null) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'hook': 'driver-fixture-clipboard-image',
      'pasteSeam': 'unavailable',
      'systemClipboardTouched': false,
      'reason': 'composer-not-ready',
    });
  }
  final bytes = await fixture.readAsBytes();
  final Future<void> task;
  if (threadId != null) {
    final composer = _client.drafts.existingComposer(threadId);
    if (composer == null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'hook': 'driver-fixture-clipboard-image',
        'pasteSeam': 'unavailable',
        'systemClipboardTouched': false,
        'reason': 'composer-not-ready',
      });
    }
    task = composer.addClipboardImage(bytes);
  } else {
    final mode = _client.drafts.startDraft.state.forProject(projectId).mode;
    task = _client.drafts.attachments.addNewThreadClipboard(
      projectId: projectId,
      mode: mode,
      pngBytes: bytes,
    );
  }
  _driverFixtureClipboardImageTask = task;
  // The admission hook is intentionally fire-and-observe: it does not await
  // the controller's preview Future.wait. The journey observes the admitted
  // metadata first, then invokes the typed preview hook below.
  unawaited(
    task.then<void>((_) {}, onError: (Object _, StackTrace stackTrace) {}),
  );
  return jsonEncode(<String, Object?>{
    'ok': true,
    'hook': 'driver-fixture-clipboard-image',
    'stage': 'admission-started',
    'pasteSeam': 'unavailable',
    'systemClipboardTouched': false,
    'previewPending': true,
  });
}

Future<String> _finishDriverFixtureClipboardImage() async {
  final task = _driverFixtureClipboardImageTask;
  if (task == null) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'hook': 'driver-fixture-clipboard-image-preview',
      'stage': 'preview-unavailable',
      'pasteSeam': 'unavailable',
      'systemClipboardTouched': false,
      'reason': 'admission-not-started',
    });
  }
  try {
    await task;
    return jsonEncode(<String, Object?>{
      'ok': true,
      'hook': 'driver-fixture-clipboard-image-preview',
      'stage': 'preview-complete',
      'pasteSeam': 'unavailable',
      'systemClipboardTouched': false,
    });
  } catch (_) {
    // Do not expose raw account/path errors through the Driver endpoint.
    return jsonEncode(<String, Object?>{
      'ok': false,
      'hook': 'driver-fixture-clipboard-image-preview',
      'stage': 'preview-failed',
      'pasteSeam': 'unavailable',
      'systemClipboardTouched': false,
    });
  }
}

// ---------------------------------------------------------------------------
// Web-search + MCP acceptance projection.
//
// Driver-only read-only view over the canonical settings/MCP state, so the
// web-search acceptance can prove the two search cards and the MCP health from
// typed fields instead of scraping widget text or the account-only snapshot.
// Nothing here mutates product state and no credential is read: the endpoint is
// reduced to scheme/host/path.

Future<String> _handleSearchSettings() async {
  final settings = _client.settings.state.canonical;
  if (settings == null) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'reason': 'studio state not ready',
    });
  }
  final web = settings.webSearch;
  final deep = settings.deepSeekWebSearch;
  return jsonEncode(<String, Object?>{
    'ok': true,
    'revision': settings.revision,
    'webSearch': <String, Object?>{
      'configuredMode': web.configuredMode,
      'effectiveMode': web.effectiveMode,
      'availability': web.availability,
      'contextSize': web.contextSize,
      'allowedDomains': web.allowedDomains,
      'country': web.country,
      'region': web.region,
      'city': web.city,
      'timezone': web.timezone,
      'accountId': web.accountId,
      'modelId': web.modelId,
    },
    'deepSeekWebSearch': <String, Object?>{
      'configuredEnabled': deep.configuredEnabled,
      'effectiveEnabled': deep.effectiveEnabled,
      'configuredFetchEnabled': deep.configuredFetchEnabled,
      'effectiveFetchEnabled': deep.effectiveFetchEnabled,
      'availability': deep.availability,
      'accountId': deep.accountId,
    },
  });
}

/// Read-only typed Client projection; no request, reducer or test write path.
String _accountUsageStateJson() {
  final facts = StudioDriverState.readFacts();
  final snapshot =
      jsonDecode(StudioDriverState.snapshotJson(observed: facts)) as Map;
  final settings = snapshot['settings'] as Map;
  final domains = settings['accountDomains'] as Map;
  final root = WidgetsBinding.instance.rootElement;
  BuildContext? context;
  if (root != null) {
    _visitElements(root, (element) {
      if (element.widget is AccountsListView ||
          element.widget is AccountDetailsView ||
          element.widget is NativeAccountEditorView ||
          element.widget is AcpAccountEditorView) {
        context = element;
      }
    });
  }
  final labels = context?.l10n;
  return jsonEncode({
    'schemaVersion': 2,
    'summaries': domains['summaries'],
    'accounts': [
      for (final summary in domains['accounts'] as List)
        {
          ...summary as Map,
          for (final detail in settings['accounts'] as List)
            if ((detail as Map)['id'] == summary['id'] &&
                summary['kind'] == 'native')
              for (final key in const [
                'templateId',
                'protocol',
                'hasBearerToken',
              ])
                key: detail[key],
        },
    ],
    'usage': domains['usage'],
    'presentation': _accountsPresentation(),
    if (labels != null)
      'labels': {
        'displayName': labels.settingsDisplayName,
        'delete': labels.settingsDeleteAccount,
        'setDefault': labels.settingsSetAsDefaultAccount,
        'noCharge': labels.settingsNoCharge,
        'restore': labels.settingsModelAutoCompactRestore,
        'discard': labels.accountsDiscard,
        'installReused': labels.acpInstallReusedBadge,
        'installRetries': labels.acpInstallFactRetries,
        'installRetryValues': {
          for (final entry
              in facts.acpInstall?.installations ??
                  const <StudioDriverAcpInstallEntryFacts>[])
            entry.provider: labels.acpInstallRetryValue(entry.retryCount),
        },
      },
  });
}

Future<String> _handleSearchMcpState() async {
  final mcp = _client.mcp.state.value;
  if (mcp == null) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'reason': 'studio state not ready',
    });
  }
  return jsonEncode(<String, Object?>{
    'ok': true,
    'revision': mcp.revision,
    'desiredConfigFingerprint': mcp.desiredConfigFingerprint,
    'appliedConfigFingerprint': mcp.appliedConfigFingerprint,
    'activeServers': mcp.activeServers,
    'servers': [
      for (final server in mcp.servers)
        <String, Object?>{
          'id': server.id,
          'transport': server.transport,
          'endpoint': _redactEndpoint(server.endpoint),
          'sourceKind': server.sourceKind,
          'mutationPolicy': server.mutationPolicy,
          'state': _mcpServerStateJson(server.state),
        },
    ],
  });
}

Map<String, Object?> _mcpServerStateJson(
  McpServerState state,
) => switch (state) {
  McpDisabledState(:final message) => {'kind': 'disabled', 'message': message},
  McpMissingCredentialState(:final message) => {
    'kind': 'missingCredential',
    'message': message,
  },
  McpCheckingState(:final message) => {'kind': 'checking', 'message': message},
  McpAvailableState(:final checkedAt, :final toolCount) => {
    'kind': 'available',
    'checkedAt': checkedAt,
    'toolCount': toolCount,
  },
  McpUnavailableState(
    :final checkedAt,
    :final code,
    :final message,
    :final retryable,
  ) =>
    {
      'kind': 'unavailable',
      'checkedAt': checkedAt,
      'code': code,
      'message': message,
      'retryable': retryable,
    },
};

/// Drops userinfo, query and fragment so only scheme/host/path leave the VM.
String _redactEndpoint(String endpoint) {
  final uri = Uri.tryParse(endpoint);
  if (uri == null) return endpoint;
  return uri.replace(userInfo: '', query: '', fragment: '').toString();
}

// ---------------------------------------------------------------------------
// Native text selection acceptance.
//
// The production timeline renders a long plain-text reply through
// `TimelinePlainText`, which delegates layout to Flutter's standard Text. This
// Driver-only bridge lets the acceptance journey
// drive the *real* `SelectionArea` selection and the product's own context-menu
// copy callback, then read the platform clipboard back. It never writes the
// domain text to the clipboard itself: every observation comes from the live
// element/render tree or from `Clipboard.getData`.
//
// These helpers live only in the Driver entrypoint; the product timeline widget
// and model are not touched.

/// The key prefix of the standard Text in the production `TimelinePlainText`.
const _plainTextKeyPrefix = 'plain-text-';

void _visitElements(Element element, void Function(Element) visit) {
  visit(element);
  element.visitChildren((Element child) => _visitElements(child, visit));
}

/// Chunks of the longest mounted plain-text body, in paint order. Scope the
/// observation to one body: the timeline can also mount the user's prompt.
List<Element> _longBodyTextElements() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return const <Element>[];
  final bodies = <Element, List<Element>>{};
  _visitElements(root, (Element element) {
    final widget = element.widget;
    if (widget is! Text) return;
    final key = widget.key;
    if (key is! ValueKey<String>) return;
    final value = key.value;
    if (value.startsWith(_plainTextKeyPrefix)) {
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is TimelinePlainText) {
          bodies.putIfAbsent(ancestor, () => <Element>[]).add(element);
          return false;
        }
        return true;
      });
    }
  });
  var longest = const <Element>[];
  var longestLength = 0;
  for (final chunks in bodies.values) {
    final length = chunks.fold<int>(0, (length, element) {
      final text = element.widget as Text;
      return length + (text.data ?? text.textSpan?.toPlainText() ?? '').length;
    });
    if (length > longestLength) {
      longest = chunks;
      longestLength = length;
    }
  }
  return longest;
}

/// The `RenderParagraph` a chunk `Text` actually painted into.
RenderParagraph? _renderParagraphOf(Element element) {
  RenderParagraph? result;
  void visit(Element current) {
    if (result != null) return;
    if (current is RenderObjectElement) {
      final renderObject = current.renderObject;
      if (renderObject is RenderParagraph) {
        result = renderObject;
        return;
      }
    }
    current.visitChildren(visit);
  }

  visit(element);
  return result;
}

/// The `SelectableRegionState` (the real `SelectionArea`) above the body chunks.
SelectableRegionState? _longBodySelectableRegion() {
  final elements = _longBodyTextElements();
  if (elements.isEmpty) return null;
  SelectableRegionState? region;
  elements.first.visitAncestorElements((Element ancestor) {
    if (ancestor is StatefulElement &&
        ancestor.state is SelectableRegionState) {
      region = ancestor.state as SelectableRegionState;
      return false;
    }
    return true;
  });
  return region;
}

/// The rendered body split: how many real paragraphs carry it and what they
/// concatenate to. Reading the `RenderParagraph` text keeps the evidence at the
/// render layer instead of the domain model.
Map<String, Object?>? _renderedLongBody() {
  final elements = _longBodyTextElements();
  if (elements.isEmpty) return null;
  final paragraphs = <RenderParagraph>[];
  final buffer = StringBuffer();
  for (final element in elements) {
    final paragraph = _renderParagraphOf(element);
    if (paragraph != null) {
      paragraphs.add(paragraph);
      buffer.write(paragraph.text.toPlainText());
      continue;
    }
    final widget = element.widget as Text;
    buffer.write(widget.data ?? widget.textSpan?.toPlainText() ?? '');
  }
  final rendered = buffer.toString();
  return <String, Object?>{
    'paragraphCount': paragraphs.length,
    'chunkCount': elements.length,
    'characters': rendered.length,
    'head': _headOf(rendered),
    'tail': _tailOf(rendered),
    'hash': _fnv1a64Hex(rendered),
  };
}

/// Read the actual painted character at a fixed viewport point. A row's top can
/// remain unchanged while a different paragraph split moves its text; checking
/// both catches that distinction without keeping another content projection.
Map<String, Object?> _longBodyLayout() {
  final elements = _longBodyTextElements();
  final root = WidgetsBinding.instance.rootElement;
  RenderBox? viewport;
  if (root != null) {
    _visitElements(root, (element) {
      if (element.widget.key == const ValueKey('timeline-scrollable')) {
        final render = element.findRenderObject();
        if (render is RenderBox && render.hasSize) viewport = render;
      }
    });
  }
  if (elements.isEmpty || viewport == null) {
    return {'ok': false, 'reason': 'body or timeline viewport is not mounted'};
  }
  final viewportTop = viewport!.localToGlobal(Offset.zero).dy;
  final sampleY = viewportTop + 24;
  final chunks = <Map<String, Object?>>[];
  Map<String, Object?>? visible;
  var offset = 0;
  for (final element in elements) {
    final paragraph = _renderParagraphOf(element);
    if (paragraph == null || !paragraph.hasSize) continue;
    final text = paragraph.text.toPlainText();
    final style = paragraph.text.style;
    final top = paragraph.localToGlobal(Offset.zero).dy;
    final wordOffset = text.indexOf('WWWWWWWWWWWWWWWWWWWW');
    final wordBoxes = wordOffset < 0
        ? const <TextBox>[]
        : paragraph.getBoxesForSelection(
            TextSelection(
              baseOffset: wordOffset,
              extentOffset: wordOffset + 20,
            ),
          );
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textAlign: paragraph.textAlign,
      textScaler: paragraph.textScaler,
      strutStyle: paragraph.strutStyle,
      locale: paragraph.locale,
      maxLines: paragraph.maxLines,
      textWidthBasis: paragraph.textWidthBasis,
      textHeightBehavior: paragraph.textHeightBehavior,
    )..layout(maxWidth: paragraph.constraints.maxWidth);
    final measuredHeight = painter.height;
    painter.dispose();
    chunks.add({
      'start': offset,
      'characters': text.length,
      'width': paragraph.size.width,
      'height': paragraph.size.height,
      'measuredHeight': measuredHeight,
      'wordWidth': wordBoxes.isEmpty
          ? null
          : wordBoxes.first.right - wordBoxes.first.left,
      'lineStartOffsets': [
        for (final y in [11.0, 33.0, 55.0])
          paragraph.getPositionForOffset(Offset(0, y)).offset,
      ],
      'minWidth': paragraph.constraints.minWidth,
      'maxWidth': paragraph.constraints.maxWidth,
      'top': top - viewportTop,
      'head': _headOf(text),
      'tail': _tailOf(text),
      'style': {
        'fontFamily': style?.fontFamily,
        'fontFamilyFallback': style?.fontFamilyFallback,
        'fontSize': style?.fontSize,
        'fontWeight': style?.fontWeight?.value,
        'letterSpacing': style?.letterSpacing,
        'wordSpacing': style?.wordSpacing,
        'height': style?.height,
        'leadingDistribution': style?.leadingDistribution?.name,
      },
      'scaledFontSize': paragraph.textScaler.scale(style?.fontSize ?? 14),
      'heightBehavior': paragraph.textHeightBehavior.toString(),
      'textAlign': paragraph.textAlign.name,
      'textScaler': paragraph.textScaler.toString(),
      'softWrap': paragraph.softWrap,
      'maxLines': paragraph.maxLines,
      'locale': paragraph.locale.toString(),
    });
    if (visible == null &&
        top <= sampleY &&
        top + paragraph.size.height > sampleY) {
      final position = paragraph.getPositionForOffset(Offset(1, sampleY - top));
      final index = position.offset.clamp(0, text.length);
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: index,
          extentOffset: (index + 1).clamp(0, text.length),
        ),
      );
      visible = {
        'characterOffset': offset + index,
        'text': text.substring(index, (index + 80).clamp(0, text.length)),
        'glyphTop': boxes.isEmpty ? null : top + boxes.first.top - viewportTop,
      };
    }
    offset += text.length;
  }
  return {
    'ok': visible != null,
    'characters': offset,
    'viewportWidth': viewport!.size.width,
    'viewportHeight': viewport!.size.height,
    'sampleY': 24,
    'visible': visible,
    'chunks': chunks,
  };
}

List<String> _menuTypes(SelectableRegionState region) {
  try {
    return <String>[
      for (final item in region.contextMenuButtonItems) item.type.name,
    ];
  } on Object {
    return const <String>[];
  }
}

ContextMenuButtonItem? _copyItemOf(SelectableRegionState region) {
  try {
    for (final item in region.contextMenuButtonItems) {
      if (item.type == ContextMenuButtonType.copy) return item;
    }
  } on Object {
    return null;
  }
  return null;
}

/// Pumps one frame so the selection geometry can settle. Bounded so a frame the
/// acceptance window cannot produce never wedges the Driver request; the copy
/// availability poll below is the real observation.
Future<void> _pumpFrame() async {
  final binding = SchedulerBinding.instance;
  binding.scheduleFrame();
  try {
    await binding.endOfFrame.timeout(const Duration(milliseconds: 120));
  } on Object {
    // See above: a missing frame is not a selection result.
  }
}

/// Selects the whole timeline region and waits (bounded) until the selection is
/// actually copyable, so the real context-menu copy callback becomes available.
Future<bool> _ensureCopyable(SelectableRegionState region) async {
  for (var attempt = 0; attempt < 60; attempt += 1) {
    if (_copyItemOf(region) != null) return true;
    if (attempt == 0 || attempt == 20 || attempt == 40) region.selectAll();
    await _pumpFrame();
  }
  return _copyItemOf(region) != null;
}

Future<String> _handleSelectAll() async {
  final region = _longBodySelectableRegion();
  if (region == null) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'reason': 'no production body chunk paragraphs are rendered',
    });
  }
  region.selectAll();
  final copyable = await _ensureCopyable(region);
  return jsonEncode(<String, Object?>{
    'ok': true,
    'copyable': copyable,
    'menuTypes': _menuTypes(region),
    ...?_renderedLongBody(),
  });
}

Future<String> _handleCopySelected() async {
  final region = _longBodySelectableRegion();
  if (region == null) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'reason': 'no production body chunk paragraphs are rendered',
    });
  }
  final copyable = await _ensureCopyable(region);
  final item = _copyItemOf(region);
  if (!copyable || item == null) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'reason': 'the timeline selection never became copyable',
      'menuTypes': _menuTypes(region),
      ...?_renderedLongBody(),
    });
  }
  // Reset the clipboard first so the readback can only come from this copy.
  await Clipboard.setData(const ClipboardData(text: ''));
  // Re-run the real select-all with no frame in between and copy immediately:
  // the product `_copy()` reads the selected content synchronously, so the copy
  // can never race a rebuild that seals another chunk and leaves it unselected.
  region.selectAll();
  final copyItem = _copyItemOf(region);
  if (copyItem == null) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'reason': 'the re-selected timeline region is not copyable',
      'menuTypes': _menuTypes(region),
      ...?_renderedLongBody(),
    });
  }
  final startedAt = DateTime.now();
  copyItem.onPressed?.call();
  String? copied;
  for (var attempt = 0; attempt < 400; attempt += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      copied = text;
      break;
    }
  }
  final copyMillis = DateTime.now().difference(startedAt).inMilliseconds;
  // Hide only the toolbar; the acceptance journey cancels the selection with a
  // real click and re-reads the region state afterwards.
  region.hideToolbar();
  await _pumpFrame();
  final copyableAfterCopy = _copyItemOf(region) != null;
  return jsonEncode(<String, Object?>{
    'ok': copied != null,
    'copied': copied,
    'copiedLength': copied?.length,
    'copiedHead': copied == null ? null : _headOf(copied),
    'copiedTail': copied == null ? null : _tailOf(copied),
    'copiedHash': copied == null ? null : _fnv1a64Hex(copied),
    'copyMillis': copyMillis,
    'copyableAfterCopy': copyableAfterCopy,
    ...?_renderedLongBody(),
  });
}

/// Whether the region still holds a copyable (uncollapsed) selection.
Future<String> _handleSelectionState() async {
  final region = _longBodySelectableRegion();
  if (region == null) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'reason': 'no production body chunk paragraphs are rendered',
    });
  }
  return jsonEncode(<String, Object?>{
    'ok': true,
    'copyable': _copyItemOf(region) != null,
    'menuTypes': _menuTypes(region),
  });
}

String _headOf(String text) =>
    text.substring(0, text.length < 64 ? text.length : 64);

String _tailOf(String text) =>
    text.substring(text.length < 64 ? 0 : text.length - 64);

/// FNV-1a over the code units, formatted as hex.
///
/// Deterministic across runs and isolates, so the acceptance script can compare
/// the clipboard readback against the canonical fixture body without shipping
/// the whole payload twice.
String _fnv1a64Hex(String text) {
  var hash = 0xcbf29ce484222325;
  for (var index = 0; index < text.length; index += 1) {
    hash ^= text.codeUnitAt(index);
    hash = hash * 0x100000001b3;
  }
  return hash.toRadixString(16);
}
