import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:flutter/widget_previews.dart';
import 'package:anywork/src/shared/composer_configuration_bar.dart';
import 'package:material_ui/material_ui.dart';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/l10n/studio_l10n.dart';
import 'package:anywork/src/platform/dropped_file.dart';
import 'package:anywork/src/platform/external_url_launcher.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_input_state.dart';
import 'package:anywork/src/features/conversation/composer/state/start_backend_view_state.dart';
import 'package:anywork/src/features/conversation/composer/view_models/composer_actions.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/composer/views/composer_submission_body.dart';
import 'package:anywork/src/features/conversation/composer/views/composer_route_selectors.dart';
import 'package:anywork/src/features/conversation/composer/views/start_model_selector_view.dart';
import 'package:anywork/src/features/status/session_selectors.dart';
import 'package:anywork/src/shared/composer_action_button.dart';

@Preview(name: 'Composer / 可编辑纯输入', group: 'Composer', size: Size(760, 340))
@Preview(name: 'Composer / 窄窗', group: 'Composer', size: Size(360, 460))
@Preview(
  name: 'Composer / Native 运行期可编辑 · 2×字号压力',
  group: 'Composer',
  size: Size(380, 460),
  textScaleFactor: 2,
)
Widget composerInputPreview() =>
    _composerPreviewHost(const _PreviewInput(key: ValueKey('native-editable')));

@Preview(
  name: 'Composer / Speed · Demo GPT-6.2 Sol',
  group: 'Composer',
  size: Size(900, 340),
)
Widget composerSpeedPreview() => _composerPreviewHost(
  const _PreviewInput(key: ValueKey('native-speed'), newConversation: true),
  locale: const Locale('en'),
);

@Preview(
  name: 'Composer / Native 新会话 · 宽窗',
  group: 'Composer',
  size: Size(760, 340),
)
@Preview(
  name: 'Composer / 普通窄窗 · 280px',
  group: 'Composer',
  size: Size(280, 340),
)
@Preview(
  name: 'Composer / 普通窄窗 · 340px',
  group: 'Composer',
  size: Size(340, 340),
)
@Preview(
  name: 'Composer / 普通窄窗 · 360px',
  group: 'Composer',
  size: Size(360, 340),
)
@Preview(
  name: 'Composer / Native 新会话 · 2×字号压力',
  group: 'Composer',
  size: Size(380, 460),
  textScaleFactor: 2,
)
Widget composerCreationPreview() => _composerPreviewHost(
  const _PreviewInput(
    key: ValueKey('native-creation'),
    newConversation: true,
    initialText: '创建一个新会话，梳理当前项目的实现边界。',
  ),
);

@Preview(name: 'Composer / 运行中停止', group: 'Composer', size: Size(1040, 220))
Widget composerStopPreview() => _composerPreviewHost(
  const _PreviewInput(
    key: ValueKey('native-running'),
    initialText: '',
    execution: AgentExecutionView(
      id: 'preview-run',
      phase: AgentExecutionPhase.running,
    ),
  ),
);

