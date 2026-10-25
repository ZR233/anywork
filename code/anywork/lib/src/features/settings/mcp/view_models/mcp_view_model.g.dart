// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(McpViewModel)
final mcpViewModelProvider = McpViewModelProvider._();

final class McpViewModelProvider
    extends $AsyncNotifierProvider<McpViewModel, McpViewState> {
  McpViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mcpViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpViewModelHash();

  @$internal
  @override
  McpViewModel create() => McpViewModel();
}

String _$mcpViewModelHash() => r'302468c448d7f6e04c22d259c60ec411d20272b4';

abstract class _$McpViewModel extends $AsyncNotifier<McpViewState> {
  FutureOr<McpViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<McpViewState>, McpViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<McpViewState>, McpViewState>,
              AsyncValue<McpViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
