// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_commands.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 设置写入的单一串行 lane。
///
/// 每次执行读取 settingsStore 的配置 revision 作 CAS。`staleRevision` / `conflict`
/// 先刷新 canonical，再重试最多两次。成功只走 [SettingsStore.merge]；失败只写
/// 命令状态区。不乐观改 canonical，也不提供 generation map、flush 或超时。

@ProviderFor(SettingsCommands)
final settingsCommandsProvider = SettingsCommandsProvider._();

/// 设置写入的单一串行 lane。
///
/// 每次执行读取 settingsStore 的配置 revision 作 CAS。`staleRevision` / `conflict`
/// 先刷新 canonical，再重试最多两次。成功只走 [SettingsStore.merge]；失败只写
/// 命令状态区。不乐观改 canonical，也不提供 generation map、flush 或超时。
final class SettingsCommandsProvider
    extends $NotifierProvider<SettingsCommands, SettingsCommandLaneState> {
  /// 设置写入的单一串行 lane。
  ///
  /// 每次执行读取 settingsStore 的配置 revision 作 CAS。`staleRevision` / `conflict`
  /// 先刷新 canonical，再重试最多两次。成功只走 [SettingsStore.merge]；失败只写
  /// 命令状态区。不乐观改 canonical，也不提供 generation map、flush 或超时。
  SettingsCommandsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsCommandsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsCommandsHash();

  @$internal
  @override
  SettingsCommands create() => SettingsCommands();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsCommandLaneState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsCommandLaneState>(value),
    );
  }
}

String _$settingsCommandsHash() => r'009eccac4ae8c1feb9577d2027825a002a70d8c8';

/// 设置写入的单一串行 lane。
///
/// 每次执行读取 settingsStore 的配置 revision 作 CAS。`staleRevision` / `conflict`
/// 先刷新 canonical，再重试最多两次。成功只走 [SettingsStore.merge]；失败只写
/// 命令状态区。不乐观改 canonical，也不提供 generation map、flush 或超时。

abstract class _$SettingsCommands extends $Notifier<SettingsCommandLaneState> {
  SettingsCommandLaneState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<SettingsCommandLaneState, SettingsCommandLaneState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SettingsCommandLaneState, SettingsCommandLaneState>,
              SettingsCommandLaneState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
