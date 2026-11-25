import 'account_presentations.dart';

/// Projects Gemini connection guidance for presentation only.
///
/// Endpoint parsing is deliberately display-only: the raw draft remains owned
/// by the editor view model and is never normalized or written back here.
AccountGeminiConnectionPresentation? projectGeminiConnection({
  required String protocol,
  required String? templateId,
  required String endpoint,
  required bool canSwitchMode,
  bool? supportsModelDiscovery,
  bool hasBundledCatalog = false,
}) {
  if (protocol != 'gemini') return null;

  final normalized = endpoint.trim().replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(normalized);
  final host = uri?.host ?? '';
  final vertexHost =
      host == 'aiplatform.googleapis.com' ||
      RegExp(r'^[a-z]+(?:-[a-z]+)*[0-9]+-aiplatform\.googleapis\.com$')
          .hasMatch(host);
  final aiStudioHost = host == 'generativelanguage.googleapis.com';
  final vertexPath =
      uri?.path == '/v1/publishers/google' ||
      uri?.path == '/v1beta1/publishers/google';
  final aiStudioPath = uri?.path == '/v1beta' || uri?.path == '/v1';
  final official =
      uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      ((vertexHost && vertexPath) || (aiStudioHost && aiStudioPath));
  final mode = switch (templateId) {
    'vertex-ai' => AccountGeminiGuidanceMode.vertexAi,
    'gemini' => AccountGeminiGuidanceMode.aiStudio,
    _ =>
      vertexHost
          ? AccountGeminiGuidanceMode.vertexAi
          : AccountGeminiGuidanceMode.aiStudio,
  };

  return AccountGeminiConnectionPresentation(
    mode: mode,
    endpointKind: official
        ? AccountGeminiEndpointKind.official
        : AccountGeminiEndpointKind.custom,
    selectedPreset: AccountGeminiEndpointPreset.values
        .where((preset) => normalized == preset.endpoint)
        .firstOrNull,
    canSwitchMode: canSwitchMode,
    supportsModelDiscovery: supportsModelDiscovery,
    hasBundledCatalog: hasBundledCatalog,
  );
}
