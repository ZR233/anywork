import 'dart:async';

import '../../../models_ports.dart' show ModelCatalogTargetReceiver;
import '../../../operations.dart';
import '../../../operations_ports.dart' show OperationRecorder;
import '../../../resources.dart';
import '../../../resources_ports.dart';
import '../domain/account_edits.dart';
import '../domain/configuration_repository.dart';
import '../domain/configuration_state.dart';
import '../domain/configuration_values.dart';
import '../domain/profile_values.dart';
import '../domain/settings_updates.dart';
import 'configuration_mirror.dart';
import 'configuration_port.dart';
import 'configuration_read_fields.dart';
import 'configuration_write_context.dart';
import 'configuration_writes.dart';
import 'profiles_mirror.dart';

/// Only this factory is exported from configuration_ports. All canonical
/// publishers, read owners and the Settings lane remain domain-private.
ConfigurationRepository createConfigurationRepository({required ConfigurationPort port, required ResourceBudget budget, required OperationRecorder operations, required ModelCatalogTargetReceiver modelTargets}) => _ConfigurationRepository(port, budget, operations, modelTargets);

final class _ConfigurationRepository implements ConfigurationRepository, ConfigurationWriteHost {
  _ConfigurationRepository(ConfigurationPort port, ResourceBudget budget, OperationRecorder operations, ModelCatalogTargetReceiver modelTargets) : lifetime = ResourceLifetime(budget) {
    configuration = ConfigurationMirror(port, lifetime, operations);
    profileCatalog = ProfilesMirror(port, lifetime, operations);
    writes = ConfigurationWrites(port: port, host: this, operations: operations, modelTargets: modelTargets, budget: budget);
  }

  final ResourceLifetime lifetime;
  late final ConfigurationMirror configuration;
  late final ProfilesMirror profileCatalog;
  late final ConfigurationWrites writes;
  bool _sealed = false;
  bool _sourcesClosed = false;

  @override
  ReadonlyLatestValue<ConfigurationState> get state => configuration.source.readonly;
  @override
  ReadonlyLatestValue<ProfilesState> get profiles => profileCatalog.source.readonly;
  @override
  bool get sealed => _sealed || lifetime.sealed;
  @override
  void admit() { if (_sealed) throw configurationCancelled; lifetime.admit(); }
  @override
  Future<T> supervise<T>(String owner, Future<T> Function() work) => lifetime.run(owner, work);
  @override
  void retainFailure(Object error, StackTrace stack) { lifetime.lastCause = error; lifetime.lastStack = stack; }
  @override
  Future<({ProductReadOrigin origin, int revision})> currentWriteBase() => configuration.writeBase();
  @override
  Future<({ProductReadOrigin origin, int revision, AccountConfiguration? account})> accountWriteBase(String accountId) => configuration.accountBase(accountId);
  @override
  Future<void> recoverCanonicalRead() async {
    await configuration.resync(retry: true);
    // Pure source recovery only. The next lane attempt constructs its request
    // from this current canonical source, never from an old UI snapshot.
    await configuration.writeBase();
  }
  @override
  Future<void> synchronizeConfiguration(ConfigurationReadTarget target, {CommitReceipt? receipt}) => configuration.synchronize(target, receipt: receipt);
  @override
  Future<void> synchronizeProfiles(AgentProfilesReadTarget target, {CommitReceipt? receipt}) => profileCatalog.synchronize(target, receipt: receipt);

