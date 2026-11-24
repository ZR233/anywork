import 'package:material_ui/material_ui.dart';

import '../../timeline/tools/items/acp/acp_tool_details_scope.dart';
import '../../timeline/tools/tool_item_view.dart';
import '../state/acp_view_state.dart';
import 'acp_content_block_view.dart';

/// ACP 工具调用薄包装层：注入 ACP 协议附加载荷作用域并委托给共享 [TimelineToolItemView]。
class AcpToolCard extends StatelessWidget {
  const AcpToolCard({
    super.key,
    required this.item,
    this.initiallyExpanded = false,
    this.isSafeLink,
    this.onOpenLink,
    this.imageBuilder,
    this.onOpenMarkdownResource,
  });

  final AcpTimelineToolCallItem item;
  final bool initiallyExpanded;
  final bool Function(String url)? isSafeLink;
  final ValueChanged<String>? onOpenLink;
  final AcpImageWidgetBuilder? imageBuilder;
  final void Function(String uri, String text)? onOpenMarkdownResource;

  @override
  Widget build(BuildContext context) {
    final safeLink = isSafeLink ?? _fallbackSafeLink;
    return AcpToolDetailsScope(
      kind: item.kindLabel,
      rawName: item.rawName,
      cardKey: ValueKey(AcpViewKeyValues.toolCard(item.toolCallId)),
      locations: item.locations,
      terminals: item.terminals,
      diffs: item.diffs,
      contentBlocksIdentity: item.contentBlocks,
      contentBlocksBuilder: item.contentBlocks.isEmpty
          ? null
          : (_) => [
              for (var i = 0; i < item.contentBlocks.length; i++)
                AcpContentBlockView(
                  id: '${item.id}:content:$i',
                  block: item.contentBlocks[i],
                  isSafeLink: safeLink,
                  onOpenLink: onOpenLink,
                  imageBuilder: imageBuilder,
                  onOpenMarkdownResource: onOpenMarkdownResource,
                ),
            ],
      child: TimelineToolItemView(
        item: item.tool,
        initiallyExpanded: initiallyExpanded || item.diffs.isNotEmpty,
      ),
    );
  }
}

bool _fallbackSafeLink(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}
