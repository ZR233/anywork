// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_status_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 只保留两处局部分页意图；每次从当前规范尾部和业务状态计算实际展示。

@ProviderFor(LiveStatusViewModel)
final liveStatusViewModelProvider = LiveStatusViewModelFamily._();

/// 只保留两处局部分页意图；每次从当前规范尾部和业务状态计算实际展示。
final class LiveStatusViewModelProvider
    extends $NotifierProvider<LiveStatusViewModel, LiveStatusView?> {
  /// 只保留两处局部分页意图；每次从当前规范尾部和业务状态计算实际展示。
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
    r'd8f09286ae1e0eca4cdf0433dc818e20b06e7e98';

/// 只保留两处局部分页意图；每次从当前规范尾部和业务状态计算实际展示。

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

  /// 只保留两处局部分页意图；每次从当前规范尾部和业务状态计算实际展示。

  LiveStatusViewModelProvider call(String threadId) =>
      LiveStatusViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'liveStatusViewModelProvider';
}

/// 只保留两处局部分页意图；每次从当前规范尾部和业务状态计算实际展示。

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
