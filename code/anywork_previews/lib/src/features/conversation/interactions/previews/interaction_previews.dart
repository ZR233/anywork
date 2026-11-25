import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/interactions/state/interaction_payload.dart';
import 'package:anywork/src/features/conversation/interactions/views/user_input_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

@Preview(name: '问题多选与禁用草稿', group: '输入交互', size: Size(720, 560))
@Preview(
  name: '问题多选 · 窄窗大字',
  group: '输入交互',
  size: Size(360, 720),
  textScaleFactor: 1.6,
)
Widget questionChoicesPreview() => _host(const _QuestionPreview());

@Preview(name: '回退问题 · 禁用后保留草稿', group: '输入交互', size: Size(520, 460))
Widget fallbackQuestionPreview() =>
    _host(const _QuestionPreview(fallback: true));

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) =>
      ListTileTheme(data: Theme.of(context).listTileTheme, child: child!),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  ),
);

class _QuestionPreview extends StatefulWidget {
  const _QuestionPreview({this.fallback = false});

  final bool fallback;

  @override
  State<_QuestionPreview> createState() => _QuestionPreviewState();
}

class _QuestionPreviewState extends State<_QuestionPreview> {
  bool _enabled = true;
  String? _answer;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchListTile(
        title: const Text('允许回答'),
        subtitle: const Text('关闭后保留当前草稿，再次开启可继续回答'),
        value: _enabled,
        onChanged: (value) => setState(() => _enabled = value),
      ),
      const SizedBox(height: 12),
      UserInputView(
        enabled: _enabled,
        payload: InteractionPayloadSnapshot(
          rawBody: '本轮需要关注哪些行为？',
          summary: '',
          toolName: '',
          formattedArguments: '',
          workingDirectory: '',
          questions: widget.fallback
              ? const []
              : const [
                  UserQuestionView(
                    id: 'verification',
                    header: '验证范围',
                    question: '可同时选择多个选项，也可补充说明。',
                    isOther: true,
                    isSecret: false,
                    options: [
                      UserQuestionOptionView(
                        label: '输入与草稿',
                        description: '切换提交资格后继续编辑',
                      ),
                      UserQuestionOptionView(
                        label: '键盘与无障碍',
                        description: 'Tab 聚焦、Space 勾选及多选状态',
                      ),
                    ],
                  ),
                ],
        ),
        onSubmit: (resolution) => setState(() {
          _answer = resolution.answers
              .map((answer) => answer.answers.join('、'))
              .join('\n');
        }),
      ),
      if (_answer case final answer?) ...[
        const SizedBox(height: 12),
        Text('本次回答：$answer'),
      ],
    ],
  );
}
