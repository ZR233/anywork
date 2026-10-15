// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_costs_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(sessionCostsStore)
final sessionCostsStoreProvider = SessionCostsStoreFamily._();

/// Riverpod owns this display observation; the Client owns the resource.

final class SessionCostsStoreProvider
    extends
        $FunctionalProvider<
          CanonicalClockState<SessionCostsStateView>,
          CanonicalClockState<SessionCostsStateView>,
          CanonicalClockState<SessionCostsStateView>
        >
    with $Provider<CanonicalClockState<SessionCostsStateView>> {
  /// Riverpod owns this display observation; the Client owns the resource.
  SessionCostsStoreProvider._({
    required SessionCostsStoreFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'sessionCostsStoreProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sessionCostsStoreHash();

  @override
  String toString() {
    return r'sessionCostsStoreProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<CanonicalClockState<SessionCostsStateView>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CanonicalClockState<SessionCostsStateView> create(Ref ref) {
    final argument = this.argument as String;
    return sessionCostsStore(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<SessionCostsStateView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<SessionCostsStateView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SessionCostsStoreProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sessionCostsStoreHash() => r'cc05c281df50ef0787af1923d7868d25f4614864';

/// Riverpod owns this display observation; the Client owns the resource.

final class SessionCostsStoreFamily extends $Family
    with
        $FunctionalFamilyOverride<
          CanonicalClockState<SessionCostsStateView>,
          String
        > {
  SessionCostsStoreFamily._()
    : super(
        retry: null,
        name: r'sessionCostsStoreProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Riverpod owns this display observation; the Client owns the resource.

  SessionCostsStoreProvider call(String rootThreadId) =>
      SessionCostsStoreProvider._(argument: rootThreadId, from: this);

  @override
  String toString() => r'sessionCostsStoreProvider';
}
