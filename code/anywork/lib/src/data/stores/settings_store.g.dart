// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 设置域：配置 revision 与模型目录 revision 独立比较。
///
/// 命令 in-flight 结果放在 [commands]，不写入 canonical 字段。
/// 未加载的时钟不会因为另一路快照夹带的水位而被标记为已消费。

@ProviderFor(SettingsStore)
final settingsStoreProvider = SettingsStoreProvider._();

/// 设置域：配置 revision 与模型目录 revision 独立比较。
///
/// 命令 in-flight 结果放在 [commands]，不写入 canonical 字段。
/// 未加载的时钟不会因为另一路快照夹带的水位而被标记为已消费。
final class SettingsStoreProvider
    extends $NotifierProvider<SettingsStore, SettingsStoreState> {
  /// 设置域：配置 revision 与模型目录 revision 独立比较。
  ///
  /// 命令 in-flight 结果放在 [commands]，不写入 canonical 字段。
  /// 未加载的时钟不会因为另一路快照夹带的水位而被标记为已消费。
  SettingsStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsStoreHash();

  @$internal
  @override
  SettingsStore create() => SettingsStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsStoreState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsStoreState>(value),
    );
  }
}

String _$settingsStoreHash() => r'8187b6eb3b938263da5db766f003bd2f005ee01d';

/// 设置域：配置 revision 与模型目录 revision 独立比较。
///
/// 命令 in-flight 结果放在 [commands]，不写入 canonical 字段。
/// 未加载的时钟不会因为另一路快照夹带的水位而被标记为已消费。

abstract class _$SettingsStore extends $Notifier<SettingsStoreState> {
  SettingsStoreState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SettingsStoreState, SettingsStoreState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SettingsStoreState, SettingsStoreState>,
              SettingsStoreState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
