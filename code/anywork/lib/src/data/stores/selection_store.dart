import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'selection_store.g.dart';

/// 纯本地选择事实。没有 canonical revision。
///
/// [needsOpen] 是“已恢复选择但尚未打开”的待打开标记。启动恢复只写选择并置位；
/// 显式打开后清除。选择变化必须改变相等性，不能被 Riverpod 的 `==` 吞掉。
@Riverpod(keepAlive: true)
class SelectionStore extends _$SelectionStore {
  @override
  SelectionStoreState build() => const SelectionStoreState();

  void restoreStartup({
    required String? projectId,
    required String? threadId,
    required bool needsOpen,
  }) {
    _assign(
      SelectionStoreState(
        selectedProjectId: projectId,
        selectedThreadId: threadId,
        needsOpen: threadId != null && needsOpen,
      ),
    );
  }

  void selectProject(String projectId) {
    if (state.selectedProjectId == projectId &&
        state.selectedThreadId == null) {
      return;
    }
    _assign(
      SelectionStoreState(selectedProjectId: projectId, needsOpen: false),
    );
  }

  void selectThread({
    required String projectId,
    required String threadId,
    bool needsOpen = false,
  }) {
    _assign(
      SelectionStoreState(
        selectedProjectId: projectId,
        selectedThreadId: threadId,
        needsOpen: needsOpen,
      ),
    );
  }

  void beginNewThread() {
    if (state.selectedThreadId == null && !state.needsOpen) return;
    _assign(
      SelectionStoreState(
        selectedProjectId: state.selectedProjectId,
        needsOpen: false,
      ),
    );
  }

  void markOpened() {
    if (!state.needsOpen) return;
    _assign(state.copyWith(needsOpen: false));
  }

  /// 项目目录前进后，选中项目已不在目录中时回退到稳定 id 序的第一个项目。
  void retainProjects(Set<String> projectIds, {String? fallbackProjectId}) {
    final selected = state.selectedProjectId;
    if (selected == null || projectIds.contains(selected)) return;
    _assign(
      SelectionStoreState(
        selectedProjectId: fallbackProjectId,
        needsOpen: false,
      ),
    );
  }

  /// 目录增量显式移除当前会话时回退。不在已加载窗口内不等于不存在。
  void replaceRemovedThread(String? nextThreadId) {
    _assign(state.copyWith(selectedThreadId: nextThreadId, needsOpen: false));
  }

  void _assign(SelectionStoreState next) {
    if (next == state) return;
    state = next;
  }
}

class SelectionStoreState {
  const SelectionStoreState({
    this.selectedProjectId,
    this.selectedThreadId,
    this.needsOpen = false,
  });

  final String? selectedProjectId;
  final String? selectedThreadId;
  final bool needsOpen;

  SelectionStoreState copyWith({
    Object? selectedProjectId = _unset,
    Object? selectedThreadId = _unset,
    bool? needsOpen,
  }) {
    return SelectionStoreState(
      selectedProjectId: identical(selectedProjectId, _unset)
          ? this.selectedProjectId
          : selectedProjectId as String?,
      selectedThreadId: identical(selectedThreadId, _unset)
          ? this.selectedThreadId
          : selectedThreadId as String?,
      needsOpen: needsOpen ?? this.needsOpen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionStoreState &&
          selectedProjectId == other.selectedProjectId &&
          selectedThreadId == other.selectedThreadId &&
          needsOpen == other.needsOpen;

  @override
  int get hashCode =>
      Object.hash(selectedProjectId, selectedThreadId, needsOpen);
}

const Object _unset = Object();
