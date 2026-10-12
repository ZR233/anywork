// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mode_catalog_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Mode 目录。时钟是 [ThreadModeCatalogView.revision]。

@ProviderFor(ModeCatalogStore)
final modeCatalogStoreProvider = ModeCatalogStoreProvider._();

/// Mode 目录。时钟是 [ThreadModeCatalogView.revision]。
final class ModeCatalogStoreProvider
    extends
        $NotifierProvider<
          ModeCatalogStore,
          CanonicalClockState<ThreadModeCatalogView>
        > {
  /// Mode 目录。时钟是 [ThreadModeCatalogView.revision]。
  ModeCatalogStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modeCatalogStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modeCatalogStoreHash();

  @$internal
  @override
  ModeCatalogStore create() => ModeCatalogStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<ThreadModeCatalogView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<ThreadModeCatalogView>>(value),
    );
  }
}

String _$modeCatalogStoreHash() => r'2ca7449e7c288351d9cfb44c87ed31ebd24d7d87';

/// Mode 目录。时钟是 [ThreadModeCatalogView.revision]。

abstract class _$ModeCatalogStore
    extends $Notifier<CanonicalClockState<ThreadModeCatalogView>> {
  CanonicalClockState<ThreadModeCatalogView> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              CanonicalClockState<ThreadModeCatalogView>,
              CanonicalClockState<ThreadModeCatalogView>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                CanonicalClockState<ThreadModeCatalogView>,
                CanonicalClockState<ThreadModeCatalogView>
              >,
              CanonicalClockState<ThreadModeCatalogView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
