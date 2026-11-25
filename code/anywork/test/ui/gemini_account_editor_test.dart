import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/accounts/accounts_views.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_projection.dart';
import 'package:anywork/src/features/settings/accounts/view_models/native_account_draft.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/account_brand.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _templates = <AccountTemplatePresentation>[
  AccountTemplatePresentation(
    key: AccountTemplateKey(kind: AccountKind.native, id: 'vertex-ai'),
    name: 'Vertex AI',
    iconKey: 'vertex',
    description: 'Vertex AI Gemini API.',
    content: AccountTemplateContent.native(
      defaultBilling: AccountBilling.metered,
      protocolLabel: 'Google Gemini',
      defaultEndpoint: 'https://aiplatform.googleapis.com/v1/publishers/google',
      supportsModelDiscovery: false,
      supportsUsageQuery: false,
    ),
  ),
  AccountTemplatePresentation(
    key: AccountTemplateKey(kind: AccountKind.native, id: 'gemini'),
    name: 'AI Studio',
    iconKey: 'gemini',
    description: 'Google AI Studio Gemini API.',
    content: AccountTemplateContent.native(
      defaultBilling: AccountBilling.metered,
      protocolLabel: 'Google Gemini',
      defaultEndpoint: 'https://generativelanguage.googleapis.com/v1beta',
      supportsModelDiscovery: true,
      supportsUsageQuery: false,
    ),
  ),
];

NativeAccountEditorPresentation _editorPresentation({
  required String templateId,
  required String endpoint,
  bool creating = true,
  List<ManualAccountModelPresentation> manualModels = const [],
}) => NativeAccountEditorPresentation(
  editorId: 'editor-$templateId',
  accountKey: creating
      ? null
      : AccountDisplayKey(kind: AccountKind.native, id: 'acct-$templateId'),
  templateKey: AccountTemplateKey(kind: AccountKind.native, id: templateId),
  templates: _templates,
  name: AccountTextPresentation(
    raw: templateId == 'vertex-ai' ? 'Vertex AI' : 'AI Studio',
    helper: 'suppressed-name-helper',
  ),
  endpoint: AccountTextPresentation(raw: endpoint),
  credential: const AccountTextPresentation(helper: 'suppressed-cred-helper'),
  protocolLabel: 'gemini',
  geminiConnection: projectGeminiConnection(
    protocol: 'gemini',
    templateId: templateId,
    endpoint: endpoint,
    canSwitchMode: creating,
    supportsModelDiscovery: templateId == 'gemini',
    hasBundledCatalog: templateId == 'vertex-ai',
  ),
  canChangeTemplate: creating,
  hasStoredCredential: !creating,
  credentialRequired: true,
  canSave: true,
  canAddModel: true,
  showSetDefaultOnCreate: creating,
  manualModels: manualModels,
  billing: const AccountBillingPresentation(
    effective: AccountBilling.metered,
    allowedOverrides: [
      AccountBilling.metered,
      AccountBilling.subscription,
      AccountBilling.noCharge,
    ],
  ),
);

