import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/commands/settings_commands.dart';
import '../../data/stores/recovery_store.dart';
import '../../data/stores/selection_store.dart';
import '../../data/stores/settings_store.dart';
import '../../domain/models/studio_models.dart';
import 'attachment_drafts.dart';

part 'start_session_controller.g.dart';

/// 起始页 route 作用域草稿。不进入全局 store；autoDispose，最后一个观察者离开即销毁。
///
/// 正文、Mode 与工作区按项目隔离，未写过的项目使用默认值（`mode.simple` / `local`）。
/// 模型与思考强度意图按 Mode 持有，不属于项目草稿：canonical 永不覆盖它们。
/// 附件引用仍在 [AttachmentDrafts]，按 projectId 组织。
@riverpod
class StartSessionController extends _$StartSessionController {
  bool _submitInFlight = false;

  @override
  StartSessionDraft build() {
    ref.onDispose(_releaseAttachments);
    return const StartSessionDraft();
  }

  void updateDraft(String projectId, String text) {
    if (state.submitting || _submitInFlight) return;
    final current = state.forProject(projectId);
    if (current.text == text && state.projects.containsKey(projectId)) return;
    state = state.copyWith(
      projects: {
        ...state.projects,
        projectId: current.copyWith(text: text),
      },
    );
  }

  void setMode(String projectId, ThreadModeId mode) {
    if (state.submitting || _submitInFlight) return;
    final current = state.forProject(projectId);
    if (current.mode == mode && state.projects.containsKey(projectId)) return;
    // 切换 Mode 不搬运另一个 Mode 的模型意图；展示回落到该 Mode 的已保存路由。
    state = state.copyWith(
      projects: {
        ...state.projects,
        projectId: current.copyWith(mode: mode),
      },
    );
  }

  void setWorkspaceMode(String projectId, ThreadWorkspaceMode mode) {
    if (state.submitting || _submitInFlight) return;
    final current = state.forProject(projectId);
    if (current.workspaceMode == mode &&
        state.projects.containsKey(projectId)) {
      return;
    }
    state = state.copyWith(
      projects: {
        ...state.projects,
        projectId: current.copyWith(workspaceMode: mode),
      },
    );
  }

  /// 显式模型意图。换模型时清掉该 Mode 的思考强度意图，避免沿用上一模型的 effort。
  void setModelIntent(ThreadModeId mode, String providerId, String model) {
    if (state.submitting || _submitInFlight) return;
    if (providerId.isEmpty || model.isEmpty) return;
    final next = StartSessionModelIntent(providerId: providerId, model: model);
    final previous = state.modelIntents[mode.id];
    if (previous == next && state.modelIntents.containsKey(mode.id)) return;
    final efforts = Map<String, String>.of(state.effortIntents);
    // 只在实际换模型时清 effort。再次点选同一模型，或首次点选当前 canonical
    // 模型，都不是换模型，不能清掉已经显式选择的思考强度。
    if (_selectedModelChanged(mode, previous, next)) {
      efforts.remove(mode.id);
    }
    state = state.copyWith(
      modelIntents: {...state.modelIntents, mode.id: next},
      effortIntents: efforts,
    );
  }

  bool _selectedModelChanged(
    ThreadModeId mode,
    StartSessionModelIntent? previous,
    StartSessionModelIntent next,
  ) {
    if (previous != null) {
      return previous.providerId != next.providerId ||
          previous.model != next.model;
    }
    final exact = _exactRoute(mode);
    return exact == null ||
        exact.providerId != next.providerId ||
        exact.model != next.model;
  }

  void setEffortIntent(ThreadModeId mode, String effort) {
    if (state.submitting || _submitInFlight) return;
    if (effort.isEmpty) return;
    if (state.effortIntents[mode.id] == effort) return;
    state = state.copyWith(
      effortIntents: {...state.effortIntents, mode.id: effort},
    );
  }

