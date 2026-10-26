import 'dart:convert';
import 'dart:math' as math;

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/diagnostics/conversation_status_diagnostics.dart';
import 'package:anywork/src/features/conversation/state/editor_keys.dart';
import 'package:anywork/src/features/conversation/view_models/composer_view_model.dart';
import 'package:anywork/src/features/conversation/view_models/conversation_view_model.dart';
import 'package:anywork/src/features/conversation/view_models/plan_view_model.dart';
import 'package:anywork/src/features/conversation/view_models/thread_status_view_model.dart';
import 'package:anywork/src/features/settings/modes/view_models/mode_editor_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork/src/features/settings/accounts/state/accounts_state.dart';
import 'package:anywork/src/features/settings/skills/view_models/skills_view_model.dart';
import 'package:anywork/src/shared/driver_projection.dart';
import 'package:anywork/src/shared/driver_bots_projection.dart';
import 'package:anywork/src/shared/driver_snapshot.dart';
import 'package:anywork/src/shared/driver_snapshot_json.dart';
import 'package:anywork/src/features/workspace/view_models/sidebar_view_model.dart';
import 'package:anywork/src/features/workspace/view_models/workspace_view_model.dart';
import 'package:anywork_client/bots.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/statistics.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Driver-owned borrowing only. All captures are serialized in their request;
/// this object retains neither a snapshot nor any product read/demand handle.
final class DriverInspection {
  DriverInspection({required this.graph, required this.container, this.bots});
  final AppGraph graph;
  final ProviderContainer container;
  final BotsRepository? bots;
  int exitRequests = 0;
  int? _armedRemainder;
  Stopwatch? _sinceArmObservation;

  /// 已挂载账号页的当前值里只取两个 domain 事实；未挂载时不实例化 owner。
  ///
  /// 读取已存在 VM 的当前值不是业务 demand；返回值不包含 feature 的呈现状态，
  /// 因此 `shared` 投影只消费 `anywork_client` 领域值。
  ///
  /// 本次 refresh 失败的字段不输出：VM 会保留上一次成功的 last-good，但那是 UI 的
  /// 展示兜底，不是 Driver 的 current 事实。两条读取各自独立，ACP 侧失败不会把模板
  /// 一起置空。读取仍在进行时沿用“来源未变即仍有效”，由 `currentAcpAccounts` 的
  /// 三键校验决定，这里不额外放行也不清空 UI 的 last-good。
  ({AcpAccountDirectory? acpAccounts, AccountTemplatesValue? templates})
  _accountsFacts() {
    if (!container.exists(accountsViewModelProvider)) {
      return (acpAccounts: null, templates: null);
    }
    final state = container.read(accountsViewModelProvider).asData?.value;
    if (state == null) return (acpAccounts: null, templates: null);
    return (
      acpAccounts: state.readIssues.containsKey(AccountsReadField.acpAccounts)
          ? null
          : state.acpAccounts,
      templates: state.readIssues.containsKey(AccountsReadField.templates)
          ? null
          : state.templates,
    );
  }

