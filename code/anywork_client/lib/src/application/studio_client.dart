import '../observation/latest_value.dart';

final class WorkspaceSelection {
  const WorkspaceSelection({
    this.threadId,
    this.projectId,
    this.settingsOpen = false,
  });
  final String? threadId;
  final String? projectId;
  final bool settingsOpen;
}

/// Navigation owns visible conversation demand independently of selection.
final class WorkspaceController {
  WorkspaceController({
    required void Function(String?) onThreadChanged,
    required void Function(String?) onVisibleThreadChanged,
  }) : _onThreadChanged = onThreadChanged,
       _onVisibleThreadChanged = onVisibleThreadChanged;

  final void Function(String?) _onThreadChanged;
  final void Function(String?) _onVisibleThreadChanged;
  final LatestValue<WorkspaceSelection> state = LatestValue(
    const WorkspaceSelection(),
  );

  void selectThread(String threadId, {String? projectId}) {
    final current = state.value;
    state.publish(
      WorkspaceSelection(
        threadId: threadId,
        projectId: projectId,
        settingsOpen: current.settingsOpen,
      ),
    );
    if (current.threadId != threadId) _onThreadChanged(threadId);
    _onVisibleThreadChanged(current.settingsOpen ? null : threadId);
  }

  void openNewSession({String? projectId}) {
    final current = state.value;
    state.publish(
      WorkspaceSelection(
        projectId: projectId,
        settingsOpen: current.settingsOpen,
      ),
    );
    if (current.threadId != null) _onThreadChanged(null);
    _onVisibleThreadChanged(null);
  }

  void showSettings() => _settings(true);
  void hideSettings() => _settings(false);

  void _settings(bool open) {
    _onVisibleThreadChanged(open ? null : state.value.threadId);
    final current = state.value;
    state.publish(
      WorkspaceSelection(
        threadId: current.threadId,
        projectId: current.projectId,
        settingsOpen: open,
      ),
    );
  }
}
