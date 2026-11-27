import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/timeline_feed_projection.dart';
import '../work_group_member_adapter.dart';
import 'tool_member_item.dart';

/// 独立媒体附件型工具调用（如 `show_files`），在具备附件读取能力时直接渲染附件视图。
class MediaToolMemberItem extends WorkGroupMemberAdapter {
  const MediaToolMemberItem();

  @override
  String get id => 'work_group.media_tool';

  @override
  WorkGroupMemberMatcher get matcher => WorkGroupMemberMatcher.custom(
    (context) => context.member is WorkGroupToolCall && context.presentsFiles,
  );

  @override
  Widget build(WorkGroupMemberContext context) {
    final builder = context.attachmentBuilder;
    if (builder != null) {
      final item = timelineFeedMember(context.member);
      return builder(item);
    }
    return const ToolMemberItem().build(context);
  }
}
