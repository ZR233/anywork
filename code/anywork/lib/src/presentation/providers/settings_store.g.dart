// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(settingsStore)
final settingsStoreProvider = SettingsStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class SettingsStoreProvider
    extends
        $FunctionalProvider<
          SettingsStoreState,
          SettingsStoreState,
          SettingsStoreState
        >
    with $Provider<SettingsStoreState> {
  /// Riverpod owns this display observation; the Client owns the resource.
  SettingsStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsStoreHash();

  @$internal
  @override
  $ProviderElement<SettingsStoreState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SettingsStoreState create(Ref ref) {
    return settingsStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsStoreState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsStoreState>(value),
    );
  }
}

String _$settingsStoreHash() => r'83faca3cf814e1a5864c0e5a45846efaa5e5fb7b';
