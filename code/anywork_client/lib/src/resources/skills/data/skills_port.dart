import 'package:anywork_client/resources_ports.dart';

import '../domain/skills_state.dart';
import '../domain/skills_values.dart';
import 'skills_frames.dart';
import 'skills_reads.dart';

abstract interface class SkillsPort {
  Future<FeedConnection<SkillsFrame>> openSkills(String projectId);
  Future<SkillsReadConnection> openSkillsRead(
    SkillsReadRef reference, {
    required ProductReadOrigin origin,
  });
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  });
  Future<SkillsReadTarget> discover(String projectId);
  Future<SkillSearchResult> search(
    String projectId,
    String query, {
    int limit = 50,
  });
}

abstract interface class SkillsReadConnection {
  Future<SkillsReadHeader> header();
  Future<SkillsEntryPage> entries({int offset = 0, int limit = 32});
  Future<SkillsEntityRead> entity(ProductEntityRef reference);

  /// Native effective-name lookup retains ASCII-insensitive matching and text.
  Future<ProductEntityRef?> lookupSkill(String name);
  Future<SkillSummaryReadPage> skills(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<TextReadPage> strings(int listId, {int offset = 0, int limit = 32});
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
