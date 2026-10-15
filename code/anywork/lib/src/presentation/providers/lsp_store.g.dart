// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lsp_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(lspStore)
final lspStoreProvider = LspStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class LspStoreProvider
    extends
        $FunctionalProvider<
          CanonicalClockState<LspStateSnapshot>,
          CanonicalClockState<LspStateSnapshot>,
          CanonicalClockState<LspStateSnapshot>
        >
    with $Provider<CanonicalClockState<LspStateSnapshot>> {
  /// Riverpod owns this display observation; the Client owns the resource.
  LspStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lspStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lspStoreHash();

  @$internal
  @override
  $ProviderElement<CanonicalClockState<LspStateSnapshot>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CanonicalClockState<LspStateSnapshot> create(Ref ref) {
    return lspStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<LspStateSnapshot> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<LspStateSnapshot>>(value),
    );
  }
}

String _$lspStoreHash() => r'f1010103a552180c90d6d1b9e55823e4014af2d1';
