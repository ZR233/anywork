// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_status_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(LiveStatusViewModel)
final liveStatusViewModelProvider = LiveStatusViewModelFamily._();

final class LiveStatusViewModelProvider
    extends $NotifierProvider<LiveStatusViewModel, LiveStatusView?> {
  LiveStatusViewModelProvider._({
    required LiveStatusViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'liveStatusViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$liveStatusViewModelHash();

  @override
  String toString() {
    return r'liveStatusViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  LiveStatusViewModel create() => LiveStatusViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LiveStatusView? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LiveStatusView?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LiveStatusViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$liveStatusViewModelHash() =>
    r'3cf211da33b49e8cd5be5e430dab11f19d1102c3';

final class LiveStatusViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          LiveStatusViewModel,
          LiveStatusView?,
          LiveStatusView?,
          LiveStatusView?,
          String
        > {
  LiveStatusViewModelFamily._()
    : super(
        retry: null,
        name: r'liveStatusViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LiveStatusViewModelProvider call(String threadId) =>
      LiveStatusViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'liveStatusViewModelProvider';
}

abstract class _$LiveStatusViewModel extends $Notifier<LiveStatusView?> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  LiveStatusView? build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LiveStatusView?, LiveStatusView?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LiveStatusView?, LiveStatusView?>,
              LiveStatusView?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
