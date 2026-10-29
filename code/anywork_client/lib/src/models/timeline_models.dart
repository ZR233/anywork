part 'timeline_todo.dart';

/// 把一行 reasoning 文本压成无标记的纯文本摘要；空行与注释占位返回 null。
///
/// 固定活动条与 Timeline 推理摘要共用这一处映射，避免两处各自实现一套去除
/// markdown 标记的规则而出现不一致。
String? plainReasoningSummary(String value) {
  var summary = value.trim();
  if (summary.isEmpty || summary == '<!-- -->') {
    return null;
  }
  if ((summary.startsWith('**') && summary.endsWith('**')) ||
      (summary.startsWith('__') && summary.endsWith('__'))) {
    summary = summary.substring(2, summary.length - 2);
  }
  summary = summary
      .replaceFirst(RegExp(r'^#{1,6}\s+'), '')
      .replaceFirst(RegExp(r'^>\s*'), '')
      .replaceFirst(RegExp(r'^(?:[-+*]|\d+[.)])\s+'), '')
      .replaceAll(RegExp(r'[*_`]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return summary.isEmpty ? null : summary;
}
