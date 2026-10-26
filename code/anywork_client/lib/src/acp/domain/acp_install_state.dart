/// `acpInstall` 的 canonical 安装观察值与草稿侧准备意图。
///
/// 安装是共享资产而不是账号字段：同一 provider/宿主目标同时最多一个操作，就绪结果
/// 携带安装身份与只读 program 诊断。下载 100%、进程退出或模板声明能力都不是就绪
/// 证明；本层不从进度推断完成，也不把就绪当成账号已保存或已认证。
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'acp_values.dart';

part 'acp_install_state.freezed.dart';

/// 单个 provider 在当前宿主目标上的准备状态。
///
/// 除 [AcpInstallIdleState] 外每个变体都携带受理时的 operation 身份；终态同样保留它，
/// 供草稿与迟到回执正确关联，而不是靠时间或先后顺序猜归属。
@Freezed(toStringOverride: false)
sealed class AcpInstallState with _$AcpInstallState {
  const AcpInstallState._();

  /// 本次 runtime 生命周期内尚未准备过。
  const factory AcpInstallState.idle() = AcpInstallIdleState;
  const factory AcpInstallState.resolving({required String operationId}) =
      AcpInstallResolving;

  /// 已冻结发行身份，正在等待该资产的跨进程锁。
  ///
  /// 等待本身可取消，但不终止另一持锁进程。
  const factory AcpInstallState.waiting({
    required String operationId,
    required AcpInstallRelease release,
  }) = AcpInstallWaiting;
  const factory AcpInstallState.downloading({
    required String operationId,
    required AcpInstallRelease release,
    required AcpInstallProgress progress,

    /// 累计自动重试次数；重启传输时进度可真实回退。
    required int retryCount,
  }) = AcpInstallDownloading;
  const factory AcpInstallState.verifying({
    required String operationId,
    required AcpInstallRelease release,
    required AcpInstallProgress progress,
  }) = AcpInstallVerifying;
  const factory AcpInstallState.extracting({
    required String operationId,
    required AcpInstallRelease release,
    required AcpInstallProgress progress,
  }) = AcpInstallExtracting;

  /// 正在原子发布；这是不可被业务取消回滚的提交阶段。
  const factory AcpInstallState.publishing({
    required String operationId,
    required AcpInstallRelease release,
  }) = AcpInstallPublishing;

  /// 业务阶段已结束、物理任务仍在收束的非终态；`failure` 只是安全清理问题。
  const factory AcpInstallState.closing({
    required String operationId,
    required AcpInstallFailure? failure,
  }) = AcpInstallClosing;
  const factory AcpInstallState.ready({
    required String operationId,
    required AcpInstalledServer server,
  }) = AcpInstallReady;
  const factory AcpInstallState.cancelling({required String operationId}) =
      AcpInstallCancelling;
  const factory AcpInstallState.cancelled({required String operationId}) =
      AcpInstallCancelled;
  const factory AcpInstallState.failed({
    required String operationId,
    required AcpInstallFailure failure,
  }) = AcpInstallFailed;

  /// 该状态归属的操作身份；未准备时为 null。
  String? get operationId => switch (this) {
    AcpInstallResolving(:final operationId) ||
    AcpInstallWaiting(:final operationId) ||
    AcpInstallDownloading(:final operationId) ||
    AcpInstallVerifying(:final operationId) ||
    AcpInstallExtracting(:final operationId) ||
    AcpInstallPublishing(:final operationId) ||
    AcpInstallClosing(:final operationId) ||
    AcpInstallReady(:final operationId) ||
    AcpInstallCancelling(:final operationId) ||
    AcpInstallCancelled(:final operationId) ||
    AcpInstallFailed(:final operationId) => operationId,
    AcpInstallIdleState() => null,
  };

  /// 是否有进行中的操作（取消入口必须保持可达）。
  bool get isBusy => switch (this) {
    AcpInstallIdleState() ||
    AcpInstallReady() ||
    AcpInstallCancelled() ||
    AcpInstallFailed() => false,
    _ => true,
  };

