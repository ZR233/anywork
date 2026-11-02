import 'studio_enums.dart';
import 'delegation_models.dart';
import '../contracts/stamps.dart';

enum ThreadStatusView {
  idle,
  queued,
  running,
  waitingTool,
  waitingInteraction,
  cancelling,
  closing,
  closed,
  faulted;

  bool get isActive => switch (this) {
    queued ||
    running ||
    waitingTool ||
    waitingInteraction ||
    cancelling => true,
    idle || closing || closed || faulted => false,
  };

  /// Explicit final close is permanent; content remains readable independently.
  bool get blocksNewExecution => this == closing || this == closed;
}

enum WorkspaceKind { project, standalone }

class StudioProject {
  const StudioProject({
    required this.id,
    required this.name,
    required this.path,
    this.kind = WorkspaceKind.project,
    this.sshAlias,
  });

  final String id;
  final String name;
  final String path;
  final WorkspaceKind kind;
  final String? sshAlias;

  bool get isStandalone => kind == WorkspaceKind.standalone;
}

/// 退役成员的角色判据：旧版 `planner` 子成员不再是合法角色。
///
/// 这是角色字符串的唯一判据；调用方只组合自己的上下文条件（例如该行是否为成员），
/// 不再重复写一遍角色比较，避免空白或措辞漂移出第二份事实。
bool isRetiredAgentRole(String role) => role.trim() == 'planner';

class StudioThread {
  const StudioThread({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.mode,
    required this.delegationMode,
    required this.delegationPreference,
    this.frozenModel,
    required this.updatedAt,
    this.createdAt,
    this.lastUserMessageAt,
    this.parentThreadId,
    this.rootThreadId = '',
    this.agentPath = '',
    this.role = 'planner',
    this.status = ThreadStatusView.idle,
    this.archived = false,
    this.workspaceMode = ThreadWorkspaceMode.local,
    required this.workspacePath,
  });

  final String id;
  final String workspaceId;
  final String title;
  final ThreadModeId mode;
  final DelegationMode delegationMode;
  final DelegationPreference delegationPreference;
  final NewThreadModelRoute? frozenModel;
  final DateTime? createdAt;
  final DateTime updatedAt;

  /// 服务端最近一次成功受理用户消息的时间；null 表示尚未有已受理用户消息。
  ///
  /// 只由成功受理推进；模型回复、工具、运行状态、标题与配置更新不改变它。
  final DateTime? lastUserMessageAt;
  final String? parentThreadId;
  final String rootThreadId;
  final String agentPath;
  final String role;
  final ThreadStatusView status;
  final bool archived;

  /// Canonical 会话工作区模式，只读来自 Thread 目录事实。
  final ThreadWorkspaceMode workspaceMode;

  /// Canonical 会话工作区地址；`local` 为项目目录，`worktree` 为工作树路径。
  ///
  /// 唯一决定会话级外部「打开工作区」入口（VS Code、Zed 与终端）的打开目标，
  /// GUI 不推导工作树布局。
  final String workspacePath;

  bool get isRoot => parentThreadId == null;

  bool get isAgent => parentThreadId != null;

  /// The former planner child role is retained for history, never execution.
  bool get isRetiredAgent => isAgent && isRetiredAgentRole(role);

  String get effectiveRootThreadId => rootThreadId.isEmpty ? id : rootThreadId;

  DateTime get effectiveCreatedAt => createdAt ?? updatedAt;

  /// 会话目录排序键：最近用户消息时间，缺失时回落到创建时间（design/19 §19.1）。
  DateTime get directorySortTime => lastUserMessageAt ?? effectiveCreatedAt;

  /// 会话目录的 canonical 降序比较器：目录排序键降序，同秒按 ID 降序破平。
  static int compareDirectoryOrder(StudioThread a, StudioThread b) {
    final time = b.directorySortTime.compareTo(a.directorySortTime);
    return time != 0 ? time : b.id.compareTo(a.id);
  }

