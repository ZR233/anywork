/// `acpAuth` 与 `acpInstall` 两个 product topic 的 typed 帧。
///
/// 两个 topic 都直接交付完整快照（后端在受理时即发布），因此不存在 header/分页读取：
/// 每帧只表达一次 owner 事实与它的领域 revision。控制帧（resync/failure/closed）携带
/// 该订阅的 feed 身份，reducer 用它拒绝跨订阅的重放。
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../domain/acp_auth_state.dart';
import '../domain/acp_install_state.dart';

part 'acp_frames.freezed.dart';

/// `acpAuth` 订阅交付的帧；基线与后续事件一样消费一次 Data delivery。
@Freezed(toStringOverride: false)
sealed class AcpAuthFrame with _$AcpAuthFrame {
  const factory AcpAuthFrame.data({
    required int deliverySequence,
    required AcpAuthEvent event,
  }) = AcpAuthData;
  const factory AcpAuthFrame.resyncRequired({
    required ProductFeedIdentity identity,
    required ProductResyncReason reason,
  }) = AcpAuthResyncRequired;
  const factory AcpAuthFrame.failure({
    required ProductFeedIdentity identity,
    required StudioFailure error,
  }) = AcpAuthFeedFailure;
  const factory AcpAuthFrame.closed({
    required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason,
  }) = AcpAuthClosed;
}

/// `acpAuth` 的 owner 事实：首帧基线与后续状态变更都携带完整快照。
@Freezed(toStringOverride: false)
sealed class AcpAuthEvent with _$AcpAuthEvent {
  const factory AcpAuthEvent.baseline({
    required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp,
    required AcpAuthSnapshot snapshot,
  }) = AcpAuthBaseline;
  const factory AcpAuthEvent.changed({
    required ProductProjectionStamp stamp,

    /// 发布方声明被本次事实取代的水位；与 reducer 当前水位不等就是 gap。
    required int baseRevision,
    required AcpAuthSnapshot snapshot,
  }) = AcpAuthChanged;
}

/// `acpInstall` 订阅交付的帧。
@Freezed(toStringOverride: false)
sealed class AcpInstallFrame with _$AcpInstallFrame {
  const factory AcpInstallFrame.data({
    required int deliverySequence,
    required AcpInstallEvent event,
  }) = AcpInstallData;
  const factory AcpInstallFrame.resyncRequired({
    required ProductFeedIdentity identity,
    required ProductResyncReason reason,
  }) = AcpInstallResyncRequired;
  const factory AcpInstallFrame.failure({
    required ProductFeedIdentity identity,
    required StudioFailure error,
  }) = AcpInstallFeedFailure;
  const factory AcpInstallFrame.closed({
    required ProductFeedIdentity identity,
    required ProductFeedCloseReason reason,
  }) = AcpInstallClosed;
}

/// `acpInstall` 的 owner 事实；每个阶段变更都携带完整快照与进度。
@Freezed(toStringOverride: false)
sealed class AcpInstallEvent with _$AcpInstallEvent {
  const factory AcpInstallEvent.baseline({
    required ProductFeedIdentity identity,
    required ProductProjectionStamp stamp,
    required AcpInstallSnapshot snapshot,
  }) = AcpInstallBaseline;
  const factory AcpInstallEvent.changed({
    required ProductProjectionStamp stamp,

    /// 发布方声明被本次事实取代的水位；与 reducer 当前水位不等就是 gap。
    required int baseRevision,
    required AcpInstallSnapshot snapshot,
  }) = AcpInstallChanged;
}
