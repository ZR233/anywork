// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skills_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SkillsViewModel)
final skillsViewModelProvider = SkillsViewModelFamily._();

final class SkillsViewModelProvider
    extends $AsyncNotifierProvider<SkillsViewModel, SkillsViewState> {
  SkillsViewModelProvider._({
    required SkillsViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'skillsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$skillsViewModelHash();

  @override
  String toString() {
    return r'skillsViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SkillsViewModel create() => SkillsViewModel();

  @override
  bool operator ==(Object other) {
    return other is SkillsViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$skillsViewModelHash() => r'8afdc38414c12a6050991597452547336f18800c';

final class SkillsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          SkillsViewModel,
          AsyncValue<SkillsViewState>,
          SkillsViewState,
          FutureOr<SkillsViewState>,
          String
        > {
  SkillsViewModelFamily._()
    : super(
        retry: null,
        name: r'skillsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SkillsViewModelProvider call(String projectId) =>
      SkillsViewModelProvider._(argument: projectId, from: this);

  @override
  String toString() => r'skillsViewModelProvider';
}

abstract class _$SkillsViewModel extends $AsyncNotifier<SkillsViewState> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  FutureOr<SkillsViewState> build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<SkillsViewState>, SkillsViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SkillsViewState>, SkillsViewState>,
              AsyncValue<SkillsViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