  StudioThread copyWith({
    String? title,
    ThreadModeId? mode,
    DateTime? createdAt,
    DateTime? lastUserMessageAt,
    DateTime? updatedAt,
    String? parentThreadId,
    String? rootThreadId,
    String? agentPath,
    String? role,
    ThreadStatusView? status,
    bool? archived,
    ThreadWorkspaceMode? workspaceMode,
    String? workspacePath,
  }) {
    return StudioThread(
      id: id,
      workspaceId: workspaceId,
      title: title ?? this.title,
      mode: mode ?? this.mode,
      delegationMode: delegationMode,
      delegationPreference: delegationPreference,
      frozenModel: frozenModel,
      createdAt: createdAt ?? this.createdAt,
      lastUserMessageAt: lastUserMessageAt ?? this.lastUserMessageAt,
      updatedAt: updatedAt ?? this.updatedAt,
      parentThreadId: parentThreadId ?? this.parentThreadId,
      rootThreadId: rootThreadId ?? this.rootThreadId,
      agentPath: agentPath ?? this.agentPath,
      role: role ?? this.role,
      status: status ?? this.status,
      archived: archived ?? this.archived,
      workspaceMode: workspaceMode ?? this.workspaceMode,
      workspacePath: workspacePath ?? this.workspacePath,
    );
  }
}

/// Bootstrap 的原始传输页；不注入或归约到 scoped 目录观察。
class ThreadDirectoryPage {
  const ThreadDirectoryPage({
    required this.threads,
    this.nextCursor,
    this.revision = 0,
  });

  final List<StudioThread> threads;
  final String? nextCursor;
  final int revision;

  bool get hasMore => nextCursor != null;
}

final class DirectoryWindow {
  DirectoryWindow({this.before, this.limit = 20}) {
    if (limit < 1 || limit > maxLimit) {
      throw ArgumentError.value(
        limit,
        'limit',
        'must be between 1 and $maxLimit',
      );
    }
  }

  static const int maxLimit = 100;
  static const int maxFrameBytes = 256 * 1024;

  final String? before;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is DirectoryWindow &&
      before == other.before &&
      limit == other.limit;

  @override
  int get hashCode => Object.hash(before, limit);
}

final class ThreadDirectoryFrame {
  ThreadDirectoryFrame({
    required this.query,
    required this.window,
    required this.stamp,
    required List<StudioThread> threads,
    this.nextCursor,
  }) : threads = List.unmodifiable(threads) {
    if (stamp.resourceKey != 'thread-directory') {
      throw ArgumentError.value(stamp.resourceKey, 'stamp.resourceKey');
    }
  }

  final DirectoryQuery query;
  final DirectoryWindow window;
  final ResourceStamp stamp;
  final List<StudioThread> threads;
  final String? nextCursor;
}

final class ThreadMetadataFrame {
  ThreadMetadataFrame({
    required this.threadId,
    required this.stamp,
    required this.thread,
  }) {
    if (stamp.resourceKey != 'thread-directory') {
      throw ArgumentError.value(stamp.resourceKey, 'stamp.resourceKey');
    }
    if (thread != null && thread!.id != threadId) {
      throw ArgumentError.value(thread!.id, 'thread.id');
    }
  }

  final String threadId;
  final ResourceStamp stamp;
  final StudioThread? thread;
}

/// 关机阶段的只读分类；canonical 状态由 [StudioShutdownProgress] 的 sealed variant 表达。
enum StudioShutdownPhase {
  stoppingSubscriptions,
  cancellingTurns,
  flushingPersistence,
  stoppingAgents,
  stoppingMcp,
  stoppingLsp,
  stopped;

  int get index1 => index + 1;
}

/// 一次关机进度的 canonical 状态；仅持久化刷新状态承载 pending commit 数。
sealed class StudioShutdownProgress {
  const StudioShutdownProgress();

