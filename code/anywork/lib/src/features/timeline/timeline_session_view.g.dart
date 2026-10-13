// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_session_view.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(timelineSessionWindow)
final timelineSessionWindowProvider = TimelineSessionWindowProvider._();

final class TimelineSessionWindowProvider
    extends
        $FunctionalProvider<
          TimelineSessionWindow?,
          TimelineSessionWindow?,
          TimelineSessionWindow?
        >
    with $Provider<TimelineSessionWindow?> {
  TimelineSessionWindowProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'timelineSessionWindowProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$timelineSessionWindowHash();

  @$internal
  @override
  $ProviderElement<TimelineSessionWindow?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TimelineSessionWindow? create(Ref ref) {
    return timelineSessionWindow(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TimelineSessionWindow? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TimelineSessionWindow?>(value),
    );
  }
}

String _$timelineSessionWindowHash() =>
    r'd361f34d20dbf79838b6928740b5e4b92d756030';
