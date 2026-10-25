/// ACP 接入的纯领域模型（不依赖 Flutter、Riverpod、FRB 或 transport）。
///
/// 这一层只表达产品语义：接入配置、目录模板、认证操作身份与认证状态。
/// 认证事实的唯一来源是后端 canonical snapshot 与 `acpAuth` 产品 topic；
/// 本层不推断“已登录”，也不从本地布尔值合成成功。
library;

import 'command_receipts.dart';
import 'collection_equality.dart';
import 'collection_extensions.dart';
import 'failure_models.dart';
import 'acp_install_models.dart';

/// 当前阶段支持的 ACP 接入协议。
///
/// wire 值是稳定身份：未知值必须由适配层显式失败，不能退回某个默认协议。
enum AcpProviderView {
  antigravity;

  static const _wire = <AcpProviderView, String>{
    AcpProviderView.antigravity: 'antigravity',
  };

  String get wire => _wire[this]!;

  /// 解析 wire 值；未知协议返回 null，由适配层报错而不是猜测。
  static AcpProviderView? fromWire(String value) {
    for (final entry in _wire.entries) {
      if (entry.value == value) return entry.key;
    }
    return null;
  }
}

/// 后端目录声明的接入模板（显示名、固定受管版本、官方安装说明地址）。
class AcpAccountTemplateView {
  const AcpAccountTemplateView({
    required this.provider,
    required this.displayName,
    this.description = '',
    this.iconKey = '',
    this.supportedVersion = '',
    this.installUrl = '',
    this.termsUrl = '',
    this.automaticInstall = const AcpInstallUnsupportedPlatformView(),
  });

  final AcpProviderView provider;
  final String displayName;
  final String description;
  final String iconKey;

  /// 产品固定的受管服务器版本（当前 1.4.1），由后端模板给出。
  ///
  /// 客户端不硬编码版本，也不允许用户选择：界面只展示这个权威值。
  final String supportedVersion;

  /// 官方安装说明地址；只展示，不从进程输出推导。
  final String installUrl;

  /// 官方服务条款地址；为空表示后端没有提供，界面因此不展示入口。
  final String termsUrl;

  /// 后端声明的自动准备资格与目标平台。
  ///
  /// 缺省是不支持：模板没声明时不能默认替用户启动下载。
  final AcpInstallAvailabilityView automaticInstall;

  /// 模板是否声明了自动准备资格。
  bool get prefersAutomaticInstall => automaticInstall.isAvailable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAccountTemplateView &&
          provider == other.provider &&
          displayName == other.displayName &&
          description == other.description &&
          iconKey == other.iconKey &&
          supportedVersion == other.supportedVersion &&
          installUrl == other.installUrl &&
          termsUrl == other.termsUrl &&
          automaticInstall == other.automaticInstall;

  @override
  int get hashCode => Object.hash(
    provider,
    displayName,
    description,
    iconKey,
    supportedVersion,
    installUrl,
    termsUrl,
    automaticInstall,
  );
}

/// 只读接入目录；空目录表示尚未加载，不能替代已加载的静态事实。
class AcpAccountCatalogView {
  const AcpAccountCatalogView({this.templates = const []});

  const AcpAccountCatalogView.empty() : templates = const [];

  final List<AcpAccountTemplateView> templates;

  bool get isUsable => templates.isNotEmpty;

  AcpAccountTemplateView? template(AcpProviderView provider) =>
      templates.where((template) => template.provider == provider).firstOrNull;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAccountCatalogView && listEquals(templates, other.templates);

  @override
  int get hashCode => Object.hashAll(templates);
}

/// 已保存的 ACP 接入配置。
///
/// 只保存接入身份与显示名：受管服务器的 program/argv 由产品固定发行决定，不是
/// 用户或客户端可编辑的配置。[connectionRevision] 是运行期拥有的连接身份，不是
/// 设置总修订；name 变化不改它。
class AcpAccountSettingsView {
  const AcpAccountSettingsView({
    required this.accountId,
    required this.name,
    required this.provider,
    this.connectionRevision = 0,
  });

  final String accountId;
  final String name;
  final AcpProviderView provider;
  final int connectionRevision;

