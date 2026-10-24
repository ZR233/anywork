/// ACP 官方 server 准备的纯领域模型（不依赖 Flutter、Riverpod、FRB 或 transport）。
///
/// 这一层只表达产品语义：模板的自动准备资格、准备操作阶段与真实进度、就绪结果
/// 与安全失败原因。唯一事实来源是后端 canonical `acpInstall` 快照；本层不推断
/// “已安装可用”，也不把下载完成当成服务器就绪、账号已保存或已登录。
library;

import 'acp_models.dart';
import 'collection_equality.dart';
import 'command_receipts.dart';

/// 模板声明的自动准备资格。
///
/// 只有后端能决定目标平台：客户端显示平台不参与选择。[target] 是后端给出的
/// 稳定目标身份（如 `linux-x86_64`），仅用于展示，不能由前端拼装。
sealed class AcpInstallAvailabilityView {
  const AcpInstallAvailabilityView();

  /// 是否允许在添加流程中默认自动准备。
  bool get isAvailable;

  /// 后端目标身份；不支持时为 null。
  String? get target;
}

final class AcpInstallAvailableView extends AcpInstallAvailabilityView {
  const AcpInstallAvailableView({required this.target});

  @override
  final String target;

  @override
  bool get isAvailable => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpInstallAvailableView && other.target == target;

  @override
  int get hashCode => Object.hash(0x0421, target);
}

/// 当前宿主平台没有官方受管发行：该账号只能等官方支持后再准备，不能报成整个 ACP 不可用。
final class AcpInstallUnsupportedPlatformView
    extends AcpInstallAvailabilityView {
  const AcpInstallUnsupportedPlatformView();

  @override
  bool get isAvailable => false;

  @override
  String? get target => null;

  @override
  bool operator ==(Object other) => other is AcpInstallUnsupportedPlatformView;

  @override
  int get hashCode => 0x0422;
}

/// 一次准备操作冻结的发行事实；操作开始后不随远端 registry 变化。
class AcpInstallReleaseView {
  const AcpInstallReleaseView({
    required this.version,
    required this.target,
    required this.archiveUrl,
    this.sha256,
  });

  final String version;
  final String target;
  final String archiveUrl;

  /// 发行方摘要；缺失时必须把信任边界表述为“官方 HTTPS 来源”，不能称作已签名。
  final String? sha256;

  bool get hasPublisherChecksum => (sha256 ?? '').trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpInstallReleaseView &&
          version == other.version &&
          target == other.target &&
          archiveUrl == other.archiveUrl &&
          sha256 == other.sha256;

  @override
  int get hashCode => Object.hash(version, target, archiveUrl, sha256);
}

/// 当前下载进度的真实字节事实。
///
/// [totalBytes] 未知时不能合成百分比；[bytesPerSecond] 没有有效样本时为 null。
class AcpInstallProgressView {
  const AcpInstallProgressView({
    this.completedBytes = 0,
    this.totalBytes,
    this.bytesPerSecond,
  });

  const AcpInstallProgressView.idle()
    : completedBytes = 0,
      totalBytes = null,
      bytesPerSecond = null;

  final int completedBytes;
  final int? totalBytes;
  final int? bytesPerSecond;

  /// 只有在总量已知且为正时才有比例；否则由调用方展示不定进度。
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    final value = completedBytes / total;
    if (value < 0) return 0;
    return value > 1 ? 1 : value;
  }

  bool get hasTotal => (totalBytes ?? 0) > 0;

  /// 有效速度样本；0 或负数不是样本。
  int? get effectiveBytesPerSecond {
    final speed = bytesPerSecond;
    return speed == null || speed <= 0 ? null : speed;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpInstallProgressView &&
          completedBytes == other.completedBytes &&
          totalBytes == other.totalBytes &&
          bytesPerSecond == other.bytesPerSecond;

  @override
  int get hashCode => Object.hash(completedBytes, totalBytes, bytesPerSecond);
}

/// 就绪结果携带的已安装身份、入口与来源事实。
class AcpInstalledServerView {
  const AcpInstalledServerView({
    required this.installationId,
    required this.release,
    required this.program,
    this.readyAt = 0,
    this.reused = false,
  });

  final String installationId;
  final AcpInstallReleaseView release;

  /// 安装后的绝对程序路径；只作只读诊断展示，不是用户可编辑的启动配置。
  final String program;

  /// 准备完成时间（Unix 秒）；只是历史事实。
  final int readyAt;

  /// 复用了既有完整校验安装，而不是本次下载。
  final bool reused;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpInstalledServerView &&
          installationId == other.installationId &&
          release == other.release &&
          program == other.program &&
          readyAt == other.readyAt &&
          reused == other.reused;

