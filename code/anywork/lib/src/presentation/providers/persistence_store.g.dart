// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'persistence_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(persistenceStore)
final persistenceStoreProvider = PersistenceStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class PersistenceStoreProvider
    extends
        $FunctionalProvider<
          PersistenceStoreState,
          PersistenceStoreState,
          PersistenceStoreState
        >
    with $Provider<PersistenceStoreState> {
  /// Riverpod owns this display observation; the Client owns the resource.
  PersistenceStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'persistenceStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$persistenceStoreHash();

  @$internal
  @override
  $ProviderElement<PersistenceStoreState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PersistenceStoreState create(Ref ref) {
    return persistenceStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PersistenceStoreState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PersistenceStoreState>(value),
    );
  }
}

String _$persistenceStoreHash() => r'64e375acf584a3dca4a803b4735ecbe18dddc228';
