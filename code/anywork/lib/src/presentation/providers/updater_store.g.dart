// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'updater_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(updaterStore)
final updaterStoreProvider = UpdaterStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class UpdaterStoreProvider
    extends
        $FunctionalProvider<
          CanonicalClockState<UpdaterStateSnapshot>,
          CanonicalClockState<UpdaterStateSnapshot>,
          CanonicalClockState<UpdaterStateSnapshot>
        >
    with $Provider<CanonicalClockState<UpdaterStateSnapshot>> {
  /// Riverpod owns this display observation; the Client owns the resource.
  UpdaterStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'updaterStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$updaterStoreHash();

  @$internal
  @override
  $ProviderElement<CanonicalClockState<UpdaterStateSnapshot>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CanonicalClockState<UpdaterStateSnapshot> create(Ref ref) {
    return updaterStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<UpdaterStateSnapshot> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<UpdaterStateSnapshot>>(value),
    );
  }
}

String _$updaterStoreHash() => r'7f514e7d358193ca81ca8368f0b8543ab1ba1238';
