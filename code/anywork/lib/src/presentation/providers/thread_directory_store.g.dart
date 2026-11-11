// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_directory_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(threadMetadataDemand)
final threadMetadataDemandProvider = ThreadMetadataDemandFamily._();

final class ThreadMetadataDemandProvider
    extends
        $FunctionalProvider<
          DirectoryObservation<ThreadMetadataFrame>,
          DirectoryObservation<ThreadMetadataFrame>,
          DirectoryObservation<ThreadMetadataFrame>
        >
    with $Provider<DirectoryObservation<ThreadMetadataFrame>> {
  ThreadMetadataDemandProvider._({
    required ThreadMetadataDemandFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'threadMetadataDemandProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$threadMetadataDemandHash();

  @override
  String toString() {
    return r'threadMetadataDemandProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<DirectoryObservation<ThreadMetadataFrame>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DirectoryObservation<ThreadMetadataFrame> create(Ref ref) {
    final argument = this.argument as String;
    return threadMetadataDemand(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DirectoryObservation<ThreadMetadataFrame> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<DirectoryObservation<ThreadMetadataFrame>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ThreadMetadataDemandProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$threadMetadataDemandHash() =>
    r'4594cb7970b6aea42a63f244357a83d751234c7c';

final class ThreadMetadataDemandFamily extends $Family
    with
        $FunctionalFamilyOverride<
          DirectoryObservation<ThreadMetadataFrame>,
          String
        > {
  ThreadMetadataDemandFamily._()
    : super(
        retry: null,
        name: r'threadMetadataDemandProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ThreadMetadataDemandProvider call(String threadId) =>
      ThreadMetadataDemandProvider._(argument: threadId, from: this);

  @override
  String toString() => r'threadMetadataDemandProvider';
}

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
    r'a16211ad20a8467dbc20a23d0e1565628a10dc02';

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
