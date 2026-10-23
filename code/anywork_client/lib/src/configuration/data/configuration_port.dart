import '../../../models_ports.dart' show ModelInputCapabilityReadPage, ModelInputSourceReadPage;
import '../../../resources.dart';
import '../../../resources_ports.dart' show FeedConnection, ProductSourceStatusReadConnection;
import '../domain/configuration_state.dart';
import 'configuration_commands.dart';
import 'configuration_frames.dart';
import 'configuration_read_pages.dart';
import 'configuration_reads.dart';
import 'profile_reads.dart';

abstract interface class ConfigurationPort {
  Future<FeedConnection<ConfigurationFrame>> openConfiguration();
  Future<FeedConnection<AgentProfilesFrame>> openAgentProfiles();
  Future<ConfigurationReadConnection> openConfigurationRead(ConfigurationReadRef reference, {required ProductReadOrigin origin});
  Future<ConfigurationRoleReadConnection> openRoleRead(ConfigurationRoleReadTarget target);
  Future<AgentProfilesReadConnection> openAgentProfilesRead(AgentProfilesReadRef reference, {required ProductReadOrigin origin});
  Future<ProductSourceStatusReadConnection> openSourceStatus(ProductSourceStatusRef reference, {required ProductReadOrigin origin});
  Future<ConfigurationCommandReply> saveAccount(UpdateAccountRequest request);
  Future<ConfigurationCommandReply> setDefaultAccount(SetDefaultAccountRequest request);
  Future<ConfigurationCommandReply> removeAccount(RemoveAccountRequest request);
  Future<ConfigurationCommandReply> removeAccountModel(RemoveAccountModelRequest request);
  Future<ConfigurationCommandReply> applyField(UpdateSettingsFieldRequest request);
  Future<ConfigurationCommandReply> setPermission(UpdatePermissionSettingsRequest request);
  Future<ProfileCommandReply> saveProfile(SaveProfileRequest request);
  Future<ProfileCommandReply> setSystemProfileEnabled(SetSystemProfileEnabledRequest request);
  Future<ConfigurationReloadResult> reload({required int expectedRevision});
}

abstract interface class ConfigurationReadConnection {
  Future<ConfigurationReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  Future<ConfigurationEntryPage> entries({int offset = 0, int limit = 32});
  Future<ConfigurationEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupAccount(String accountId);
  Future<AccountConfigurationReadPage> accounts(int listId, {int offset = 0, int limit = 32});
  Future<CustomModelConfigurationReadPage> customModels(int listId, {int offset = 0, int limit = 32});
  Future<ModelConnectionReadPage> modelConnections(int listId, {int offset = 0, int limit = 32});
  Future<ModelAutoCompactReadPage> autoCompactOverrides(int listId, {int offset = 0, int limit = 32});
  Future<ModeModelRouteReadPage> modeRoutes(int listId, {int offset = 0, int limit = 32});
  Future<RoleModelRouteReadPage> roleRoutes(int listId, {int offset = 0, int limit = 32});
  Future<McpConfigurationReadPage> mcpConfigs(int listId, {int offset = 0, int limit = 32});
  Future<TextReadPage> strings(int listId, {int offset = 0, int limit = 32});
  Future<ModelInputCapabilityReadPage> inputCapabilities(int listId, {int offset = 0, int limit = 32});
  Future<ModelInputSourceReadPage> inputSources(int listId, {int offset = 0, int limit = 32});
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

abstract interface class AgentProfilesReadConnection {
  Future<AgentProfilesReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  Future<AgentProfilesEntryPage> entries({int offset = 0, int limit = 32});
  Future<AgentProfilesEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupProfile(String profileId);
  Future<AgentProfileReadPage> profiles(int listId, {int offset = 0, int limit = 32});
  Future<ProfileDiagnosticReadPage> diagnostics(int listId, {int offset = 0, int limit = 32});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
