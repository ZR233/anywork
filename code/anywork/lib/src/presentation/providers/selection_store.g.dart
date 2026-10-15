// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'selection_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(selectionStore)
final selectionStoreProvider = SelectionStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class SelectionStoreProvider
    extends
        $FunctionalProvider<
          SelectionStoreState,
          SelectionStoreState,
          SelectionStoreState
        >
    with $Provider<SelectionStoreState> {
  /// Riverpod owns this display observation; the Client owns the resource.
  SelectionStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectionStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectionStoreHash();

  @$internal
  @override
  $ProviderElement<SelectionStoreState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SelectionStoreState create(Ref ref) {
    return selectionStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SelectionStoreState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SelectionStoreState>(value),
    );
  }
}

String _$selectionStoreHash() => r'526eda592f856aa1f2a5efea97b79984222bba24';
