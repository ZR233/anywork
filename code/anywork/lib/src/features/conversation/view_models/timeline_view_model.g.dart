// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TimelineViewModel)
final timelineViewModelProvider = TimelineViewModelFamily._();

final class TimelineViewModelProvider
    extends $AsyncNotifierProvider<TimelineViewModel, TimelineViewState> {
  TimelineViewModelProvider._({
    required TimelineViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'timelineViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$timelineViewModelHash();

  @override
  String toString() {
    return r'timelineViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TimelineViewModel create() => TimelineViewModel();

  @override
  bool operator ==(Object other) {
    return other is TimelineViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$timelineViewModelHash() => r'1c86a380e3b0ca2f0bdfe80afc13d29dfac923c6';

final class TimelineViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          TimelineViewModel,
          AsyncValue<TimelineViewState>,
          TimelineViewState,
          FutureOr<TimelineViewState>,
          String
        > {
  TimelineViewModelFamily._()
    : super(
        retry: null,
        name: r'timelineViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TimelineViewModelProvider call(String threadId) =>
      TimelineViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'timelineViewModelProvider';
}

abstract class _$TimelineViewModel extends $AsyncNotifier<TimelineViewState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  FutureOr<TimelineViewState> build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<TimelineViewState>, TimelineViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<TimelineViewState>, TimelineViewState>,
              AsyncValue<TimelineViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
