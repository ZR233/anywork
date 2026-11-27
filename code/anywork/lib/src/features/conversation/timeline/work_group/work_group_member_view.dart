import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../state/chat_item_presentation.dart';
import 'work_group_member_adapter.dart';
import 'work_group_member_registry.dart';

/// 实时工作组与历史工作组唯一的统一成员条目视图。
class WorkGroupMemberView extends StatelessWidget {
  const WorkGroupMemberView({
    required this.member,
    this.isLive = false,
    this.now,
    this.bodyBuilder,
    this.attachmentBuilder,
    this.isDisplayActive,
    this.monotonicMicros,
    this.onContentLayout,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.registry,
    super.key,
  });

  final WorkGroupMember member;
  final bool isLive;
  final DateTime Function()? now;
  final Widget Function(String id, String text)? bodyBuilder;
  final Widget Function(ChatItemPresentation item)? attachmentBuilder;
  final bool Function()? isDisplayActive;
  final int Function()? monotonicMicros;
  final void Function(String itemId, int layoutCompletedMicros)?
  onContentLayout;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final WorkGroupMemberRegistry? registry;

  @override
  Widget build(BuildContext context) {
    final activeRegistry = registry ?? workGroupMemberRegistry;
    final adapter = activeRegistry.resolveForMember(member, isLive: isLive);
    return adapter.build(
      WorkGroupMemberContext(
        buildContext: context,
        member: member,
        isLive: isLive,
        now: now,
        bodyBuilder: bodyBuilder,
        attachmentBuilder: attachmentBuilder,
        isDisplayActive: isDisplayActive,
        monotonicMicros: monotonicMicros,
        onContentLayout: onContentLayout,
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
      ),
    );
  }
}
