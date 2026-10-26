import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/configuration_acp_commands.dart'
    as acp;
import '../../../../rust/api/studio/products/read/configuration_commands.dart'
    as native;
import '../../../../rust/api/studio/products/read/profile_commands.dart'
    as profile;
import '../../../../rust/api/studio/types/command.dart' as command;
import '../../shared/receipt_converters.dart';
import '../catalog_references.dart';
import 'call_failures.dart';

CommitReceipt _confirmedReceipt(
  command.BridgeStudioCommandReceipt value,
  OperationId operation,
) {
  // The original call is verified and its native outcome already confirms the
  // commit. A bad nested identity makes this receipt unusable, not unknown.
  try {
    requireConfigurationOperation(value.operationId, operation);
    return commitReceiptFromBridge(value);
  } on Object catch (error) {
    throw CommandDispatchFailure.confirmedWithoutUsableReceipt(
      failure: configurationCallFailure(error),
    );
  }
}

ConfigurationCommandReply _configurationReply(
  native.BridgeConfigurationCommandReply value,
  OperationId operation,
) {
  final receipt = _confirmedReceipt(value.receipt, operation);
  try {
    return ConfigurationCommandReply(
      receipt: receipt,
      configuration: configurationTargetFromBridge(value.configuration),
      models: modelCatalogTargetFromBridge(value.models),
    );
  } on Object catch (error) {
    throw CommandDispatchFailure.committedButUnobserved(
      receipt: receipt,
      failure: configurationCallFailure(error),
    );
  }
}

ConfigurationCommandReply configurationOutcomeFromBridge(
  native.BridgeConfigurationCommandOutcome value,
  OperationId operation,
) => switch (value) {
  native.BridgeConfigurationCommandOutcome_Committed(:final reply) =>
    _configurationReply(reply, operation),
  native.BridgeConfigurationCommandOutcome_CommittedButUnobserved(
    :final receipt,
    :final error,
  ) =>
    throw CommandDispatchFailure.committedButUnobserved(
      receipt: _confirmedReceipt(receipt, operation),
      failure: configurationCallFailure(error),
    ),
  native.BridgeConfigurationCommandOutcome_Rejected(
    :final operationId,
    :final error,
  ) =>
    _rejected(operationId, operation, error),
  native.BridgeConfigurationCommandOutcome_Unknown(
    :final operationId,
    :final error,
  ) =>
    _unknown(operationId, operation, error),
};

/// ACP 提交只携带真实 Settings 回执与本次提交捕获的配置读取目标。
///
/// 提交后的目标映射失败保留真实回执（`committedButUnobserved`），回执本身不可用则是
/// `confirmedWithoutUsableReceipt`；只有原生 typed `Rejected` 才是拒绝，普通调用异常由
/// 调用方归为 `unknownOutcome`（design 25.19.4）。
AcpAccountCommandReply acpAccountOutcomeFromBridge(
  acp.BridgeAcpAccountCommandOutcome value,
  OperationId operation,
) => switch (value) {
  acp.BridgeAcpAccountCommandOutcome_Committed(:final reply) =>
    _acpAccountReply(reply, operation),
  acp.BridgeAcpAccountCommandOutcome_CommittedButUnobserved(
    :final receipt,
    :final error,
  ) =>
    throw CommandDispatchFailure.committedButUnobserved(
      receipt: _confirmedReceipt(receipt, operation),
      failure: configurationCallFailure(error),
    ),
  acp.BridgeAcpAccountCommandOutcome_Rejected(
    :final operationId,
    :final error,
  ) =>
    _rejected(operationId, operation, error),
  acp.BridgeAcpAccountCommandOutcome_Unknown(
    :final operationId,
    :final error,
  ) =>
    _unknown(operationId, operation, error),
};

AcpAccountCommandReply _acpAccountReply(
  acp.BridgeAcpAccountCommandReply value,
  OperationId operation,
) {
  final receipt = _confirmedReceipt(value.receipt, operation);
  try {
    return AcpAccountCommandReply(
      receipt: receipt,
      configuration: configurationTargetFromBridge(value.configuration),
    );
  } on Object catch (error) {
    throw CommandDispatchFailure.committedButUnobserved(
      receipt: receipt,
      failure: configurationCallFailure(error),
    );
  }
}

