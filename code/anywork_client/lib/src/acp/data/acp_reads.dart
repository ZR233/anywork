/// ACP 的具名有界读取与显式命令值。
///
/// 这里只承载两个资源各自的单次原生调用值：读取（`readAuthState`／
/// `readInstallState`／`readAccountCatalog`）与显式命令（检查、登录、取消、准备）
/// 各返回一份有界结果，没有分页、游标、流或轮询入口。命令回执只证明受理，绝不表示
/// 登录完成、安装就绪或进度前进。
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../operations.dart';
// OperationId 由 identity.dart 定义；这里引入定义库而不是窄 `show`，否则生成的
// `$OperationIdCopyWith` 在本文件生成物里不可见。
import '../../resources/domain/identity.dart';
import '../domain/acp_auth_state.dart';
import '../domain/acp_install_state.dart';
import '../domain/acp_values.dart';

part 'acp_reads.freezed.dart';

/// 受理一次认证操作；身份在提交前冻结，运行期据此拒绝已撤代的操作。
@freezed
abstract class AcpAuthStartRequest with _$AcpAuthStartRequest {
  const factory AcpAuthStartRequest({
    required OperationId operationId,
    required String accountId,

    /// 提交时冻结的连接代次；保存/删除/发行变化后旧值会被运行期拒绝。
    required int expectedConnectionRevision,
    required AcpAuthAction action,
  }) = _AcpAuthStartRequest;
}

/// 取消指定接入当前的操作；`targetOperationId` 必须命中当前操作身份。
@freezed
abstract class AcpAuthCancelRequest with _$AcpAuthCancelRequest {
  const factory AcpAuthCancelRequest({
    required OperationId operationId,
    required String accountId,
    required OperationId targetOperationId,
  }) = _AcpAuthCancelRequest;
}

/// 受理一次官方 server 准备；只表达 provider，宿主 target 由后端决定。
@freezed
abstract class AcpInstallStartRequest with _$AcpInstallStartRequest {
  const factory AcpInstallStartRequest({
    required OperationId operationId,
    required AcpProvider provider,
  }) = _AcpInstallStartRequest;
}

/// 取消该 provider 当前准备操作；`targetOperationId` 必须命中当前操作身份。
@freezed
abstract class AcpInstallCancelRequest with _$AcpInstallCancelRequest {
  const factory AcpInstallCancelRequest({
    required OperationId operationId,
    required AcpProvider provider,
    required OperationId targetOperationId,
  }) = _AcpInstallCancelRequest;
}

/// 认证命令的受理回执与受理时的 canonical 快照。
///
/// 适配层只保留原始调用的回执与快照；两者都必须属于同一次操作，不能把最新快照或
/// 另一个接入的状态当作本命令的证据。
@freezed
abstract class AcpAuthCommandReply with _$AcpAuthCommandReply {
  const factory AcpAuthCommandReply({
    required CommitReceipt receipt,
    required AcpAuthSnapshot snapshot,
  }) = _AcpAuthCommandReply;
}

/// 安装命令的受理回执与受理时的 canonical 快照。
@freezed
abstract class AcpInstallCommandReply with _$AcpInstallCommandReply {
  const factory AcpInstallCommandReply({
    required CommitReceipt receipt,
    required AcpInstallSnapshot snapshot,
  }) = _AcpInstallCommandReply;
}