  /// 只读取已装配 owner 的当前值；本方法不建立任何订阅或业务 demand。
  ///
  /// ACP 认证与安装事实随 [captureDriverSnapshot] 从 `graph.acpAuth` /
  /// `graph.acpInstall` 的 canonical 镜像直接借用：`state.value` 是同步读取，
  /// 因此 Driver 既不会 `observe()` 出一个租约，也不会用 `synchronize()` 把
  /// 未加载的领域变成已加载，更不会启动检查、安装或取消。未加载就保持
  /// `null`（JSON 里 `acpAuthLoaded=false`、`acpInstall.loaded=false`）。
  DriverSnapshot capture() {
    final selection = graph.workspace.state.value.selection;
    final accountsFacts = _accountsFacts();
    final project = selection.projectId;
    final thread = selection.threadId;
    final start = project == null
        ? null
        : composerViewModelProvider(ComposerKey.start(projectId: project));
    final composer = thread == null
        ? null
        : composerViewModelProvider(ComposerKey.thread(threadId: thread));
    final conversation = thread == null
        ? null
        : conversationViewModelProvider(thread);
    final status = thread == null
        ? null
        : threadStatusViewModelProvider(thread);
    final plan = thread == null ? null : planViewModelProvider(thread);
    return captureDriverSnapshot(
      graph,
      visible: DriverViewFacts(
        workspace: container.exists(workspaceViewModelProvider)
            ? container.read(workspaceViewModelProvider).asData?.value
            : null,
        sidebar: container.exists(sidebarViewModelProvider)
            ? container.read(sidebarViewModelProvider).asData?.value
            : null,
        startComposer: start != null && container.exists(start)
            ? container.read(start).asData?.value
            : null,
        threadComposer: composer != null && container.exists(composer)
            ? container.read(composer).asData?.value
            : null,
        conversation: conversation != null && container.exists(conversation)
            ? container.read(conversation).asData?.value
            : null,
        status: status != null && container.exists(status)
            ? container.read(status).asData?.value
            : null,
        plan: plan != null && container.exists(plan)
            ? container.read(plan).asData?.value
            : null,
        // ACP 账号目录与 Native 模板只由设置页自己的有界读取供出：exists() 不会
        // 实例化 owner，因此未打开账号页时这里保持 null，而不是替它发起读取。
        // 只把两个 domain 值交给 shared 投影，不把 feature 的 ViewState 交出去。
        acpAccounts: accountsFacts.acpAccounts,
        templates: accountsFacts.templates,
      ),
      bots: bots == null
          ? const DriverBotsUnknown('Application BotsRepository not injected')
          : projectBotsState(bots!.state.value),
    );
  }

  String snapshotJson() {
    final values = capture();
    final snapshot = values.toJson();
    return jsonEncode({
      ...snapshot,
      ...exitStatus(),
      'driverDiagnostics': diagnostics(values),
      'delegation': delegation(values),
    });
  }

  /// A read-only native remainder observation, not a second watchdog/deadline.
  /// No armed observation means Unknown; the coordinator's private budget is
  /// not guessed from a Dart wall-clock or replaced by a fresh thirty seconds.
  void observeNativeArm(int remaining) {
    _armedRemainder = remaining;
    _sinceArmObservation = Stopwatch()..start();
  }

  Map<String, Object?> exitStatus() {
    final exit = graph.exitCoordinator.state.value;
    final remaining = _armedRemainder == null
        ? null
        : math.max(
            0,
            _armedRemainder! - _sinceArmObservation!.elapsedMilliseconds,
          );
    return {
      'nativeExit': {
        'remainingMs': remaining,
        'cleanupBudgetMs': remaining == null
            ? null
            : math.max(0, math.min(28000, remaining - 2000)),
        'requests': exitRequests,
        'budgetSource': 'driver-arm-observation',
        'requestsSource': 'driver-delivered-to-coordinator',
      },
      'shutdownReport': exit.report == null
          ? null
          : shutdownDiagnostic(exit.report!.shutdown),
      'shutdownPhases': [exit.phase.name],
      'shutdownPhasesAvailability': 'current-only',
      'startup': startupDiagnostic(graph.startup.state.value),
      'clientResources': [
        for (final resource in graph.budget.usage)
          {
            'kind': resource.kind.name,
            'owner': resource.owner,
            'phase': resource.phase.name,
          },
      ],
      'unresolvedClientResources': [
        for (final resource in exit.unresolved)
          {
            'owner': resource.owner,
            'issues': [
              for (final issue in resource.issues)
                {
                  'code': issue.diagnostic.code,
                  'recovery': issue.recovery.name,
                },
            ],
          },
      ],
    };
  }