  StudioShutdownPhase get phase => switch (this) {
    StoppingSubscriptionsProgress() =>
      StudioShutdownPhase.stoppingSubscriptions,
    CancellingTurnsProgress() => StudioShutdownPhase.cancellingTurns,
    FlushingPersistenceProgress() => StudioShutdownPhase.flushingPersistence,
    StoppingAgentsProgress() => StudioShutdownPhase.stoppingAgents,
    StoppingMcpProgress() => StudioShutdownPhase.stoppingMcp,
    StoppingLspProgress() => StudioShutdownPhase.stoppingLsp,
    StoppedProgress() => StudioShutdownPhase.stopped,
  };
}

final class StoppingSubscriptionsProgress extends StudioShutdownProgress {
  const StoppingSubscriptionsProgress();
}

final class CancellingTurnsProgress extends StudioShutdownProgress {
  const CancellingTurnsProgress();
}

final class FlushingPersistenceProgress extends StudioShutdownProgress {
  const FlushingPersistenceProgress({required this.pendingCommits});

  final int pendingCommits;
}

final class StoppingAgentsProgress extends StudioShutdownProgress {
  const StoppingAgentsProgress();
}

final class StoppingMcpProgress extends StudioShutdownProgress {
  const StoppingMcpProgress();
}

final class StoppingLspProgress extends StudioShutdownProgress {
  const StoppingLspProgress();
}

final class StoppedProgress extends StudioShutdownProgress {
  const StoppedProgress();
}

enum DirectoryFilter { all, running, attention }

class DirectoryQuery {
  const DirectoryQuery({
    this.workspaceId,
    this.search,
    this.archived = false,
    this.filter = DirectoryFilter.all,
  }) : threadIds = null,
       excludedThreadIds = const [];

  factory DirectoryQuery.withThreadIds({
    String? workspaceId,
    String? search,
    bool archived = false,
    DirectoryFilter filter = DirectoryFilter.all,
    Iterable<String>? threadIds,
    Iterable<String> excludedThreadIds = const [],
  }) {
    return DirectoryQuery._(
      workspaceId: workspaceId,
      search: search,
      archived: archived,
      filter: filter,
      threadIds: threadIds == null
          ? null
          : _normalizeDirectoryIds(threadIds, 'threadIds'),
      excludedThreadIds: _normalizeDirectoryIds(
        excludedThreadIds,
        'excludedThreadIds',
      ),
    );
  }

  const DirectoryQuery._({
    this.workspaceId,
    this.search,
    required this.archived,
    required this.filter,
    required this.threadIds,
    required this.excludedThreadIds,
  });

  static const int maxIdFilterItems = 64;

  final String? workspaceId;
  final String? search;
  final bool archived;
  final DirectoryFilter filter;
  final List<String>? threadIds;
  final List<String> excludedThreadIds;

  @override
  bool operator ==(Object other) =>
      other is DirectoryQuery &&
      workspaceId == other.workspaceId &&
      search == other.search &&
      archived == other.archived &&
      filter == other.filter &&
      _stringListsEqual(threadIds, other.threadIds) &&
      _stringListsEqual(excludedThreadIds, other.excludedThreadIds);

  @override
  int get hashCode => Object.hash(
    workspaceId,
    search,
    archived,
    filter,
    threadIds == null,
    Object.hashAll(threadIds ?? const <String>[]),
    Object.hashAll(excludedThreadIds),
  );
}

List<String> _normalizeDirectoryIds(
  Iterable<String> source,
  String argumentName,
) {
  final ids = List<String>.of(source);
  if (ids.length > DirectoryQuery.maxIdFilterItems ||
      ids.any((id) => id.trim().isEmpty)) {
    throw ArgumentError.value(
      source,
      argumentName,
      'requires at most 64 nonempty identities',
    );
  }
  ids.sort();
  return List.unmodifiable(ids.toSet());
}

bool _stringListsEqual(List<String>? left, List<String>? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
