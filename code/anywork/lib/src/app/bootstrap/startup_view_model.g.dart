// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'startup_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// build only registers an observation. App bootstrap, not a rebuild, calls
/// StartupRepository.start (initialize → prepare → open → listen → start).

@ProviderFor(StartupViewModel)
final startupViewModelProvider = StartupViewModelProvider._();

/// build only registers an observation. App bootstrap, not a rebuild, calls
/// StartupRepository.start (initialize → prepare → open → listen → start).
final class StartupViewModelProvider
    extends $AsyncNotifierProvider<StartupViewModel, StartupViewState> {
  /// build only registers an observation. App bootstrap, not a rebuild, calls
  /// StartupRepository.start (initialize → prepare → open → listen → start).
  StartupViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'startupViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$startupViewModelHash();

  @$internal
  @override
  StartupViewModel create() => StartupViewModel();
}

String _$startupViewModelHash() => r'4865c1b4e351481595ca5b4b081312b1d95a7939';

/// build only registers an observation. App bootstrap, not a rebuild, calls
/// StartupRepository.start (initialize → prepare → open → listen → start).

abstract class _$StartupViewModel extends $AsyncNotifier<StartupViewState> {
  FutureOr<StartupViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<StartupViewState>, StartupViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<StartupViewState>, StartupViewState>,
              AsyncValue<StartupViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
