import 'package:freezed_annotation/freezed_annotation.dart';

import '../../configuration/domain/config_projection_stamp.dart';
import 'thread_identity.dart';

part 'configuration_values.freezed.dart';

enum ThreadCapabilitySupport { unsupported }

@freezed
abstract class ModelRouteBrief with _$ModelRouteBrief {
  const factory ModelRouteBrief({
    required int revision,
    required bool available,
    required bool hasUnavailableReason,
  }) = _ModelRouteBrief;
}

@Freezed(toStringOverride: false)
abstract class ThreadModelRoute with _$ThreadModelRoute {
  const factory ThreadModelRoute({
    required String? botId,
    required String accountId,
    required String modelId,
    required String? effort,
    required int revision,
    required bool available,
    required String? unavailableReason,
  }) = _ThreadModelRoute;
}

@freezed
abstract class ThreadConfigurationValue with _$ThreadConfigurationValue {
  const factory ThreadConfigurationValue({
    required ThreadConfigurationReadRef details,
    required ConfigProjectionStamp sources,
    required int modeRevision,
    required int? modeBindingRevision,
    required ModelRouteBrief? modelRoute,
    required int activeSkillCount,
    required ThreadCapabilitySupport activeMcp,
    required ThreadCapabilitySupport activeLsp,
    required ThreadCapabilitySupport mcpHealth,
  }) = _ThreadConfigurationValue;
}
