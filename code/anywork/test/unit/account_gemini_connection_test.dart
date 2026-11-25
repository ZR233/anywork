import 'package:anywork/src/features/settings/accounts/state/account_gemini_connection.dart';
import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requires the exact Gemini protocol', () {
    for (final protocol in [
      'Google Gemini',
      'gemini-compatible',
      'open_ai',
      'GEMINI',
    ]) {
      expect(
        projectGeminiConnection(
          protocol: protocol,
          templateId: 'gemini',
          endpoint: AccountGeminiEndpointPreset.aiStudio.endpoint,
          canSwitchMode: false,
        ),
        isNull,
        reason: protocol,
      );
    }
  });

  test('classifies official endpoints only for permitted URI fields', () {
    const cases =
        <
          (
            String,
            AccountGeminiEndpointKind,
            AccountGeminiGuidanceMode,
            AccountGeminiEndpointPreset?,
          )
        >[
          (
            'https://generativelanguage.googleapis.com/v1beta',
            AccountGeminiEndpointKind.official,
            AccountGeminiGuidanceMode.aiStudio,
            AccountGeminiEndpointPreset.aiStudio,
          ),
          (
            ' https://aiplatform.googleapis.com/v1/publishers/google/ ',
            AccountGeminiEndpointKind.official,
            AccountGeminiGuidanceMode.vertexAi,
            AccountGeminiEndpointPreset.vertexGlobal,
          ),
          (
            'https://us-central1-aiplatform.googleapis.com/v1/publishers/google',
            AccountGeminiEndpointKind.official,
            AccountGeminiGuidanceMode.vertexAi,
            AccountGeminiEndpointPreset.vertexUsCentral1,
          ),
          (
            'https://aiplatform.googleapis.com:443/v1/publishers/google',
            AccountGeminiEndpointKind.official,
            AccountGeminiGuidanceMode.vertexAi,
            null,
          ),
          (
            'https://user@aiplatform.googleapis.com/v1/publishers/google',
            AccountGeminiEndpointKind.custom,
            AccountGeminiGuidanceMode.vertexAi,
            null,
          ),
          (
            'https://aiplatform.googleapis.com/v1/publishers/google?x=1',
            AccountGeminiEndpointKind.custom,
            AccountGeminiGuidanceMode.vertexAi,
            null,
          ),
          (
            'https://aiplatform.googleapis.com.example.test/v1/publishers/google',
            AccountGeminiEndpointKind.custom,
            AccountGeminiGuidanceMode.aiStudio,
            null,
          ),
          (
            'https://proxy.example/aiplatform.googleapis.com',
            AccountGeminiEndpointKind.custom,
            AccountGeminiGuidanceMode.aiStudio,
            null,
          ),
          (
            'https://aiplatform.googleapis.com@proxy.example/v1',
            AccountGeminiEndpointKind.custom,
            AccountGeminiGuidanceMode.aiStudio,
            null,
          ),
          (
            'https://proxy.example/v1?host=aiplatform.googleapis.com',
            AccountGeminiEndpointKind.custom,
            AccountGeminiGuidanceMode.aiStudio,
            null,
          ),
          (
            'https://generativelanguage.googleapis.com/v1#fragment',
            AccountGeminiEndpointKind.custom,
            AccountGeminiGuidanceMode.aiStudio,
            null,
          ),
          (
            'http://aiplatform.googleapis.com/v1/publishers/google',
            AccountGeminiEndpointKind.custom,
            AccountGeminiGuidanceMode.vertexAi,
            null,
          ),
          (
            'https://aiplatform.googleapis.com/unsupported/path',
            AccountGeminiEndpointKind.custom,
            AccountGeminiGuidanceMode.vertexAi,
            null,
          ),
          (
            'https://aiplatform.googleapis.com:8443/v1/publishers/google',
            AccountGeminiEndpointKind.custom,
            AccountGeminiGuidanceMode.vertexAi,
            null,
          ),
          (
            'http://[invalid',
            AccountGeminiEndpointKind.custom,
            AccountGeminiGuidanceMode.aiStudio,
            null,
          ),
        ];

    for (final (endpoint, kind, mode, preset) in cases) {
      final value = projectGeminiConnection(
        protocol: 'gemini',
        templateId: null,
        endpoint: endpoint,
        canSwitchMode: false,
      )!;
      expect((value.endpointKind, value.mode), (kind, mode), reason: endpoint);
      expect(value.selectedPreset, preset, reason: endpoint);
    }
  });

  test('template guidance takes priority over endpoint host inference', () {
    final vertexTemplate = projectGeminiConnection(
      protocol: 'gemini',
      templateId: 'vertex-ai',
      endpoint: AccountGeminiEndpointPreset.aiStudio.endpoint,
      canSwitchMode: false,
    )!;
    final aiStudioTemplate = projectGeminiConnection(
      protocol: 'gemini',
      templateId: 'gemini',
      endpoint: AccountGeminiEndpointPreset.vertexGlobal.endpoint,
      canSwitchMode: false,
    )!;

    expect(vertexTemplate.mode, AccountGeminiGuidanceMode.vertexAi);
    expect(aiStudioTemplate.mode, AccountGeminiGuidanceMode.aiStudio);
  });

  test('unknown templates infer Vertex from host and default to AI Studio', () {
    final vertex = projectGeminiConnection(
      protocol: 'gemini',
      templateId: 'missing-template',
      endpoint: AccountGeminiEndpointPreset.vertexGlobal.endpoint,
      canSwitchMode: false,
    )!;
    final defaulted = projectGeminiConnection(
      protocol: 'gemini',
      templateId: 'missing-template',
      endpoint: 'https://proxy.example/v1',
      canSwitchMode: false,
    )!;

    expect(vertex.mode, AccountGeminiGuidanceMode.vertexAi);
    expect(defaulted.mode, AccountGeminiGuidanceMode.aiStudio);
  });

  test('passes editor and catalog facts through without deriving them', () {
    final value = projectGeminiConnection(
      protocol: 'gemini',
      templateId: 'gemini',
      endpoint: AccountGeminiEndpointPreset.aiStudio.endpoint,
      canSwitchMode: true,
      supportsModelDiscovery: false,
      hasBundledCatalog: true,
    )!;

    expect(value.canSwitchMode, isTrue);
    expect(value.supportsModelDiscovery, isFalse);
    expect(value.hasBundledCatalog, isTrue);
  });
}
