// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_timeline_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(acpTimelineHeaderViewModel)
final acpTimelineHeaderViewModelProvider = AcpTimelineHeaderViewModelFamily._();

final class AcpTimelineHeaderViewModelProvider
    extends
        $FunctionalProvider<
          AcpTimelineHeaderViewState,
          AcpTimelineHeaderViewState,
          AcpTimelineHeaderViewState
        >
    with $Provider<AcpTimelineHeaderViewState> {
  AcpTimelineHeaderViewModelProvider._({
    required AcpTimelineHeaderViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpTimelineHeaderViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpTimelineHeaderViewModelHash();

  @override
  String toString() {
    return r'acpTimelineHeaderViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<AcpTimelineHeaderViewState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AcpTimelineHeaderViewState create(Ref ref) {
    final argument = this.argument as String;
    return acpTimelineHeaderViewModel(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpTimelineHeaderViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpTimelineHeaderViewState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpTimelineHeaderViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpTimelineHeaderViewModelHash() =>
    r'39e1a807c08e04df2abe38532f18aed827bce491';

final class AcpTimelineHeaderViewModelFamily extends $Family
    with $FunctionalFamilyOverride<AcpTimelineHeaderViewState, String> {
  AcpTimelineHeaderViewModelFamily._()
    : super(
        retry: null,
        name: r'acpTimelineHeaderViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpTimelineHeaderViewModelProvider call(String threadId) =>
      AcpTimelineHeaderViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpTimelineHeaderViewModelProvider';
}

@ProviderFor(acpTimelineItemViewModel)
final acpTimelineItemViewModelProvider = AcpTimelineItemViewModelFamily._();

final class AcpTimelineItemViewModelProvider
    extends
        $FunctionalProvider<
          AcpTimelineItemPresentation?,
          AcpTimelineItemPresentation?,
          AcpTimelineItemPresentation?
        >
    with $Provider<AcpTimelineItemPresentation?> {
  AcpTimelineItemViewModelProvider._({
    required AcpTimelineItemViewModelFamily super.from,
    required (String, int) super.argument,
  }) : super(
         retry: null,
         name: r'acpTimelineItemViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpTimelineItemViewModelHash();

  @override
  String toString() {
    return r'acpTimelineItemViewModelProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<AcpTimelineItemPresentation?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AcpTimelineItemPresentation? create(Ref ref) {
    final argument = this.argument as (String, int);
    return acpTimelineItemViewModel(ref, argument.$1, argument.$2);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpTimelineItemPresentation? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpTimelineItemPresentation?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpTimelineItemViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpTimelineItemViewModelHash() =>
    r'd494fbc7ae96b55733f1f94811a910cb029b8269';

final class AcpTimelineItemViewModelFamily extends $Family
    with
        $FunctionalFamilyOverride<AcpTimelineItemPresentation?, (String, int)> {
  AcpTimelineItemViewModelFamily._()
    : super(
        retry: null,
        name: r'acpTimelineItemViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpTimelineItemViewModelProvider call(String threadId, int index) =>
      AcpTimelineItemViewModelProvider._(
        argument: (threadId, index),
        from: this,
      );

  @override
  String toString() => r'acpTimelineItemViewModelProvider';
}