@Preview(name: 'Composer / 主操作全部状态', group: 'Composer', size: Size(760, 180))
Widget composerActionStatesPreview() => _composerPreviewHost(
  Builder(
    builder: (context) {
      final l10n = context.l10n;
      final states = [
        (ComposerActionButtonState.send, l10n.composerSend, true),
        (
          ComposerActionButtonState.sendAndContinue,
          l10n.composerSendAndContinue,
          true,
        ),
        (ComposerActionButtonState.stop, l10n.composerStop, true),
        (
          ComposerActionButtonState.continueConversation,
          l10n.composerContinueTooltip,
          true,
        ),
        (ComposerActionButtonState.busy, l10n.composerStopping, true),
        (ComposerActionButtonState.send, l10n.composerSend, false),
        (
          ComposerActionButtonState.readOnly,
          l10n.composerAgentReadOnlyTitle,
          false,
        ),
      ];
      return Wrap(
        spacing: 24,
        runSpacing: 16,
        children: [
          for (final (state, label, enabled) in states)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ComposerActionButton(
                  state: state,
                  tooltip: label,
                  onPressed: enabled ? () {} : null,
                ),
                const SizedBox(height: 8),
                Text(
                  !enabled && state == ComposerActionButtonState.send
                      ? '$label（禁用）'
                      : label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
        ],
      );
    },
  ),
);

@Preview(name: 'Composer / 失败正文可选择复制', group: 'Composer', size: Size(760, 640))
Widget composerSubmissionPreview() => _composerPreviewHost(
  const _PreviewInput(key: ValueKey('native-submission'), showSubmission: true),
);

Widget _composerPreviewHost(
  Widget child, {
  Locale locale = const Locale('zh'),
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  theme: pureStudioTheme(locale: locale),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) =>
      ListTileTheme(data: Theme.of(context).listTileTheme, child: child!),
  home: Scaffold(
    body: Center(
      child: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  ),
);

class _PreviewInput extends StatefulWidget {
  const _PreviewInput({
    required super.key,
    this.showSubmission = false,
    this.newConversation = false,
    this.initialText = '输入下一条消息',
    this.execution,
  });
  final bool showSubmission;
  // Preview-only distinction; production owns creation layout and controls.
  final bool newConversation;
  final String initialText;
  final AgentExecutionView? execution;
  @override
  State<_PreviewInput> createState() => _PreviewInputState();
}

// Preview-only editing data, not another production draft owner.
class _PreviewInputState extends State<_PreviewInput>
    implements ComposerActions {
  late String _text = widget.initialText;
  String? _serviceTier;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.showSubmission) ...[
        ComposerSubmissionBody(
          submission: ComposerSubmission(
            inputId: 'preview-failed-submission',
            text:
                '**冻结的上一条输入**\n\n'
                '```dart\n  final value = 1;\n```\n\n'
                '[安全链接](https://example.com/guide)\n\n'
                '[不可打开的链接](javascript:alert)\n\n'
                '![外部图片](https://example.com/image.png)',
            attachments: const [],
            phase: ComposerSubmissionPhase.failed,
          ),
          isSafeLink: (raw) => safeExternalWebUrl(raw) != null,
          onLink: (_) {},
        ),
        Text(context.l10n.composerSubmissionFailed),
        const SizedBox(height: 16),
      ],
      PromptComposerView(
        targetKey: widget.key!,
        creationCard: widget.newConversation,
        actions: this,
        state: ComposerInputState(
          composer: ComposerThreadState.idle(draft: _text),
          enabled: true,
          nowMs: 0,
          execution: widget.execution,
          inputCapabilities: const [
            ModelInputCapabilityView(
              modality: ModelModalityView.image,
              sources: [ModelInputSourceView.local],
            ),
          ],
        ),
        selectorBar: ComposerConfigurationBar(
          moreTooltip: context.l10n.acpConfigMoreLabel,
          entries: [
            ComposerConfigurationEntry(
              id: 'mode',
              inline: _modeSelector(false),
              measureInlineWidth: _modeSelector(false).measureInlineWidth,
              menuItem: _modeSelector(true),
            ),
            if (widget.newConversation) ...[
              ComposerConfigurationEntry(
                id: 'native-model',
                inline: _startModelSelector(false),
                measureInlineWidth: _startModelSelector(false)
                    .measureInlineWidth,
                menuItem: _startModelSelector(true),
              ),
              ComposerConfigurationEntry(
                id: 'native-effort',
                inline: _startEffortSelector(false),
                measureInlineWidth: _startEffortSelector(false)
                    .measureInlineWidth,
                menuItem: _startEffortSelector(true),
              ),
              ?serviceTierConfigurationEntry(
                accounts: _previewAccounts,
                accountId: 'preview-account',
                modelId: 'preview-model',
                serviceTier: _serviceTier,
                enabled: true,
                onSelected: (value) => setState(() => _serviceTier = value),
              ),
            ] else
              ...modelRouteConfigurationEntries(
                accounts: _previewAccounts,
                pending: false,
                accountId: 'preview-account',
                modelId: 'preview-model',
                effort: 'high',
                serviceTier: _serviceTier,
                unavailableReason:
                    context.l10n.statusModelRouteUnavailableFallback,
                onModelSelected: (_, _) {},
                onEffortSelected: (_) {},
                onServiceTierSelected: (value) =>
                    setState(() => _serviceTier = value),
              ),
          ],
        ),
      ),
    ],
  );

  SessionModeSelector _modeSelector(bool inMenu) => SessionModeSelector(
    inMenu: inMenu,
    catalog: const ThreadModeCatalogView(),
    mode: ThreadModeId.auto,
    enabled: widget.execution == null,
    onSelected: (_) {},
  );

  StartModelSelectorView _startModelSelector(bool inMenu) =>
      StartModelSelectorView(
        inMenu: inMenu,
        state: _previewStartBackend,
        onSelectModel: (_, _) {},
        onSelectService: (_) {},
        onManageServices: () {},
      );

  ReasoningEffortSelector _startEffortSelector(bool inMenu) =>
      ReasoningEffortSelector(
        inMenu: inMenu,
        accounts: _previewAccounts,
        accountId: 'preview-account',
        modelId: 'preview-model',
        effort: 'high',
        onEffortSelected: (_) {},
      );

  @override
  void updateText(String text) => setState(() => _text = text);
  @override
  void submit() => setState(() => _text = '');
  @override
  void stop(String expectedExecutionId) {}
  @override
  void continueConversation() {}
  @override
  void removeAttachment(String draftId) {}
  @override
  void addUrl(String url) {}
  @override
  void pickAttachments(
    List<ModelInputCapabilityView> capabilities,
    bool Function() isCurrent,
  ) {}
  @override
  Future<void> dropAttachments(
    List<DroppedFileTransfer> files,
    bool Function() isCurrent,
  ) async {}
  @override
  void paste(ComposerTextPaste textPaste) {
    if (textPaste.isCurrent()) textPaste.invoke();
  }
}

