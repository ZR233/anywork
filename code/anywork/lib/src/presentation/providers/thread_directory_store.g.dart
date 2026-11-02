// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_directory_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Metadata is independent of list membership, filtering and pagination.

@ProviderFor(threadMetadataStore)
final threadMetadataStoreProvider = ThreadMetadataStoreFamily._();

/// Metadata is independent of list membership, filtering and pagination.

final class ThreadMetadataStoreProvider
    extends
        $FunctionalProvider<
          DirectoryObservationState<ThreadMetadataFrame>,
          DirectoryObservationState<ThreadMetadataFrame>,
          DirectoryObservationState<ThreadMetadataFrame>
        >
    with $Provider<DirectoryObservationState<ThreadMetadataFrame>> {
  /// Metadata is independent of list membership, filtering and pagination.
  ThreadMetadataStoreProvider._({
    required ThreadMetadataStoreFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'threadMetadataStoreProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$threadMetadataStoreHash();

  @override
  String toString() {
    return r'threadMetadataStoreProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<DirectoryObservationState<ThreadMetadataFrame>>
  $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  DirectoryObservationState<ThreadMetadataFrame> create(Ref ref) {
    final argument = this.argument as String;
    return threadMetadataStore(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    DirectoryObservationState<ThreadMetadataFrame> value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<DirectoryObservationState<ThreadMetadataFrame>>(
            value,
          ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ThreadMetadataStoreProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$threadMetadataStoreHash() =>
    r'8fd7f4a4ec9ae074cd0e9dc346f5250b5a1f35f0';

/// Metadata is independent of list membership, filtering and pagination.

final class ThreadMetadataStoreFamily extends $Family
    with
        $FunctionalFamilyOverride<
          DirectoryObservationState<ThreadMetadataFrame>,
          String
        > {
  ThreadMetadataStoreFamily._()
    : super(
        retry: null,
        name: r'threadMetadataStoreProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Metadata is independent of list membership, filtering and pagination.

  ThreadMetadataStoreProvider call(String threadId) =>
      ThreadMetadataStoreProvider._(argument: threadId, from: this);

  @override
  String toString() => r'threadMetadataStoreProvider';
}
