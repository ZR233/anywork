// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mode_catalog_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(modeCatalogStore)
final modeCatalogStoreProvider = ModeCatalogStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class ModeCatalogStoreProvider
    extends
        $FunctionalProvider<
          CanonicalClockState<ThreadModeCatalogView>,
          CanonicalClockState<ThreadModeCatalogView>,
          CanonicalClockState<ThreadModeCatalogView>
        >
    with $Provider<CanonicalClockState<ThreadModeCatalogView>> {
  /// Riverpod owns this display observation; the Client owns the resource.
  ModeCatalogStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modeCatalogStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modeCatalogStoreHash();

  @$internal
  @override
  $ProviderElement<CanonicalClockState<ThreadModeCatalogView>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CanonicalClockState<ThreadModeCatalogView> create(Ref ref) {
    return modeCatalogStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<ThreadModeCatalogView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<ThreadModeCatalogView>>(value),
    );
  }
}

String _$modeCatalogStoreHash() => r'e2d2a107f94d352c802e0e506576ee7ee7aeb481';
