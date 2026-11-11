import 'package:anywork_client/studio_client.dart';
import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/material3_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/dropped_file.dart';
import '../../../../platform/external_url_launcher.dart';
import '../state/composer_input_state.dart';
import '../view_models/composer_actions.dart';
import '../views/prompt_composer_view.dart';
import '../views/composer_submission_body.dart';

@Preview(name: 'Composer / 可编辑纯输入', group: 'Composer', size: Size(760, 340))
@Preview(name: 'Composer / 窄窗', group: 'Composer', size: Size(360, 460))
Widget composerInputPreview() => _composerPreviewHost(const _PreviewInput());

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
  const _PreviewInput({this.showSubmission = false});
  final bool showSubmission;
  @override
  State<_PreviewInput> createState() => _PreviewInputState();
}

// Preview-only editing data, not another production draft owner.
class _PreviewInputState extends State<_PreviewInput>
    implements ComposerActions {
  String _text = '输入下一条消息';

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
          inputCapabilities: const [
            ModelInputCapabilityView(
              modality: ModelModalityView.image,
              sources: [ModelInputSourceView.local],
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
