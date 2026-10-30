import '../../../anywork_client.dart' show ReadModel;

class SelectionStore extends ReadModel<SelectionStoreState> {
  SelectionStore() : super(const SelectionStoreState());

  int _navigationGeneration = 0;

  /// Register intent before queued work starts, without changing selection or
  /// resource demand. Older navigation may finish, but can no longer publish.
  int beginNavigation() => ++_navigationGeneration;

  bool isCurrentNavigation(int generation) =>
      generation == _navigationGeneration;

  void restoreStartup({
    required String? workspaceId,
    required String? threadId,
    required bool needsOpen,
  }) {
    _assign(
      SelectionStoreState(
        selectedProjectId: workspaceId,
        selectedThreadId: threadId,
        needsOpen: threadId != null && needsOpen,
      ),
    );
  }

  void selectProject(String workspaceId) {
    _assign(
      SelectionStoreState(selectedProjectId: workspaceId, needsOpen: false),
    );
  }

  void selectThread({
    required String workspaceId,
    required String threadId,
    bool needsOpen = false,
  }) {
    _assign(
      SelectionStoreState(
        selectedProjectId: workspaceId,
        selectedThreadId: threadId,
        needsOpen: needsOpen,
      ),
    );
  }

  void beginNewThread() {
    _assign(
      SelectionStoreState(
        selectedProjectId: state.selectedProjectId,
        needsOpen: false,
      ),
    );
  }

  void markOpened() {
    _assign(state.copyWith(needsOpen: false));
  }

  /// 项目目录前进后，选中项目已不在目录中时回退到稳定 id 序的第一个项目。
  void retainProjects(Set<String> workspaceIds, {String? fallbackProjectId}) {
    final selected = state.selectedProjectId;
    if (selected == null || workspaceIds.contains(selected)) return;
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
    // Direct selection changes and canonical removal also retire pending
    // navigation, including explicit selection of an already selected value.
    beginNavigation();
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
