/// 统一右侧边栏的面板种类。
enum ConversationSidebarPanelKind { workflow, plan, file, todo }

/// 统一右侧边栏的宽度/覆盖呈现模式。
enum ConversationSidebarLayoutMode { split, expanded }

/// 单个会话线程的右侧边栏局部 UI 状态，不持有或改写业务事实。
///
/// 窗口宽度变化只影响实际呈现（窄窗自动转为浮层或全宽），不会覆盖用户的
/// 收起、面板切换与宽屏分栏/全宽选择。
class ConversationSidebarState<F> {
  bool _open = false;
  ConversationSidebarPanelKind? _activeKind;
  final Map<ConversationSidebarPanelKind, ConversationSidebarLayoutMode>
  _modeByKind = {};
  String? _planIdentity;
  String? _lastPendingPlanIdentity;
  F? _file;
  ConversationSidebarPanelKind? _returnKindOnFileClose;

  bool get isOpen => _open && _activeKind != null;
  ConversationSidebarPanelKind? get activeKind => _activeKind;
  F? get file => _file;

  bool isPanelOpen(ConversationSidebarPanelKind kind) =>
      isOpen && _activeKind == kind;

  ConversationSidebarLayoutMode layoutModeFor(
    ConversationSidebarPanelKind kind, {
    ConversationSidebarLayoutMode defaultMode =
        ConversationSidebarLayoutMode.split,
  }) => _modeByKind[kind] ?? defaultMode;

  /// 观察当前会话计划引用：
  /// - 新的待确认计划默认以 [pendingDefaultMode]（默认全展开）自动打开；
  /// - 同一待确认身份重复观察绝不覆盖用户的收起、页签切换或分栏选择；
  /// - 只读计划身份变化或计划移除时，自动退休旧的计划阅读选中态。
  void observePlan({
    required String? identity,
    required bool pending,
    ConversationSidebarLayoutMode pendingDefaultMode =
        ConversationSidebarLayoutMode.expanded,
  }) {
    if (_planIdentity != identity) {
      _planIdentity = identity;
      _modeByKind.remove(ConversationSidebarPanelKind.plan);
      if (_activeKind == ConversationSidebarPanelKind.plan) {
        if (identity == null) {
          _open = false;
          _activeKind = null;
        } else if (!pending) {
          _open = false;
        }
      }
      if (identity == null &&
          _returnKindOnFileClose == ConversationSidebarPanelKind.plan) {
        _returnKindOnFileClose = null;
      }
    }

    if (pending && identity != null && identity != _lastPendingPlanIdentity) {
      _lastPendingPlanIdentity = identity;
      _activeKind = ConversationSidebarPanelKind.plan;
      _open = true;
      _modeByKind[ConversationSidebarPanelKind.plan] = pendingDefaultMode;
    }
  }

  void openPanel(
    ConversationSidebarPanelKind kind, {
    ConversationSidebarLayoutMode? defaultMode,
  }) {
    _activeKind = kind;
    _open = true;
    if (defaultMode != null && !_modeByKind.containsKey(kind)) {
      _modeByKind[kind] = defaultMode;
    }
  }

  void togglePanel(
    ConversationSidebarPanelKind kind, {
    ConversationSidebarLayoutMode? defaultMode,
  }) {
    if (isPanelOpen(kind)) {
      collapse();
    } else {
      openPanel(kind, defaultMode: defaultMode);
    }
  }

  void collapse() {
    _open = false;
  }

  void expand({List<ConversationSidebarPanelKind> availableOrder = const []}) {
    final remembered = _activeKind;
    if (remembered != null &&
        (availableOrder.isEmpty || availableOrder.contains(remembered))) {
      _open = true;
      return;
    }
    if (availableOrder.isNotEmpty) {
      _activeKind = availableOrder.first;
      _open = true;
    }
  }

  void toggleSidebar({
    required List<ConversationSidebarPanelKind> availableOrder,
  }) {
    if (isOpen) {
      collapse();
    } else {
      expand(availableOrder: availableOrder);
    }
  }

  void openFile(F file) {
    if (_open &&
        _activeKind != null &&
        _activeKind != ConversationSidebarPanelKind.file) {
      _returnKindOnFileClose = _activeKind;
    } else if (!_open) {
      _returnKindOnFileClose = null;
    }
    _file = file;
    _activeKind = ConversationSidebarPanelKind.file;
    _open = true;
    _modeByKind[ConversationSidebarPanelKind.file] =
        ConversationSidebarLayoutMode.split;
  }

  void closeFile({
    List<ConversationSidebarPanelKind> remainingAvailable = const [],
  }) {
    _file = null;
    _modeByKind.remove(ConversationSidebarPanelKind.file);
    final returnKind = _returnKindOnFileClose;
    _returnKindOnFileClose = null;
    if (_activeKind == ConversationSidebarPanelKind.file) {
      if (returnKind != null && remainingAvailable.contains(returnKind)) {
        _activeKind = returnKind;
        _open = true;
      } else {
        _open = false;
        _activeKind = null;
      }
    }
  }

  void toggleLayoutMode(
    ConversationSidebarPanelKind kind, {
    ConversationSidebarLayoutMode defaultMode =
        ConversationSidebarLayoutMode.split,
  }) {
    final current = layoutModeFor(kind, defaultMode: defaultMode);
    _modeByKind[kind] = current == ConversationSidebarLayoutMode.expanded
        ? ConversationSidebarLayoutMode.split
        : ConversationSidebarLayoutMode.expanded;
  }

  /// 当可用面板集合变化且当前选中面板已消失时，收敛为收起态，避免空白边栏。
  void reconcileAvailable(Set<ConversationSidebarPanelKind> available) {
    if (_returnKindOnFileClose != null &&
        !available.contains(_returnKindOnFileClose)) {
      _returnKindOnFileClose = null;
    }
    if (_activeKind != null && !available.contains(_activeKind)) {
      _open = false;
      _activeKind = null;
    }
  }
}
