import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/read/configuration_commands.dart'
    as native;
import '../../../../rust/api/studio/products/read/profile_commands.dart'
    as profile;
import '../../shared/adapter_failure.dart';
import 'call_failures.dart';
import 'command_inputs.dart';
import 'configuration_command_call.dart';
import 'configuration_feeds.dart';
import 'configuration_read_connection.dart';
import 'configuration_reload_call.dart';
import 'paired_read_connections.dart';
import 'profile_command_call.dart';
import 'profiles_read_connection.dart';
import 'scalar_values.dart';
import 'source_status_connection.dart';

/// Production transport leaf. Construction starts no source/reload/probe and
/// owns no Repository state. The App supplies the SDK budget/recorder/Models
/// receiver when assembling createConfigurationRepository around this port.
final class FrbConfigurationPort implements ConfigurationPort {
  const FrbConfigurationPort();

  @override
  Future<FeedConnection<ConfigurationFrame>> openConfiguration() async {
    final connection = FrbConfigurationConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<FeedConnection<AgentProfilesFrame>> openAgentProfiles() async {
    final connection = FrbAgentProfilesConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<ConfigurationReadConnection> openConfigurationRead(
    ConfigurationReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbConfigurationReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<ConfigurationRoleReadConnection> openRoleRead(
    ConfigurationRoleReadTarget target,
  ) async {
    final connection = FrbConfigurationRoleReadConnection(target);
    await connection.opened;
    return connection;
  }

  @override
  Future<ConfigurationStartReadConnection> openStartRead(
    ConfigurationRoleReadTarget sources,
  ) async {
    final connection = FrbConfigurationStartReadConnection(sources);
    await connection.opened;
    return connection;
  }

  @override
  Future<AgentProfilesReadConnection> openAgentProfilesRead(
    AgentProfilesReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbAgentProfilesReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbConfigurationSourceStatusConnection(
      reference,
      origin,
    );
    await connection.opened;
    return connection;
  }

  @override
  Future<ConfigurationCommandCall> saveAccount(UpdateAccountRequest request) =>
      _beginConfiguration(
        request.operationId,
        request.expectedRevision,
        () => native.BridgeConfigurationMutation.saveAccount(
          input: configurationAccountToBridge(request.account),
        ),
      );
  @override
  Future<ConfigurationCommandCall> setDefaultAccount(
    SetDefaultAccountRequest request,
  ) => _beginConfiguration(
    request.operationId,
    request.expectedRevision,
    () => native.BridgeConfigurationMutation.setDefaultAccount(
      accountId: request.accountId,
    ),
  );
  @override
  Future<ConfigurationCommandCall> removeAccount(
    RemoveAccountRequest request,
  ) => _beginConfiguration(
    request.operationId,
    request.expectedRevision,
    () => native.BridgeConfigurationMutation.removeAccount(
      accountId: request.accountId,
      replacementAccountId: request.replacementAccountId,
    ),
  );
  @override
  Future<ConfigurationCommandCall> removeAccountModel(
    RemoveAccountModelRequest request,
  ) => _beginConfiguration(
    request.operationId,
    request.expectedRevision,
    () => native.BridgeConfigurationMutation.removeAccountModel(
      accountId: request.accountId,
      modelId: request.modelId,
    ),
  );
  @override
  Future<ConfigurationCommandCall> setAccountModelEnabled(
    SetAccountModelEnabledRequest request,
  ) => _beginConfiguration(
    request.operationId,
    request.expectedRevision,
    () => native.BridgeConfigurationMutation.setAccountModelEnabled(
      accountId: request.accountId,
      modelId: request.modelId,
      enabled: request.enabled,
    ),
  );
  @override
  Future<ConfigurationCommandCall> setAccountBillingKind(
    SetAccountBillingKindRequest request,
  ) => _beginConfiguration(
    request.operationId,
    request.expectedRevision,
    () => native.BridgeConfigurationMutation.setAccountBillingKind(
      accountId: request.accountId,
      billingKind: request.billingKind == null
          ? null
          : configurationBillingToBridge(request.billingKind!),
    ),
  );
  @override
  Future<ConfigurationCommandCall> applyField(
    UpdateSettingsFieldRequest request,
  ) => _beginConfiguration(
    request.operationId,
    request.expectedRevision,
    () => native.BridgeConfigurationMutation.applyField(
      update: configurationFieldToBridge(request.update),
    ),
  );
  @override
  Future<ConfigurationCommandCall> setPermission(
    UpdatePermissionSettingsRequest request,
  ) => _beginConfiguration(
    request.operationId,
    request.expectedRevision,
    () => native.BridgeConfigurationMutation.setPermission(mode: request.mode),
  );

  Future<ConfigurationCommandCall> _beginConfiguration(
    OperationId operation,
    int revision,
    native.BridgeConfigurationMutation Function() mutation,
  ) async {
    final request = _prepare(
      () => configurationRequestToBridge(operation, revision, mutation()),
    );
    final call = FrbConfigurationCommandCall.begin(operation, request);
    if (!await call.opened) {
      throw configurationUnknownFailure(
        adapterProtocol('configuration-command-missing-begin'),
      );
    }
    return call;
  }

  @override
  Future<ConfigurationCommandCall?> findConfigurationCommand(
    OperationId operationId,
  ) async {
    final call = FrbConfigurationCommandCall.find(operationId);
    return await call.opened ? call : null;
  }

  @override
  Future<ProfileCommandCall> saveProfile(SaveProfileRequest request) =>
      _beginProfile(request.operationId, () => saveProfileToBridge(request));
  @override
  Future<ProfileCommandCall> setSystemProfileEnabled(
    SetSystemProfileEnabledRequest request,
  ) => _beginProfile(
    request.operationId,
    () => systemProfileEnabledToBridge(request),
  );
  Future<ProfileCommandCall> _beginProfile(
    OperationId operation,
    profile.BridgeProfileCommandRequest Function() build,
  ) async {
    final request = _prepare(build);
    final call = FrbProfileCommandCall.begin(operation, request);
    if (!await call.opened) {
      throw configurationUnknownFailure(
        adapterProtocol('profile-command-missing-begin'),
      );
    }
    return call;
  }

  @override
  Future<ProfileCommandCall?> findProfileCommand(
    OperationId operationId,
  ) async {
    final call = FrbProfileCommandCall.find(operationId);
    return await call.opened ? call : null;
  }

  @override
  Future<ConfigurationReloadCall> reload(
    ConfigurationReloadRequest request,
  ) async {
    final input = _prepare(() => configurationReloadToBridge(request));
    final call = FrbConfigurationReloadCall.begin(request.operationId, input);
    if (!await call.opened) {
      throw configurationUnknownFailure(
        adapterProtocol('configuration-reload-missing-begin'),
      );
    }
    return call;
  }

  @override
  Future<ConfigurationReloadCall?> findConfigurationReload(
    OperationId operationId,
  ) async {
    final call = FrbConfigurationReloadCall.find(operationId);
    return await call.opened ? call : null;
  }

  // This runs strictly before invoking begin. Local input conversion failure
  // proves no native call was issued, unlike any error in find or result.
  T _prepare<T>(T Function() convert) {
    try {
      return convert();
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        CommandDispatchFailure.rejected(
          failure: configurationCallFailure(error),
        ),
        stack,
      );
    }
  }
}