  Map<String, Object?> diagnostics([DriverSnapshot? snapshot]) {
    final values = snapshot ?? capture();
    final active = graph.conversation.active.value;
    final selected = values.selection.threadId;
    final accounts = values.configuredAccounts;
    final catalogs = values.catalogAccounts;
    Map<String, Object?>? composer(bool start) {
      final attachments = start
          ? values.startDraft?.attachments
          : values.composer?.attachments;
      if (attachments == null) return null;
      return {
        'present': attachments.isNotEmpty,
        'previewReady': null,
        'previewAvailability': 'unavailable-metadata-only',
        'attachmentGeneration': start
            ? values.startDraft?.attachmentGeneration
            : values.composer?.attachmentGeneration,
        'submissionPending':
            (start
                    ? values.startDraft?.submission
                    : values.composer?.submission)
                is SubmittingDraft,
        'attachments': [
          for (final attachment in attachments)
            {
              'id': attachment.id,
              'name': attachment.filename,
              'filename': attachment.filename,
              'modality': attachment.modality.name,
              'byteSize': attachment.byteSize,
              'previewReady': null,
            },
        ],
      };
    }

    return {
      'schemaVersion': 2,
      ...conversationStatusDiagnostics(
        !values.selection.needsOpen && active?.threadId == selected
            ? active
            : null,
      ),
      'skills': skills(),
      'composer': {'newThread': composer(true), 'thread': composer(false)},
      'accounts': {
        'availability': accounts == null ? 'unavailable' : 'available',
        'list': accounts == null
            ? null
            : [
                for (final account in accounts)
                  {
                    'id': account.accountId,
                    'status': catalogs
                        ?.where(
                          (catalog) => catalog.accountId == account.accountId,
                        )
                        .firstOrNull
                        ?.modelCatalog
                        .error
                        ?.runtimeType
                        .toString(),
                    'modelCount': catalogs
                        ?.where(
                          (catalog) => catalog.accountId == account.accountId,
                        )
                        .firstOrNull
                        ?.effectiveModels
                        .length,
                    'defaultModelConfigured': catalogs
                        ?.where(
                          (catalog) => catalog.accountId == account.accountId,
                        )
                        .firstOrNull
                        ?.defaultModelId
                        .isNotEmpty,
                  },
              ],
        'details': catalogs == null
            ? null
            : [
                for (final catalog in catalogs)
                  {
                    'id': catalog.accountId,
                    'models': [
                      for (final model in catalog.effectiveModels)
                        modelDiagnostic(model),
                    ],
                  },
              ],
      },
      'topics': {
        'availability': 'partial',
        'registryAvailability': 'unavailable',
        'leaseRefs': null,
        'connections': null,
        'projectionRevisions': {
          'settings':
              values.configuration.projection.header?.configurationRevision,
          'modelCatalog': values.models.projection.header?.catalogRevision,
          'selectedThread': values.execution?.stamp?.revision,
          'persistence': values.persistence.projection.header?.revision,
        },
      },
      'seams': {
        'clipboardImageReaderOverride': false,
        'pasteObservation': 'unavailable',
        'fixtureHook': 'driver-fixture-clipboard-image',
        'fixtureAdmissionHook': 'driver-fixture-clipboard-image',
        'fixturePreviewHook': 'driver-fixture-clipboard-image-preview',
        'fixturePreviewStage': 'metadata-only-no-preview-fact',
        'fixtureAwaitsPreviewInAdmissionHook': false,
        'runtimeEventEndpoint': 'typed-session-observation',
        'systemClipboardTouched': false,
      },
    };
  }

