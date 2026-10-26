// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_account_editor_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// ACP 接入新建/编辑表单的状态与受管安装准备编排。
///
/// 表单持有自己的 `acpInstall` 观察租约：离开页面/重建/返回只释放自身租约，不取消已受理
/// 的准备，也不重新发起准备。安装事实只来自 canonical 快照；本 VM 不从进度推断就绪，也
/// 不在准备成功时创建账号——保存与写入属于配置领域，由调用方在准备就绪后显式提交。

@ProviderFor(AcpAccountEditorViewModel)
final acpAccountEditorViewModelProvider = AcpAccountEditorViewModelFamily._();

/// ACP 接入新建/编辑表单的状态与受管安装准备编排。
///
/// 表单持有自己的 `acpInstall` 观察租约：离开页面/重建/返回只释放自身租约，不取消已受理
/// 的准备，也不重新发起准备。安装事实只来自 canonical 快照；本 VM 不从进度推断就绪，也
/// 不在准备成功时创建账号——保存与写入属于配置领域，由调用方在准备就绪后显式提交。
final class AcpAccountEditorViewModelProvider
    extends
        $AsyncNotifierProvider<
          AcpAccountEditorViewModel,
          AcpAccountEditorViewState
        > {
  /// ACP 接入新建/编辑表单的状态与受管安装准备编排。
  ///
  /// 表单持有自己的 `acpInstall` 观察租约：离开页面/重建/返回只释放自身租约，不取消已受理
  /// 的准备，也不重新发起准备。安装事实只来自 canonical 快照；本 VM 不从进度推断就绪，也
  /// 不在准备成功时创建账号——保存与写入属于配置领域，由调用方在准备就绪后显式提交。
  AcpAccountEditorViewModelProvider._({
    required AcpAccountEditorViewModelFamily super.from,
    required AcpAccountEditorTarget super.argument,
  }) : super(
         retry: null,
         name: r'acpAccountEditorViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpAccountEditorViewModelHash();

  @override
  String toString() {
    return r'acpAccountEditorViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AcpAccountEditorViewModel create() => AcpAccountEditorViewModel();

  @override
  bool operator ==(Object other) {
    return other is AcpAccountEditorViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpAccountEditorViewModelHash() =>
    r'dcf87b60eac4eea5299a887a59508652a2b73cb6';

/// ACP 接入新建/编辑表单的状态与受管安装准备编排。
///
/// 表单持有自己的 `acpInstall` 观察租约：离开页面/重建/返回只释放自身租约，不取消已受理
/// 的准备，也不重新发起准备。安装事实只来自 canonical 快照；本 VM 不从进度推断就绪，也
/// 不在准备成功时创建账号——保存与写入属于配置领域，由调用方在准备就绪后显式提交。

final class AcpAccountEditorViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AcpAccountEditorViewModel,
          AsyncValue<AcpAccountEditorViewState>,
          AcpAccountEditorViewState,
          FutureOr<AcpAccountEditorViewState>,
          AcpAccountEditorTarget
        > {
  AcpAccountEditorViewModelFamily._()
    : super(
        retry: null,
        name: r'acpAccountEditorViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// ACP 接入新建/编辑表单的状态与受管安装准备编排。
  ///
  /// 表单持有自己的 `acpInstall` 观察租约：离开页面/重建/返回只释放自身租约，不取消已受理
  /// 的准备，也不重新发起准备。安装事实只来自 canonical 快照；本 VM 不从进度推断就绪，也
  /// 不在准备成功时创建账号——保存与写入属于配置领域，由调用方在准备就绪后显式提交。

  AcpAccountEditorViewModelProvider call(AcpAccountEditorTarget target) =>
      AcpAccountEditorViewModelProvider._(argument: target, from: this);

  @override
  String toString() => r'acpAccountEditorViewModelProvider';
}

/// ACP 接入新建/编辑表单的状态与受管安装准备编排。
///
/// 表单持有自己的 `acpInstall` 观察租约：离开页面/重建/返回只释放自身租约，不取消已受理
/// 的准备，也不重新发起准备。安装事实只来自 canonical 快照；本 VM 不从进度推断就绪，也
/// 不在准备成功时创建账号——保存与写入属于配置领域，由调用方在准备就绪后显式提交。

abstract class _$AcpAccountEditorViewModel
    extends $AsyncNotifier<AcpAccountEditorViewState> {
  late final _$args = ref.$arg as AcpAccountEditorTarget;
  AcpAccountEditorTarget get target => _$args;

  FutureOr<AcpAccountEditorViewState> build(AcpAccountEditorTarget target);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<AcpAccountEditorViewState>,
              AcpAccountEditorViewState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AcpAccountEditorViewState>,
                AcpAccountEditorViewState
              >,
              AsyncValue<AcpAccountEditorViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