ProfileCommandReply _profileReply(
  profile.BridgeProfileCommandReply value,
  OperationId operation,
) {
  final receipt = _confirmedReceipt(value.receipt, operation);
  try {
    return ProfileCommandReply(
      receipt: receipt,
      configuration: configurationTargetFromBridge(value.configuration),
      models: modelCatalogTargetFromBridge(value.models),
      profiles: profilesTargetFromBridge(value.profiles),
    );
  } on Object catch (error) {
    throw CommandDispatchFailure.committedButUnobserved(
      receipt: receipt,
      failure: configurationCallFailure(error),
    );
  }
}

ProfileCommandReply profileOutcomeFromBridge(
  profile.BridgeProfileCommandOutcome value,
  OperationId operation,
) => switch (value) {
  profile.BridgeProfileCommandOutcome_Committed(:final reply) => _profileReply(
    reply,
    operation,
  ),
  profile.BridgeProfileCommandOutcome_CommittedButUnobserved(
    :final receipt,
    :final error,
  ) =>
    throw CommandDispatchFailure.committedButUnobserved(
      receipt: _confirmedReceipt(receipt, operation),
      failure: configurationCallFailure(error),
    ),
  profile.BridgeProfileCommandOutcome_ConfirmedWithoutUsableReceipt(
    :final operationId,
    :final error,
  ) =>
    _confirmedWithoutReceipt(operationId, operation, error),
  profile.BridgeProfileCommandOutcome_Rejected(
    :final operationId,
    :final error,
  ) =>
    _rejected(operationId, operation, error),
  profile.BridgeProfileCommandOutcome_Unknown(
    :final operationId,
    :final error,
  ) =>
    _unknown(operationId, operation, error),
};

ConfigurationReloadResult _reloadResult(
  String operationId,
  profile.BridgeConfigurationReloadResult value,
  OperationId operation,
) {
  try {
    requireConfigurationOperation(operationId, operation);
    // A normal reload has no receipt; only these original three read targets.
    return ConfigurationReloadResult(
      configuration: configurationTargetFromBridge(value.configuration),
      models: modelCatalogTargetFromBridge(value.models),
      profiles: profilesTargetFromBridge(value.profiles),
    );
  } on Object catch (error) {
    throw CommandDispatchFailure.confirmedWithoutUsableReceipt(
      failure: configurationCallFailure(error),
    );
  }
}

ConfigurationReloadResult reloadOutcomeFromBridge(
  profile.BridgeConfigurationReloadOutcome value,
  OperationId operation,
) => switch (value) {
  profile.BridgeConfigurationReloadOutcome_Returned(
    :final operationId,
    :final result,
  ) =>
    _reloadResult(operationId, result, operation),
  profile.BridgeConfigurationReloadOutcome_AdoptedButUnobserved(
    :final operationId,
    :final error,
  ) =>
    _confirmedWithoutReceipt(operationId, operation, error),
  profile.BridgeConfigurationReloadOutcome_Rejected(
    :final operationId,
    :final error,
  ) =>
    _rejected(operationId, operation, error),
  profile.BridgeConfigurationReloadOutcome_Unknown(
    :final operationId,
    :final error,
  ) =>
    _unknown(operationId, operation, error),
};

Never _rejected(String actual, OperationId expected, Object error) {
  requireConfigurationOperation(actual, expected);
  throw CommandDispatchFailure.rejected(
    failure: configurationCallFailure(error),
  );
}

Never _unknown(String actual, OperationId expected, Object error) {
  requireConfigurationOperation(actual, expected);
  throw CommandDispatchFailure.unknownOutcome(
    failure: configurationCallFailure(error),
  );
}

Never _confirmedWithoutReceipt(
  String actual,
  OperationId expected,
  Object error,
) {
  try {
    requireConfigurationOperation(actual, expected);
  } on Object catch (validationError) {
    throw CommandDispatchFailure.confirmedWithoutUsableReceipt(
      failure: configurationCallFailure(validationError),
    );
  }
  throw CommandDispatchFailure.confirmedWithoutUsableReceipt(
    failure: configurationCallFailure(error),
  );
}
