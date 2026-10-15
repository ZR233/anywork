// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'studio_update_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Update startup and installation survive observer and route lifetimes.

@ProviderFor(studioUpdateController)
final studioUpdateControllerProvider = StudioUpdateControllerProvider._();

/// Update startup and installation survive observer and route lifetimes.

final class StudioUpdateControllerProvider
    extends
        $FunctionalProvider<
          UpdaterStateSnapshot,
          UpdaterStateSnapshot,
          UpdaterStateSnapshot
        >
    with $Provider<UpdaterStateSnapshot> {
  /// Update startup and installation survive observer and route lifetimes.
  StudioUpdateControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'studioUpdateControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$studioUpdateControllerHash();

  @$internal
  @override
  $ProviderElement<UpdaterStateSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  UpdaterStateSnapshot create(Ref ref) {
    return studioUpdateController(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UpdaterStateSnapshot value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UpdaterStateSnapshot>(value),
    );
  }
}

String _$studioUpdateControllerHash() =>
    r'5006246d50b96dad8c272643f3ccf1c329b11c84';
