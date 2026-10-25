import '../../../models_ports.dart'
    show ModelInputCapabilityReadPage, ModelInputSourceReadPage;
import '../../../resources.dart';
import '../../../resources_ports.dart'
    show FeedConnection, ProductSourceStatusReadConnection;
import '../domain/configuration_state.dart';
import '../domain/start_route_values.dart';
import 'configuration_commands.dart';
import 'configuration_frames.dart';
import 'configuration_read_pages.dart';
import 'configuration_reads.dart';
import 'profile_reads.dart';

abstract interface class ConfigurationPort {
  Future<FeedConnection<ConfigurationFrame>> openConfiguration();
  Future<FeedConnection<AgentProfilesFrame>> openAgentProfiles();
  Future<ConfigurationReadConnection> openConfigurationRead(
    ConfigurationReadRef reference, {
    required ProductReadOrigin origin,
  });
  Future<ConfigurationRoleReadConnection> openRoleRead(
    ConfigurationRoleReadTarget target,
  );
  Future<ConfigurationStartReadConnection> openStartRead(
    ConfigurationRoleReadTarget sources,
  );
  Future<AgentProfilesReadConnection> openAgentProfilesRead(
    AgentProfilesReadRef reference, {
    required ProductReadOrigin origin,
  });
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  });
  // Begin rejection is admission rejection (no call was created). Once a call
  // is admitted, business failures, including CAS rejection, belong to result.
  Future<ConfigurationCommandCall> saveAccount(UpdateAccountRequest request);
  Future<ConfigurationCommandCall> setDefaultAccount(
    SetDefaultAccountRequest request,
  );
  Future<ConfigurationCommandCall> removeAccount(RemoveAccountRequest request);
  Future<ConfigurationCommandCall> removeAccountModel(
    RemoveAccountModelRequest request,
  );
  Future<ConfigurationCommandCall> setAccountModelEnabled(
    SetAccountModelEnabledRequest request,
  );
  Future<ConfigurationCommandCall> setAccountBillingKind(
    SetAccountBillingKindRequest request,
  );
  Future<ConfigurationCommandCall> applyField(
    UpdateSettingsFieldRequest request,
  );
  Future<ConfigurationCommandCall> setPermission(
    UpdatePermissionSettingsRequest request,
  );
  Future<ConfigurationCommandCall?> findConfigurationCommand(
    OperationId operationId,
  );
  Future<ProfileCommandCall> saveProfile(SaveProfileRequest request);
  Future<ProfileCommandCall> setSystemProfileEnabled(
    SetSystemProfileEnabledRequest request,
  );
  Future<ProfileCommandCall?> findProfileCommand(OperationId operationId);
  Future<ConfigurationReloadCall> reload(ConfigurationReloadRequest request);
  Future<ConfigurationReloadCall?> findConfigurationReload(
    OperationId operationId,
  );
}

/// One native invocation, retaining its original commit materials until close.
/// result observes that invocation; it never begins another mutation. callId is
/// independent of the business OperationId and is the FeedCloseReport.feedId.
abstract interface class ConfigurationCommandCall {
  String get callId;
  OperationId get operationId;
  Future<ConfigurationCommandReply> result();
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

/// Profile saves/settings retain the original receipt and all three materials.
/// Admission, result failure and callId/close rules match ConfigurationCommandCall.
abstract interface class ProfileCommandCall {
  String get callId;
  OperationId get operationId;
  Future<ProfileCommandReply> result();
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

/// A real reload invocation, not a save transaction or a fabricated receipt.
/// Admission, result failure and callId/close rules match ConfigurationCommandCall.
abstract interface class ConfigurationReloadCall {
  String get callId;
  OperationId get operationId;
  Future<ConfigurationReloadResult> result();
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class ConfigurationReadConnection {
  Future<ConfigurationReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  Future<ConfigurationEntryPage> entries({int offset = 0, int limit = 32});
  Future<ConfigurationEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupAccount(String accountId);
  Future<AccountConfigurationReadPage> accounts(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<CustomModelConfigurationReadPage> customModels(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelConnectionReadPage> modelConnections(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelAutoCompactReadPage> autoCompactOverrides(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModeModelRouteReadPage> modeRoutes(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<RoleModelRouteReadPage> roleRoutes(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<McpConfigurationReadPage> mcpConfigs(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<TextReadPage> strings(int listId, {int offset = 0, int limit = 32});
  Future<ModelInputCapabilityReadPage> inputCapabilities(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ModelInputSourceReadPage> inputSources(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class ConfigurationRoleReadConnection {
  Future<ConfigurationRoleReadTarget> header();
  Future<RoleRouteRead> roleRoute(String roleId);
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

/// A real Configuration paired scope, sharing its original 8 scopes/64 calls.
/// Native validates/pins sources.reference and all original targets/clocks;
/// this is not roleRoute, a latest settings read or a ModeCatalog transaction.
abstract interface class ConfigurationStartReadConnection {
  Future<ConfigurationRoleReadTarget> header();
  Future<StartRouteRead> resolve(StartRouteQuery query);
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class AgentProfilesReadConnection {
  Future<AgentProfilesReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  Future<AgentProfilesEntryPage> entries({int offset = 0, int limit = 32});
  Future<AgentProfilesEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupProfile(String profileId);
  Future<AgentProfileReadPage> profiles(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<ProfileDiagnosticReadPage> diagnostics(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
