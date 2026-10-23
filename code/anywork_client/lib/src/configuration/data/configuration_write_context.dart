import '../../../models.dart' show ModelCatalogReadTarget;
import '../../../operations.dart';
import '../../../resources.dart';
import '../domain/configuration_state.dart';
import '../domain/configuration_values.dart';
import 'configuration_commands.dart';

/// Business-local hooks implemented by the concrete Configuration repository.
/// These are not exported ports or a facade. The host owns the real supervised
/// work, pins and canonical writers; the write lane owns frozen command jobs.
abstract interface class ConfigurationWriteHost {
  bool get sealed;
  void admit();
  Future<T> supervise<T>(String owner, Future<T> Function() work);
  Future<({ProductReadOrigin origin, int revision})> currentWriteBase();
  Future<({ProductReadOrigin origin, int revision, AccountConfiguration? account})> accountWriteBase(String accountId);
  Future<void> recoverCanonicalRead();
  Future<void> synchronizeConfiguration(ConfigurationReadTarget target, {CommitReceipt? receipt});
  Future<void> synchronizeProfiles(AgentProfilesReadTarget target, {CommitReceipt? receipt});
  void retainFailure(Object error, StackTrace stack);
}

/// Only the three typed native reply shapes in this domain are folded here;
/// it carries no settings snapshot, JSON or heterogeneous business payload.
final class ConfigurationWriteReply {
  const ConfigurationWriteReply({required this.receipt, required this.configuration, required this.models, required this.profiles});
  factory ConfigurationWriteReply.settings(ConfigurationCommandReply value) => ConfigurationWriteReply(receipt: value.receipt, configuration: value.configuration, models: value.models, profiles: null);
  factory ConfigurationWriteReply.profile(ProfileCommandReply value) => ConfigurationWriteReply(receipt: value.receipt, configuration: value.configuration, models: value.models, profiles: value.profiles);
  factory ConfigurationWriteReply.reload(ConfigurationReloadResult value) => ConfigurationWriteReply(receipt: null, configuration: value.configuration, models: value.models, profiles: value.profiles);

  final CommitReceipt? receipt;
  final ConfigurationReadTarget configuration;
  final ModelCatalogReadTarget models;
  final AgentProfilesReadTarget? profiles;
}
