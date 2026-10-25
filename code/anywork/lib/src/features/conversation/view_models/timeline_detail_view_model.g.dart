// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_detail_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TimelineDetailViewModel)
final timelineDetailViewModelProvider = TimelineDetailViewModelFamily._();

final class TimelineDetailViewModelProvider
    extends
        $AsyncNotifierProvider<
          TimelineDetailViewModel,
          TimelineDetailViewState
        > {
  TimelineDetailViewModelProvider._({
    required TimelineDetailViewModelFamily super.from,
    required TimelineDetailKey super.argument,
  }) : super(
         retry: null,
         name: r'timelineDetailViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$timelineDetailViewModelHash();

  @override
  String toString() {
    return r'timelineDetailViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TimelineDetailViewModel create() => TimelineDetailViewModel();

  @override
  bool operator ==(Object other) {
    return other is TimelineDetailViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$timelineDetailViewModelHash() =>
    r'02ddef7cb53974461406a355290eac96c4573a1e';

final class TimelineDetailViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          TimelineDetailViewModel,
          AsyncValue<TimelineDetailViewState>,
          TimelineDetailViewState,
          FutureOr<TimelineDetailViewState>,
          TimelineDetailKey
        > {
  TimelineDetailViewModelFamily._()
    : super(
        retry: null,
        name: r'timelineDetailViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TimelineDetailViewModelProvider call(TimelineDetailKey key) =>
      TimelineDetailViewModelProvider._(argument: key, from: this);

  @override
  String toString() => r'timelineDetailViewModelProvider';
}

abstract class _$TimelineDetailViewModel
    extends $AsyncNotifier<TimelineDetailViewState> {
  late final _$args = ref.$arg as TimelineDetailKey;
  TimelineDetailKey get key => _$args;

  FutureOr<TimelineDetailViewState> build(TimelineDetailKey key);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<TimelineDetailViewState>,
              TimelineDetailViewState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<TimelineDetailViewState>,
                TimelineDetailViewState
              >,
              AsyncValue<TimelineDetailViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
