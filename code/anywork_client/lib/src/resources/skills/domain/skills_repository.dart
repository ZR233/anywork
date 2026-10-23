import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import 'skills_state.dart';
import 'skills_values.dart';

abstract interface class SkillsRepository {
  ProjectSkillsQuery project(String projectId);
  OperationTicket<SkillsReadTarget> discover(String projectId);
  Future<SkillSearchResult> search(String projectId, String query, {int limit = 50});
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

abstract interface class ProjectSkillsQuery {
  String get projectId;
  ReadonlyLatestValue<SkillsState> get state;
  Future<void> loadSkillsPage({int limit = 32});
  Future<void> loadWarnings();
  Future<void> loadProjectDirectory();
  Future<void> loadConfigFingerprint();
  Future<void> loadSourceStatus();
  void requestClose();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
