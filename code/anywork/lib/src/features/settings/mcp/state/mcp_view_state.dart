import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/mcp.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/settings_action.dart';

part 'mcp_view_state.freezed.dart';

enum McpConfigField { enabled, endpoint }
enum McpReadField { configuration, runtime, configurationStatus, runtimeStatus }

@Freezed(toStringOverride: false)
abstract class McpServerDraft with _$McpServerDraft {
  const factory McpServerDraft({required bool enabled, required String endpoint,
    @Default({}) Set<McpConfigField> dirty, @Default({}) Map<McpConfigField, int> revisions,
    @Default({}) Map<McpConfigField, SettingsAction> actions, @Default(false) bool composing}) = _McpServerDraft;
}

@Freezed(toStringOverride: false)
abstract class McpViewState with _$McpViewState {
  const factory McpViewState({required ConfigurationState configurationSource, required McpState source,
    @Default({}) Map<String, McpServerDraft> drafts, @Default({}) Map<String, SettingsAction> resets,
    SettingsAction? resetAllAction, @Default(0) int latestIntent,
    @Default({}) Map<McpReadField, StudioFailure> readIssues,
    @Default({}) Set<McpReadField> reading}) = _McpViewState;
}
