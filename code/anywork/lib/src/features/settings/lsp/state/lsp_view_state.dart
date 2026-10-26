import 'package:anywork_client/lsp.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/settings_action.dart';

part 'lsp_view_state.freezed.dart';

enum LspReadField { servers, status }

enum LspActionKind { probe, repair, resetServer, resetWorkspace }

@Freezed(toStringOverride: false)
abstract class LspCatalogViewState with _$LspCatalogViewState {
  const factory LspCatalogViewState({
    required LspState source,
    @Default({}) Map<LspReadField, StudioFailure> readIssues,
    @Default({}) Set<LspReadField> reading,
  }) = _LspCatalogViewState;
}

@freezed
abstract class LspActionsViewState with _$LspActionsViewState {
  const factory LspActionsViewState({
    required String projectId,
    @Default(0) int latestIntent,
    @Default({}) Map<(LspActionKind, String?), SettingsAction> actions,
  }) = _LspActionsViewState;
}
