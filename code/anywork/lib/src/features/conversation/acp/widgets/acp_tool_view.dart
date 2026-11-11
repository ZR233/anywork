import 'package:anywork_client/acp_sessions.dart';
import 'package:material_ui/material_ui.dart';

import '../../timeline/widgets/timeline_patch_diff_view.dart';
import '../../timeline/widgets/timeline_tool_blocks.dart';
import '../connectors/acp_content_block.dart';
import '../view_models/acp_content_view_model.dart';

class AcpToolView extends StatelessWidget {
  const AcpToolView({super.key, required this.id, required this.fields});

  final AcpToolCallId id;
  final AcpToolCallUpdateFieldsView fields;

  @override
  Widget build(BuildContext context) => TimelineToolDetails(
    key: ValueKey(id),
    item: acpToolPresentation(id, fields),
    declaredContents: [
      for (var index = 0; index < (fields.content?.length ?? 0); index++)
        switch (fields.content![index]) {
          AcpToolContentView(:final content) => AcpContentBlock(
            id: '${id.value}-$index',
            content: content,
          ),
          final AcpToolDiffView diff => TimelinePatchDiffView(
            document: acpDiffPresentation(diff),
          ),
          AcpToolTerminalView(:final terminalId) => SelectableText(
            '终端 ${terminalId.value} · 终端输出由服务端管理',
          ),
        },
      if (fields.status == null) const Text('服务端尚未提供工具状态'),
      for (final location in fields.locations ?? <AcpToolCallLocationView>[])
        SelectableText(
          '${location.path}${location.line == null ? '' : ':${location.line}'}',
        ),
    ],
  );
}
