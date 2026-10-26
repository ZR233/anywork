/// ACP 接入的纯领域值：provider、账号模板/设置、认证方法与失败、安装发行与进度。
///
/// 认证事实的唯一来源是 `acpAuth` canonical 快照，安装事实的唯一来源是 `acpInstall`
/// canonical 快照；本层不推断“已登录”“已安装”或“进度前进”，也不持有 transport、
/// Flutter 或 FRB 类型。账号只持久化稳定 ID、provider 与名称：受管服务器的
/// program/argv 属于产品固定发行，不是账号字段，因此这里不存在可编辑的执行入口。
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'acp_values.freezed.dart';

/// 当前阶段支持的 ACP 接入协议。
///
/// wire 值是稳定身份：未知值由适配层显式失败，不能退回某个默认协议。
enum AcpProvider { antigravity }

/// 后端目录声明的接入模板：显示名、固定受管版本与官方说明地址。
@Freezed(toStringOverride: false)
abstract class AcpAccountTemplate with _$AcpAccountTemplate {
  const AcpAccountTemplate._();

  const factory AcpAccountTemplate({
    required AcpProvider provider,
    required String displayName,

    /// 一句话说明；界面不用它推断协议或凭据语义。
    required String description,

    /// 品牌图标键；空字符串表示模板没有提供，展示层回退到首字母。
    required String iconKey,

    /// 产品固定的受管服务器版本；客户端不硬编码版本，也不允许用户选择。
    required String supportedVersion,

    /// 官方安装说明地址；空字符串表示不展示入口，也不从进程输出推导。
    required String installUrl,

    /// 官方条款地址；空字符串表示后端未提供。
    required String termsUrl,

    /// 后端声明的自动准备资格与目标平台；缺省是不支持。
    required AcpInstallAvailability automaticInstall,
  }) = _AcpAccountTemplate;

  /// 模板是否声明了自动准备资格。
  bool get prefersAutomaticInstall => automaticInstall.isAvailable;
}

/// 只读接入目录；空目录表示后端没有可用模板，不是“尚未加载”的替代事实。
@Freezed(toStringOverride: false)
abstract class AcpAccountCatalog with _$AcpAccountCatalog {
  const AcpAccountCatalog._();

  const factory AcpAccountCatalog({
    required List<AcpAccountTemplate> templates,
  }) = _AcpAccountCatalog;

  /// 后端没有声明模板时的空目录。
  static const AcpAccountCatalog empty = AcpAccountCatalog(
    templates: <AcpAccountTemplate>[],
  );

  bool get isUsable => templates.isNotEmpty;

  AcpAccountTemplate? template(AcpProvider provider) {
    for (final template in templates) {
      if (template.provider == provider) return template;
    }
    return null;
  }
}

/// 已保存的 ACP 接入配置。
///
/// [connectionRevision] 是 runtime 拥有的非密钥连接身份：只有 provider 或固定发行
/// 身份真正变化才改变，名称编辑不改变它。它既不是 Settings revision，也不是
/// `acpAuth` topic 的 revision。
@Freezed(toStringOverride: false)
abstract class AcpAccountSettings with _$AcpAccountSettings {
  const AcpAccountSettings._();

  const factory AcpAccountSettings({
    required String accountId,
    required String name,
    required AcpProvider provider,
    required int connectionRevision,
  }) = _AcpAccountSettings;

  /// 观察只用同时匹配账号身份与连接身份的条目。
  ///
  /// 只按 accountId 匹配会让删除后重建的同 ID 账号套用旧观察结果。
  bool matches(String accountId, int connectionRevision) =>
      this.accountId == accountId &&
      this.connectionRevision == connectionRevision;
}

/// 一次接入配置写入的意图；保存结果由配置领域解析 connectionRevision。
@freezed
abstract class AcpAccountUpdate with _$AcpAccountUpdate {
  const factory AcpAccountUpdate({
    required String accountId,
    required String name,
    required AcpProvider provider,
  }) = _AcpAccountUpdate;
}

/// 服务端实际宣告的认证方法类别。
///
/// [unsupported] 表示服务端声明了本实现未支持的方式：它既不是 agent 也不是
/// terminal，不能据此发送认证请求。
enum AcpAuthMethodKind { agent, terminal, unsupported }

/// 服务端实际宣告的认证方法。
@Freezed(toStringOverride: false)
abstract class AcpAuthMethod with _$AcpAuthMethod {
  const AcpAuthMethod._();

