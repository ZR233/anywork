// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(mcpStore)
final mcpStoreProvider = McpStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class McpStoreProvider
    extends
        $FunctionalProvider<
          CanonicalClockState<McpStateSnapshot>,
          CanonicalClockState<McpStateSnapshot>,
          CanonicalClockState<McpStateSnapshot>
        >
    with $Provider<CanonicalClockState<McpStateSnapshot>> {
  /// Riverpod owns this display observation; the Client owns the resource.
  McpStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mcpStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpStoreHash();

  @$internal
  @override
  $ProviderElement<CanonicalClockState<McpStateSnapshot>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CanonicalClockState<McpStateSnapshot> create(Ref ref) {
    return mcpStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<McpStateSnapshot> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<McpStateSnapshot>>(value),
    );
  }
}

String _$mcpStoreHash() => r'62d169e67e548a8bc4cfd778aa75d061c156c4ec';