  @override
  int get hashCode =>
      Object.hash(installationId, release, program, readyAt, reused);
}

/// 准备阶段；下载 100% 仍然不是就绪。
enum AcpInstallStageView {
  resolve,
  waitForLock,
  download,
  verify,
  extract,
  publish,
  close,
}

/// 准备失败的 typed 类别；恢复动作按类型决定，不解析任何字符串。
enum AcpInstallFailureCodeView {
  unsupportedPlatform,
  sourceRejected,
  network,
  timeout,
  tooLarge,
  checksumMismatch,
  invalidArchive,
  missingExecutable,
  cacheCorrupt,
  io,
  busy,
  staleOperation,
  cancelled,
  resourceClose,
}

/// UI 可安全展示的准备失败：消息由后端脱敏后给出。
class AcpInstallFailureView {
  const AcpInstallFailureView({
    required this.code,
    required this.stage,
    required this.message,
    required this.retryable,
  });

  final AcpInstallFailureCodeView code;
  final AcpInstallStageView stage;
  final String message;
  final bool retryable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpInstallFailureView &&
          code == other.code &&
          stage == other.stage &&
          message == other.message &&
          retryable == other.retryable;

  @override
  int get hashCode => Object.hash(code, stage, message, retryable);
}

/// 单个 provider 的准备状态。
///
/// 所有已受理变体（含 [AcpInstallCancelledState] 与 [AcpInstallFailedState]）都
/// 保留 operation 身份，草稿据此判断“这是我的结果”还是迟到的旧操作。
sealed class AcpInstallStateView {
  const AcpInstallStateView();

  /// 该状态绑定的操作身份；未准备时为 null。终态同样保留，供草稿正确关联。
  String? get operationId => switch (this) {
    AcpResolvingState(:final operationId) => operationId,
    AcpWaitingForAssetState(:final operationId) => operationId,
    AcpDownloadingState(:final operationId) => operationId,
    AcpInstallVerifyingState(:final operationId) => operationId,
    AcpExtractingState(:final operationId) => operationId,
    AcpPublishingState(:final operationId) => operationId,
    AcpInstallClosingState(:final operationId) => operationId,
    AcpInstallReadyState(:final operationId) => operationId,
    AcpInstallCancellingState(:final operationId) => operationId,
    AcpInstallCancelledState(:final operationId) => operationId,
    AcpInstallFailedState(:final operationId) => operationId,
    AcpInstallIdleState() => null,
  };

  /// 是否有进行中的操作（取消入口必须保持可达）。
  bool get isBusy => switch (this) {
    AcpInstallIdleState() ||
    AcpInstallReadyState() ||
    AcpInstallCancelledState() ||
    AcpInstallFailedState() => false,
    _ => true,
  };

  bool get isSettled => !isBusy;

  bool get isReady => this is AcpInstallReadyState;

  /// 当前阶段展示用的阶段身份；未准备/终态为 null。
  AcpInstallStageView? get stage => switch (this) {
    AcpResolvingState() => AcpInstallStageView.resolve,
    AcpWaitingForAssetState() => AcpInstallStageView.waitForLock,
    AcpDownloadingState() => AcpInstallStageView.download,
    AcpInstallVerifyingState() => AcpInstallStageView.verify,
    AcpExtractingState() => AcpInstallStageView.extract,
    AcpPublishingState() => AcpInstallStageView.publish,
    AcpInstallClosingState() => AcpInstallStageView.close,
    _ => null,
  };

  /// 该操作冻结的发行事实；解析前或未准备时为 null。
  AcpInstallReleaseView? get release => switch (this) {
    AcpWaitingForAssetState(:final release) => release,
    AcpDownloadingState(:final release) => release,
    AcpInstallVerifyingState(:final release) => release,
    AcpExtractingState(:final release) => release,
    AcpPublishingState(:final release) => release,
    AcpInstallReadyState(:final server) => server.release,
    _ => null,
  };

  /// 当前进度；只有下载/校验/解压阶段有真实字节。
  AcpInstallProgressView? get progress => switch (this) {
    AcpDownloadingState(:final progress) => progress,
    AcpInstallVerifyingState(:final progress) => progress,
    AcpExtractingState(:final progress) => progress,
    _ => null,
  };

  /// 累计自动重试次数；只有下载阶段有该事实。
  int get retryCount => switch (this) {
    AcpDownloadingState(:final retryCount) => retryCount,
    _ => 0,
  };

  /// 就绪结果；只有 Ready 携带。
  AcpInstalledServerView? get server => switch (this) {
    AcpInstallReadyState(:final server) => server,
    _ => null,
  };

