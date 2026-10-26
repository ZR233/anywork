// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'release_notes_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ReleaseNotesViewModel)
final releaseNotesViewModelProvider = ReleaseNotesViewModelFamily._();

final class ReleaseNotesViewModelProvider
    extends $AsyncNotifierProvider<ReleaseNotesViewModel, ReleaseNotesState> {
  ReleaseNotesViewModelProvider._({
    required ReleaseNotesViewModelFamily super.from,
    required UpdateSummary super.argument,
  }) : super(
         retry: null,
         name: r'releaseNotesViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$releaseNotesViewModelHash();

  @override
  String toString() {
    return r'releaseNotesViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ReleaseNotesViewModel create() => ReleaseNotesViewModel();

  @override
  bool operator ==(Object other) {
    return other is ReleaseNotesViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$releaseNotesViewModelHash() =>
    r'089cb74a7b52586e9809a923c31576d1d01f5cec';

final class ReleaseNotesViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          ReleaseNotesViewModel,
          AsyncValue<ReleaseNotesState>,
          ReleaseNotesState,
          FutureOr<ReleaseNotesState>,
          UpdateSummary
        > {
  ReleaseNotesViewModelFamily._()
    : super(
        retry: null,
        name: r'releaseNotesViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ReleaseNotesViewModelProvider call(UpdateSummary summary) =>
      ReleaseNotesViewModelProvider._(argument: summary, from: this);

  @override
  String toString() => r'releaseNotesViewModelProvider';
}

abstract class _$ReleaseNotesViewModel
    extends $AsyncNotifier<ReleaseNotesState> {
  late final _$args = ref.$arg as UpdateSummary;
  UpdateSummary get summary => _$args;

  FutureOr<ReleaseNotesState> build(UpdateSummary summary);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<ReleaseNotesState>, ReleaseNotesState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ReleaseNotesState>, ReleaseNotesState>,
              AsyncValue<ReleaseNotesState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
