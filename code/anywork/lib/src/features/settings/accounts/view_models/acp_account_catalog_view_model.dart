import 'package:anywork_client/acp.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';

part 'acp_account_catalog_view_model.g.dart';

/// ACP 接入模板目录（只读默认值：显示名、固定受管版本、官方说明地址与安装资格）。
///
/// 目录是产品默认值而不是事实：本 VM 只在显式需求时做一次有界读取，不联网、不启动程序、
/// 不缓存为第二事实源，也不据此推断安装或认证结果。ACP 接入与 Native 模板在展示层合并为
/// 统一入口的 typed 选项。
@riverpod
class AcpAccountCatalogViewModel extends _$AcpAccountCatalogViewModel {
  @override
  Future<AcpAccountCatalog> build() =>
      ref.watch(acpAuthRepositoryProvider).readCatalog();

  /// 显式重新读取；失败作为 typed 失败保留，不退回空目录冒充成功。
  Future<void> reload() async {
    try {
      final catalog = await ref.read(acpAuthRepositoryProvider).readCatalog();
      state = AsyncData(catalog);
    } on StudioFailure catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }
}