  bool get isSettled => !isBusy;

  bool get isReady => this is AcpInstallReady;

  /// 当前阶段身份；未准备与终态为 null。
  AcpInstallStage? get stage => switch (this) {
    AcpInstallResolving() => AcpInstallStage.resolve,
    AcpInstallWaiting() => AcpInstallStage.waitForLock,
    AcpInstallDownloading() => AcpInstallStage.download,
    AcpInstallVerifying() => AcpInstallStage.verify,
    AcpInstallExtracting() => AcpInstallStage.extract,
    AcpInstallPublishing() => AcpInstallStage.publish,
    AcpInstallClosing() => AcpInstallStage.close,
    _ => null,
  };

  /// 该操作冻结的发行事实；解析前与未准备时为 null。
  AcpInstallRelease? get release => switch (this) {
    AcpInstallWaiting(:final release) ||
    AcpInstallDownloading(:final release) ||
    AcpInstallVerifying(:final release) ||
    AcpInstallExtracting(:final release) ||
    AcpInstallPublishing(:final release) => release,
    AcpInstallReady(:final server) => server.release,
    _ => null,
  };

  /// 当前进度；只有下载/校验/解压阶段有真实字节。
  AcpInstallProgress? get progress => switch (this) {
    AcpInstallDownloading(:final progress) ||
    AcpInstallVerifying(:final progress) ||
    AcpInstallExtracting(:final progress) => progress,
    _ => null,
  };

  /// 本次操作累计的自动重试次数；只有下载阶段有该事实。
  int get retryCount => switch (this) {
    AcpInstallDownloading(:final retryCount) => retryCount,
    _ => 0,
  };

  /// 就绪结果；只有就绪状态携带。
  AcpInstalledServer? get server => switch (this) {
    AcpInstallReady(:final server) => server,
    _ => null,
  };

  /// 失败/收束问题；只有失败与收束阶段携带。
  AcpInstallFailure? get failure => switch (this) {
    AcpInstallClosing(:final failure) => failure,
    AcpInstallFailed(:final failure) => failure,
    _ => null,
  };
}

/// 一个 provider 的安装条目。
@freezed
abstract class AcpInstallEntry with _$AcpInstallEntry {
  const factory AcpInstallEntry({
    required AcpProvider provider,
    required AcpInstallState state,
  }) = _AcpInstallEntry;
}

/// `acpInstall` 领域的 canonical 快照；revision 独立于 Settings 与 `acpAuth`。
@Freezed(toStringOverride: false)
abstract class AcpInstallSnapshot with _$AcpInstallSnapshot {
  const AcpInstallSnapshot._();

  const factory AcpInstallSnapshot({
    required int revision,
    required int updatedAt,
    required List<AcpInstallEntry> installations,
  }) = _AcpInstallSnapshot;

  /// 尚未准备任何 provider 的空快照；不是“全部已就绪”的伪造条目。
  static const AcpInstallSnapshot empty = AcpInstallSnapshot(
    revision: 0,
    updatedAt: 0,
    installations: <AcpInstallEntry>[],
  );

  AcpInstallEntry? entry(AcpProvider provider) {
    for (final entry in installations) {
      if (entry.provider == provider) return entry;
    }
    return null;
  }

  /// 没有条目的 provider 按“未准备”处理，不伪造已就绪。
  AcpInstallState stateOf(AcpProvider provider) =>
      entry(provider)?.state ?? const AcpInstallState.idle();

  /// 该 provider 当前 canonical 的就绪结果（无论 operation 身份）。
  ///
  /// 调用方必须再用 [AcpPreparationIntent] 判断它是否属于当前草稿的意图。
  AcpInstalledServer? readyServer(AcpProvider provider) =>
      stateOf(provider).server;
}

/// 快照自身的领域水位；与 transport 投影戳相互独立。
@freezed
abstract class AcpInstallHeader with _$AcpInstallHeader {
  const factory AcpInstallHeader({
    required int revision,
    required int updatedAt,
  }) = _AcpInstallHeader;
}

