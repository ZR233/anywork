import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/studio_client.dart'
    show AcpAuthSnapshotView, AcpAuthStateView;

/// ACP 认证观察的只读适配。
///
/// Client 拥有 `acpAuth` store 与产品 topic 租约；这里只借用当前 canonical 快照。
/// Ref 销毁只取消本次观察，不取消已启动的检查或登录。
final acpAuthStateProvider =
    Provider.autoDispose<CanonicalClockState<AcpAuthSnapshotView>>((ref) {
      final source = ref.read(anyworkClientProvider).acpAuth.source;
      return observeClient(ref, source, (_) => ref.invalidateSelf());
    }, name: 'acpAuthStateProvider');