  Map<String, Object?> delegation(DriverSnapshot values) {
    final config = values.configuration;
    final defaults = config.projection.sync.phase == ResourceSyncPhase.ready
        ? currentDriverRead(
            config.delegation,
            config.projection.stamp?.origin,
            reference: config.projection.header?.reference,
          )
        : null;
    final start = values.startDraft;
    return {
      'defaults': defaults == null
          ? null
          : {
              'mode': defaults.mode.name,
              'preference': defaults.preference.name,
            },
      'settingsRevision': config.projection.header?.configurationRevision,
      'catalogRevision': values.models.projection.header?.catalogRevision,
      'accountModels': values.catalogAccounts == null
          ? null
          : [
              for (final account in values.catalogAccounts!)
                for (final model in account.effectiveModels)
                  {
                    'accountId': account.accountId,
                    'modelId': model.modelId,
                    'enabled': model.enabled,
                    'textEligible': model.typeSupport.any(
                      (type) =>
                          type.modelType == ModelType.text &&
                          type.exclusions.isEmpty,
                    ),
                    'pending': null,
                    'pendingEnabled': null,
                    'error': null,
                  },
            ],
      'drafts': start == null
          ? null
          : [
              {
                'projectId': values.selection.projectId,
                'modeOverride': start.delegationModeOverride?.name,
                'preferenceOverride': start.delegationPreferenceOverride?.name,
                'effectiveMode':
                    start.delegationModeOverride?.name ?? defaults?.mode.name,
                'effectivePreference':
                    start.delegationPreferenceOverride?.name ??
                    defaults?.preference.name,
                'workspaceMode': start.workspaceMode.name,
                'submitting': start.submission is SubmittingDraft,
              },
            ],
      'threads': values.directory == null
          ? null
          : [
              for (final thread in values.directory!)
                {
                  'threadId': thread.id,
                  'mode': thread.delegationMode.name,
                  'preference': thread.delegationPreference.name,
                  'frozenModel': _selection(thread.frozenModel),
                },
            ],
      'agents': values.agents == null
          ? null
          : [
              for (final agent in values.agents!)
                {
                  'threadId': agent.threadId,
                  'taskSummary': agent.task,
                  'role': agent.role,
                  'state': agentDiagnostic(agent)['status'],
                  'mode': agent.delegationMode.name,
                  'preference': agent.delegationPreference.name,
                  'frozenModel': _selection(agent.frozenModel),
                },
            ],
      'modelDetails': null,
    };
  }

  Map<String, Object?> modeEditor() {
    final editor = container.exists(modeEditorViewModelProvider)
        ? container.read(modeEditorViewModelProvider).asData?.value
        : null;
    final catalog = graph.modes.state.value;
    final modes = catalog.projection.sync.phase == ResourceSyncPhase.ready
        ? currentDriverRows(catalog.modes, catalog.projection.stamp?.origin)
        : null;
    final workflow = capture().toJson()['workflow'];
    return {
      'availability': editor == null ? 'unknown' : 'available',
      'document': editor?.document?.toJson(),
      'jsonText': editor?.jsonText,
      'dirty': editor?.dirty,
      'readOnly': editor?.readOnly,
      'busy': editor?.busy,
      'canUndo': editor?.undo.isNotEmpty,
      'canRedo': editor?.redo.isNotEmpty,
      'error': editor?.error?.code.name,
      'issues': editor == null
          ? null
          : [
              for (final issue in editor.issues)
                {
                  'code': issue.code,
                  'path': issue.path,
                  'message': issue.message,
                },
            ],
      'preview': editor?.preview == null
          ? null
          : {
              'accepted': editor!.preview!.accepted,
              'message': editor.preview!.message,
              'currentState': editor.preview!.currentState?.toJson(),
              'transitions': [
                for (final transition in editor.preview!.transitions)
                  transition.toJson(),
              ],
              'path': editor.preview!.path,
              'terminal': editor.preview!.terminal,
            },
      'catalogRevision': catalog.projection.header?.revision,
      'catalog': modes == null
          ? null
          : [
              for (final mode in modes)
                {
                  'id': mode.id.id,
                  'displayName': mode.displayName,
                  'readOnly': mode.readOnly,
                },
            ],
      'threadId': graph.workspace.state.value.selection.threadId,
      'run': workflow is Map<String, Object?> ? workflow['currentRun'] : null,
    };
  }

