// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider_usage_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(providerUsageStore)
final providerUsageStoreProvider = ProviderUsageStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class ProviderUsageStoreProvider
    extends
        $FunctionalProvider<
          CanonicalClockState<ProviderUsageStateSnapshot>,
          CanonicalClockState<ProviderUsageStateSnapshot>,
          CanonicalClockState<ProviderUsageStateSnapshot>
        >
    with $Provider<CanonicalClockState<ProviderUsageStateSnapshot>> {
  /// Riverpod owns this display observation; the Client owns the resource.
  ProviderUsageStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'providerUsageStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$providerUsageStoreHash();

  @$internal
  @override
  $ProviderElement<CanonicalClockState<ProviderUsageStateSnapshot>>
  $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  CanonicalClockState<ProviderUsageStateSnapshot> create(Ref ref) {
    return providerUsageStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    CanonicalClockState<ProviderUsageStateSnapshot> value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<ProviderUsageStateSnapshot>>(
            value,
          ),
    );
  }
}

String _$providerUsageStoreHash() =>
    r'd8ca1b9a4d47980788f59a2d858bfab11c45c65a';
