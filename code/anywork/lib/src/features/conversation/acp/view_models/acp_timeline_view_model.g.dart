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
    r'8281cdef95793e94bd22bd7d72fa15a306dde2b4';

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

@ProviderFor(acpTimelineRowsViewModel)
final acpTimelineRowsViewModelProvider = AcpTimelineRowsViewModelFamily._();

final class AcpTimelineRowsViewModelProvider
    extends
        $FunctionalProvider<
          List<AcpTimelineRow>,
          List<AcpTimelineRow>,
          List<AcpTimelineRow>
        >
    with $Provider<List<AcpTimelineRow>> {
  AcpTimelineRowsViewModelProvider._({
    required AcpTimelineRowsViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpTimelineRowsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpTimelineRowsViewModelHash();

  @override
  String toString() {
    return r'acpTimelineRowsViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<AcpTimelineRow>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<AcpTimelineRow> create(Ref ref) {
    final argument = this.argument as String;
    return acpTimelineRowsViewModel(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AcpTimelineRow> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AcpTimelineRow>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpTimelineRowsViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpTimelineRowsViewModelHash() =>
    r'bd73a49e0dc32ea3bcacc537e514153732900447';

final class AcpTimelineRowsViewModelFamily extends $Family
    with $FunctionalFamilyOverride<List<AcpTimelineRow>, String> {
  AcpTimelineRowsViewModelFamily._()
    : super(
        retry: null,
        name: r'acpTimelineRowsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpTimelineRowsViewModelProvider call(String threadId) =>
      AcpTimelineRowsViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpTimelineRowsViewModelProvider';
}
