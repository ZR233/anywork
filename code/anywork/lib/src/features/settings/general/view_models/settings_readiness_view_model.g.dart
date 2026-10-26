// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_readiness_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The Settings shell only prepares public configuration. It does not mount a
/// hidden General/Updates connector or request another tab's business details.

@ProviderFor(SettingsReadinessViewModel)
final settingsReadinessViewModelProvider =
    SettingsReadinessViewModelProvider._();

/// The Settings shell only prepares public configuration. It does not mount a
/// hidden General/Updates connector or request another tab's business details.
final class SettingsReadinessViewModelProvider
    extends
        $AsyncNotifierProvider<
          SettingsReadinessViewModel,
          SettingsReadinessState
        > {
  /// The Settings shell only prepares public configuration. It does not mount a
  /// hidden General/Updates connector or request another tab's business details.
  SettingsReadinessViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsReadinessViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsReadinessViewModelHash();

  @$internal
  @override
  SettingsReadinessViewModel create() => SettingsReadinessViewModel();
}

String _$settingsReadinessViewModelHash() =>
    r'288a2776fd047b560968c4125969e8230fdc4ab8';

/// The Settings shell only prepares public configuration. It does not mount a
/// hidden General/Updates connector or request another tab's business details.

abstract class _$SettingsReadinessViewModel
    extends $AsyncNotifier<SettingsReadinessState> {
  FutureOr<SettingsReadinessState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<SettingsReadinessState>, SettingsReadinessState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<SettingsReadinessState>,
                SettingsReadinessState
              >,
              AsyncValue<SettingsReadinessState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
