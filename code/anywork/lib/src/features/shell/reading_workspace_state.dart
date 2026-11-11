/// 阅读布局是局部选择，不复制计划的业务状态或决议资格。
enum ReadingMode { fullWidth, sideBySide }

/// 一个会话的阅读选择。窗口约束只影响呈现，不写入用户选择。
class ReadingWorkspaceState<T> {
  String? _planIdentity;
  String? _lastPendingIdentity;
  bool _planOpen = false;
  ReadingMode _planMode = ReadingMode.fullWidth;
  T? _file;
  ReadingMode _fileMode = ReadingMode.sideBySide;

  bool get planOpen => _planOpen;
  T? get file => _file;
  bool get readingOpen => _planOpen || _file != null;
  ReadingMode get mode => _file != null ? _fileMode : _planMode;

  /// 重复观察同一交互不覆盖用户关闭、重开、并排或文件阅读的选择。
  /// 新待确认交互优先打开计划，并重新使用全宽默认值。
  void observePlan({required String? identity, required bool pending}) {
    if (_planIdentity != identity) {
      _planIdentity = identity;
      _planOpen = false;
      _planMode = ReadingMode.fullWidth;
    }
    if (pending && identity != null && identity != _lastPendingIdentity) {
      _lastPendingIdentity = identity;
      openPlan();
      _planMode = ReadingMode.fullWidth;
    }
  }

  void openPlan() {
    if (_planIdentity == null) return;
    _file = null;
    _planOpen = true;
  }

  void closePlan() => _planOpen = false;

  void togglePlan() {
    if (_planOpen) {
      closePlan();
    } else {
      openPlan();
    }
  }

  void openFile(T file) {
    _planOpen = false;
    _file = file;
    _fileMode = ReadingMode.sideBySide;
  }

  void closeFile() => _file = null;

  void toggleMode() {
    final next = mode == ReadingMode.fullWidth
        ? ReadingMode.sideBySide
        : ReadingMode.fullWidth;
    if (_file != null) {
      _fileMode = next;
    } else {
      _planMode = next;
    }
  }

  bool fullWidth({required bool sideBySideFeasible}) =>
      !sideBySideFeasible || mode == ReadingMode.fullWidth;
}
