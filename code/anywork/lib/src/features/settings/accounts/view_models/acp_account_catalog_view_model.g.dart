// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_account_catalog_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// ACP 接入模板目录（只读默认值：显示名、固定受管版本、官方说明地址与安装资格）。
///
/// 目录是产品默认值而不是事实：本 VM 只在显式需求时做一次有界读取，不联网、不启动程序、
/// 不缓存为第二事实源，也不据此推断安装或认证结果。ACP 接入与 Native 模板在展示层合并为
/// 统一入口的 typed 选项。

@ProviderFor(AcpAccountCatalogViewModel)
final acpAccountCatalogViewModelProvider =
    AcpAccountCatalogViewModelProvider._();

/// ACP 接入模板目录（只读默认值：显示名、固定受管版本、官方说明地址与安装资格）。
///
/// 目录是产品默认值而不是事实：本 VM 只在显式需求时做一次有界读取，不联网、不启动程序、
/// 不缓存为第二事实源，也不据此推断安装或认证结果。ACP 接入与 Native 模板在展示层合并为
/// 统一入口的 typed 选项。
final class AcpAccountCatalogViewModelProvider
    extends
        $AsyncNotifierProvider<AcpAccountCatalogViewModel, AcpAccountCatalog> {
  /// ACP 接入模板目录（只读默认值：显示名、固定受管版本、官方说明地址与安装资格）。
  ///
  /// 目录是产品默认值而不是事实：本 VM 只在显式需求时做一次有界读取，不联网、不启动程序、
  /// 不缓存为第二事实源，也不据此推断安装或认证结果。ACP 接入与 Native 模板在展示层合并为
  /// 统一入口的 typed 选项。
  AcpAccountCatalogViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'acpAccountCatalogViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$acpAccountCatalogViewModelHash();

  @$internal
  @override
  AcpAccountCatalogViewModel create() => AcpAccountCatalogViewModel();
}

String _$acpAccountCatalogViewModelHash() =>
    r'd8e0c11e4a997066a977d46bc3157d9a2baf44ec';

/// ACP 接入模板目录（只读默认值：显示名、固定受管版本、官方说明地址与安装资格）。
///
/// 目录是产品默认值而不是事实：本 VM 只在显式需求时做一次有界读取，不联网、不启动程序、
/// 不缓存为第二事实源，也不据此推断安装或认证结果。ACP 接入与 Native 模板在展示层合并为
/// 统一入口的 typed 选项。

abstract class _$AcpAccountCatalogViewModel
    extends $AsyncNotifier<AcpAccountCatalog> {
  FutureOr<AcpAccountCatalog> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<AcpAccountCatalog>, AcpAccountCatalog>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AcpAccountCatalog>, AcpAccountCatalog>,
              AsyncValue<AcpAccountCatalog>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
