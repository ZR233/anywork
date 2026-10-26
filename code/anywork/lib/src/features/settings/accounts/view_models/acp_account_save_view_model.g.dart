// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_account_save_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// ACP 账号“保存并连接”的编排 owner。
///
/// 保存写入属于 `configuration`，连接检查属于 `acpAuth`；本 VM 是唯一同时持有两者的地方，
/// 因此编辑 VM 不需要第二个资源。两步严格顺序执行：
/// 1. 提交配置写入并等它**结算**（canonical 事实成立，不只是受理）；
/// 2. 重新读取 ACP 目录解析该账号的连接代次，再以冻结的代次提交连接检查。
///
/// 第二步失败只表达“账号已保存，连接未完成”：不回滚保存、不清空调用方草稿、不重发保存，
/// 也不从本地布尔值推断登录成功。名称编辑（非新建）只写配置，不发起检查。

@ProviderFor(AcpAccountSaveViewModel)
final acpAccountSaveViewModelProvider = AcpAccountSaveViewModelFamily._();

/// ACP 账号“保存并连接”的编排 owner。
///
/// 保存写入属于 `configuration`，连接检查属于 `acpAuth`；本 VM 是唯一同时持有两者的地方，
/// 因此编辑 VM 不需要第二个资源。两步严格顺序执行：
/// 1. 提交配置写入并等它**结算**（canonical 事实成立，不只是受理）；
/// 2. 重新读取 ACP 目录解析该账号的连接代次，再以冻结的代次提交连接检查。
///
/// 第二步失败只表达“账号已保存，连接未完成”：不回滚保存、不清空调用方草稿、不重发保存，
/// 也不从本地布尔值推断登录成功。名称编辑（非新建）只写配置，不发起检查。
final class AcpAccountSaveViewModelProvider
    extends
        $AsyncNotifierProvider<
          AcpAccountSaveViewModel,
          AcpAccountSaveViewState
        > {
  /// ACP 账号“保存并连接”的编排 owner。
  ///
  /// 保存写入属于 `configuration`，连接检查属于 `acpAuth`；本 VM 是唯一同时持有两者的地方，
  /// 因此编辑 VM 不需要第二个资源。两步严格顺序执行：
  /// 1. 提交配置写入并等它**结算**（canonical 事实成立，不只是受理）；
  /// 2. 重新读取 ACP 目录解析该账号的连接代次，再以冻结的代次提交连接检查。
  ///
  /// 第二步失败只表达“账号已保存，连接未完成”：不回滚保存、不清空调用方草稿、不重发保存，
  /// 也不从本地布尔值推断登录成功。名称编辑（非新建）只写配置，不发起检查。
  AcpAccountSaveViewModelProvider._({
    required AcpAccountSaveViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpAccountSaveViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpAccountSaveViewModelHash();

  @override
  String toString() {
    return r'acpAccountSaveViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AcpAccountSaveViewModel create() => AcpAccountSaveViewModel();

  @override
  bool operator ==(Object other) {
    return other is AcpAccountSaveViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpAccountSaveViewModelHash() =>
    r'9e9fe90e37cee27341bfb5f1677b904fed8c5470';

/// ACP 账号“保存并连接”的编排 owner。
///
/// 保存写入属于 `configuration`，连接检查属于 `acpAuth`；本 VM 是唯一同时持有两者的地方，
/// 因此编辑 VM 不需要第二个资源。两步严格顺序执行：
/// 1. 提交配置写入并等它**结算**（canonical 事实成立，不只是受理）；
/// 2. 重新读取 ACP 目录解析该账号的连接代次，再以冻结的代次提交连接检查。
///
/// 第二步失败只表达“账号已保存，连接未完成”：不回滚保存、不清空调用方草稿、不重发保存，
/// 也不从本地布尔值推断登录成功。名称编辑（非新建）只写配置，不发起检查。

final class AcpAccountSaveViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AcpAccountSaveViewModel,
          AsyncValue<AcpAccountSaveViewState>,
          AcpAccountSaveViewState,
          FutureOr<AcpAccountSaveViewState>,
          String
        > {
  AcpAccountSaveViewModelFamily._()
    : super(
        retry: null,
        name: r'acpAccountSaveViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// ACP 账号“保存并连接”的编排 owner。
  ///
  /// 保存写入属于 `configuration`，连接检查属于 `acpAuth`；本 VM 是唯一同时持有两者的地方，
  /// 因此编辑 VM 不需要第二个资源。两步严格顺序执行：
  /// 1. 提交配置写入并等它**结算**（canonical 事实成立，不只是受理）；
  /// 2. 重新读取 ACP 目录解析该账号的连接代次，再以冻结的代次提交连接检查。
  ///
  /// 第二步失败只表达“账号已保存，连接未完成”：不回滚保存、不清空调用方草稿、不重发保存，
  /// 也不从本地布尔值推断登录成功。名称编辑（非新建）只写配置，不发起检查。

  AcpAccountSaveViewModelProvider call(String accountId) =>
      AcpAccountSaveViewModelProvider._(argument: accountId, from: this);

  @override
  String toString() => r'acpAccountSaveViewModelProvider';
}

/// ACP 账号“保存并连接”的编排 owner。
///
/// 保存写入属于 `configuration`，连接检查属于 `acpAuth`；本 VM 是唯一同时持有两者的地方，
/// 因此编辑 VM 不需要第二个资源。两步严格顺序执行：
/// 1. 提交配置写入并等它**结算**（canonical 事实成立，不只是受理）；
/// 2. 重新读取 ACP 目录解析该账号的连接代次，再以冻结的代次提交连接检查。
///
/// 第二步失败只表达“账号已保存，连接未完成”：不回滚保存、不清空调用方草稿、不重发保存，
/// 也不从本地布尔值推断登录成功。名称编辑（非新建）只写配置，不发起检查。

abstract class _$AcpAccountSaveViewModel
    extends $AsyncNotifier<AcpAccountSaveViewState> {
  late final _$args = ref.$arg as String;
  String get accountId => _$args;

  FutureOr<AcpAccountSaveViewState> build(String accountId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<AcpAccountSaveViewState>,
              AcpAccountSaveViewState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AcpAccountSaveViewState>,
                AcpAccountSaveViewState
              >,
              AsyncValue<AcpAccountSaveViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
