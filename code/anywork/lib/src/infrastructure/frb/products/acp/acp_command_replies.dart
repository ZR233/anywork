import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/types/acp.dart' as native;
import '../../../../rust/api/studio/types/acp_install.dart' as native_install;
import '../../../../rust/api/studio/types/command.dart' as native_command;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/receipt_converters.dart';
import 'acp_converters.dart';

/// ACP 显式命令的调用边界：受理回执与受理时快照分别验证。
///
/// 生成的 ACP 入口只返回 `Result<Reply, BridgeError>`，没有 draft 那样的 typed 拒绝
/// 边界，因此调用后的任何普通失败都只能记为
/// [UnknownOutcomeCommandDispatchFailure]：错误码与消息都不能证明这次意图没有被
/// 受理，适配层也不据此自动重发。已经被原生层确认的受理必须保留真实证据：
/// 无法转换快照时使用 [CommittedButUnobservedCommandDispatchFailure]（保留回执），
/// 连回执都无法转换时才退到
/// [ConfirmedWithoutUsableReceiptCommandDispatchFailure]。两者都不会合成 rejected。
StudioFailure acpCommandFailure(Object error) {
  if (error case CommandDispatchFailure(:final failure)) return failure;
  try {
    return bridgeFailure(error);
  } on Object catch (mappingError) {
    return adapterFailure(mappingError, operation: 'acp-command');
  }
}

/// 调用一个 ACP 命令并完成回执转换；不做重试、不合并认证与安装的受理身份。
Future<({CommitReceipt receipt, R value})> acpCommandDispatch<R>(
  Future<R> Function() send, {
  required native_command.BridgeStudioCommandReceipt Function(R) receiptOf,
}) async {
  final R value;
  try {
    value = await send();
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(
      CommandDispatchFailure.unknownOutcome(failure: acpCommandFailure(error)),
      stack,
    );
  }
  final CommitReceipt receipt;
  try {
    receipt = commitReceiptFromBridge(receiptOf(value));
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(
      CommandDispatchFailure.confirmedWithoutUsableReceipt(
        failure: acpCommandFailure(error),
      ),
      stack,
    );
  }
  return (receipt: receipt, value: value);
}

/// `startAcpAuth`／`cancelAcpAuth` 的受理回执与受理时认证快照。
Future<AcpAuthCommandReply> acpAuthCommand(
  Future<native.BridgeAcpAuthCommandReply> Function() send,
) async {
  final dispatched = await acpCommandDispatch(
    send,
    receiptOf: (value) => value.receipt,
  );
  final AcpAuthSnapshot snapshot;
  try {
    snapshot = acpAuthSnapshotFromBridge(dispatched.value.snapshot);
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(
      CommandDispatchFailure.committedButUnobserved(
        receipt: dispatched.receipt,
        failure: acpCommandFailure(error),
      ),
      stack,
    );
  }
  return AcpAuthCommandReply(receipt: dispatched.receipt, snapshot: snapshot);
}

/// `startAcpInstall`／`cancelAcpInstall` 的受理回执与受理时安装快照。
///
/// 受理只证明准备操作被接受：进度、阶段与就绪仍由 `acpInstall` 观察收敛。
Future<AcpInstallCommandReply> acpInstallCommand(
  Future<native_install.BridgeAcpInstallCommandReply> Function() send,
) async {
  final dispatched = await acpCommandDispatch(
    send,
    receiptOf: (value) => value.receipt,
  );
  final AcpInstallSnapshot snapshot;
  try {
    snapshot = acpInstallSnapshotFromBridge(dispatched.value.snapshot);
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(
      CommandDispatchFailure.committedButUnobserved(
        receipt: dispatched.receipt,
        failure: acpCommandFailure(error),
      ),
      stack,
    );
  }
  return AcpInstallCommandReply(
    receipt: dispatched.receipt,
    snapshot: snapshot,
  );
}
