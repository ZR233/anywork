// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_session_view.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(timelineDisplayState)
final timelineDisplayStateProvider = TimelineDisplayStateProvider._();

final class TimelineDisplayStateProvider
    extends
        $FunctionalProvider<
          TimelineSessionViewState?,
          TimelineSessionViewState?,
          TimelineSessionViewState?
        >
    with $Provider<TimelineSessionViewState?> {
  TimelineDisplayStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'timelineDisplayStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$timelineDisplayStateHash();

  @$internal
  @override
  $ProviderElement<TimelineSessionViewState?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TimelineSessionViewState? create(Ref ref) {
    return timelineDisplayState(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TimelineSessionViewState? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TimelineSessionViewState?>(value),
    );
  }
}

String _$timelineDisplayStateHash() =>
    r'a55cbbbb546ab358ba69ef2a56aa4bdd80694c9d';
