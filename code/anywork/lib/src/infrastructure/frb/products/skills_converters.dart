import 'package:anywork_client/skills_ports.dart';

import '../../../rust/api/studio/products/feed/skills.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';
import 'resource_headers.dart';

SkillsBaseline skillsBaselineFromBridge(native.BridgeSkillsBaseline value) =>
    SkillsBaseline(
      header: skillsHeaderFromBridge(value.header),
      collection: value.collection == null
          ? null
          : collectionRefFromBridge(value.collection!),
    );

SkillsChange skillsChangeFromBridge(native.BridgeSkillsChange value) =>
    SkillsChange(
      header: skillsHeaderFromBridge(value.header),
      baseCollectionRevision: nullableU64(
        value.baseCollectionRevision,
        'Skills base collection revision',
      ),
      collection: value.collection == null
          ? null
          : collectionRefFromBridge(value.collection!),
      upserted: value.upserted.map(entityRefFromBridge).toList(growable: false),
      removedEntries: value.removedEntries
          .map((entry) => exactU64(entry, 'Skills removed entry'))
          .toList(growable: false),
    );

SkillsEvent skillsEventFromBridge(native.BridgeSkillsEvent value) =>
    switch (value) {
      native.BridgeSkillsEvent_Baseline(
        :final identity,
        :final stamp,
        :final value,
      ) =>
        SkillsEvent.baseline(
          identity: productFeedIdentityFromBridge(identity),
          stamp: productStampFromBridge(stamp),
          value: skillsBaselineFromBridge(value),
        ),
      native.BridgeSkillsEvent_Change(
        :final stamp,
        :final baseRevision,
        :final value,
      ) =>
        SkillsEvent.change(
          stamp: productStampFromBridge(stamp),
          baseRevision: exactU64(baseRevision, 'Skills base revision'),
          value: skillsChangeFromBridge(value),
        ),
    };

SkillsFrame skillsFrameFromBridge(native.BridgeSkillsFrame value) =>
    switch (value) {
      native.BridgeSkillsFrame_Data(:final deliverySequence, :final event) =>
        SkillsFrame.data(
          deliverySequence: exactU64(
            deliverySequence,
            'Skills delivery sequence',
          ),
          event: skillsEventFromBridge(event),
        ),
      native.BridgeSkillsFrame_ResyncRequired(:final identity, :final reason) =>
        SkillsFrame.resyncRequired(
          identity: productFeedIdentityFromBridge(identity),
          reason: productResyncFromBridge(reason),
        ),
      native.BridgeSkillsFrame_Failure(:final identity, :final error) =>
        SkillsFrame.failure(
          identity: productFeedIdentityFromBridge(identity),
          error: bridgeFailure(error),
        ),
      native.BridgeSkillsFrame_Closed(:final identity, :final reason) =>
        SkillsFrame.closed(
          identity: productFeedIdentityFromBridge(identity),
          reason: productClosedFromBridge(reason),
        ),
    };
