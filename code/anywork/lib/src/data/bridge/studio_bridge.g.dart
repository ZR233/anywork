// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'studio_bridge.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 全 app 唯一的 topic / thread 流消费点。
///
/// 帧在进入 store reduce 之前按领域水位拒收。Lagged、failure、closed 只把对应
/// store 标成局部重同步，不覆盖 last-known canonical。租约归零即取消订阅；
/// 重建先取消旧句柄，再接收新的 Baseline / snapshot。

@ProviderFor(studioBridge)
final studioBridgeProvider = StudioBridgeProvider._();

/// 全 app 唯一的 topic / thread 流消费点。
///
/// 帧在进入 store reduce 之前按领域水位拒收。Lagged、failure、closed 只把对应
/// store 标成局部重同步，不覆盖 last-known canonical。租约归零即取消订阅；
/// 重建先取消旧句柄，再接收新的 Baseline / snapshot。

final class StudioBridgeProvider
    extends $FunctionalProvider<StudioBridge, StudioBridge, StudioBridge>
    with $Provider<StudioBridge> {
  /// 全 app 唯一的 topic / thread 流消费点。
  ///
  /// 帧在进入 store reduce 之前按领域水位拒收。Lagged、failure、closed 只把对应
  /// store 标成局部重同步，不覆盖 last-known canonical。租约归零即取消订阅；
  /// 重建先取消旧句柄，再接收新的 Baseline / snapshot。
  StudioBridgeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'studioBridgeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$studioBridgeHash();

  @$internal
  @override
  $ProviderElement<StudioBridge> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  StudioBridge create(Ref ref) {
    return studioBridge(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudioBridge value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudioBridge>(value),
    );
  }
}

String _$studioBridgeHash() => r'1bc9010235ff633c322d2ae112dda3d46213edd6';