  Map<String, Object?> statistics() {
    final state = graph.statistics.state.value;
    final snapshot = state.snapshot;
    final summaryRows = snapshot?.summaries;
    final historyRows = snapshot?.history;
    return {
      'loaded': snapshot != null,
      'syncPhase': state.sync.phase.name,
      'syncError': state.sync.error == null
          ? null
          : {
              'code': state.sync.error!.code.name,
              'retryable': state.sync.error!.retryable,
            },
      'revision': snapshot?.revision,
      'statisticsPending': snapshot?.statisticsPending,
      'statisticsGap': snapshot?.statisticsGap,
      'readFailed': snapshot?.readFailed,
      'summaries': summaryRows == null
          ? null
          : [
              for (final summary in summaryRows)
                {
                  'accountId': summary.identity.accountId,
                  'accountDisplayName': summary.identity.accountDisplayName,
                  'modelId': summary.identity.modelId,
                  ..._counters(summary.counters),
                  'effortBreakdowns': [
                    for (final effort in summary.effortBreakdowns)
                      {
                        'effort': effort.identity.effort,
                        ..._counters(effort.counters),
                      },
                  ],
                },
            ],
      'history': historyRows == null
          ? null
          : [
              for (final sample in historyRows)
                {
                  'accountId': sample.identity.accountId,
                  'accountDisplayName': sample.identity.accountDisplayName,
                  'modelId': sample.identity.modelId,
                  'sentModel': sample.identity.sentModel,
                  'reportedModel': sample.identity.reportedModel,
                  'matchState': sample.identity.modelMatchState.name,
                  'effort': sample.identity.effort,
                  'tokens': sample.counters.completionTokens,
                  'ttftMillis': sample.counters.ttftMillis,
                  'decodeMillis': sample.counters.decodeMillis,
                  'responseMillis': sample.counters.totalResponseMillis,
                  'tokensPerSecond': sample.counters.tokensPerSecond,
                },
            ],
    };
  }

  Map<String, Object?> skills() {
    final project = graph.workspace.state.value.selection.projectId;
    final provider = project == null ? null : skillsViewModelProvider(project);
    final view = provider != null && container.exists(provider)
        ? container.read(provider).asData?.value
        : null;
    final state = view?.source;
    final config = graph.configuration.state.value;
    final settings = config.projection.sync.phase == ResourceSyncPhase.ready
        ? currentDriverRead(
            config.skillsSettings,
            config.projection.stamp?.origin,
            reference: config.projection.header?.reference,
          )
        : null;
    final rows = state?.projection.sync.phase == ResourceSyncPhase.ready
        ? currentDriverRows(state!.skills, state.projection.stamp?.origin)
        : null;
    return {
      'projectId': project,
      'status': switch (state?.projection.header?.source.brief) {
        null => null,
        UninitializedObservedBrief() => 'uninitialized',
        LoadingObservedBrief() => 'loading',
        ReadyObservedBrief() => 'ready',
        RefreshingObservedBrief() => 'refreshing',
        StaleObservedBrief() => 'stale',
        DegradedObservedBrief() => 'degraded',
        FailedObservedBrief() => 'failed',
        StoppedObservedBrief() => 'stopped',
      },
      'catalogRevision': state?.projection.header?.catalogRevision,
      'skills': rows == null ? null : [for (final skill in rows) skill.name],
      'warnings': state == null
          ? null
          : currentDriverRead(state.warnings, state.projection.stamp?.origin),
      'error': state?.projection.sync.error?.code.name,
      'config': settings == null
          ? {'availability': 'unavailable'}
          : {
              'availability': 'available',
              'enabled': settings.enabled,
              'systemEnabled': settings.systemEnabled,
              'projectDir': settings.projectDir,
              'userDir': settings.userDir,
              'externalDirs': settings.externalDirs,
              'disabledCount': settings.disabled.length,
            },
    };
  }

