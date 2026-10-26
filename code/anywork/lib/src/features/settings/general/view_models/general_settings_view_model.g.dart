// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'general_settings_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(GeneralSettingsViewModel)
final generalSettingsViewModelProvider = GeneralSettingsViewModelProvider._();

final class GeneralSettingsViewModelProvider
    extends
        $AsyncNotifierProvider<
          GeneralSettingsViewModel,
          GeneralSettingsViewState
        > {
  GeneralSettingsViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'generalSettingsViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$generalSettingsViewModelHash();

  @$internal
  @override
  GeneralSettingsViewModel create() => GeneralSettingsViewModel();
}

String _$generalSettingsViewModelHash() =>
    r'565598047ee50b581d73daeb0ed303c2167d6916';

abstract class _$GeneralSettingsViewModel
    extends $AsyncNotifier<GeneralSettingsViewState> {
  FutureOr<GeneralSettingsViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<GeneralSettingsViewState>,
              GeneralSettingsViewState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<GeneralSettingsViewState>,
                GeneralSettingsViewState
              >,
              AsyncValue<GeneralSettingsViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