/// `acpInstall` 在 Dart 侧的 canonical 镜像；结构与 `acpAuth` 独立。
@Freezed(toStringOverride: false)
abstract class AcpInstallObservation with _$AcpInstallObservation {
  const AcpInstallObservation._();

  const factory AcpInstallObservation({
    required ProductProjection<AcpInstallHeader> projection,
    required Materialized<AcpInstallSnapshot, ResourceStamp>? snapshot,
  }) = _AcpInstallObservation;

  /// 领域尚未连接、也没有任何读取时的初始值。
  static const AcpInstallObservation idle = AcpInstallObservation(
    projection: ProductProjection<AcpInstallHeader>(
      stamp: null,
      header: null,
      sync: ResourceSyncState(
        phase: ResourceSyncPhase.idle,
        error: null,
        retryExhausted: false,
      ),
    ),
    snapshot: null,
  );

  /// 最近一次 canonical 快照；未加载时为 null。
  AcpInstallSnapshot? get canonical => snapshot?.value;

  /// 未加载或条目缺失都按“未准备”处理，不伪造已就绪。
  AcpInstallState stateOf(AcpProvider provider) =>
      canonical?.stateOf(provider) ?? const AcpInstallState.idle();

  AcpInstallEntry? entryOf(AcpProvider provider) => canonical?.entry(provider);

  /// 该 provider 当前 canonical 的就绪结果（任何操作身份）。
  AcpInstalledServer? readyServer(AcpProvider provider) =>
      canonical?.readyServer(provider);
}

/// 草稿对一次准备意图的认领。
///
/// 草稿只在 **provider + operation + 代次** 同时匹配时采用就绪结果：换来源、另建
/// 草稿或取消表单都会推进 [generation] 并清空 [operationId]，迟到的旧 Ready 因此
/// 不会被写进新字段。已准备结果需要显式认领（[claim]），不按同品牌或路径相似自动绑定。
@Freezed(toStringOverride: false)
abstract class AcpPreparationIntent with _$AcpPreparationIntent {
  const AcpPreparationIntent._();

  const factory AcpPreparationIntent({
    required AcpProvider provider,

    /// 草稿/来源意图代次；每次更换来源或重建草稿都推进。
    required int generation,

    /// 当前等待/已认领的安装操作；null 表示没有绑定。
    required String? operationId,
  }) = _AcpPreparationIntent;

  /// 新建的未绑定意图。
  static AcpPreparationIntent fresh({required AcpProvider provider}) =>
      AcpPreparationIntent(
        provider: provider,
        generation: 0,
        operationId: null,
      );

  /// 同一草稿内替换来源或重新发起：清空绑定并推进代次。
  AcpPreparationIntent renewed() => AcpPreparationIntent(
    provider: provider,
    generation: generation + 1,
    operationId: null,
  );

  /// 认领一个已知操作（本表单 start 的受理结果，或用户显式使用已准备结果）。
  AcpPreparationIntent claim(String operationId) => AcpPreparationIntent(
    provider: provider,
    generation: generation,
    operationId: operationId,
  );

  /// 该状态是否属于本草稿的当前意图（provider 与 operation 都要匹配）。
  bool accepts(AcpInstallState state, {required AcpProvider provider}) {
    final bound = operationId;
    if (provider != this.provider || bound == null) return false;
    return state.operationId == bound;
  }

  /// 仅当 canonical 状态属于本意图且已就绪时返回结果：其他操作的就绪结果不可用。
  AcpInstalledServer? resolve(
    AcpInstallState state, {
    required AcpProvider provider,
  }) {
    if (!accepts(state, provider: provider)) return null;
    return state.server;
  }

  /// 当前 provider 已就绪但属于另一个操作：只能由用户显式“使用已准备结果”认领。
  AcpInstalledServer? availableElsewhere(
    AcpInstallState state, {
    required AcpProvider provider,
  }) {
    if (provider != this.provider) return null;
    final server = state.server;
    if (server == null) return null;
    if (operationId == null) return server;
    return state.operationId == operationId ? null : server;
  }
}
