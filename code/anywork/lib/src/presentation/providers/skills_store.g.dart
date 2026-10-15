// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skills_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(skillsStore)
final skillsStoreProvider = SkillsStoreFamily._();

/// Riverpod owns this display observation; the Client owns the resource.

final class SkillsStoreProvider
    extends
        $FunctionalProvider<
          CanonicalClockState<SkillsStateSnapshot>,
          CanonicalClockState<SkillsStateSnapshot>,
          CanonicalClockState<SkillsStateSnapshot>
        >
    with $Provider<CanonicalClockState<SkillsStateSnapshot>> {
  /// Riverpod owns this display observation; the Client owns the resource.
  SkillsStoreProvider._({
    required SkillsStoreFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'skillsStoreProvider',
         isAutoDispose: true,
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
  $ProviderElement<CanonicalClockState<SkillsStateSnapshot>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CanonicalClockState<SkillsStateSnapshot> create(Ref ref) {
    final argument = this.argument as String;
    return skillsStore(ref, argument);
  }

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

String _$skillsStoreHash() => r'd0e049d02b634653a16848539a4a212f69e6c6e3';

/// Riverpod owns this display observation; the Client owns the resource.

final class SkillsStoreFamily extends $Family
    with
        $FunctionalFamilyOverride<
          CanonicalClockState<SkillsStateSnapshot>,
          String
        > {
  SkillsStoreFamily._()
    : super(
        retry: null,
        name: r'skillsStoreProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Riverpod owns this display observation; the Client owns the resource.

  SkillsStoreProvider call(String projectId) =>
      SkillsStoreProvider._(argument: projectId, from: this);

  @override
  String toString() => r'skillsStoreProvider';
}
