// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skills_preferences_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Global disabled-name intent, independent of the visible Project catalog.

@ProviderFor(SkillsPreferencesViewModel)
final skillsPreferencesViewModelProvider =
    SkillsPreferencesViewModelProvider._();

/// Global disabled-name intent, independent of the visible Project catalog.
final class SkillsPreferencesViewModelProvider
    extends
        $AsyncNotifierProvider<
          SkillsPreferencesViewModel,
          SkillsPreferencesState
        > {
  /// Global disabled-name intent, independent of the visible Project catalog.
  SkillsPreferencesViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skillsPreferencesViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skillsPreferencesViewModelHash();

  @$internal
  @override
  SkillsPreferencesViewModel create() => SkillsPreferencesViewModel();
}

String _$skillsPreferencesViewModelHash() =>
    r'7201731ecfc22cb6dc2d0d9126eb41b3a1c7c08a';

/// Global disabled-name intent, independent of the visible Project catalog.

abstract class _$SkillsPreferencesViewModel
    extends $AsyncNotifier<SkillsPreferencesState> {
  FutureOr<SkillsPreferencesState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<SkillsPreferencesState>, SkillsPreferencesState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<SkillsPreferencesState>,
                SkillsPreferencesState
              >,
              AsyncValue<SkillsPreferencesState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
