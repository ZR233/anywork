import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/studio_client.dart'
    show AcpInstallSnapshotView, AcpInstallStateView, AcpInstalledServerView;

/// ACP 官方 server 准备的只读适配。
///
/// Client 拥有 `acpInstall` store 与产品 topic 租约；这里只借用当前 canonical
/// 快照。Ref 销毁只取消本次观察，不取消下载，也不拥有任务关闭权。
final acpInstallStateProvider =
    Provider.autoDispose<CanonicalClockState<AcpInstallSnapshotView>>((ref) {
      final source = ref.read(anyworkClientProvider).acpInstall.source;
      return observeClient(ref, source, (_) => ref.invalidateSelf());
    }, name: 'acpInstallStateProvider');