  /// 一次性组装创建命令。哨兵在任何 await 之前置位。
  ///
  /// 有显式模型意图时只把 provider+model 写入设置 lane（effort 由服务端处理：
  /// 同 provider+model 保留，否则模型默认）。显式思考强度再作为独立字段命令发送。
  /// 随后复用 [AttachmentDrafts.submitNewThread]：排空设置 lane、校验 route 失败、
  /// 再创建并提交。成功后销毁本路由草稿。
  Future<bool> submit(String projectId) async {
    if (_submitInFlight || state.submitting) return false;
    if (!_readyToSubmit(projectId)) return false;
    _submitInFlight = true;
    state = state.copyWith(submitting: true);
    try {
      final project = state.forProject(projectId);
      await _persistRouteIntent(project.mode);
      if (!ref.mounted) return false;
      final accepted = await ref
          .read(attachmentDraftsProvider.notifier)
          .submitNewThread(
            projectId: projectId,
            text: project.text,
            mode: project.mode,
            workspaceMode: project.workspaceMode,
          );
      if (!ref.mounted) return accepted;
      if (accepted) {
        state = const StartSessionDraft();
        return true;
      }
      return false;
    } catch (error) {
      if (ref.mounted) {
        ref
            .read(attachmentDraftsProvider.notifier)
            .reportNewThreadFailure(projectId, error);
      }
      return false;
    } finally {
      _submitInFlight = false;
      if (ref.mounted && state.submitting) {
        state = state.copyWith(submitting: false);
      }
    }
  }

  bool _readyToSubmit(String projectId) {
    final text = state.forProject(projectId).text.trim();
    final attachments = ref
        .read(attachmentDraftsProvider)
        .newThread(projectId)
        .attachments;
    if (text.isEmpty && attachments.isEmpty) return false;
    final selection = ref.read(selectionStoreProvider);
    if (selection.selectedProjectId != projectId ||
        selection.selectedThreadId != null) {
      return false;
    }
    final issues = ref.read(recoveryStoreProvider).value?.values ?? const [];
    return !issues.any(
      (issue) =>
          issue.blocksAccess &&
          issue.scope == RecoveryIssueScope.project &&
          issue.projectId == projectId,
    );
  }

  Future<void> _persistRouteIntent(ThreadModeId mode) async {
    final commands = ref.read(settingsCommandsProvider.notifier);
    final before = _exactRoute(mode);
    final intent = state.modelIntentFor(mode);
    if (intent != null &&
        (before == null ||
            before.providerId != intent.providerId ||
            before.model != intent.model)) {
      await commands.setModeModelField(
        mode: mode,
        providerId: intent.providerId,
        model: intent.model,
      );
      if (!ref.mounted) return;
    }
    final effort = state.effortIntentFor(mode);
    if (effort == null || effort.isEmpty) return;
    final landed = _exactRoute(mode);
    if (landed?.effort == effort) return;
    await commands.setModeReasoningEffortField(mode: mode, effort: effort);
  }

  ModeModelRouteView? _exactRoute(ThreadModeId mode) {
    final routes =
        ref.read(settingsStoreProvider).canonical?.modeModelRoutes ?? const [];
    for (final route in routes) {
      if (route.modeId == mode) return route;
    }
    return null;
  }

  void _releaseAttachments() {
    if (state.submitting || _submitInFlight) return;
    final board = ref.read(attachmentDraftsProvider);
    final projectIds = {...state.projects.keys, ...board.newThreadDrafts.keys};
    for (final projectId in projectIds) {
      final composer = board.newThread(projectId);
      if (composer.isSubmissionPending || composer.attachments.isEmpty) {
        continue;
      }
      unawaited(
        ref
            .read(attachmentDraftsProvider.notifier)
            .releaseOrphans(
              projectId: projectId,
              threadId: null,
              draftIds: [
                for (final attachment in composer.attachments) attachment.id,
              ],
            ),
      );
    }
  }
}

/// 起始页草稿。相等性按值比较，供 ViewProvider 过滤通知。
class StartSessionDraft {
  const StartSessionDraft({
    this.projects = const {},
    this.modelIntents = const {},
    this.effortIntents = const {},
    this.submitting = false,
  });

