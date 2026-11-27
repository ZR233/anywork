import 'dart:collection';

import 'package:anywork_client/models.dart';

import 'items/agent_member_item.dart';
import 'items/fallback_member_item.dart';
import 'items/file_change_member_item.dart';
import 'items/media_tool_member_item.dart';
import 'items/reasoning_member_item.dart';
import 'items/skill_member_item.dart';
import 'items/tool_member_item.dart';
import 'work_group_member_adapter.dart';

/// 集中管理工作组成员渲染适配器的注册与分派表。
///
/// 与 `TimelineToolItemRegistry` 保持相同契约：
/// - exact-kind O(1) 索引与构造期重复校验；
/// - 有序特化规则（如独立媒体附件）优先于泛化条目；
/// - 未匹配时回退 [fallback]。
class WorkGroupMemberRegistry {
  WorkGroupMemberRegistry({
    required List<WorkGroupMemberAdapter> adapters,
    this.fallback = const FallbackWorkGroupMemberItem(),
  }) : adapters = UnmodifiableListView([...adapters, fallback]),
       _orderedAdapters = UnmodifiableListView(adapters) {
    final kindIndex = <WorkGroupMemberKind, WorkGroupMemberAdapter>{};
    void registerKinds(WorkGroupMemberAdapter adapter) {
      for (final kind in adapter.matcher.exactKinds) {
        if (kindIndex.containsKey(kind)) {
          throw ArgumentError(
            'Duplicate exact WorkGroupMemberKind "$kind" between '
            '${kindIndex[kind]!.runtimeType} and ${adapter.runtimeType}.',
          );
        }
        kindIndex[kind] = adapter;
      }
    }

    for (final adapter in adapters) {
      registerKinds(adapter);
    }
    registerKinds(fallback);
    _byExactKind = UnmodifiableMapView(kindIndex);
  }

  /// 包含 [fallback] 在内的全部已注册适配器。
  final List<WorkGroupMemberAdapter> adapters;

  /// 按注册顺序评估的专有适配器列表。
  final List<WorkGroupMemberAdapter> _orderedAdapters;

  /// 无匹配时的兜底适配器。
  final WorkGroupMemberAdapter fallback;

  late final Map<WorkGroupMemberKind, WorkGroupMemberAdapter> _byExactKind;

  Map<WorkGroupMemberKind, WorkGroupMemberAdapter> get exactKindIndex =>
      _byExactKind;

  Set<WorkGroupMemberKind> get exactKinds => _byExactKind.keys.toSet();

  WorkGroupMemberAdapter? lookupExact(WorkGroupMemberKind kind) =>
      _byExactKind[kind];

  WorkGroupMemberAdapter resolve(WorkGroupMemberMatchContext context) {
    final exact = lookupExact(context.kind);
    for (final adapter in _orderedAdapters) {
      if (identical(adapter, exact)) {
        if (adapter.matcher.matches(context)) return adapter;
        continue;
      }
      if (adapter.matcher.exactKinds.isEmpty &&
          adapter.matcher.matches(context)) {
        return adapter;
      }
    }
    if (exact != null && exact.matcher.matches(context)) {
      return exact;
    }
    return fallback;
  }

  WorkGroupMemberAdapter resolveForMember(
    WorkGroupMember member, {
    bool isLive = false,
  }) => resolve(WorkGroupMemberMatchContext.fromMember(member, isLive: isLive));
}

/// 应用默认的全局工作组成员注册表。
final WorkGroupMemberRegistry workGroupMemberRegistry = WorkGroupMemberRegistry(
  adapters: const [
    ReasoningMemberItem(),
    MediaToolMemberItem(),
    ToolMemberItem(),
    AgentMemberItem(),
    FileChangeMemberItem(),
    SkillMemberItem(),
  ],
);
