import 'package:anywork_client/studio_client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'started_items_state.freezed.dart';

enum StartedServiceStatus {
  checking,
  loading,
  probing,
  starting,
  initializing,
  connecting,
  stopping,
  indexing,
  busy,
  ready,
  failed,
  disabled,
  unsupported,
}

@freezed
abstract class StartedService with _$StartedService {
  const factory StartedService({
    required String id,
    required String name,
    required StartedServiceStatus status,
    int? percentage,
    String? diagnostic,
    @Default(true) bool canReconnect,
  }) = _StartedService;
}

@freezed
abstract class StartedItemsState with _$StartedItemsState {
  const factory StartedItemsState({
    @Default(<String>[]) List<String> skills,
    @Default(<StartedService>[]) List<StartedService> mcp,
    @Default(<StartedService>[]) List<StartedService> lsp,
    required DomainSyncStatus mcpSync,
    required DomainSyncStatus lspSync,
    @Default(<String>{}) Set<String> pending,
    @Default(<String, String>{}) Map<String, String> errors,
  }) = _StartedItemsState;
}
