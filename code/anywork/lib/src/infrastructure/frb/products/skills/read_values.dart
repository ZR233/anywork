import 'package:anywork_client/skills_ports.dart';

import '../../../../rust/api/studio/products/read/skills.dart' as native;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';

SkillSource skillSourceFromBridge(native.BridgeSkillSource value) =>
    switch (value) {
      native.BridgeSkillSource.project => SkillSource.project,
      native.BridgeSkillSource.user => SkillSource.user,
      native.BridgeSkillSource.system => SkillSource.system,
      native.BridgeSkillSource.external_ => SkillSource.external,
    };

SkillsReadHeader skillsReadHeaderFromBridge(
  native.BridgeSkillsReadHeader value,
) => SkillsReadHeader(
  projectId: readTextFromBridge(value.projectId),
  configFingerprint: readTextFromBridge(value.configFingerprint),
  catalogRevision: exactU64(value.catalogRevision, 'skills catalog revision'),
  catalog: SkillCatalogRead(
    projectDir: readTextFromBridge(value.catalog.projectDir),
    skills: typedListFromBridge(value.catalog.skills),
    warnings: typedListFromBridge(value.catalog.warnings),
    complete: value.catalog.complete,
  ),
);

SkillResourceBaseRead skillResourceReadFromBridge(
  native.BridgeSkillResourceBaseRead value,
) => switch (value) {
  native.BridgeSkillResourceBaseRead_Directory(:final path) =>
    SkillResourceBaseRead.directory(path: readTextFromBridge(path)),
  native.BridgeSkillResourceBaseRead_Url(:final url) =>
    SkillResourceBaseRead.url(url: readTextFromBridge(url)),
  native.BridgeSkillResourceBaseRead_Opaque(:final description) =>
    SkillResourceBaseRead.opaque(description: readTextFromBridge(description)),
};

SkillSummaryRead skillReadFromBridge(native.BridgeSkillSummaryRead value) =>
    SkillSummaryRead(
      name: readTextFromBridge(value.name),
      description: readTextFromBridge(value.description),
      category: nullableReadText(value.category),
      platforms: typedListFromBridge(value.platforms),
      source: skillSourceFromBridge(value.source),
      providerId: readTextFromBridge(value.providerId),
      invocation: SkillInvocationPolicyRead(
        modelInvocable: value.invocation.modelInvocable,
        userInvocable: value.invocation.userInvocable,
      ),
      resourceBase: skillResourceReadFromBridge(value.resourceBase),
    );

SkillsEntityRead skillsEntityFromBridge(native.BridgeSkillsEntityRead value) =>
    SkillsEntityRead(
      reference: entityRefFromBridge(value.reference),
      value: skillReadFromBridge(value.value),
    );

SkillsEntryPage skillsEntriesFromBridge(native.BridgeSkillsEntryPage value) =>
    SkillsEntryPage(
      collection: collectionRefFromBridge(value.collection),
      offset: exactU64(value.offset, 'skills entries offset'),
      items: value.items.map(entityRefFromBridge).toList(growable: false),
      nextOffset: nullableU64(value.nextOffset, 'skills next entries offset'),
    );

SkillSummaryReadPage skillsPageFromBridge(
  native.BridgeSkillSummaryReadPage value,
) => SkillSummaryReadPage(
  listId: exactU64(value.listId, 'skills list'),
  offset: exactU64(value.offset, 'skills offset'),
  total: exactU64(value.total, 'skills total'),
  items: value.items.map(skillReadFromBridge).toList(growable: false),
  nextOffset: nullableU64(value.nextOffset, 'skills next offset'),
);
