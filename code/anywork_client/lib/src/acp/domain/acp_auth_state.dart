/// `acpAuth` 的 canonical 认证观察值。
///
/// [AcpAuthState] 是后端发布给单个接入的状态机：[AcpAuthState.verified] 只记录当时
/// 的观察，不代表凭据永久有效；本层不从本地布尔值、进程存活或浏览器关闭合成登录
/// 成功。[AcpAuthObservation] 是本领域在 Dart 侧唯一的 canonical 镜像：transport
/// 投影加上当前 materialize 的快照，二者必须相互一致。
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'acp_values.dart';

part 'acp_auth_state.freezed.dart';

/// 一个接入的认证观察状态。
///
/// 携带 operation 的变体只描述某次显式操作；迟到结果由 reducer 按 revision 丢弃，
/// 不在 UI 里用本地标志推断状态。
@Freezed(toStringOverride: false)
sealed class AcpAuthState with _$AcpAuthState {
  const AcpAuthState._();

  /// 重启后、保存后或连接身份变化后的初始状态：既不是失败也不是通过。
  const factory AcpAuthState.unchecked() = AcpAuthUnchecked;
  const factory AcpAuthState.checking({required String operationId}) =
      AcpAuthChecking;

  /// 需要登录：保留服务端实际宣告的方法，由 UI 决定唯一主操作。
  ///
  /// `server` 为 null 表示服务端没有提供可观察身份；此时不能用账号名或空字符串
  /// 伪造服务端事实。
  const factory AcpAuthState.required({
    required AcpServerInfo? server,
    required List<AcpAuthMethod> methods,
  }) = AcpAuthRequired;
  const factory AcpAuthState.authenticating({
    required String operationId,
    required String methodId,
  }) = AcpAuthAuthenticating;
  const factory AcpAuthState.verifying({required String operationId}) =
      AcpAuthVerifying;

  /// 协议已结束、进程与管道仍在收束的非终态。
  ///
  /// 它既不是“已认证”也不是“已取消”：不能重新 start，也不能显示完成。可选的
  /// `failure` 只是安全清理问题（资源尚未确认收束），不是认证结果。
  const factory AcpAuthState.closing({
    required String operationId,
    required AcpAuthFailure? failure,
  }) = AcpAuthClosing;

  /// 认证可用；只代表当时观察，且不改变已保存配置事实。
  const factory AcpAuthState.verified({
    /// 观察时间（Unix 秒）；不代表凭据长期有效。
    required int checkedAt,

    /// 服务端观察身份；对端未提供时为 null（不伪造）。
    required AcpServerInfo? server,
  }) = AcpAuthVerified;
  const factory AcpAuthState.cancelling({required String operationId}) =
      AcpAuthCancelling;
  const factory AcpAuthState.cancelled() = AcpAuthCancelled;
  const factory AcpAuthState.failed({required AcpAuthFailure failure}) =
      AcpAuthFailed;

  /// 是否有进行中的操作（取消入口必须保持可达）。
  bool get isBusy => switch (this) {
    AcpAuthChecking() ||
    AcpAuthAuthenticating() ||
    AcpAuthVerifying() ||
    AcpAuthClosing() ||
    AcpAuthCancelling() => true,
    _ => false,
  };

  /// 只有非 busy 状态才是可以给出恢复/完成动作的终态。
  bool get isSettled => !isBusy;

  /// 当前状态对应的 operation 身份；无操作时为 null。
  String? get operationId => switch (this) {
    AcpAuthChecking(:final operationId) => operationId,
    AcpAuthAuthenticating(:final operationId) => operationId,
    AcpAuthVerifying(:final operationId) => operationId,
    AcpAuthClosing(:final operationId) => operationId,
    AcpAuthCancelling(:final operationId) => operationId,
    _ => null,
  };
}

/// [AcpAuthRequired] 的可直接用于登录的方法：只有 agent 类型可以发送认证请求。
extension AcpAuthRequiredMethods on AcpAuthRequired {
  List<AcpAuthMethod> get agentMethods =>
      methods.where((method) => method.isAgent).toList(growable: false);

  /// 服务端没有宣告任何方法。
  bool get hasNoMethods => methods.isEmpty;

