## 长内容，也能轻松阅读

把说明、路径与代码放在同一张表里，阅读时保持完整上下文。缩窄窗口后，内容应自然换行，文字大小保持一致。

| 内容 | 示例与路径 | 阅读提示 |
| :--- | :--- | :--- |
| 长说明 | Timeline 会把当前会话里的 Markdown 内容持续呈现出来；即使某个单元格包含很长的中文说明，也应该完整显示，并且与相邻行列保持清晰的间距。 | 自然换行，不截断 |
| 行内代码 | `resolveTimelineMarkdownTableCellWithPreservedWhitespaceAndSelectableInlineCodeWithoutChangingOriginalContent` | 等宽字体与轻底色，长标识符也能折行 |
| 文件路径 | `C:/workspaces/anywork/packages/client/src/features/timeline/rendering/markdown/long_content_layout.dart` | 复制后仍是完整路径 |
| 参考链接 | [Markdown 排版与自动换行的详细说明](https://example.com/docs/timeline/markdown/long-content-layout) | 链接文字与正文保持一致的阅读节奏 |

> 引用里的长内容同样需要自适应：`timeline.renderMarkdownWithPreservedWhitespaceAndSelectableInlineCodeWithoutChangingOriginalContent` 应完整呈现。引用线、背景与文字之间保持适当留白，窄窗口下也不挤出阅读列。

### 代码保持原样，阅读自动折行

```dart
Future<void> renderTimeline() async {
  final target = workspace.resolve("C:/workspaces/anywork/packages/client/src/features/timeline/rendering/markdown/long_content_layout.dart");
  await timeline.renderMarkdown(target: target, preserveWhitespace: true, preserveSelection: true, wrapLongTableCells: true);
}
```

行内片段 `source`、`target` 与 `preserveWhitespace` 和中文基线对齐；选择并复制长代码时，字符、缩进和原始换行应逐字保留。
