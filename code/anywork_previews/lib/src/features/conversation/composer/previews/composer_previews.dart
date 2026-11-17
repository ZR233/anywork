import 'package:anywork_client/studio_client.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/l10n/studio_l10n.dart';
import 'package:anywork/src/platform/dropped_file.dart';
import 'package:anywork/src/platform/external_url_launcher.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_input_state.dart';
import 'package:anywork/src/features/conversation/composer/view_models/composer_actions.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/composer/views/composer_submission_body.dart';
import 'package:anywork/src/features/conversation/composer/views/composer_route_selectors.dart';
import 'package:anywork/src/features/status/session_selectors.dart';
import 'package:anywork/src/shared/composer_action_button.dart';

@Preview(name: 'Composer / 可编辑纯输入', group: 'Composer', size: Size(760, 340))
@Preview(name: 'Composer / 窄窗', group: 'Composer', size: Size(360, 460))
Widget composerInputPreview() => _composerPreviewHost(const _PreviewInput());

@Preview(name: 'Composer / 运行中停止', group: 'Composer', size: Size(1040, 220))
Widget composerStopPreview() => _composerPreviewHost(
  const _PreviewInput(
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
Widget composerSubmissionPreview() =>
    _composerPreviewHost(const _PreviewInput(showSubmission: true));

Widget _composerPreviewHost(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  theme: pureStudioTheme(locale: const Locale('zh')),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
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
    this.showSubmission = false,
    this.initialText = '输入下一条消息',
    this.execution,
  });
  final bool showSubmission;
  final String initialText;
  final AgentExecutionView? execution;
  @override
  State<_PreviewInput> createState() => _PreviewInputState();
}

// Preview-only editing data, not another production draft owner.
class _PreviewInputState extends State<_PreviewInput>
    implements ComposerActions {
  late String _text = widget.initialText;

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
        targetKey: 'preview',
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
        selectorBar: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          runSpacing: 4,
          children: [
            SessionModeSelector(
              catalog: const ThreadModeCatalogView(),
              mode: ThreadModeId.task,
              enabled: widget.execution == null,
              onSelected: (_) {},
            ),
            ...modelRouteSelectorChildren(
              accounts: _previewAccounts,
              pending: false,
              accountId: 'preview-account',
              modelId: 'preview-model',
              effort: 'high',
              blockedReason: widget.execution == null
                  ? null
                  : context.l10n.statusModelSwitchWhileRunning,
              unavailableReason:
                  context.l10n.statusModelRouteUnavailableFallback,
              onModelSelected: (_, _) {},
              onEffortSelected: (_) {},
            ),
          ],
        ),
      ),
    ],
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
    name: '预览账号',
    billingKind: null,
    models: const [
      AccountModelView(
        modelId: 'preview-model',
        displayName: '预览模型',
        reasoningEfforts: ['low', 'high'],
        typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
      ),
    ],
  ),
];
