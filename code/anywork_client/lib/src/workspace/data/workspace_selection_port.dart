import '../domain/directory_values.dart';
import '../domain/selection.dart';

/// Composition-only capability injected into D1. Never export from workspace.dart.
abstract interface class WorkspaceSubmissionSelection {
  WorkspaceIntentStamp capture(String projectId);
  bool adoptCreatedThread(
    WorkspaceThreadRecord thread,
    WorkspaceIntentStamp expected,
  );
}
