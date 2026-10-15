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

/// Settings navigation changes presentation only; it never changes Chat demand.
final class WorkspaceController {
  WorkspaceController({required void Function(String?) onThreadChanged})
    : _onThreadChanged = onThreadChanged;

  final void Function(String?) _onThreadChanged;
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
  }

  void showSettings() => _settings(true);
  void hideSettings() => _settings(false);

  void _settings(bool open) {
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
