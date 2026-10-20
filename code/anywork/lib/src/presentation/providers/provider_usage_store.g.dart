// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider_usage_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(accountUsageStore)
final accountUsageStoreProvider = AccountUsageStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class AccountUsageStoreProvider
    extends
        $FunctionalProvider<
          CanonicalClockState<AccountUsageStateSnapshot>,
          CanonicalClockState<AccountUsageStateSnapshot>,
          CanonicalClockState<AccountUsageStateSnapshot>
        >
    with $Provider<CanonicalClockState<AccountUsageStateSnapshot>> {
  /// Riverpod owns this display observation; the Client owns the resource.
  AccountUsageStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountUsageStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountUsageStoreHash();

  @$internal
  @override
  $ProviderElement<CanonicalClockState<AccountUsageStateSnapshot>>
  $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  CanonicalClockState<AccountUsageStateSnapshot> create(Ref ref) {
    return accountUsageStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    CanonicalClockState<AccountUsageStateSnapshot> value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<AccountUsageStateSnapshot>>(
            value,
          ),
    );
  }
}

String _$accountUsageStoreHash() => r'ec14e1baf41bc25dcfcf3eee07de9b67b12d40c8';
