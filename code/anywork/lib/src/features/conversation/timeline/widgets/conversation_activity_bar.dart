import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../live_status/live_status_state.dart';
import 'timeline_activity_clock.dart';
import 'timeline_activity_row.dart';
import 'timeline_activity_section.dart';

class ConversationRealtimeNotices extends StatelessWidget {
  const ConversationRealtimeNotices({required this.notices, super.key});
  final List<LiveStatusNotice> notices;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final notice in notices)
        switch (notice) {
          ExecutionLiveNotice(:final view) => ConversationActivityStatus(
            view: view,
          ),
          UnrestoredLiveNotice() => const Text('上次执行未收束，尚未恢复'),
        },
    ],
  );
}

/// 实时区唯一外壳。生产连接层和官方预览传入同一套纯呈现组件。
class ConversationActivityBar extends StatelessWidget {
  const ConversationActivityBar({
    required this.children,
    this.leading = const [],
    super.key,
  });
  final List<Widget> children;
  final List<Widget> leading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 7, 12, 1),
    child: Align(
      alignment: Alignment.center,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: StudioLayout.conversationWidth,
        ),
        child: Semantics(
          container: true,
          identifier: 'conversation-activity',
          child: Material(
            key: const ValueKey('conversation-activity'),
            color: context.colors.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: context.colors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: LiveStatusMotionHost(
                child: LayoutBuilder(
                  builder: (context, constraints) => ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.hasBoundedHeight
                          ? constraints.maxHeight
                          : MediaQuery.sizeOf(context).height * .45,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (leading.isNotEmpty)
                          Flexible(
                            key: const ObjectKey(ConversationActivityBar),
                            fit: FlexFit.loose,
                            child: SingleChildScrollView(
                              primary: false,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: leading,
                              ),
                            ),
                          ),
                        for (final child in children)
                          Flexible(
                            key: child.key,
                            flex: 3,
                            fit: FlexFit.loose,
                            child: child,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 无正文的当前状态；不创建空工作组、详情入口或本地业务状态。
class ConversationActivityStatus extends StatelessWidget {
  const ConversationActivityStatus({required this.view, super.key});
  final ConversationActivityView view;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: TimelineActivitySection(
      header: TimelineActivityRow(
        label: context.conversationActivityLabel(view),
        icon: view.kind.icon,
        indicatorStyle: resolveLiveHeaderIndicatorStyle(view),
        isIssue: view.kind.isIssue,
        active:
            view.waits ||
            view.kind == ConversationActivityKind.responding ||
            view.kind == ConversationActivityKind.planning,
        emphasized:
            view.kind == ConversationActivityKind.responding ||
            view.kind == ConversationActivityKind.runningTool ||
            view.kind == ConversationActivityKind.planning,
        expandable: false,
        header: true,
        summary: view.kind == ConversationActivityKind.compacting
            ? null
            : view.errorMessage ?? view.summary,
        meta:
            view.kind == ConversationActivityKind.thinking &&
                view.thinkingSeconds != null
            ? activityDurationLabel(context, view.thinkingSeconds!)
            : null,
        metaKey: const ValueKey('conversation-activity-trailing-meta'),
      ),
    ),
  );
}

/// 当前文本的唯一呈现入口；正文读取与窗口翻页仍由连接层负责。
class ConversationResponseView extends StatelessWidget {
  const ConversationResponseView({
    required this.child,
    this.startedAt,
    this.finishedAt,
    this.active = true,
    super.key,
  });
  final Widget child;
  final int? startedAt;
  final int? finishedAt;
  final bool active;

  @override
  Widget build(BuildContext context) => TimelineActivitySection(
    maxBodyHeight: 196,
    followOutput: active,
    header: TimelineActivityClock(
      startedAt: startedAt,
      finishedAt: finishedAt,
      running: active,
      builder: (context, seconds) => TimelineActivityRow(
        label: context.l10n.conversationActivityResponding,
        icon: Icons.chat_bubble_outline,
        indicatorStyle: TimelineActivityIndicatorStyle.writing,
        active: active,
        emphasized: active,
        header: true,
        expandable: false,
        meta: seconds == null ? null : activityDurationLabel(context, seconds),
      ),
    ),
    body: Padding(
      padding: const EdgeInsetsDirectional.only(
        start: TimelineActivityRow.headerContentIndent,
        top: 6,
        bottom: 2,
      ),
      child: child,
    ),
  );
}