  @override
  Future<void> loadSourceStatus() { admit(); return configuration.loadStatus(); }
  @override
  Future<void> loadProfilesSourceStatus() { admit(); return profileCatalog.loadStatus(); }
  @override
  Future<void> loadAccountsPage({int limit = 32}) { admit(); return configuration.page(limit: limit); }
  @override
  Future<void> loadProfilesPage({int limit = 32}) { admit(); return profileCatalog.page(limit: limit); }
  @override
  Future<String?> loadDefaultAccountId() { admit(); return configuration.fields.defaults(); }
  @override
  Future<List<ModeModelRoute>> loadModeRoutes() { admit(); return configuration.fields.modeRoutes(); }
  @override
  Future<List<RoleModelRoute>> loadRoleRoutes() { admit(); return configuration.fields.roleRoutes(); }
  @override
  Future<RoleRouteRead> roleRoute({required ConfigurationRoleReadTarget target, required String roleId}) { admit(); return configuration.roleRoute(target: target, roleId: roleId); }
  @override
  Future<String> loadPermissionMode() { admit(); return configuration.fields.permission(); }
  @override
  Future<List<McpConfiguration>> loadMcpConfigurations() { admit(); return configuration.fields.mcp(); }
  @override
  Future<List<ProfileDiagnostic>> loadProfileDiagnostics() { admit(); return profileCatalog.diagnostics(); }
  @override
  Future<AccountConfiguration> loadAccount(String accountId) {
    admit();
    return configuration.account(accountId).then((value) => value ?? (throw const StudioFailure(code: StudioFailureCode.notFound, message: 'The requested account does not exist in this configuration.', retryable: false, correlationId: 'configuration')));
  }
  @override
  Future<InstructionsSettings> loadInstructions() { admit(); return configuration.fields.instructions(); }
  @override
  Future<SkillsSettings> loadSkillsSettings() { admit(); return configuration.fields.skills(); }
  @override
  Future<GeneralSettings> loadGeneralSettings() { admit(); return configuration.fields.general(); }
  @override
  Future<WebSearchConfiguration> loadWebSearchSettings() { admit(); return configuration.fields.webSearch(); }
  @override
  Future<DeepSeekSearchConfiguration> loadDeepSeekSettings() { admit(); return configuration.fields.deepSeekSearch(); }
  @override
  Future<AgentProfileSnapshot> loadProfile(String profileId) { admit(); return profileCatalog.detail(profileId); }

  @override
  OperationTicket<Unit> saveAccount(AccountEdit intent) => writes.saveAccount(intent);
  @override
  OperationTicket<Unit> setDefaultAccount(String accountId) => writes.setDefaultAccount(accountId);
  @override
  OperationTicket<Unit> removeAccount(String accountId, {String? replacementAccountId}) => writes.removeAccount(accountId, replacementAccountId: replacementAccountId);
  @override
  OperationTicket<Unit> removeAccountModel(String accountId, String modelId) => writes.removeAccountModel(accountId, modelId);
  @override
  OperationTicket<Unit> applyField(SettingsFieldUpdate update) => writes.applyField(update);
  @override
  SettingsWriteBatch applyFields(List<SettingsFieldUpdate> updates) => writes.applyFields(updates);
  @override
  OperationTicket<Unit> setPermissionMode(PermissionMode mode) => writes.setPermissionMode(mode);
  @override
  OperationTicket<Unit> saveProfile(AgentProfileEdit profile) => writes.saveProfile(profile);
  @override
  OperationTicket<Unit> setSystemProfileEnabled(String profileId, bool enabled) => writes.setSystemProfileEnabled(profileId, enabled);
  @override
  OperationTicket<Unit> reload() => writes.reload();

  @override
  void seal() { _sealed = true; writes.seal(); }
  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) => _close(deadline, true);

  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    seal();
    // Keep the original admitted lane's read/feed dependencies alive while it
    // settles. A deadline cancels that wait, never reopens lifetime admission.
    if (deadline == null) { await writes.join(); } else {
      final expired = Completer<void>(); final remaining = deadline.difference(DateTime.now());
      final timer = Timer(remaining.isNegative ? Duration.zero : remaining, () => expired.complete());
      try { await Future.any([writes.join(), expired.future]); } finally { timer.cancel(); }
    }
    final resources = await lifetime.close(deadline: deadline, retry: retry);
    final unresolved = [...resources.unresolved, ...writes.unresolved];
    if (unresolved.isEmpty && !_sourcesClosed) {
      _sourcesClosed = true;
      const closed = ResourceSyncState(phase: ResourceSyncPhase.closed, error: null, retryExhausted: false);
      configuration.source.publish(configuration.source.value.copyWith(projection: configuration.source.value.projection.copyWith(sync: closed)));
      profileCatalog.source.publish(profileCatalog.source.value.copyWith(projection: profileCatalog.source.value.projection.copyWith(sync: closed)));
      configuration.source.close(); profileCatalog.source.close();
    }
    return CloseReport(unresolved: unresolved);
  }
}
