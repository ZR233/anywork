// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_account_auth_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 一个已保存接入的认证状态与命令。
///
/// 业务状态只来自 canonical `acpAuth` 观察：本 VM 持有自己的观察租约，离开页面/重建/返回
/// 只释放自身租约，不取消已受理的检查或登录，也不重启检查。命令只提交意图并记录受理与
/// 结果；`closing`/`cancelling` 是忙而不是终态，取消入口只由 canonical 的 operation 身份
/// 决定是否可达。

@ProviderFor(AcpAccountAuthViewModel)
final acpAccountAuthViewModelProvider = AcpAccountAuthViewModelFamily._();

/// 一个已保存接入的认证状态与命令。
///
/// 业务状态只来自 canonical `acpAuth` 观察：本 VM 持有自己的观察租约，离开页面/重建/返回
/// 只释放自身租约，不取消已受理的检查或登录，也不重启检查。命令只提交意图并记录受理与
/// 结果；`closing`/`cancelling` 是忙而不是终态，取消入口只由 canonical 的 operation 身份
/// 决定是否可达。
final class AcpAccountAuthViewModelProvider
    extends
        $AsyncNotifierProvider<
          AcpAccountAuthViewModel,
          AcpAccountAuthViewState
        > {
  /// 一个已保存接入的认证状态与命令。
  ///
  /// 业务状态只来自 canonical `acpAuth` 观察：本 VM 持有自己的观察租约，离开页面/重建/返回
  /// 只释放自身租约，不取消已受理的检查或登录，也不重启检查。命令只提交意图并记录受理与
  /// 结果；`closing`/`cancelling` 是忙而不是终态，取消入口只由 canonical 的 operation 身份
  /// 决定是否可达。
  AcpAccountAuthViewModelProvider._({
    required AcpAccountAuthViewModelFamily super.from,
    required AcpAccountTarget super.argument,
  }) : super(
         retry: null,
         name: r'acpAccountAuthViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpAccountAuthViewModelHash();

  @override
  String toString() {
    return r'acpAccountAuthViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AcpAccountAuthViewModel create() => AcpAccountAuthViewModel();

  @override
  bool operator ==(Object other) {
    return other is AcpAccountAuthViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpAccountAuthViewModelHash() =>
    r'2e9e71e6db37eb3afbc7c55682d32d70163d2022';

/// 一个已保存接入的认证状态与命令。
///
/// 业务状态只来自 canonical `acpAuth` 观察：本 VM 持有自己的观察租约，离开页面/重建/返回
/// 只释放自身租约，不取消已受理的检查或登录，也不重启检查。命令只提交意图并记录受理与
/// 结果；`closing`/`cancelling` 是忙而不是终态，取消入口只由 canonical 的 operation 身份
/// 决定是否可达。

final class AcpAccountAuthViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AcpAccountAuthViewModel,
          AsyncValue<AcpAccountAuthViewState>,
          AcpAccountAuthViewState,
          FutureOr<AcpAccountAuthViewState>,
          AcpAccountTarget
        > {
  AcpAccountAuthViewModelFamily._()
    : super(
        retry: null,
        name: r'acpAccountAuthViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 一个已保存接入的认证状态与命令。
  ///
  /// 业务状态只来自 canonical `acpAuth` 观察：本 VM 持有自己的观察租约，离开页面/重建/返回
  /// 只释放自身租约，不取消已受理的检查或登录，也不重启检查。命令只提交意图并记录受理与
  /// 结果；`closing`/`cancelling` 是忙而不是终态，取消入口只由 canonical 的 operation 身份
  /// 决定是否可达。

  AcpAccountAuthViewModelProvider call(AcpAccountTarget target) =>
      AcpAccountAuthViewModelProvider._(argument: target, from: this);

  @override
  String toString() => r'acpAccountAuthViewModelProvider';
}

/// 一个已保存接入的认证状态与命令。
///
/// 业务状态只来自 canonical `acpAuth` 观察：本 VM 持有自己的观察租约，离开页面/重建/返回
/// 只释放自身租约，不取消已受理的检查或登录，也不重启检查。命令只提交意图并记录受理与
/// 结果；`closing`/`cancelling` 是忙而不是终态，取消入口只由 canonical 的 operation 身份
/// 决定是否可达。

abstract class _$AcpAccountAuthViewModel
    extends $AsyncNotifier<AcpAccountAuthViewState> {
  late final _$args = ref.$arg as AcpAccountTarget;
  AcpAccountTarget get target => _$args;

  FutureOr<AcpAccountAuthViewState> build(AcpAccountTarget target);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<AcpAccountAuthViewState>,
              AcpAccountAuthViewState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AcpAccountAuthViewState>,
                AcpAccountAuthViewState
              >,
              AsyncValue<AcpAccountAuthViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
