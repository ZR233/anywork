import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../app/theme/material3_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../views/plan_detail_view.dart';
import '../widgets/timeline_markdown.dart';

const _document = '''
# 时间线与实时状态栏

将过程和确定回执收敛为紧凑的阅读轨，正文继续按文档阅读。

## 实施范围

- 直接复用生产组件，不创建另一套预览界面。
- 保留逐条可靠完成、按需正文窗口与原始内容。
- 在窄窗口与文字缩放下保持可阅读和可操作。

```dart
// 预览只使用合成展示值，不装配业务运行时。
const status = PlanDetailStatus.approved;
```
''';

Widget _host(
  PlanDetailStatus status, {
  double textScale = 1,
  bool fullWidth = false,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  theme: pureStudioTheme(locale: const Locale('zh')),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: ListTileTheme(data: Theme.of(context).listTileTheme, child: child!),
  ),
  home: Scaffold(
    body: PlanDetailView(
      identity: 'preview:plan-detail',
      title: '时间线与实时状态栏',
      status: status,
      fullWidth: fullWidth,
      // Workspace layout owns these actions in production. This preview
      // presents fixed values rather than simulating a second workspace.
      onClose: () {},
      onToggleReadingMode: () {},
      body: TimelineMarkdown(
        id: 'preview:plan-document',
        text: _document,
        onLink: (_) {},
        isSafeLink: (_) => false,
        imageBuilder: (_, _) => const Text('预览不加载远程图片'),
      ),
    ),
  ),
);

@Preview(name: '计划详情 / 等待确认', group: 'Timeline · 计划详情', size: Size(760, 560))
Widget planDetailAwaitingPreview() =>
    _host(PlanDetailStatus.awaitingConfirmation);

@Preview(name: '计划详情 / 已批准', group: 'Timeline · 计划详情', size: Size(760, 560))
Widget planDetailApprovedPreview() => _host(PlanDetailStatus.approved);

@Preview(name: '计划详情 / 全宽固定场景', group: 'Timeline · 计划详情', size: Size(1040, 560))
Widget planDetailFullWidthPreview() =>
    _host(PlanDetailStatus.approved, fullWidth: true);

@Preview(name: '计划详情 / 修订与窄窗缩放', group: 'Timeline · 计划详情', size: Size(360, 480))
Widget planDetailRevisionNarrowPreview() =>
    _host(PlanDetailStatus.revisionRequested, textScale: 1.3);
