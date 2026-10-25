// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_workspace_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SettingsWorkspaceViewModel)
final settingsWorkspaceViewModelProvider =
    SettingsWorkspaceViewModelProvider._();

final class SettingsWorkspaceViewModelProvider
    extends
        $AsyncNotifierProvider<
          SettingsWorkspaceViewModel,
          SettingsWorkspaceState
        > {
  SettingsWorkspaceViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsWorkspaceViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsWorkspaceViewModelHash();

  @$internal
  @override
  SettingsWorkspaceViewModel create() => SettingsWorkspaceViewModel();
}

String _$settingsWorkspaceViewModelHash() =>
    r'439b416ed6c76e9c6c67268cb38338e4ce264b5a';

abstract class _$SettingsWorkspaceViewModel
    extends $AsyncNotifier<SettingsWorkspaceState> {
  FutureOr<SettingsWorkspaceState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<SettingsWorkspaceState>, SettingsWorkspaceState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<SettingsWorkspaceState>,
                SettingsWorkspaceState
              >,
              AsyncValue<SettingsWorkspaceState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
