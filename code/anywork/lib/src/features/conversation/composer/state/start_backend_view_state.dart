import 'package:freezed_annotation/freezed_annotation.dart';

part 'start_backend_view_state.freezed.dart';

@freezed
abstract class StartBackendServiceItem with _$StartBackendServiceItem {
  const factory StartBackendServiceItem({
    required String id,
    required String name,
    String? brandKey,
    required bool enabled,
  }) = _StartBackendServiceItem;
}

@freezed
abstract class StartBackendDiagnosticItem with _$StartBackendDiagnosticItem {
  const factory StartBackendDiagnosticItem({
    required String fileName,
    required String message,
  }) = _StartBackendDiagnosticItem;
}

@freezed
abstract class StartBackendViewState with _$StartBackendViewState {
  const StartBackendViewState._();

  const factory StartBackendViewState({
    @Default(<StartBackendServiceItem>[])
    List<StartBackendServiceItem> services,
    @Default(<StartBackendDiagnosticItem>[])
    List<StartBackendDiagnosticItem> diagnostics,
    String? accountId,
    @Default(false) bool enabled,
    @Default(true) bool loading,
    String? failure,
  }) = _StartBackendViewState;

  StartBackendServiceItem? get selectedService => accountId == null
      ? null
      : services.where((item) => item.id == accountId).firstOrNull;

  String? get serviceName => selectedService?.name;
}
