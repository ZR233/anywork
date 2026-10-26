/// 一个观察者对 ACP canonical 资源的租约。
library;

import '../../../resources.dart';

/// 页面级观察租约：只拥有自己的订阅，不拥有业务操作。
///
/// 同一资源可以存在多个租约；[release] 只取消本租约的观察与预算占用，不关闭共享
/// 订阅、不取消已受理的检查/登录/准备命令，也不去重其它观察者。只有仓库的
/// `close()`／`retryCleanup()` 才在既有 shutdown 预算内 join 在途操作。
abstract interface class AcpObservationLease<T> implements Observation {
  /// 只读最新值；与被观察的仓库状态是同一个发布源。
  ReadonlyLatestValue<T> get latest;

  /// 释放本租约；等价于 [cancel]，用于表达“离开页面只放弃自己的订阅”。
  void release();
}
