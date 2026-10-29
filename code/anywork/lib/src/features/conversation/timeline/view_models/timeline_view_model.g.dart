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
    extends
        $AsyncNotifierProvider<TimelineViewModel, TimelineSessionViewState?> {
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

String _$timelineViewModelHash() => r'08c6c9bf8dbe92a50a0eded99ea1da6c0e1e3aad';

final class TimelineViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          TimelineViewModel,
          AsyncValue<TimelineSessionViewState?>,
          TimelineSessionViewState?,
          FutureOr<TimelineSessionViewState?>,
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

abstract class _$TimelineViewModel
    extends $AsyncNotifier<TimelineSessionViewState?> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  FutureOr<TimelineSessionViewState?> build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<TimelineSessionViewState?>,
              TimelineSessionViewState?
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<TimelineSessionViewState?>,
                TimelineSessionViewState?
              >,
              AsyncValue<TimelineSessionViewState?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