  /// 失败/收束问题；只有失败与收束阶段携带。
  AcpInstallFailureView? get failure => switch (this) {
    AcpInstallClosingState(:final failure) => failure,
    AcpInstallFailedState(:final failure) => failure,
    _ => null,
  };
}

final class AcpInstallIdleState extends AcpInstallStateView {
  const AcpInstallIdleState();

  @override
  bool operator ==(Object other) => other is AcpInstallIdleState;

  @override
  int get hashCode => 0x0410;
}

final class AcpResolvingState extends AcpInstallStateView {
  const AcpResolvingState({required this.operationId});

  @override
  final String operationId;

  @override
  bool operator ==(Object other) =>
      other is AcpResolvingState && other.operationId == operationId;

  @override
  int get hashCode => Object.hash(0x0411, operationId);
}

/// 等待跨进程资产锁；等待本身可取消，但不终止另一持锁进程。
final class AcpWaitingForAssetState extends AcpInstallStateView {
  const AcpWaitingForAssetState({
    required this.operationId,
    required this.release,
  });

  @override
  final String operationId;

  @override
  final AcpInstallReleaseView release;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpWaitingForAssetState &&
          other.operationId == operationId &&
          other.release == release;

  @override
  int get hashCode => Object.hash(0x0412, operationId, release);
}

final class AcpDownloadingState extends AcpInstallStateView {
  const AcpDownloadingState({
    required this.operationId,
    required this.release,
    required this.progress,
    this.retryCount = 0,
  });

  @override
  final String operationId;

  @override
  final AcpInstallReleaseView release;

  @override
  final AcpInstallProgressView progress;

  /// 累计自动重试次数；重启传输时进度可真实回退。
  @override
  final int retryCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpDownloadingState &&
          other.operationId == operationId &&
          other.release == release &&
          other.progress == progress &&
          other.retryCount == retryCount;

  @override
  int get hashCode =>
      Object.hash(0x0413, operationId, release, progress, retryCount);
}

final class AcpInstallVerifyingState extends AcpInstallStateView {
  const AcpInstallVerifyingState({
    required this.operationId,
    required this.release,
    required this.progress,
  });

  @override
  final String operationId;

  @override
  final AcpInstallReleaseView release;

  @override
  final AcpInstallProgressView progress;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpInstallVerifyingState &&
          other.operationId == operationId &&
          other.release == release &&
          other.progress == progress;

  @override
  int get hashCode => Object.hash(0x0414, operationId, release, progress);
}

final class AcpExtractingState extends AcpInstallStateView {
  const AcpExtractingState({
    required this.operationId,
    required this.release,
    required this.progress,
  });

  @override
  final String operationId;

  @override
  final AcpInstallReleaseView release;

  @override
  final AcpInstallProgressView progress;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpExtractingState &&
          other.operationId == operationId &&
          other.release == release &&
          other.progress == progress;

  @override
  int get hashCode => Object.hash(0x0415, operationId, release, progress);
}

/// 不可被业务取消回滚的提交阶段。
final class AcpPublishingState extends AcpInstallStateView {
  const AcpPublishingState({required this.operationId, required this.release});

  @override
  final String operationId;

  @override
  final AcpInstallReleaseView release;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpPublishingState &&
          other.operationId == operationId &&
          other.release == release;

  @override
  int get hashCode => Object.hash(0x0416, operationId, release);
}

/// 物理资源仍在收束的 busy 非终态；[failure] 只是安全清理问题。
final class AcpInstallClosingState extends AcpInstallStateView {
  const AcpInstallClosingState({required this.operationId, this.failure});

  @override
  final String operationId;

  @override
  final AcpInstallFailureView? failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpInstallClosingState &&
          other.operationId == operationId &&
          other.failure == failure;

  @override
  int get hashCode => Object.hash(0x0417, operationId, failure);
}

final class AcpInstallReadyState extends AcpInstallStateView {
  const AcpInstallReadyState({required this.operationId, required this.server});

  @override
  final String operationId;

  @override
  final AcpInstalledServerView server;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpInstallReadyState &&
          other.operationId == operationId &&
          other.server == server;

  @override
  int get hashCode => Object.hash(0x0418, operationId, server);
}

final class AcpInstallCancellingState extends AcpInstallStateView {
  const AcpInstallCancellingState({required this.operationId});

  @override
  final String operationId;

  @override
  bool operator ==(Object other) =>
      other is AcpInstallCancellingState && other.operationId == operationId;

  @override
  int get hashCode => Object.hash(0x0419, operationId);
}

final class AcpInstallCancelledState extends AcpInstallStateView {
  const AcpInstallCancelledState({required this.operationId});

  @override
  final String operationId;

  @override
  bool operator ==(Object other) =>
      other is AcpInstallCancelledState && other.operationId == operationId;

