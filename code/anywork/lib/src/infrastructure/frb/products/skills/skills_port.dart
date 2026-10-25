import 'package:anywork_client/skills_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/read/skills.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../resource_references.dart';
import 'search_values.dart';
import 'skills_feed.dart';
import 'skills_read_connection.dart';
import 'source_status_connection.dart';

final class FrbSkillsPort implements SkillsPort {
  const FrbSkillsPort();

  @override
  Future<FeedConnection<SkillsFrame>> openSkills(String projectId) async {
    final connection = FrbSkillsConnection(projectId);
    await connection.opened;
    return connection;
  }

  @override
  Future<SkillsReadConnection> openSkillsRead(
    SkillsReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbSkillsReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbSkillsSourceStatusConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<SkillsReadTarget> discover(String projectId) => bridgeQuery(
    () async => skillsTargetFromBridge(
      await native.skillsDiscover(projectId: projectId),
    ),
  );

  @override
  Future<SkillSearchResult> search(
    String projectId,
    String query, {
    int limit = 50,
  }) => bridgeQuery(() async {
    final value = skillsSearchFromBridge(
      await native.skillsSearch(
        projectId: projectId,
        query: query,
        limit: limit,
      ),
    );
    if (value.projectId != projectId || value.matches.length > limit) {
      throw adapterProtocol('skills-search-target');
    }
    return value;
  });
}