  Map<String, Object?> persistenceQueue() {
    final queue = graph.persistence.queue.value;
    final rows = queue.projection.sync.phase == ResourceSyncPhase.ready
        ? currentDriverRows(queue.threads, queue.projection.stamp?.origin)
        : null;
    return {
      'pendingOperations': queue.projection.header?.pendingOperations,
      'threads': rows == null
          ? null
          : [
              for (final row in rows)
                {
                  'threadId': row.threadId,
                  'fault': row.fault?.name,
                  'generation': row.faultGeneration,
                  'stateDirty': row.stateDirtyRevision,
                  'stateDurable': row.stateDurableRevision,
                  'historyAdmitted': row.historyAdmittedSequence,
                  'historyDurable': row.historyDurableSequence,
                  'pending': row.pendingOperations,
                  'error': row.lastError,
                },
            ],
    };
  }

  Map<String, Object?> searchSettings() {
    final config = graph.configuration.state.value;
    final models = graph.models.state.value;
    final configOrigin = config.projection.sync.phase == ResourceSyncPhase.ready
        ? config.projection.stamp?.origin
        : null;
    final modelOrigin = models.projection.sync.phase == ResourceSyncPhase.ready
        ? models.projection.stamp?.origin
        : null;
    final desired = currentDriverRead(
      config.webSearch,
      configOrigin,
      reference: config.projection.header?.reference,
    );
    final desiredDeep = currentDriverRead(
      config.deepSeekSearch,
      configOrigin,
      reference: config.projection.header?.reference,
    );
    final effective = currentDriverRead(
      models.webSearch,
      modelOrigin,
      reference: models.projection.header?.reference,
    );
    final effectiveDeep = currentDriverRead(
      models.deepSeekSearch,
      modelOrigin,
      reference: models.projection.header?.reference,
    );
    return {
      'ok':
          desired != null &&
          desiredDeep != null &&
          effective != null &&
          effectiveDeep != null,
      'revision': config.projection.header?.configurationRevision,
      'webSearch': {
        'configuredMode': desired?.configuredMode,
        'effectiveMode': effective?.effectiveMode,
        'availability': effective?.availability,
        'contextSize': desired?.contextSize,
        'allowedDomains': desired?.allowedDomains,
        'country': desired?.country,
        'region': desired?.region,
        'city': desired?.city,
        'timezone': desired?.timezone,
        'accountId': effective?.accountId,
        'modelId': effective?.modelId,
      },
      'deepSeekWebSearch': {
        'configuredEnabled': desiredDeep?.configuredEnabled,
        'effectiveEnabled': effectiveDeep?.effectiveEnabled,
        'configuredFetchEnabled': desiredDeep?.configuredFetchEnabled,
        'effectiveFetchEnabled': effectiveDeep?.effectiveFetchEnabled,
        'availability': effectiveDeep?.availability,
        'accountId': effectiveDeep?.accountId,
      },
    };
  }
}

Map<String, Object?> shutdownDiagnostic(StudioShutdownReport report) => {
  'outcome': report.outcome.name,
  'persistence': switch (report.persistence) {
    UnknownPendingPersistence() => 'unknown',
    CountPendingPersistence(:final count) => 'pending:$count',
    DrainedPendingPersistence() => 'drained',
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

Map<String, Object?>? _selection(ModelSelection? selection) => selection == null
    ? null
    : {
        'accountId': selection.model.accountId,
        'modelId': selection.model.modelId,
        'effort': selection.effort,
      };

Map<String, Object?> _counters(PerformanceCounters counters) => {
  'samples': counters.sampleCount,
  'tokens': counters.completionTokens,
  'tokensPerSecond': counters.tokensPerSecond,
  'ttftSampleCount': counters.ttftSampleCount,
  'averageTtftMillis': counters.averageTtftMillis,
};
