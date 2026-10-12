// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 项目目录与 Agent 目录。两者是协议上独立的 revision，不合成一个水位。

@ProviderFor(ProjectStore)
final projectStoreProvider = ProjectStoreProvider._();

/// 项目目录与 Agent 目录。两者是协议上独立的 revision，不合成一个水位。
final class ProjectStoreProvider
    extends $NotifierProvider<ProjectStore, ProjectStoreState> {
  /// 项目目录与 Agent 目录。两者是协议上独立的 revision，不合成一个水位。
  ProjectStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectStoreHash();

  @$internal
  @override
  ProjectStore create() => ProjectStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectStoreState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectStoreState>(value),
    );
  }
}

String _$projectStoreHash() => r'02cbb74ecaa03eba1216ded5860b37ad79ef4eb0';

/// 项目目录与 Agent 目录。两者是协议上独立的 revision，不合成一个水位。

abstract class _$ProjectStore extends $Notifier<ProjectStoreState> {
  ProjectStoreState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ProjectStoreState, ProjectStoreState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ProjectStoreState, ProjectStoreState>,
              ProjectStoreState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
