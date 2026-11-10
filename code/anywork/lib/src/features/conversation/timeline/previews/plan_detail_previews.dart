import 'package:material_ui/material_ui.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../app/theme/material3_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../interactions/views/plan_confirmation_view.dart';
import '../views/plan_detail_view.dart';
import '../views/plan_receipt_view.dart';
import '../widgets/timeline_markdown.dart';

// The frozen sample is shared with design/prototypes/plan-workspace/plan.js.
const _document = '''
# 优化项目搜索体验

让项目与会话更容易查找，并保留当前阅读位置。

## 实施范围

- 搜索时同时匹配项目名与会话标题。
- 保留最近使用的项目与当前选中会话。
- 覆盖空结果、长名称和窄窗口。

## 实施步骤

1. 整理现有搜索入口与交互。
2. 统一搜索结果和选中反馈。
3. 验证键盘操作与窗口缩放。

## 验证方式

检查搜索、切换和清空后的阅读位置，确保结果清楚、操作可达。
''';
const _feedback = '请先保留当前选中的会话，再补充空结果提示。';
const _error = '提交失败，请重试。';

Widget _markdown(String id) => TimelineMarkdown(
  id: 'preview:plan:$id',
  text: _document,
  onLink: (_) {},
  isSafeLink: (_) => false,
  imageBuilder: (_, _) => const SizedBox.shrink(),
);

Widget _host(
  String id, {
  PlanDetailStatus status = PlanDetailStatus.awaitingConfirmation,
  bool confirm = false,
  bool empty = false,
  bool feedback = false,
  bool submitting = false,
  bool error = false,
  bool fullWidth = false,
  bool history = false,
  double textScale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  theme: pureStudioTheme(locale: const Locale('zh')),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: ListTileTheme(data: Theme.of(context).listTileTheme, child: child!),
  ),
  home: Scaffold(
    key: ValueKey('plan-preview:$id'),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: history
          ? const _History()
          : LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  Expanded(
                    child: PlanDetailView(
                      identity: 'preview:$id',
                      title: context.l10n.interactionPlanDetailsTitle,
                      status: status,
                      fullWidth: fullWidth,
                      onClose: () {},
                      onToggleReadingMode: () {},
                      body: empty ? null : _markdown(id),
                    ),
                  ),
                  if (confirm) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * .58,
                      ),
                      child: SingleChildScrollView(
                        primary: false,
                        child: _Feedback(
                          initialText: feedback ? _feedback : '',
                          submitting: submitting,
                          error: error ? _error : null,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    ),
  ),
);

/// Local editing only; preview callbacks never claim a business decision.
class _Feedback extends StatefulWidget {
  const _Feedback({
    required this.initialText,
    required this.submitting,
    required this.error,
  });
  final String initialText;
  final bool submitting;
  final String? error;

  @override
  State<_Feedback> createState() => _FeedbackState();
}

class _FeedbackState extends State<_Feedback> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PlanConfirmationView(
    controller: _controller,
    available: true,
    enabled: true,
    submitting: widget.submitting,
    error: widget.error,
    onFeedbackChanged: (_) => setState(() {}),
    onSubmitRevision: () {},
    onApprove: () {},
  );
}

class _History extends StatelessWidget {
  const _History();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final receipts = [
      (l10n.planReceiptApproved, Icons.check, '你的回复', '已批准此计划并开始执行'),
      (
        l10n.planReceiptRevisionRequested,
        Icons.edit_outlined,
        '你的修改意见',
        _feedback,
      ),
      (l10n.planReceiptCancelled, Icons.close, '', ''),
      (l10n.planReceiptAnswered, Icons.description_outlined, '', ''),
    ];
    return SingleChildScrollView(
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Column(
          children: [
            for (var index = 0; index < receipts.length; index++)
              PlanReceiptView(
                label: receipts[index].$1,
                icon: receipts[index].$2,
                documentVersion: index + 1,
                initiallyExpanded: index == 0,
                children: [
                  SelectionArea(child: _markdown('history:$index')),
                  if (receipts[index].$4.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SelectionArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            receipts[index].$3,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(receipts[index].$4),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

@Preview(name: 'Plan / drafting', group: 'Plan workspace', size: Size(760, 720))
Widget planDraftingPreview() =>
    _host('drafting', status: PlanDetailStatus.drafting, empty: true);

@Preview(name: 'Plan / awaiting', group: 'Plan workspace', size: Size(760, 720))
Widget planAwaitingPreview() => _host('awaiting', confirm: true);

@Preview(name: 'Plan / feedback', group: 'Plan workspace', size: Size(760, 720))
Widget planFeedbackPreview() =>
    _host('feedback', confirm: true, feedback: true);

@Preview(
  name: 'Plan / submitting',
  group: 'Plan workspace',
  size: Size(760, 720),
)
Widget planSubmittingPreview() =>
    _host('submitting', confirm: true, feedback: true, submitting: true);

@Preview(name: 'Plan / error', group: 'Plan workspace', size: Size(760, 720))
Widget planErrorPreview() =>
    _host('error', confirm: true, feedback: true, error: true);

@Preview(name: 'Plan / revision', group: 'Plan workspace', size: Size(760, 720))
Widget planRevisionPreview() =>
    _host('revision', status: PlanDetailStatus.revisionRequested);

@Preview(name: 'Plan / approved', group: 'Plan workspace', size: Size(760, 720))
Widget planApprovedPreview() =>
    _host('approved', status: PlanDetailStatus.approved);

@Preview(name: 'Plan / full', group: 'Plan workspace', size: Size(1040, 720))
Widget planFullPreview() =>
    _host('full', status: PlanDetailStatus.approved, fullWidth: true);

@Preview(name: 'Plan / narrow', group: 'Plan workspace', size: Size(360, 760))
Widget planNarrowPreview() => _host('narrow', confirm: true);

@Preview(name: 'Plan / large', group: 'Plan workspace', size: Size(360, 900))
Widget planLargePreview() => _host('large', confirm: true, textScale: 1.5);

@Preview(name: 'Plan / short', group: 'Plan workspace', size: Size(640, 480))
Widget planShortPreview() => _host('short', confirm: true);

@Preview(name: 'Plan / history', group: 'Plan workspace', size: Size(760, 720))
Widget planHistoryPreview() => _host('history', history: true);
