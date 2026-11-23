import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../../state/patch_presentation.dart';

/// 将 ACP 工具调用特有的协议附加载荷（类别、路径、终端、Diff 与富内容块）
/// 以纯数据作用域注入 [TimelineToolItemView]，避免 `timeline/` 反向依赖 `acp/`。
class AcpToolDetailsScope extends InheritedWidget {
  const AcpToolDetailsScope({
    this.kind,
    this.rawName,
    this.cardKey,
    this.locations = const [],
    this.terminals = const [],
    this.diffs = const [],
    this.contentBlocksIdentity = const [],
    this.contentBlocksBuilder,
    required super.child,
    super.key,
  });

  final String? kind;
  final String? rawName;
  final Key? cardKey;
  final List<String> locations;
  final List<String> terminals;
  final List<TimelinePatchDocument> diffs;
  final List<Object?> contentBlocksIdentity;
  final List<Widget> Function(BuildContext context)? contentBlocksBuilder;

  static AcpToolDetailsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AcpToolDetailsScope>();

  @override
  bool updateShouldNotify(covariant AcpToolDetailsScope oldWidget) =>
      kind != oldWidget.kind ||
      rawName != oldWidget.rawName ||
      cardKey != oldWidget.cardKey ||
      !listEquals(locations, oldWidget.locations) ||
      !listEquals(terminals, oldWidget.terminals) ||
      !listEquals(diffs, oldWidget.diffs) ||
      !listEquals(contentBlocksIdentity, oldWidget.contentBlocksIdentity) ||
      (contentBlocksBuilder != null) !=
          (oldWidget.contentBlocksBuilder != null);
}
