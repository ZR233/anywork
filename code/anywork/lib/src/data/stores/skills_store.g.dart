// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skills_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 项目 Skills。family 参数是稳定 projectId；时钟是该快照的 revision。

@ProviderFor(SkillsStore)
final skillsStoreProvider = SkillsStoreFamily._();

/// 项目 Skills。family 参数是稳定 projectId；时钟是该快照的 revision。
final class SkillsStoreProvider
    extends
        $NotifierProvider<
          SkillsStore,
          CanonicalClockState<SkillsStateSnapshot>
        > {
  /// 项目 Skills。family 参数是稳定 projectId；时钟是该快照的 revision。
  SkillsStoreProvider._({
    required SkillsStoreFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'skillsStoreProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$skillsStoreHash();

  @override
  String toString() {
    return r'skillsStoreProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SkillsStore create() => SkillsStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<SkillsStateSnapshot> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<SkillsStateSnapshot>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SkillsStoreProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$skillsStoreHash() => r'8bd33a4fa9242682e20ea8dd2bd35afbbdd43b58';

/// 项目 Skills。family 参数是稳定 projectId；时钟是该快照的 revision。

final class SkillsStoreFamily extends $Family
    with
        $ClassFamilyOverride<
          SkillsStore,
          CanonicalClockState<SkillsStateSnapshot>,
          CanonicalClockState<SkillsStateSnapshot>,
          CanonicalClockState<SkillsStateSnapshot>,
          String
        > {
  SkillsStoreFamily._()
    : super(
        retry: null,
        name: r'skillsStoreProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// 项目 Skills。family 参数是稳定 projectId；时钟是该快照的 revision。

  SkillsStoreProvider call(String projectId) =>
      SkillsStoreProvider._(argument: projectId, from: this);

  @override
  String toString() => r'skillsStoreProvider';
}

/// 项目 Skills。family 参数是稳定 projectId；时钟是该快照的 revision。

abstract class _$SkillsStore
    extends $Notifier<CanonicalClockState<SkillsStateSnapshot>> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  CanonicalClockState<SkillsStateSnapshot> build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              CanonicalClockState<SkillsStateSnapshot>,
              CanonicalClockState<SkillsStateSnapshot>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                CanonicalClockState<SkillsStateSnapshot>,
                CanonicalClockState<SkillsStateSnapshot>
              >,
              CanonicalClockState<SkillsStateSnapshot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
