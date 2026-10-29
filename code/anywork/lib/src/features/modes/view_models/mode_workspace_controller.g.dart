// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mode_workspace_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Mode 工作区界面状态的唯一 owner。
///
/// 只管理呈现状态；文档草稿的读取、编辑与命令仍全部经 Client
/// `ModeEditorOwner`（见 design/25 §25.12），控制器不复制任何业务事实。

@ProviderFor(ModeWorkspaceController)
final modeWorkspaceControllerProvider = ModeWorkspaceControllerProvider._();

/// Mode 工作区界面状态的唯一 owner。
///
/// 只管理呈现状态；文档草稿的读取、编辑与命令仍全部经 Client
/// `ModeEditorOwner`（见 design/25 §25.12），控制器不复制任何业务事实。
final class ModeWorkspaceControllerProvider
    extends $NotifierProvider<ModeWorkspaceController, ModeWorkspaceViewState> {
  /// Mode 工作区界面状态的唯一 owner。
  ///
  /// 只管理呈现状态；文档草稿的读取、编辑与命令仍全部经 Client
  /// `ModeEditorOwner`（见 design/25 §25.12），控制器不复制任何业务事实。
  ModeWorkspaceControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modeWorkspaceControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modeWorkspaceControllerHash();

  @$internal
  @override
  ModeWorkspaceController create() => ModeWorkspaceController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ModeWorkspaceViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ModeWorkspaceViewState>(value),
    );
  }
}

String _$modeWorkspaceControllerHash() =>
    r'91d529e5f88d924e6f2f1c11351c9d503a92146d';

/// Mode 工作区界面状态的唯一 owner。
///
/// 只管理呈现状态；文档草稿的读取、编辑与命令仍全部经 Client
/// `ModeEditorOwner`（见 design/25 §25.12），控制器不复制任何业务事实。

abstract class _$ModeWorkspaceController
    extends $Notifier<ModeWorkspaceViewState> {
  ModeWorkspaceViewState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<ModeWorkspaceViewState, ModeWorkspaceViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ModeWorkspaceViewState, ModeWorkspaceViewState>,
              ModeWorkspaceViewState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