Widget _wrapEditor({
  required NativeAccountEditorPresentation presentation,
  ValueChanged<AccountTemplateKey>? onTemplateChanged,
  void Function(NativeAccountField, String)? onFieldChanged,
  double textScale = 1,
}) => MaterialApp(
  locale: const Locale('zh'),
  theme: pureStudioTheme(locale: const Locale('zh')),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: NativeAccountEditorView(
      value: presentation,
      onFieldChanged: onFieldChanged ?? (_, _) {},
      onTemplateChanged: onTemplateChanged ?? (_) {},
      onBillingChanged: (_) {},
      onResetBilling: () {},
      onAddModel: () {},
      onManualModelFieldChanged: (_, _, _) {},
      onManualModelConnectionChanged: (_, _) {},
      onManualModelWireApiChanged: (_, _) {},
      onRemoveManualModel: (_) {},
      modelActions: AccountModelActions(
        onCompactPreset: (_, _) {},
        onEnabledChanged: (_, _) {},
        onConnectionChanged: (_, _) {},
        onCompactChanged: (_, _) {},
        onAction: (_, _) {},
      ),
      onSave: () {},
      onCancel: () {},
    ),
  ),
);

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets(
    'Google text outside the host does not identify an official endpoint',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrapEditor(
          presentation: _editorPresentation(
            templateId: 'vertex-ai',
            endpoint:
                'https://proxy.example/v1?upstream=aiplatform.googleapis.com',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('自定义端点'), findsOneWidget);
      expect(find.text('隐式缓存'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'creating Vertex AI account switches mode and applies region preset',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      AccountTemplateKey? switchedTemplate;
      final fieldChanges = <(NativeAccountField, String)>[];

      await tester.pumpWidget(
        _wrapEditor(
          presentation: _editorPresentation(
            templateId: 'vertex-ai',
            endpoint: 'https://aiplatform.googleapis.com/v1/publishers/google',
          ),
          onTemplateChanged: (key) => switchedTemplate = key,
          onFieldChanged: (field, raw) => fieldChanges.add((field, raw)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('gemini-access-mode-switcher')),
        findsOneWidget,
      );
      expect(find.text('x-goog-api-key'), findsOneWidget);
      expect(find.text('内置目录'), findsOneWidget);
      expect(find.text('Vertex AI API 密钥'), findsOneWidget);
      expect(find.text('suppressed-name-helper'), findsNothing);
      expect(find.text('suppressed-cred-helper'), findsNothing);

      await tester.tap(find.text('us-central1'));
      await tester.pump();
      expect(fieldChanges, [
        (
          NativeAccountField.endpoint,
          'https://us-central1-aiplatform.googleapis.com/v1/publishers/google',
        ),
      ]);

      await tester.tap(find.text('AI Studio').first);
      await tester.pump();
      expect(
        switchedTemplate,
        const AccountTemplateKey(kind: AccountKind.native, id: 'gemini'),
      );
    },
  );

  testWidgets(
    'endpoint presets support keyboard activation and disable while saving',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final changes = <(NativeAccountField, String)>[];
      final presentation = _editorPresentation(
        templateId: 'vertex-ai',
        endpoint: 'https://aiplatform.googleapis.com/v1/publishers/google',
      );
      Widget host({required bool saving}) => _wrapEditor(
        presentation: presentation.copyWith(saving: saving),
        onFieldChanged: (field, raw) => changes.add((field, raw)),
      );
      await tester.pumpWidget(host(saving: false));
      await tester.pumpAndSettle();
      final region = find.text('us-central1');
      await tester.ensureVisible(region);
      Focus.of(tester.element(region)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(changes, [
        (
          NativeAccountField.endpoint,
          'https://us-central1-aiplatform.googleapis.com/v1/publishers/google',
        ),
      ]);
      await tester.pumpWidget(host(saving: true));
      // Saving deliberately keeps an indeterminate progress indicator active.
      await tester.pump(const Duration(milliseconds: 300));
      final chip = find.ancestor(of: region, matching: find.byType(ChoiceChip));
      expect(tester.widget<ChoiceChip>(chip).onSelected, isNull);
      await tester.tap(region);
      await tester.pump(const Duration(milliseconds: 300));
      expect(changes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'creating Gemini AI Studio account shows online discovery and switches back',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      AccountTemplateKey? switchedTemplate;

      await tester.pumpWidget(
        _wrapEditor(
          presentation: _editorPresentation(
            templateId: 'gemini',
            endpoint: 'https://generativelanguage.googleapis.com/v1beta',
          ),
          onTemplateChanged: (key) => switchedTemplate = key,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('在线目录'), findsOneWidget);
      expect(find.text('Gemini API (v1beta)'), findsOneWidget);
      expect(find.text('Gemini API 密钥'), findsOneWidget);
      expect(find.text('suppressed-name-helper'), findsNothing);
      expect(find.text('suppressed-cred-helper'), findsNothing);

      await tester.tap(find.text('Vertex AI').first);
      await tester.pump();
      expect(
        switchedTemplate,
        const AccountTemplateKey(kind: AccountKind.native, id: 'vertex-ai'),
      );
    },
  );

  testWidgets(
    'editing existing Vertex AI account hides mode switcher and locks manual model wire API',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrapEditor(
          presentation: _editorPresentation(
            templateId: 'vertex-ai',
            endpoint: 'https://aiplatform.googleapis.com/v1/publishers/google',
            creating: false,
            manualModels: const [
              ManualAccountModelPresentation(
                editorKey: 'row-1',
                id: AccountTextPresentation(raw: 'gemini-4-neon'),
                name: AccountTextPresentation(raw: 'Gemini 4 Neon'),
                contextWindow: AccountTextPresentation(raw: '1048576'),
                maxOutputTokens: AccountTextPresentation(raw: '65536'),
                wireApi: AccountWireApi.geminiGenerateContent,
                allowedWireApis: [AccountWireApi.geminiGenerateContent],
                connection: AccountConnection.http,
                allowedConnections: [
                  AccountConnection.automatic,
                  AccountConnection.http,
                ],
                canRemove: true,
                canEditId: true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('gemini-access-mode-switcher')),
        findsNothing,
      );
      expect(find.text('us-central1'), findsOneWidget);
      expect(find.text('Gemini API（generateContent，HTTP）'), findsOneWidget);
      expect(find.text('OpenAI Responses (HTTP)'), findsNothing);
    },
  );

  test('ManualModelDraft restricts allowed WireApi and connection modes by account protocol', () {
    const strings = AccountStrings({'required': 'Required'});
    const geminiDraft = ManualModelDraft(
      editorKey: 'g1',
      id: 'gemini-4-hydrogen',
      wireApi: AccountWireApi.geminiGenerateContent,
    );
    final geminiPresentation = geminiDraft.presentation(
      strings,
      null,
      accountProtocol: 'gemini',
    );
    expect(geminiPresentation.allowedWireApis, [
      AccountWireApi.geminiGenerateContent,
    ]);
    expect(geminiPresentation.allowedConnections, [
      AccountConnection.automatic,
      AccountConnection.http,
    ]);

    const openAiDraft = ManualModelDraft(
      editorKey: 'o1',
      id: 'gpt-6-astra',
      wireApi: AccountWireApi.responses,
    );
    final openAiPresentation = openAiDraft.presentation(
      strings,
      null,
      accountProtocol: 'openai',
    );
    expect(openAiPresentation.allowedWireApis, [
      AccountWireApi.chatCompletions,
      AccountWireApi.responses,
    ]);
  });

  testWidgets(
    'narrow 400x900 viewport with 1.3 text scale renders Gemini editor without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrapEditor(
          presentation: _editorPresentation(
            templateId: 'vertex-ai',
            endpoint: 'https://aiplatform.googleapis.com/v1/publishers/google',
          ),
          textScale: 1.3,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Vertex AI'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets('AccountBrandMark loads vertex and gemini SVG brand assets', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              AccountBrandMark(iconKey: 'vertex', fallbackName: 'Vertex'),
              AccountBrandMark(iconKey: 'gemini', fallbackName: 'Gemini'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SvgPicture), findsNWidgets(2));
    final pictures = tester.widgetList<SvgPicture>(find.byType(SvgPicture));
    for (final picture in pictures) {
      final loader = picture.bytesLoader as SvgAssetLoader;
      final bytes = await loader.loadBytes(null);
      expect(bytes.lengthInBytes, greaterThan(0));
    }
  });

  testWidgets(
    'AccountTemplateSelector merges vertex-ai and gemini into a single Gemini entry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const openAiTemplate = AccountTemplatePresentation(
        key: AccountTemplateKey(kind: AccountKind.native, id: 'openai'),
        name: 'OpenAI',
        iconKey: 'openai',
        content: AccountTemplateContent.native(
          defaultBilling: AccountBilling.metered,
          protocolLabel: 'OpenAI',
          defaultEndpoint: 'https://api.openai.com/v1',
          supportsModelDiscovery: true,
          supportsUsageQuery: false,
        ),
      );
      AccountTemplateKey? picked;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AccountTemplateSelector(
              templates: [openAiTemplate, ..._templates],
              selected: openAiTemplate.key,
              onSelected: (key) => picked = key,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownMenu<AccountTemplateKey>));
      await tester.pumpAndSettle();

      expect(find.text('Gemini'), findsAtLeastNWidgets(1));
      expect(find.text('Vertex AI'), findsNothing);
      expect(find.text('AI Studio'), findsNothing);

      await tester.tap(find.text('Gemini').last);
      await tester.pumpAndSettle();
      expect(
        picked,
        const AccountTemplateKey(kind: AccountKind.native, id: 'gemini'),
      );
    },
  );
}
