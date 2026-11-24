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
    r'ad9b56046803b104c2c9af9706217c52e45deb86';

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

@ProviderFor(acpTimelineItemViewModel)
final acpTimelineItemViewModelProvider = AcpTimelineItemViewModelFamily._();

final class AcpTimelineItemViewModelProvider
    extends
        $FunctionalProvider<AcpTimelineRow?, AcpTimelineRow?, AcpTimelineRow?>
    with $Provider<AcpTimelineRow?> {
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
  $ProviderElement<AcpTimelineRow?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AcpTimelineRow? create(Ref ref) {
    final argument = this.argument as (String, int);
    return acpTimelineItemViewModel(ref, argument.$1, argument.$2);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpTimelineRow? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpTimelineRow?>(value),
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
    r'f1a38ace6e9772eb213f84934b75c53110d10133';

final class AcpTimelineItemViewModelFamily extends $Family
    with $FunctionalFamilyOverride<AcpTimelineRow?, (String, int)> {
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
