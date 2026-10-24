import 'package:anywork_client/studio_client.dart';

/// 把编辑保存 pending 绑到一次草稿操作，避免旧 ACK/finally 锁住或清掉新草稿。
final class AccountDraftSaveSession {
  int _epoch = 0;
  bool _saving = false;

  bool get isSaving => _saving;

  int begin() {
    _saving = true;
    return ++_epoch;
  }

  bool owns(int epoch) => _saving && epoch == _epoch;

  void succeed(int epoch) {
    if (!owns(epoch)) return;
    _saving = false;
  }

  void fail(int epoch) {
    if (!owns(epoch)) return;
    _saving = false;
  }

  void abandon() {
    _epoch++;
    _saving = false;
  }
}

/// 一次取消尝试的身份：表单实例 + provider + 目标 operation + 唯一序号。
typedef AcpCancelAttempt = ({
  String formId,
  AcpProviderView provider,
  String operationId,
  int sequence,
});

/// 把“取消在途/取消失败”绑到具体草稿与 operation。
///
/// 只做本地观察记账：换草稿或换 operation 后旧回执不再写错误位、也不再清掉新
/// 尝试的 pending；它**不取消**已发出的产品命令，Client 仍拥有该命令与资源。
final class AccountDraftCancelSession {
  int _sequence = 0;
  AcpCancelAttempt? _inFlight;

  AcpCancelAttempt? get inFlight => _inFlight;

  /// 该「表单 + provider + 目标 operation」是否有本 session 发起的取消在途。
  ///
  /// 同一表单换了 operation（旧操作已由事件终止、用户显式重试新操作）时旧在途
  /// 不再算 pending：否则新操作会被旧回执锁住。
  bool isPending({
    required String formId,
    required AcpProviderView provider,
    required String operationId,
  }) {
    final current = _inFlight;
    return current != null &&
        current.formId == formId &&
        current.provider == provider &&
        current.operationId == operationId;
  }

  /// 发起一次取消：只有完全相同的目标（表单+provider+operation）在途时才拒绝。
  ///
  /// [operationId] 必须是非空 canonical 目标：没有目标就没有可取消的身份。
  AcpCancelAttempt? begin({
    required String formId,
    required AcpProviderView provider,
    required String operationId,
  }) {
    if (isPending(
      formId: formId,
      provider: provider,
      operationId: operationId,
    )) {
      return null;
    }
    return _inFlight = (
      formId: formId,
      provider: provider,
      operationId: operationId,
      sequence: ++_sequence,
    );
  }

  /// await 之后：这次尝试是否仍代表“当前表单 + 当前 provider + 同一 operation”。
  bool accepts(
    AcpCancelAttempt attempt, {
    required String? currentFormId,
    required AcpProviderView currentProvider,
    required String? currentOperationId,
  }) =>
      identical(_inFlight, attempt) &&
      currentFormId == attempt.formId &&
      currentProvider == attempt.provider &&
      currentOperationId == attempt.operationId;

  /// 尝试结束：只有它仍是当前在途才释放；返回是否由它真正释放。
  bool finish(AcpCancelAttempt attempt) {
    if (!identical(_inFlight, attempt)) return false;
    _inFlight = null;
    return true;
  }
}
