// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bots_settings_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BotsSettingsViewModel)
final botsSettingsViewModelProvider = BotsSettingsViewModelProvider._();

final class BotsSettingsViewModelProvider
    extends
        $AsyncNotifierProvider<BotsSettingsViewModel, BotsSettingsViewState> {
  BotsSettingsViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'botsSettingsViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$botsSettingsViewModelHash();

  @$internal
  @override
  BotsSettingsViewModel create() => BotsSettingsViewModel();
}

String _$botsSettingsViewModelHash() =>
    r'dfca87a63ad7622e5d39d5978febfbfd89f34200';

abstract class _$BotsSettingsViewModel
    extends $AsyncNotifier<BotsSettingsViewState> {
  FutureOr<BotsSettingsViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<BotsSettingsViewState>, BotsSettingsViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<BotsSettingsViewState>,
                BotsSettingsViewState
              >,
              AsyncValue<BotsSettingsViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
