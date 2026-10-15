// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_session_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(threadSessionStore)
final threadSessionStoreProvider = ThreadSessionStoreFamily._();

/// Riverpod owns this display observation; the Client owns the resource.

final class ThreadSessionStoreProvider
    extends
        $FunctionalProvider<
          ThreadSessionState,
          ThreadSessionState,
          ThreadSessionState
        >
    with $Provider<ThreadSessionState> {
  /// Riverpod owns this display observation; the Client owns the resource.
  ThreadSessionStoreProvider._({
    required ThreadSessionStoreFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'threadSessionStoreProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$threadSessionStoreHash();

  @override
  String toString() {
    return r'threadSessionStoreProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ThreadSessionState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ThreadSessionState create(Ref ref) {
    final argument = this.argument as String;
    return threadSessionStore(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThreadSessionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThreadSessionState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ThreadSessionStoreProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$threadSessionStoreHash() =>
    r'8e816d364f2cf739a58e71ba73c65d95ec633bc4';

/// Riverpod owns this display observation; the Client owns the resource.

final class ThreadSessionStoreFamily extends $Family
    with $FunctionalFamilyOverride<ThreadSessionState, String> {
  ThreadSessionStoreFamily._()
    : super(
        retry: null,
        name: r'threadSessionStoreProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Riverpod owns this display observation; the Client owns the resource.

  ThreadSessionStoreProvider call(String threadId) =>
      ThreadSessionStoreProvider._(argument: threadId, from: this);

  @override
  String toString() => r'threadSessionStoreProvider';
}