  /// 服务端只宣告了 terminal 方法：本阶段无法登录。
  bool get terminalOnly =>
      methods.isNotEmpty &&
      agentMethods.isEmpty &&
      methods.every((method) => method.isTerminal);

  /// 服务端只有未知/未实现的方法：同样不可登录，但与 terminal 原因不同。
  bool get unsupportedOnly =>
      methods.isNotEmpty &&
      agentMethods.isEmpty &&
      !methods.any((method) => method.isTerminal);
}

/// 单个接入在认证观察里的条目。
@freezed
abstract class AcpAuthAccount with _$AcpAuthAccount {
  const factory AcpAuthAccount({
    required String accountId,

    /// 本次观察对应的连接身份；不等于 Settings revision。
    required int connectionRevision,
    required AcpAuthState state,
  }) = _AcpAuthAccount;
}

/// `acpAuth` 领域的 canonical 快照；revision 独立于 Settings 与 `acpInstall`。
@Freezed(toStringOverride: false)
abstract class AcpAuthSnapshot with _$AcpAuthSnapshot {
  const AcpAuthSnapshot._();

  const factory AcpAuthSnapshot({
    required int revision,
    required int updatedAt,
    required List<AcpAuthAccount> accounts,
  }) = _AcpAuthSnapshot;

  /// 尚未产生任何观察的空快照；不是“全部未检查”的伪造条目。
  static const AcpAuthSnapshot empty = AcpAuthSnapshot(
    revision: 0,
    updatedAt: 0,
    accounts: <AcpAuthAccount>[],
  );

  /// 按账号身份与连接身份查找条目；连接身份不匹配视为没有观察。
  AcpAuthAccount? account(String accountId, {required int connectionRevision}) {
    for (final account in accounts) {
      if (account.accountId == accountId &&
          account.connectionRevision == connectionRevision) {
        return account;
      }
    }
    return null;
  }

  /// 按账号身份查找条目；只用于命令受理快照的身份核对。
  AcpAuthAccount? accountById(String accountId) {
    for (final account in accounts) {
      if (account.accountId == accountId) return account;
    }
    return null;
  }

  /// 没有匹配条目的接入按未检查处理，不伪造成功。
  AcpAuthState stateOf(String accountId, {required int connectionRevision}) =>
      account(accountId, connectionRevision: connectionRevision)?.state ??
      const AcpAuthState.unchecked();
}

/// 快照自身的领域水位；与 transport 投影戳（ownerEpoch + incarnation）相互独立。
@freezed
abstract class AcpAuthHeader with _$AcpAuthHeader {
  const factory AcpAuthHeader({required int revision, required int updatedAt}) =
      _AcpAuthHeader;
}

/// `acpAuth` 在 Dart 侧的 canonical 镜像。
///
/// [projection] 只保存 transport 事实与 [AcpAuthHeader]；[snapshot] 保存最近一次
/// materialize 的完整快照，其 origin 必须与投影戳一致。没有快照不等于“全部未检查”
/// 的已加载事实：调用方按状态查询时得到的是未检查。
@Freezed(toStringOverride: false)
abstract class AcpAuthObservation with _$AcpAuthObservation {
  const AcpAuthObservation._();

  const factory AcpAuthObservation({
    required ProductProjection<AcpAuthHeader> projection,
    required Materialized<AcpAuthSnapshot, ResourceStamp>? snapshot,
  }) = _AcpAuthObservation;

  /// 领域尚未连接、也没有任何读取时的初始值。
  static const AcpAuthObservation idle = AcpAuthObservation(
    projection: ProductProjection<AcpAuthHeader>(
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
  AcpAuthSnapshot? get canonical => snapshot?.value;

  /// 只有同时匹配账号身份与连接身份时才返回观察状态，否则是未检查。
  AcpAuthState stateOf(String accountId, {required int connectionRevision}) =>
      canonical?.stateOf(accountId, connectionRevision: connectionRevision) ??
      const AcpAuthState.unchecked();

  AcpAuthAccount? accountOf(
    String accountId, {
    required int connectionRevision,
  }) => canonical?.account(accountId, connectionRevision: connectionRevision);
}
