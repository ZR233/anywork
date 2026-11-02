import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../app/theme/material3_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/conversation_current_views.dart';

Widget _currentPreviewHost(
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
  double width = 720,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  theme: pureStudioTheme(locale: const Locale('zh')),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, appChild) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: ListTileTheme(
      data: Theme.of(context).listTileTheme,
      child: appChild!,
    ),
  ),
  home: Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

const _longCurrentText = '''
## 当前计划文档

保持 Main current 为唯一 owner；纯组件只消费 connector 已接纳的有界窗口。

1. 原始引用与修订身份不变。
2. 页面读取仅由显式展开触发。
3. 失效、失败与下一段动作沿原 owner 回调返回。

这是一段用于检查长中文、`行内代码` 与段落间距的合成内容。它证明生产组件在阅读列内的呈现和局部交互，不证明 FRB、SQLite 或真实模型行为。
''';

@Preview(
  name: 'Current / 有界正文与分页动作',
  group: 'Timeline · Current 纯组件',
  size: Size(820, 460),
)
Widget conversationCurrentWindowPreview() => _currentPreviewHost(
  ConversationCurrentDetailsView(
    invalidationNotice: '当前文档已更新，原版本已失效',
    windows: [
      ConversationCurrentWindowView(
        id: 'preview-plan',
        label: '当前计划文档',
        text: _longCurrentText,
        offset: 32768,
        end: 65536,
        availableThrough: 98304,
        onFirst: () {},
        onNext: () {},
      ),
    ],
  ),
);

@Preview(
  name: 'Current / 集合、条目与读取诊断',
  group: 'Timeline · Current 纯组件',
  size: Size(820, 540),
)
Widget conversationCurrentCollectionsPreview() => _currentPreviewHost(
  ConversationCurrentDetailsView(
    cleanupError: '内容观察释放尚未确认',
    onRetryCleanup: () {},
    completedItems: ConversationCurrentEntryView(
      title: '已完成成员',
      onExpansionChanged: (_) {},
      child: const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Text('explorer · 已完成边界梳理\nreviewer · 正在复核视觉层级'),
      ),
    ),
    collections: [
      ConversationCurrentCollectionView(
        title: '当前工具',
        onExpansionChanged: (_) {},
        entries: [
          ConversationCurrentEntryView(
            title: 'exec · cargo flutter analyze',
            child: const SelectableText(
              '{\n'
              '  "command": "cargo flutter analyze",\n'
              '  "status": "running"\n'
              '}',
            ),
          ),
          ConversationCurrentEntryView(
            title: 'wait · 等待两个成员返回结果',
            child: const SelectableText(
              'task:explorer · succeeded\n'
              'task:reviewer · running',
            ),
          ),
        ],
        onNextPage: () {},
      ),
      ConversationCurrentCollectionView(
        title: '当前交互',
        stale: true,
        onExpansionChanged: (_) {},
        onReload: () {},
      ),
    ],
  ),
);

@Preview(
  name: 'Current / 窄窗与 160% 字体缩放',
  group: 'Timeline · Current 纯组件',
  size: Size(390, 560),
)
Widget conversationCurrentNarrowScaledPreview() => _currentPreviewHost(
  const ConversationActivityBar(
    view: ConversationActivityView(
      identity: 'preview:current-narrow',
      kind: ConversationActivityKind.responding,
    ),
    // Use the same production scroll owner as current content. This is not a
    // preview-only overflow wrapper or an externally controlled disclosure.
    content: ConversationCurrentDetailsView(
      windows: [
        ConversationCurrentWindowView(
          id: 'preview-narrow',
          label: '当前回复正文',
          text: _longCurrentText,
          offset: 0,
          end: 32768,
          availableThrough: 65536,
        ),
      ],
    ),
    maxResponseHeight: 360,
  ),
  textScaler: const TextScaler.linear(1.6),
  width: 340,
);
