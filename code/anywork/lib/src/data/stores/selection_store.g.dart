// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'selection_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 纯本地选择事实。没有 canonical revision。
///
/// [needsOpen] 是“已恢复选择但尚未打开”的待打开标记。启动恢复只写选择并置位；
/// 显式打开后清除。选择变化必须改变相等性，不能被 Riverpod 的 `==` 吞掉。

@ProviderFor(SelectionStore)
final selectionStoreProvider = SelectionStoreProvider._();

/// 纯本地选择事实。没有 canonical revision。
///
/// [needsOpen] 是“已恢复选择但尚未打开”的待打开标记。启动恢复只写选择并置位；
/// 显式打开后清除。选择变化必须改变相等性，不能被 Riverpod 的 `==` 吞掉。
final class SelectionStoreProvider
    extends $NotifierProvider<SelectionStore, SelectionStoreState> {
  /// 纯本地选择事实。没有 canonical revision。
  ///
  /// [needsOpen] 是“已恢复选择但尚未打开”的待打开标记。启动恢复只写选择并置位；
  /// 显式打开后清除。选择变化必须改变相等性，不能被 Riverpod 的 `==` 吞掉。
  SelectionStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectionStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectionStoreHash();

  @$internal
  @override
  SelectionStore create() => SelectionStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SelectionStoreState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SelectionStoreState>(value),
    );
  }
}

String _$selectionStoreHash() => r'b0c5d368cecf32e17b76cd8d9a56919eadfe6681';

/// 纯本地选择事实。没有 canonical revision。
///
/// [needsOpen] 是“已恢复选择但尚未打开”的待打开标记。启动恢复只写选择并置位；
/// 显式打开后清除。选择变化必须改变相等性，不能被 Riverpod 的 `==` 吞掉。

abstract class _$SelectionStore extends $Notifier<SelectionStoreState> {
  SelectionStoreState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SelectionStoreState, SelectionStoreState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SelectionStoreState, SelectionStoreState>,
              SelectionStoreState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