  const factory AcpAuthMethod({
    required String id,
    required String name,

    /// 服务端说明；null 表示对端未提供，UI 不合成文案。
    required String? description,
    required AcpAuthMethodKind kind,
  }) = _AcpAuthMethod;

  bool get isAgent => kind == AcpAuthMethodKind.agent;
  bool get isTerminal => kind == AcpAuthMethodKind.terminal;
  bool get isUnsupported => kind == AcpAuthMethodKind.unsupported;
}

/// 已观察到的 server 身份；只代表观察当时的事实，不代表永久在线。
@Freezed(toStringOverride: false)
abstract class AcpServerInfo with _$AcpServerInfo {
  const AcpServerInfo._();

  const factory AcpServerInfo({
    required String name,

    /// 服务端标题；null 表示对端未提供，不用本地账号名称补造。
    required String? title,
    required String version,
  }) = _AcpServerInfo;

  String get displayName {
    final trimmed = (title ?? '').trim();
    return trimmed.isEmpty ? name : trimmed;
  }
}

/// 认证失败的安全类别；恢复动作按类型决定，不解析原始字符串。
enum AcpAuthFailureCode {
  /// 固定发行的受管安装尚未准备：必须显式准备，命令不会隐式下载或修复。
  preparationRequired,

  /// 已存在的受管安装损坏或与冻结描述符不一致。
  installationInvalid,

  /// 当前宿主平台没有产品支持的官方发行。
  unsupportedPlatform,

  /// 协商出的 server 版本缺失或不是产品固定支持的版本。
  serverVersionMismatch,

  /// 无法启动官方程序或所需监督资源。
  startup,

  /// 已验证安装的入口程序缺失或不可执行。
  missingExecutable,

  /// 文件系统、管道或其它本地 IO 失败。
  io,

  /// 协商的 ACP 版本不受支持（与 server 版本不符是不同类别）。
  unsupportedVersion,

  /// 认证方法不支持（含仅有 terminal 方法）。
  unsupportedMethod,

  /// 官方程序报告的认证失败。
  authentication,

  /// `session/new` 探测失败。
  probe,

  /// 协议错误或意外响应。
  protocol,

  /// 管道断开或进程提前退出。
  transport,

  /// 阶段超时。
  timeout,

  /// 输出/资源预算超限。
  resourceLimit,

  /// 显式取消。
  cancelled,

  /// 操作已过期（配置变化、删除或迟到结果）。
  staleOperation,

  /// 所属接入的连接身份已被改写，旧操作不再代表当前配置。
  configChanged,

  /// 进程或管道未能确认回收。
  cleanup,

  /// 内部不变量被破坏。
  internal,
}

/// 失败发生的阶段。
enum AcpAuthStage {
  /// 启动前验证受管安装（只读，不下载、不修复）。
  prepare,

  /// 官方程序启动。
  process,

  /// 准备接入专属探测目录。
  config,
  initialize,
  authenticate,
  probe,
  close,

  /// 进程与管道收尾。
  cleanup,
}

/// 类型化认证失败：阶段、类别、安全摘要与可重试提示。
///
/// [message] 已由后端脱敏；本层不解析它来决定恢复动作。
@freezed
abstract class AcpAuthFailure with _$AcpAuthFailure {
  const factory AcpAuthFailure({
    required AcpAuthFailureCode code,
    required AcpAuthStage stage,
    required String message,
    required bool retryable,
  }) = _AcpAuthFailure;
}

/// 显式提交给运行期的认证意图。
///
/// 查询、订阅与页面进入都不会构造这些值：只有用户的显式动作才会。
@Freezed(toStringOverride: false)
sealed class AcpAuthAction with _$AcpAuthAction {
  /// 连接检查：initialize + `session/new` 探测，不发送 prompt。
  const factory AcpAuthAction.check() = AcpAuthCheck;

  /// 登录：只允许服务端实际宣告的 agent 方法。
  const factory AcpAuthAction.authenticate({required String methodId}) =
      AcpAuthAuthenticate;
}

/// 模板声明的自动准备资格。
///
/// 只有后端能决定目标平台：客户端显示平台不参与选择。目标身份只用于展示，
/// 不能由前端拼装。
@Freezed(toStringOverride: false)
sealed class AcpInstallAvailability with _$AcpInstallAvailability {
  const AcpInstallAvailability._();

