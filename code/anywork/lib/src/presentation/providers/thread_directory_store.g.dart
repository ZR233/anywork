// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_directory_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(threadDirectoryStore)
final threadDirectoryStoreProvider = ThreadDirectoryStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class ThreadDirectoryStoreProvider
    extends
        $FunctionalProvider<
          ThreadDirectoryStoreState,
          ThreadDirectoryStoreState,
          ThreadDirectoryStoreState
        >
    with $Provider<ThreadDirectoryStoreState> {
  /// Riverpod owns this display observation; the Client owns the resource.
  ThreadDirectoryStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'threadDirectoryStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$threadDirectoryStoreHash();

  @$internal
  @override
  $ProviderElement<ThreadDirectoryStoreState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ThreadDirectoryStoreState create(Ref ref) {
    return threadDirectoryStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThreadDirectoryStoreState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThreadDirectoryStoreState>(value),
    );
  }
}

String _$threadDirectoryStoreHash() =>
    r'20c0e15e3ee3b95f5644aa65b62e7ef3d3b99221';
