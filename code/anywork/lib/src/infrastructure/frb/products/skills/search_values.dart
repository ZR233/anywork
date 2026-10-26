import 'package:anywork_client/skills.dart';

import '../../../../rust/api/studio/products/read/skills.dart' as native;
import '../../shared/exact_numbers.dart';
import 'read_values.dart';

SkillResourceBase skillSearchResourceFromBridge(
  native.BridgeSkillSearchResourceBase value,
) => switch (value) {
  native.BridgeSkillSearchResourceBase_Directory(:final path) =>
    SkillResourceBase.directory(path: path),
  native.BridgeSkillSearchResourceBase_Url(:final url) => SkillResourceBase.url(
    url: url,
  ),
  native.BridgeSkillSearchResourceBase_Opaque(:final description) =>
    SkillResourceBase.opaque(description: description),
};

SkillSummary skillSearchSummaryFromBridge(
  native.BridgeSkillSearchSummary value,
) => SkillSummary(
  name: value.name,
  description: value.description,
  category: value.category,
  platforms: value.platforms,
  source: skillSourceFromBridge(value.source),
  providerId: value.providerId,
  invocation: SkillInvocationPolicy(
    modelInvocable: value.invocation.modelInvocable,
    userInvocable: value.invocation.userInvocable,
  ),
  resourceBase: skillSearchResourceFromBridge(value.resourceBase),
);

SkillSearchResult skillsSearchFromBridge(
  native.BridgeSkillsSearchResult value,
) => SkillSearchResult(
  projectId: value.projectId,
  catalogRevision: exactU64(
    value.catalogRevision,
    'skills search catalog revision',
  ),
  matches: value.matches
      .map(skillSearchSummaryFromBridge)
      .toList(growable: false),
  truncated: value.truncated,
);
