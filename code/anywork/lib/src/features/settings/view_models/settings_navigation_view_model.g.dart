// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_navigation_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SettingsNavigationViewModel)
final settingsNavigationViewModelProvider =
    SettingsNavigationViewModelProvider._();

final class SettingsNavigationViewModelProvider
    extends
        $AsyncNotifierProvider<
          SettingsNavigationViewModel,
          SettingsNavigationState
        > {
  SettingsNavigationViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsNavigationViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsNavigationViewModelHash();

  @$internal
  @override
  SettingsNavigationViewModel create() => SettingsNavigationViewModel();
}

String _$settingsNavigationViewModelHash() =>
    r'7745b9a6f9d18feeb1f33bf399cc5a0987e3b689';

abstract class _$SettingsNavigationViewModel
    extends $AsyncNotifier<SettingsNavigationState> {
  FutureOr<SettingsNavigationState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<SettingsNavigationState>,
              SettingsNavigationState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<SettingsNavigationState>,
                SettingsNavigationState
              >,
              AsyncValue<SettingsNavigationState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
