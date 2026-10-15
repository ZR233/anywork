// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recovery_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(recoveryStore)
final recoveryStoreProvider = RecoveryStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class RecoveryStoreProvider
    extends
        $FunctionalProvider<
          CanonicalClockState<RecoveryStateSnapshot>,
          CanonicalClockState<RecoveryStateSnapshot>,
          CanonicalClockState<RecoveryStateSnapshot>
        >
    with $Provider<CanonicalClockState<RecoveryStateSnapshot>> {
  /// Riverpod owns this display observation; the Client owns the resource.
  RecoveryStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recoveryStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recoveryStoreHash();

  @$internal
  @override
  $ProviderElement<CanonicalClockState<RecoveryStateSnapshot>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CanonicalClockState<RecoveryStateSnapshot> create(Ref ref) {
    return recoveryStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<RecoveryStateSnapshot> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<RecoveryStateSnapshot>>(value),
    );
  }
}

String _$recoveryStoreHash() => r'4fd6205601bf044943159cd8fa8a5abfd179e24a';