  AcpAccountSettingsView copyWith({
    String? name,
    AcpProviderView? provider,
    int? connectionRevision,
  }) {
    return AcpAccountSettingsView(
      accountId: accountId,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      connectionRevision: connectionRevision ?? this.connectionRevision,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAccountSettingsView &&
          accountId == other.accountId &&
          name == other.name &&
          provider == other.provider &&
          connectionRevision == other.connectionRevision;

  @override
  int get hashCode =>
      Object.hash(accountId, name, provider, connectionRevision);
}

/// 一次接入配置写入的意图（保存后由后端解析 connectionRevision）。
class AcpAccountUpdateView {
  const AcpAccountUpdateView({
    required this.accountId,
    required this.name,
    required this.provider,
  });

  final String accountId;
  final String name;
  final AcpProviderView provider;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAccountUpdateView &&
          accountId == other.accountId &&
          name == other.name &&
          provider == other.provider;

  @override
  int get hashCode => Object.hash(accountId, name, provider);
}

/// 服务端实际宣告的认证方法类别。
///
/// `unsupported` 表示服务端声明了本实现未支持的方式：不能把它伪装成 `terminal`，
/// 也不能据此发送认证请求。
enum AcpAuthMethodKindView { agent, terminal, unsupported }

class AcpAuthMethodView {
  const AcpAuthMethodView({
    required this.id,
    required this.name,
    required this.kind,
    this.description = '',
  });

  final String id;
  final String name;
  final String description;
  final AcpAuthMethodKindView kind;

  bool get isAgent => kind == AcpAuthMethodKindView.agent;

  bool get isTerminal => kind == AcpAuthMethodKindView.terminal;

  bool get isUnsupported => kind == AcpAuthMethodKindView.unsupported;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAuthMethodView &&
          id == other.id &&
          name == other.name &&
          description == other.description &&
          kind == other.kind;

  @override
  int get hashCode => Object.hash(id, name, description, kind);
}

/// 已观察到的 server 身份；只代表观察当时的事实。
class AcpServerInfoView {
  const AcpServerInfoView({
    required this.name,
    required this.version,
    this.title = '',
  });

  final String name;
  final String version;
  final String title;

  String get displayName {
    final trimmed = title.trim();
    return trimmed.isEmpty ? name : trimmed;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpServerInfoView &&
          name == other.name &&
          version == other.version &&
          title == other.title;

  @override
  int get hashCode => Object.hash(name, version, title);
}

/// 失败类别；恢复动作按类型决定，不解析原始字符串。
enum AcpAuthFailureCodeView {
  /// 本机没有可用的固定版本受管安装：需要用户显式执行准备。
  preparationRequired,

  /// 已存在的受管安装损坏或与固定描述符不一致。
  installationInvalid,

  /// 当前宿主平台没有官方受管发行。
  unsupportedPlatform,

  /// 受管服务器自报版本不是产品固定版本。
  serverVersionMismatch,
  startup,
  missingExecutable,
  io,
  unsupportedVersion,
  unsupportedMethod,
  authentication,
  probe,
  protocol,
  transport,
  timeout,
  resourceLimit,
  cancelled,
  cleanup,
  staleOperation,
  configChanged,
  internal,
}

/// 失败发生的阶段。
enum AcpAuthStageView {
  /// 后台安装验证（固定受管安装的存在性与一致性）。
  prepare,
  initialize,
  authenticate,
  probe,
  close,
  process,
  config,
  cleanup,
}

/// UI 可安全展示的失败事实：消息由后端脱敏后给出。
class AcpAuthFailureView {
  const AcpAuthFailureView({
    required this.code,
    required this.stage,
    required this.message,
    required this.retryable,
  });

  final AcpAuthFailureCodeView code;
  final AcpAuthStageView stage;
  final String message;
  final bool retryable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAuthFailureView &&
          code == other.code &&
          stage == other.stage &&
          message == other.message &&
          retryable == other.retryable;

  @override
  int get hashCode => Object.hash(code, stage, message, retryable);
}

/// 一个接入的认证观察状态。
///
/// 携带 operation 的变体只描述某次显式操作；迟到结果由 reducer 按 revision 丢弃，
/// 不在 UI 里用本地标志推断状态。
sealed class AcpAuthStateView {
  const AcpAuthStateView();

  /// 是否有进行中的操作（取消入口必须保持可达）。
  bool get isBusy => switch (this) {
    AcpCheckingState() ||
    AcpAuthenticatingState() ||
    AcpVerifyingState() ||
    AcpClosingState() ||
    AcpCancellingState() => true,
    _ => false,
  };

  /// 只有非 busy 状态才是可以给出恢复/完成动作的终态。
  bool get isSettled => !isBusy;

  /// 当前状态对应的 operation 身份；无操作时为 null。
  String? get operationId => switch (this) {
    AcpCheckingState(operationId: final id) => id,
    AcpAuthenticatingState(operationId: final id) => id,
    AcpVerifyingState(operationId: final id) => id,
    AcpClosingState(operationId: final id) => id,
    AcpCancellingState(operationId: final id) => id,
    _ => null,
  };
}

final class AcpUncheckedState extends AcpAuthStateView {
  const AcpUncheckedState();

  @override
  bool operator ==(Object other) => other is AcpUncheckedState;

  @override
  int get hashCode => 0x0201;
}

final class AcpCheckingState extends AcpAuthStateView {
  const AcpCheckingState({required this.operationId});

  final String operationId;

  @override
  bool operator ==(Object other) =>
      other is AcpCheckingState && other.operationId == operationId;

  @override
  int get hashCode => Object.hash(0x0202, operationId);
}

/// 需要登录：保留服务端实际宣告的方法，由 UI 决定唯一主操作。
///
/// [server] 为 null 表示服务端没有提供可观察身份（缺少 `agentInfo`）。此时不能用
/// 账号名或空字符串伪造服务端事实，UI 只显示“未提供信息”或省略该元数据。
final class AcpRequiredState extends AcpAuthStateView {
  const AcpRequiredState({required this.server, this.methods = const []});

  final AcpServerInfoView? server;
  final List<AcpAuthMethodView> methods;

  /// 可直接用于登录的方法（只有 agent 类型可以发送认证请求）。
  List<AcpAuthMethodView> get agentMethods =>
      methods.where((method) => method.isAgent).toList(growable: false);

  /// 服务端没有宣告任何方法。
  bool get hasNoMethods => methods.isEmpty;

  /// 服务端只宣告了 terminal 方法：本阶段无法登录。
  ///
  /// 未知/未实现的方法不算 terminal：两者都不可登录，但原因与提示不同。
  bool get terminalOnly =>
      methods.isNotEmpty &&
      agentMethods.isEmpty &&
      methods.every((method) => method.isTerminal);

  /// 服务端只有未知/未实现的方法：同样不可登录，但与 terminal 原因不同。
  bool get unsupportedOnly =>
      methods.isNotEmpty &&
      agentMethods.isEmpty &&
      !methods.any((m) => m.isTerminal);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpRequiredState &&
          server == other.server &&
          listEquals(methods, other.methods);

  @override
  int get hashCode => Object.hash(0x0203, server, Object.hashAll(methods));
}

final class AcpAuthenticatingState extends AcpAuthStateView {
  const AcpAuthenticatingState({
    required this.operationId,
    required this.methodId,
  });

  final String operationId;
  final String methodId;

  @override
  bool operator ==(Object other) =>
      other is AcpAuthenticatingState &&
      other.operationId == operationId &&
      other.methodId == methodId;

  @override
  int get hashCode => Object.hash(0x0204, operationId, methodId);
}

final class AcpVerifyingState extends AcpAuthStateView {
  const AcpVerifyingState({required this.operationId});

  final String operationId;

  @override
  bool operator ==(Object other) =>
      other is AcpVerifyingState && other.operationId == operationId;

  @override
  int get hashCode => Object.hash(0x0205, operationId);
}

final class AcpVerifiedState extends AcpAuthStateView {
  const AcpVerifiedState({required this.checkedAt, required this.server});

  /// 观察时间（Unix 秒）；只是历史观察，不代表凭据长期有效。
  final int checkedAt;

  /// 服务端观察身份；对端未提供时为 null（不伪造）。
  final AcpServerInfoView? server;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpVerifiedState &&
          other.checkedAt == checkedAt &&
          other.server == server;

  @override
  int get hashCode => Object.hash(0x0206, checkedAt, server);
}

/// 协议已结束、进程与管道仍在收束的 busy 非终态。
///
/// 它既不是“已认证”也不是“已取消”：不能重新 start，也不能显示完成。可选的
/// [failure] 只是安全清理问题（资源尚未确认收束），不是认证结果。
final class AcpClosingState extends AcpAuthStateView {
  const AcpClosingState({required this.operationId, this.failure});

  final String operationId;
  final AcpAuthFailureView? failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpClosingState &&
          other.operationId == operationId &&
          other.failure == failure;

  @override
  int get hashCode => Object.hash(0x020a, operationId, failure);
}

final class AcpCancellingState extends AcpAuthStateView {
  const AcpCancellingState({required this.operationId});

  final String operationId;

  @override
  bool operator ==(Object other) =>
      other is AcpCancellingState && other.operationId == operationId;

  @override
  int get hashCode => Object.hash(0x0207, operationId);
}

final class AcpCancelledState extends AcpAuthStateView {
  const AcpCancelledState();

  @override
  bool operator ==(Object other) => other is AcpCancelledState;

  @override
  int get hashCode => 0x0208;
}

final class AcpFailedState extends AcpAuthStateView {
  const AcpFailedState({required this.failure});

  final AcpAuthFailureView failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpFailedState && other.failure == failure;

  @override
  int get hashCode => Object.hash(0x0209, failure);
}

/// 单个接入在认证观察里的条目。
class AcpAuthAccountView {
  const AcpAuthAccountView({
    required this.accountId,
    required this.connectionRevision,
    required this.state,
  });

  final String accountId;

  /// 观察所属的连接代次：账号身份 + 产品固定受管发行共同决定，name 变化不改它。
  final int connectionRevision;

  final AcpAuthStateView state;

  /// 只有账号身份 **和** 连接身份同时匹配时才可用。
  ///
  /// 只按 accountId 匹配会让删除后重建的同 ID 账号套用旧观察结果；跨 topic 乱序时
  /// 这会把已失效的 Verified 当成当前事实。
  bool matches(String accountId, int connectionRevision) =>
      this.accountId == accountId &&
      this.connectionRevision == connectionRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAuthAccountView &&
          accountId == other.accountId &&
          connectionRevision == other.connectionRevision &&
          state == other.state;

  @override
  int get hashCode => Object.hash(accountId, connectionRevision, state);
}

/// `acpAuth` 领域的 canonical snapshot。
class AcpAuthSnapshotView {
  const AcpAuthSnapshotView({
    required this.revision,
    required this.updatedAt,
    this.accounts = const [],
  });

  const AcpAuthSnapshotView.empty()
    : revision = 0,
      updatedAt = 0,
      accounts = const [];

  final int revision;
  final int updatedAt;
  final List<AcpAuthAccountView> accounts;

  /// 按账号身份与连接身份查找条目；连接身份不匹配视为没有观察。
  AcpAuthAccountView? account(
    String accountId, {
    required int connectionRevision,
  }) => accounts
      .where((account) => account.matches(accountId, connectionRevision))
      .firstOrNull;

  /// 没有匹配条目的接入按 [AcpUncheckedState] 处理，不伪造成功。
  AcpAuthStateView stateOf(
    String accountId, {
    required int connectionRevision,
  }) =>
      account(accountId, connectionRevision: connectionRevision)?.state ??
      const AcpUncheckedState();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAuthSnapshotView &&
          revision == other.revision &&
          updatedAt == other.updatedAt &&
          listEquals(accounts, other.accounts);

  @override
  int get hashCode =>
      Object.hash(revision, updatedAt, Object.hashAll(accounts));
}

/// 认证命令的接受回执与随命令返回的 canonical snapshot。
final class AcpAuthCommandReply {
  const AcpAuthCommandReply({required this.receipt, required this.snapshot});

  final StudioCommandReceipt receipt;
  final AcpAuthSnapshotView snapshot;
}

/// 显式提交给运行期的认证动作。
sealed class AcpAuthActionView {
  const AcpAuthActionView();
}

/// 连接检查：initialize + `session/new` 探测，不发送 prompt。
final class AcpCheckActionView extends AcpAuthActionView {
  const AcpCheckActionView();

  @override
  bool operator ==(Object other) => other is AcpCheckActionView;

  @override
  int get hashCode => 0x0211;
}

/// 登录：只允许服务端实际宣告的 agent 方法。
final class AcpAuthenticateActionView extends AcpAuthActionView {
  const AcpAuthenticateActionView(this.methodId);

  final String methodId;

  @override
  bool operator ==(Object other) =>
      other is AcpAuthenticateActionView && other.methodId == methodId;

  @override
  int get hashCode => Object.hash(0x0212, methodId);
}

/// “保存并连接”的结果：保存是已成立的事实，检查是否受理是另一件事。
final class AcpSaveAndConnectResult {
  const AcpSaveAndConnectResult({required this.saved, this.checkFailure});

  final AcpAccountSettingsView saved;

  /// 检查命令被拒绝时的 typed 原因；null 表示已受理（不代表已登录）。
  final StudioFailure? checkFailure;
}
