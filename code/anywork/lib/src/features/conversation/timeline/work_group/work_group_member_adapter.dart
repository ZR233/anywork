import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/studio_l10n.dart';
import '../state/chat_item_presentation.dart';
import '../state/timeline_feed_projection.dart';

/// 实时与历史工作组共享的成员分类。
enum WorkGroupMemberKind {
  reasoning,
  toolCall,
  agent,
  fileChange,
  skill,
  fallback,
}

WorkGroupMemberKind workGroupMemberKindOf(WorkGroupMember member) =>
    switch (member) {
      WorkGroupReasoning() => WorkGroupMemberKind.reasoning,
      WorkGroupToolCall() => WorkGroupMemberKind.toolCall,
      WorkGroupAgent() => WorkGroupMemberKind.agent,
      WorkGroupFileChange() => WorkGroupMemberKind.fileChange,
      WorkGroupSkill() => WorkGroupMemberKind.skill,
      WorkGroupFallback() => WorkGroupMemberKind.fallback,
    };

/// 供 [WorkGroupMemberMatcher] 评估匹配规则的轻量上下文。
@immutable
class WorkGroupMemberMatchContext {
  const WorkGroupMemberMatchContext({
    required this.member,
    required this.kind,
    this.isLive = false,
    this.toolName,
    this.presentationContract,
    this.presentsFiles = false,
  });

  factory WorkGroupMemberMatchContext.fromMember(
    WorkGroupMember member, {
    bool isLive = false,
  }) {
    final kind = workGroupMemberKindOf(member);
    if (member is WorkGroupToolCall) {
      final raw = member.payloadJson.trim();
      final presentsFiles =
          raw.isNotEmpty &&
          raw != '{}' &&
          timelineFeedMember(member).presentsFiles;
      return WorkGroupMemberMatchContext(
        member: member,
        kind: kind,
        isLive: isLive,
        toolName: member.toolName,
        presentationContract: member.presentationContract,
        presentsFiles: presentsFiles,
      );
    }
    return WorkGroupMemberMatchContext(
      member: member,
      kind: kind,
      isLive: isLive,
    );
  }

  final WorkGroupMember member;
  final WorkGroupMemberKind kind;
  final bool isLive;
  final String? toolName;
  final String? presentationContract;
  final bool presentsFiles;
}

/// 声明式工作组成员匹配规则（沿用 [TimelineToolMatcher] 模式）。
@immutable
abstract class WorkGroupMemberMatcher {
  const WorkGroupMemberMatcher();

  /// 精确匹配一个 [WorkGroupMemberKind]。
  const factory WorkGroupMemberMatcher.kind(WorkGroupMemberKind kind) =
      _ExactKindMatcher;

  /// 匹配任意子规则。
  const factory WorkGroupMemberMatcher.anyOf(
    List<WorkGroupMemberMatcher> matchers,
  ) = _AnyOfMemberMatcher;

  /// 使用自定义谓词匹配（可声明用于重复校验与索引的 [exactKinds]）。
  const factory WorkGroupMemberMatcher.custom(
    bool Function(WorkGroupMemberMatchContext context) predicate, {
    Set<WorkGroupMemberKind> exactKinds,
  }) = _CustomMemberMatcher;

  Set<WorkGroupMemberKind> get exactKinds => const <WorkGroupMemberKind>{};

  bool matches(WorkGroupMemberMatchContext context);
}

final class _ExactKindMatcher extends WorkGroupMemberMatcher {
  const _ExactKindMatcher(this.kind);

  final WorkGroupMemberKind kind;

  @override
  Set<WorkGroupMemberKind> get exactKinds => {kind};

  @override
  bool matches(WorkGroupMemberMatchContext context) => context.kind == kind;
}

final class _AnyOfMemberMatcher extends WorkGroupMemberMatcher {
  const _AnyOfMemberMatcher(this.matchers);

  final List<WorkGroupMemberMatcher> matchers;

  @override
  Set<WorkGroupMemberKind> get exactKinds {
    final kinds = <WorkGroupMemberKind>{};
    for (final matcher in matchers) {
      kinds.addAll(matcher.exactKinds);
    }
    return kinds;
  }

  @override
  bool matches(WorkGroupMemberMatchContext context) {
    for (final matcher in matchers) {
      if (matcher.matches(context)) return true;
    }
    return false;
  }
}

final class _CustomMemberMatcher extends WorkGroupMemberMatcher {
  const _CustomMemberMatcher(
    this.predicate, {
    this.exactKinds = const <WorkGroupMemberKind>{},
  });

  final bool Function(WorkGroupMemberMatchContext context) predicate;

  @override
  final Set<WorkGroupMemberKind> exactKinds;

  @override
  bool matches(WorkGroupMemberMatchContext context) => predicate(context);
}

/// 渲染单个工作组成员条目的上下文。
class WorkGroupMemberContext {
  const WorkGroupMemberContext({
    required this.buildContext,
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
  });

  final BuildContext buildContext;
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

  AppLocalizations get l10n => buildContext.l10n;
}

/// 单个工作组成员类型的独立渲染适配器。
abstract class WorkGroupMemberAdapter {
  const WorkGroupMemberAdapter();

  String get id;

  WorkGroupMemberMatcher get matcher;

  Widget build(WorkGroupMemberContext context);
}
