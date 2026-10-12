import '../../domain/models/studio_models.dart';
import '../stores/domain_sync.dart';

/// 串行命令 lane。
///
/// 尾部 future 故意不失败：一条命令失败只返回给调用方，不毒化后续命令。
/// 不提供 flush、超时或 generation map；页面离开不取消已入队命令。
class CommandLane {
  Future<void> _tail = Future<void>.value();

  Future<T> enqueue<T>(Future<T> Function() operation) {
    final task = _tail.then((_) => operation());
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }
}

/// revision / conflict 就地刷新后重试，最多两次。刷新失败则保留原冲突。
Future<T> retryRevisionConflict<T>(
  Future<T> Function() attempt, {
  required Future<bool> Function() refresh,
}) async {
  var retries = 0;
  while (true) {
    try {
      return await attempt();
    } on StudioFailure catch (error, stackTrace) {
      if (!isRetryableRevisionFailure(error) || retries >= 2) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      retries += 1;
      if (!await refresh()) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }
}
