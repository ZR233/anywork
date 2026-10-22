// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bots_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(botsStore)
final botsStoreProvider = BotsStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class BotsStoreProvider
    extends
        $FunctionalProvider<
          CanonicalClockState<BotsStateSnapshot>,
          CanonicalClockState<BotsStateSnapshot>,
          CanonicalClockState<BotsStateSnapshot>
        >
    with $Provider<CanonicalClockState<BotsStateSnapshot>> {
  /// Riverpod owns this display observation; the Client owns the resource.
  BotsStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'botsStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$botsStoreHash();

  @$internal
  @override
  $ProviderElement<CanonicalClockState<BotsStateSnapshot>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CanonicalClockState<BotsStateSnapshot> create(Ref ref) {
    return botsStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<BotsStateSnapshot> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<BotsStateSnapshot>>(value),
    );
  }
}

String _$botsStoreHash() => r'9627c218d1721feca485822f09f8433a18367985';

@ProviderFor(botsQueryStore)
final botsQueryStoreProvider = BotsQueryStoreProvider._();

final class BotsQueryStoreProvider
    extends $FunctionalProvider<BotsQueryState, BotsQueryState, BotsQueryState>
    with $Provider<BotsQueryState> {
  BotsQueryStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'botsQueryStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$botsQueryStoreHash();

  @$internal
  @override
  $ProviderElement<BotsQueryState> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BotsQueryState create(Ref ref) {
    return botsQueryStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BotsQueryState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BotsQueryState>(value),
    );
  }
}

String _$botsQueryStoreHash() => r'8e890bfa8a90c3584982813f8d86b7d17ae1fbc2';

@ProviderFor(botsSendStore)
final botsSendStoreProvider = BotsSendStoreProvider._();

final class BotsSendStoreProvider
    extends $FunctionalProvider<BotsSendState, BotsSendState, BotsSendState>
    with $Provider<BotsSendState> {
  BotsSendStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'botsSendStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$botsSendStoreHash();

  @$internal
  @override
  $ProviderElement<BotsSendState> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BotsSendState create(Ref ref) {
    return botsSendStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BotsSendState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BotsSendState>(value),
    );
  }
}

String _$botsSendStoreHash() => r'25466037d882c181ab094ef84c8d7191f78c7e91';
