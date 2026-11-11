// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_status_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 实时状态栏组件专属 ViewModel：
/// 在组件内部统一观察 FRB 驱动的会话状态流（`threadSessionStoreProvider`）与
/// 时间线实时展示窗口流（`TimelineDisplayLease.live`），驱动纯领域状态机并执行外部副作用，
/// 使外壳页脚与时间线连接器不再承担外围数据拼装与业务判断。

@ProviderFor(LiveStatusViewModel)
final liveStatusViewModelProvider = LiveStatusViewModelFamily._();

/// 实时状态栏组件专属 ViewModel：
/// 在组件内部统一观察 FRB 驱动的会话状态流（`threadSessionStoreProvider`）与
/// 时间线实时展示窗口流（`TimelineDisplayLease.live`），驱动纯领域状态机并执行外部副作用，
/// 使外壳页脚与时间线连接器不再承担外围数据拼装与业务判断。
final class LiveStatusViewModelProvider
    extends $NotifierProvider<LiveStatusViewModel, LiveStatusAggregate?> {
  /// 实时状态栏组件专属 ViewModel：
  /// 在组件内部统一观察 FRB 驱动的会话状态流（`threadSessionStoreProvider`）与
  /// 时间线实时展示窗口流（`TimelineDisplayLease.live`），驱动纯领域状态机并执行外部副作用，
  /// 使外壳页脚与时间线连接器不再承担外围数据拼装与业务判断。
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
  Override overrideWithValue(LiveStatusAggregate? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LiveStatusAggregate?>(value),
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
    r'54443a1c68c8702f9d365b58024425133841f372';

/// 实时状态栏组件专属 ViewModel：
/// 在组件内部统一观察 FRB 驱动的会话状态流（`threadSessionStoreProvider`）与
/// 时间线实时展示窗口流（`TimelineDisplayLease.live`），驱动纯领域状态机并执行外部副作用，
/// 使外壳页脚与时间线连接器不再承担外围数据拼装与业务判断。

final class LiveStatusViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          LiveStatusViewModel,
          LiveStatusAggregate?,
          LiveStatusAggregate?,
          LiveStatusAggregate?,
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

  /// 实时状态栏组件专属 ViewModel：
  /// 在组件内部统一观察 FRB 驱动的会话状态流（`threadSessionStoreProvider`）与
  /// 时间线实时展示窗口流（`TimelineDisplayLease.live`），驱动纯领域状态机并执行外部副作用，
  /// 使外壳页脚与时间线连接器不再承担外围数据拼装与业务判断。

  LiveStatusViewModelProvider call(String threadId) =>
      LiveStatusViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'liveStatusViewModelProvider';
}

/// 实时状态栏组件专属 ViewModel：
/// 在组件内部统一观察 FRB 驱动的会话状态流（`threadSessionStoreProvider`）与
/// 时间线实时展示窗口流（`TimelineDisplayLease.live`），驱动纯领域状态机并执行外部副作用，
/// 使外壳页脚与时间线连接器不再承担外围数据拼装与业务判断。

abstract class _$LiveStatusViewModel extends $Notifier<LiveStatusAggregate?> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  LiveStatusAggregate? build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LiveStatusAggregate?, LiveStatusAggregate?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LiveStatusAggregate?, LiveStatusAggregate?>,
              LiveStatusAggregate?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
