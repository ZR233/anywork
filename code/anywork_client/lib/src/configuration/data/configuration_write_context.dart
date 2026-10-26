import '../../../models.dart' show ModelCatalogReadTarget;
import '../../../operations.dart';
import '../../../resources.dart';
import '../../../resources_ports.dart' show ResourceLifetime;
import '../domain/configuration_state.dart';
import '../domain/configuration_values.dart';
import 'configuration_commands.dart';

/// Business-local hooks implemented by the concrete Configuration repository.
/// These are not exported ports or a facade. The host owns the real supervised
/// work, pins and canonical writers; the write lane owns frozen command jobs.
abstract interface class ConfigurationWriteHost {
  bool get sealed;
  ResourceLifetime get lifetime;

  /// Completion/identity of the original public cleanup, not a new admission.
  /// A caller's deadline does not end this attempt or permit another retry.
  Future<void>? get cleanupAttempt;
  void admit();
  Future<T> supervise<T>(String owner, Future<T> Function() work);
  Future<({ProductReadOrigin origin, int revision})> currentWriteBase();
  Future<
    ({ProductReadOrigin origin, int revision, AccountConfiguration? account})
  >
  accountWriteBase(String accountId);
  Future<void> recoverCanonicalRead();
  Future<void> synchronizeConfiguration(
    ConfigurationReadTarget target, {
    CommitReceipt? receipt,
  });
  Future<void> synchronizeProfiles(
    AgentProfilesReadTarget target, {
    CommitReceipt? receipt,
  });

  /// Settings 写入没有 configuration/models 读目标时，等待 settings topic 覆盖真实回执。
  Future<void> observeSettings(CommitReceipt receipt);

  /// 消费 ACP 账号写入捕获的原配置目标：完整读取该固定目标的 ACP 目录页并校验行集。
  ///
  /// 必须在原调用关闭前完成；失败保留已确定的提交证据，不退化为重新保存。
  /// This is the only boundary that observes such a write: it also waits for
  /// the real Settings receipt, so a caller must not observe that receipt again
  /// and open a second owner-replacement window.
  Future<void> consumeAcpAccountTarget(
    ConfigurationReadTarget target, {
    required CommitReceipt receipt,
  });
  void retainFailure(Object error, StackTrace stack);
}

/// Only the typed native reply shapes of this domain are folded here; it
/// carries no settings snapshot, JSON or heterogeneous business payload. A
/// Settings-only write leaves the configuration/models read targets null
/// instead of inventing them.
final class ConfigurationWriteReply {
  const ConfigurationWriteReply({
    required this.receipt,
    required this.configuration,
    required this.models,
    required this.profiles,
    required this.acpConfiguration,
  });
  factory ConfigurationWriteReply.settings(ConfigurationCommandReply value) =>
      ConfigurationWriteReply(
        receipt: value.receipt,
        configuration: value.configuration,
        models: value.models,
        profiles: null,
        acpConfiguration: null,
      );
  factory ConfigurationWriteReply.profile(ProfileCommandReply value) =>
      ConfigurationWriteReply(
        receipt: value.receipt,
        configuration: value.configuration,
        models: value.models,
        profiles: value.profiles,
        acpConfiguration: null,
      );
  factory ConfigurationWriteReply.reload(ConfigurationReloadResult value) =>
      ConfigurationWriteReply(
        receipt: null,
        configuration: value.configuration,
        models: value.models,
        profiles: value.profiles,
        acpConfiguration: null,
      );

  /// 一次 ACP 账号写入只带真实 Settings 回执与本次提交捕获的配置读取目标。
  ///
  /// 它不是 configuration+models 双目标事务：`configuration`/`models` 保持 null（不
  /// 伪造 Settings 读目标或模型目录回执），ACP 目录改从 [acpConfiguration] 这份原目标
  /// 读取；材料版本与 Settings revision 相互独立，不能互相顶替。
  factory ConfigurationWriteReply.acpAccount(AcpAccountCommandReply value) =>
      ConfigurationWriteReply(
        receipt: value.receipt,
        configuration: null,
        models: null,
        profiles: null,
        acpConfiguration: value.configuration,
      );

  final CommitReceipt? receipt;
  final ConfigurationReadTarget? configuration;
  final ModelCatalogReadTarget? models;
  final AgentProfilesReadTarget? profiles;

  /// ACP 账号写入捕获的配置读取目标；只有该写入种类携带。
  final ConfigurationReadTarget? acpConfiguration;
}
