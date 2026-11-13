// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'studio_update_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Projects Client update snapshots into sidebar and settings vocabulary.

@ProviderFor(StudioUpdateViewModel)
final studioUpdateViewModelProvider = StudioUpdateViewModelProvider._();

/// Projects Client update snapshots into sidebar and settings vocabulary.
final class StudioUpdateViewModelProvider
    extends $NotifierProvider<StudioUpdateViewModel, StudioUpdateViewState> {
  /// Projects Client update snapshots into sidebar and settings vocabulary.
  StudioUpdateViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'studioUpdateViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$studioUpdateViewModelHash();

  @$internal
  @override
  StudioUpdateViewModel create() => StudioUpdateViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudioUpdateViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudioUpdateViewState>(value),
    );
  }
}

String _$studioUpdateViewModelHash() =>
    r'4cc4235c0066c1ab172362d9df5ad2b5bd92d2b0';

/// Projects Client update snapshots into sidebar and settings vocabulary.

abstract class _$StudioUpdateViewModel
    extends $Notifier<StudioUpdateViewState> {
  StudioUpdateViewState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<StudioUpdateViewState, StudioUpdateViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StudioUpdateViewState, StudioUpdateViewState>,
              StudioUpdateViewState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