  @override
  int get hashCode => Object.hash(0x041a, operationId);
}

final class AcpInstallFailedState extends AcpInstallStateView {
  const AcpInstallFailedState({
    required this.operationId,
    required this.failure,
  });

  @override
  final String operationId;

  @override
  final AcpInstallFailureView failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpInstallFailedState &&
          other.operationId == operationId &&
          other.failure == failure;

  @override
  int get hashCode => Object.hash(0x041b, operationId, failure);
}

/// 单个 provider 的安装条目。
class AcpInstallEntryView {
  const AcpInstallEntryView({required this.provider, required this.state});

  final AcpProviderView provider;

  final AcpInstallStateView state;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpInstallEntryView &&
          other.provider == provider &&
          other.state == state;

  @override
  int get hashCode => Object.hash(provider, state);
}

/// `acpInstall` 领域的 canonical snapshot。
class AcpInstallSnapshotView {
  const AcpInstallSnapshotView({
    required this.revision,
    required this.updatedAt,
    this.installations = const [],
  });

  const AcpInstallSnapshotView.empty()
    : revision = 0,
      updatedAt = 0,
      installations = const [];

  final int revision;
  final int updatedAt;
  final List<AcpInstallEntryView> installations;

  /// 没有条目的 provider 按“未准备”处理，不伪造已就绪。
  AcpInstallStateView stateOf(AcpProviderView provider) =>
      entry(provider)?.state ?? const AcpInstallIdleState();

  AcpInstallEntryView? entry(AcpProviderView provider) =>
      installations.where((entry) => entry.provider == provider).firstOrNull;

  /// 该 provider 当前 canonical 的就绪结果（无论 operation 身份）。
  AcpInstalledServerView? readyServer(AcpProviderView provider) =>
      stateOf(provider).server;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpInstallSnapshotView &&
          revision == other.revision &&
          updatedAt == other.updatedAt &&
          listEquals(installations, other.installations);

  @override
  int get hashCode =>
      Object.hash(revision, updatedAt, Object.hashAll(installations));
}

/// 准备命令的接受回执与随命令返回的 canonical snapshot。
final class AcpInstallCommandReply {
  const AcpInstallCommandReply({required this.receipt, required this.snapshot});

  final StudioCommandReceipt receipt;
  final AcpInstallSnapshotView snapshot;
}

/// 草稿对一次准备意图的认领。
///
/// 草稿只在 **provider + operation + 代次** 同时匹配时回填程序与参数：
/// 换来源、另建草稿或取消表单都会推进 [generation] 并清空 [operationId]，
/// 迟到的旧 Ready 因此不会被写进新字段。已准备结果需要显式认领（[claim]），
/// 不按同品牌或路径相似自动绑定。
class AcpPreparationIntent {
  const AcpPreparationIntent({
    required this.provider,
    this.generation = 0,
    this.operationId,
  });

  final AcpProviderView provider;

  /// 草稿/来源意图代次；每次更换来源或重建草稿都推进。
  final int generation;

  /// 本草稿正在等待/已认领的安装操作；null 表示没有绑定。
  final String? operationId;

  /// 同一草稿内替换来源或重新发起：清空绑定并推进代次。
  AcpPreparationIntent renewed() =>
      AcpPreparationIntent(provider: provider, generation: generation + 1);

  /// 认领一个已知操作（本表单 start 的受理结果，或用户显式使用已准备结果）。
  AcpPreparationIntent claim(String operationId) => AcpPreparationIntent(
    provider: provider,
    generation: generation,
    operationId: operationId,
  );

  /// 该状态是否属于本草稿的当前意图（provider 与 operation 都要匹配）。
  bool accepts(AcpInstallStateView state, {required AcpProviderView provider}) {
    final bound = operationId;
    if (provider != this.provider || bound == null) return false;
    return state.operationId == bound;
  }

  /// 仅当 canonical 状态属于本意图且已就绪时返回结果：其他操作的就绪结果不可用。
  AcpInstalledServerView? resolve(
    AcpInstallStateView state, {
    required AcpProviderView provider,
  }) {
    if (!accepts(state, provider: provider)) return null;
    return state.server;
  }

  /// 当前 provider 已就绪但属于另一个操作：只能由用户显式“使用已准备结果”认领。
  AcpInstalledServerView? availableElsewhere(
    AcpInstallStateView state, {
    required AcpProviderView provider,
  }) {
    if (provider != this.provider) return null;
    final server = state.server;
    if (server == null) return null;
    if (operationId == null) return server;
    return state.operationId == operationId ? null : server;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpPreparationIntent &&
          other.provider == provider &&
          other.generation == generation &&
          other.operationId == operationId;

  @override
  int get hashCode => Object.hash(provider, generation, operationId);
}
