// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remote_directory_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(RemoteDirectoryViewModel)
final remoteDirectoryViewModelProvider = RemoteDirectoryViewModelFamily._();

final class RemoteDirectoryViewModelProvider
    extends
        $AsyncNotifierProvider<
          RemoteDirectoryViewModel,
          RemoteDirectoryViewState
        > {
  RemoteDirectoryViewModelProvider._({
    required RemoteDirectoryViewModelFamily super.from,
    required (String, int, bool) super.argument,
  }) : super(
         retry: null,
         name: r'remoteDirectoryViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$remoteDirectoryViewModelHash();

  @override
  String toString() {
    return r'remoteDirectoryViewModelProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  RemoteDirectoryViewModel create() => RemoteDirectoryViewModel();

  @override
  bool operator ==(Object other) {
    return other is RemoteDirectoryViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$remoteDirectoryViewModelHash() =>
    r'0ac8a2a75dd8762be546a321ce281f9ff886867f';

final class RemoteDirectoryViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          RemoteDirectoryViewModel,
          AsyncValue<RemoteDirectoryViewState>,
          RemoteDirectoryViewState,
          FutureOr<RemoteDirectoryViewState>,
          (String, int, bool)
        > {
  RemoteDirectoryViewModelFamily._()
    : super(
        retry: null,
        name: r'remoteDirectoryViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RemoteDirectoryViewModelProvider call(
    String alias,
    int pickerId,
    bool showProjectNameField,
  ) => RemoteDirectoryViewModelProvider._(
    argument: (alias, pickerId, showProjectNameField),
    from: this,
  );

  @override
  String toString() => r'remoteDirectoryViewModelProvider';
}

abstract class _$RemoteDirectoryViewModel
    extends $AsyncNotifier<RemoteDirectoryViewState> {
  late final _$args = ref.$arg as (String, int, bool);
  String get alias => _$args.$1;
  int get pickerId => _$args.$2;
  bool get showProjectNameField => _$args.$3;

  FutureOr<RemoteDirectoryViewState> build(
    String alias,
    int pickerId,
    bool showProjectNameField,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<RemoteDirectoryViewState>,
              RemoteDirectoryViewState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<RemoteDirectoryViewState>,
                RemoteDirectoryViewState
              >,
              AsyncValue<RemoteDirectoryViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, _$args.$3),
    );
  }
}