  final Map<String, StartSessionProjectDraft> projects;
  final Map<String, StartSessionModelIntent> modelIntents;
  final Map<String, String> effortIntents;
  final bool submitting;

  StartSessionProjectDraft forProject(String? projectId) {
    if (projectId == null) return const StartSessionProjectDraft();
    return projects[projectId] ?? const StartSessionProjectDraft();
  }

  StartSessionModelIntent? modelIntentFor(ThreadModeId mode) =>
      modelIntents[mode.id];

  String? effortIntentFor(ThreadModeId mode) {
    final effort = effortIntents[mode.id];
    if (effort == null || effort.isEmpty) return null;
    return effort;
  }

  StartSessionDraft copyWith({
    Map<String, StartSessionProjectDraft>? projects,
    Map<String, StartSessionModelIntent>? modelIntents,
    Map<String, String>? effortIntents,
    bool? submitting,
  }) {
    return StartSessionDraft(
      projects: projects ?? this.projects,
      modelIntents: modelIntents ?? this.modelIntents,
      effortIntents: effortIntents ?? this.effortIntents,
      submitting: submitting ?? this.submitting,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StartSessionDraft &&
          submitting == other.submitting &&
          _mapEquals(projects, other.projects) &&
          _mapEquals(modelIntents, other.modelIntents) &&
          _mapEquals(effortIntents, other.effortIntents);

  @override
  int get hashCode => Object.hash(
    submitting,
    _mapHash(projects),
    _mapHash(modelIntents),
    _mapHash(effortIntents),
  );
}

class StartSessionProjectDraft {
  const StartSessionProjectDraft({
    this.text = '',
    this.mode = ThreadModeId.simple,
    this.workspaceMode = ThreadWorkspaceMode.local,
  });

  final String text;
  final ThreadModeId mode;
  final ThreadWorkspaceMode workspaceMode;

  StartSessionProjectDraft copyWith({
    String? text,
    ThreadModeId? mode,
    ThreadWorkspaceMode? workspaceMode,
  }) {
    return StartSessionProjectDraft(
      text: text ?? this.text,
      mode: mode ?? this.mode,
      workspaceMode: workspaceMode ?? this.workspaceMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StartSessionProjectDraft &&
          text == other.text &&
          mode == other.mode &&
          workspaceMode == other.workspaceMode;

  @override
  int get hashCode => Object.hash(text, mode, workspaceMode);
}

class StartSessionModelIntent {
  const StartSessionModelIntent({
    required this.providerId,
    required this.model,
  });

  final String providerId;
  final String model;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StartSessionModelIntent &&
          providerId == other.providerId &&
          model == other.model;

  @override
  int get hashCode => Object.hash(providerId, model);
}

/// 显示规则：显式 intent 优先，否则使用命令 lane 已组合的 `pending.target ?? canonical`。
ModeModelRouteView? overlayStartSessionRoute({
  required ThreadModeId mode,
  required ModeModelRouteView? laneRoute,
  StartSessionModelIntent? modelIntent,
  String? effortIntent,
}) {
  final explicitEffort = effortIntent != null && effortIntent.isNotEmpty
      ? effortIntent
      : null;
  if (modelIntent == null && explicitEffort == null) return laneRoute;
  final providerId = modelIntent?.providerId ?? laneRoute?.providerId;
  final model = modelIntent?.model ?? laneRoute?.model;
  if (providerId == null ||
      model == null ||
      providerId.isEmpty ||
      model.isEmpty) {
    return laneRoute;
  }
  return ModeModelRouteView(
    modeId: mode,
    providerId: providerId,
    model: model,
    effort:
        explicitEffort ??
        (laneRoute != null &&
                laneRoute.providerId == providerId &&
                laneRoute.model == model
            ? laneRoute.effort
            : ''),
  );
}

bool _mapEquals<K, V>(Map<K, V> left, Map<K, V> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

int _mapHash<K, V>(Map<K, V> values) => Object.hashAll(
  (values.entries.toList()..sort(
        (left, right) => left.key.toString().compareTo(right.key.toString()),
      ))
      .map((entry) => Object.hash(entry.key, entry.value)),
);
