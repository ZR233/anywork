// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(projectStore)
final projectStoreProvider = ProjectStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class ProjectStoreProvider
    extends
        $FunctionalProvider<
          ProjectStoreState,
          ProjectStoreState,
          ProjectStoreState
        >
    with $Provider<ProjectStoreState> {
  /// Riverpod owns this display observation; the Client owns the resource.
  ProjectStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectStoreHash();

  @$internal
  @override
  $ProviderElement<ProjectStoreState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ProjectStoreState create(Ref ref) {
    return projectStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectStoreState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectStoreState>(value),
    );
  }
}

String _$projectStoreHash() => r'662ee237c59f7879dcc063db4cc66382f1383670';
