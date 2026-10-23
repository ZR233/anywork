import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

part 'lsp_values.freezed.dart';

@Freezed(toStringOverride: false)
sealed class LspActivity with _$LspActivity {
  const factory LspActivity.idle() = IdleLspActivity;
  const factory LspActivity.busy({
    required String? title,
    required String? message,
    required int? percentage,
  }) = BusyLspActivity;
  const factory LspActivity.indexing({
    required String? title,
    required String? message,
    required int? percentage,
  }) = IndexingLspActivity;
}

@Freezed(toStringOverride: false)
sealed class LspServerState with _$LspServerState {
  const factory LspServerState.checking({required String message}) =
      CheckingLspServerState;
  const factory LspServerState.disabled({required String message}) =
      DisabledLspServerState;
  const factory LspServerState.unavailable({
    required int checkedAt,
    required SourceStateError error,
  }) = UnavailableLspServerState;
  const factory LspServerState.available({
    required int checkedAt,
    required int diagnosticCount,
    required LspActivity activity,
  }) = AvailableLspServerState;
}

@Freezed(toStringOverride: false)
abstract class LspServer with _$LspServer {
  const factory LspServer({
    required String id,
    required String displayName,
    required List<String> extensions,
    required List<String> languageIds,
    required LspServerState state,
  }) = _LspServer;
}

@freezed
abstract class LspHealth with _$LspHealth {
  const factory LspHealth({
    required List<LspServer> lspServers,
    required List<String> activeLspServers,
  }) = _LspHealth;
}