final _previewAccounts = [
  ModelSelectionAccount(
    id: 'preview-account',
    name: 'OpenAI（预览）',
    brandKey: 'openai',
    billingKind: null,
    models: const [
      AccountModelView(
        modelId: 'preview-model',
        displayName: 'Demo GPT-6.2 Sol',
        reasoningEfforts: ['low', 'high'],
        inputCapabilities: [
          ModelInputCapabilityView(
            modality: ModelModalityView.text,
            sources: [],
          ),
          ModelInputCapabilityView(
            modality: ModelModalityView.image,
            sources: [ModelInputSourceView.local],
          ),
        ],
        serviceTiers: ModelServiceTierParameterView(
          candidates: [
            ModelServiceTierView(id: 'priority', displayName: 'Fast'),
            ModelServiceTierView(id: 'ultrafast', displayName: 'Ultrafast'),
          ],
        ),
        typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
      ),
    ],
  ),
  ModelSelectionAccount(
    id: 'preview-gemini',
    name: 'Gemini（预览）',
    brandKey: 'gemini',
    billingKind: null,
    models: const [
      AccountModelView(
        modelId: 'preview-gemini-model',
        displayName: 'Demo Gemini',
        reasoningEfforts: [],
        inputCapabilities: [
          ModelInputCapabilityView(
            modality: ModelModalityView.text,
            sources: [],
          ),
          ModelInputCapabilityView(
            modality: ModelModalityView.image,
            sources: [ModelInputSourceView.local],
          ),
          ModelInputCapabilityView(
            modality: ModelModalityView.audio,
            sources: [ModelInputSourceView.local],
          ),
        ],
        typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
      ),
    ],
  ),
];

// Synthetic summaries only: no account configuration or service is accessed.
final _previewStartBackend = StartBackendViewState(
  modelAccounts: _previewAccounts,
  modelAccountId: 'preview-account',
  modelId: 'preview-model',
  services: const [
    StartBackendServiceItem(
      id: 'preview-acp-service',
      name: '合成 ACP 服务',
      enabled: true,
    ),
  ],
  nativeEnabled: true,
  enabled: true,
  loading: false,
);