  const factory AcpInstallAvailability.available({required String target}) =
      AcpInstallAvailable;
  const factory AcpInstallAvailability.unsupportedPlatform() =
      AcpInstallUnsupportedPlatform;

  /// 是否允许在添加流程中默认自动准备。
  bool get isAvailable => switch (this) {
    AcpInstallAvailable() => true,
    AcpInstallUnsupportedPlatform() => false,
  };

  /// 后端目标身份；不支持时为 null。
  String? get target => switch (this) {
    AcpInstallAvailable(:final target) => target,
    AcpInstallUnsupportedPlatform() => null,
  };
}

/// 一次准备操作冻结的发行事实；操作开始后不随远端 registry 变化。
@Freezed(toStringOverride: false)
abstract class AcpInstallRelease with _$AcpInstallRelease {
  const AcpInstallRelease._();

  const factory AcpInstallRelease({
    required String version,
    required String target,
    required String archiveUrl,

    /// 发行方摘要；缺失时必须把信任边界表述为“官方 HTTPS 来源”，不能称作已签名。
    required String? sha256,
  }) = _AcpInstallRelease;

  bool get hasPublisherChecksum => (sha256 ?? '').trim().isNotEmpty;
}

/// 当前下载阶段的实际进度。
///
/// [totalBytes] 未知时不能合成百分比；[bytesPerSecond] 没有有效样本时为 null。
/// [completedBytes] 是本地当前有效长度（重试续传时可能真实回退），不是传输累计。
@Freezed(toStringOverride: false)
abstract class AcpInstallProgress with _$AcpInstallProgress {
  const AcpInstallProgress._();

  const factory AcpInstallProgress({
    required int completedBytes,
    required int? totalBytes,
    required int? bytesPerSecond,
  }) = _AcpInstallProgress;

  /// 尚未开始任何下载时的真实进度。
  static const AcpInstallProgress idle = AcpInstallProgress(
    completedBytes: 0,
    totalBytes: null,
    bytesPerSecond: null,
  );

  bool get hasTotal => (totalBytes ?? 0) > 0;

  /// 只有在总量已知且为正时才有比例；否则由调用方展示不定进度。
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    final value = completedBytes / total;
    if (value < 0) return 0;
    return value > 1 ? 1 : value;
  }

  /// 有效速度样本；0 或负数不是样本。
  int? get effectiveBytesPerSecond {
    final speed = bytesPerSecond;
    return speed == null || speed <= 0 ? null : speed;
  }
}

/// 已就绪的官方 server：安装身份、只读 program 诊断与复用标记。
///
/// 固定 argv 留在内部启动边界，不进账号编辑/保存 DTO；`program` 只作只读诊断，
/// 不是用户可编辑的启动配置。就绪只证明 server 可启动，不证明账号已保存或已认证。
@freezed
abstract class AcpInstalledServer with _$AcpInstalledServer {
  const factory AcpInstalledServer({
    required String installationId,
    required AcpInstallRelease release,
    required String program,

    /// 准备完成时间（Unix 秒）；只是历史事实。
    required int readyAt,

    /// 本次操作复用了既有完整安装，而不是重新下载。
    required bool reused,
  }) = _AcpInstalledServer;
}

/// 失败发生在安装链的哪一步。
enum AcpInstallStage {
  resolve,
  waitForLock,
  download,
  verify,
  extract,
  publish,
  close,
}

/// 安装失败的安全类别；恢复决策只依赖它，不解析 message。
enum AcpInstallFailureCode {
  /// 当前宿主平台没有可自动准备的官方包。
  unsupportedPlatform,

  /// 来源、重定向或格式不在允许范围内。
  sourceRejected,
  network,
  timeout,

  /// 元数据、包或解压结果超过预算。
  tooLarge,
  checksumMismatch,
  invalidArchive,
  missingExecutable,

  /// 已发布安装回执与实际内容不一致；现场保留，不静默修复。
  cacheCorrupt,
  io,
  busy,
  staleOperation,
  cancelled,

  /// 物理资源未能确认收束。
  resourceClose,
}

/// UI 可安全展示的准备失败：消息由后端脱敏后给出。
@freezed
abstract class AcpInstallFailure with _$AcpInstallFailure {
  const factory AcpInstallFailure({
    required AcpInstallFailureCode code,
    required AcpInstallStage stage,
    required String message,
    required bool retryable,
  }) = _AcpInstallFailure;
}
