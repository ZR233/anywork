import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../live_status/live_status_header_spec.dart';
import '../live_status/live_status_state.dart';
import 'timeline_activity_clock.dart';
import 'timeline_activity_row.dart';
import 'timeline_activity_section.dart';

/// 实时区唯一外壳。生产连接层和官方预览传入同一套纯呈现组件。
class ConversationActivityBar extends StatelessWidget {
  const ConversationActivityBar({required this.children, super.key});

  final List<Widget> children;

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
                        for (final child in children)
                          child is Flexible
                              ? child
                              : Flexible(
                                  key: child.key,
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

/// 无正文的当前状态；统一通过 [LiveStatusHeaderSpec] 派生图标、语义色、动画样式与耗时文案。
class ConversationActivityStatus extends StatelessWidget {
  const ConversationActivityStatus({
    required this.view,
    this.storageSeverity,
    this.specOverride,
    super.key,
  });

  final ConversationActivityView view;
  final LiveStorageSeverity? storageSeverity;
  final LiveStatusHeaderSpec? specOverride;

  @override
  Widget build(BuildContext context) {
    final spec =
        specOverride ??
        LiveStatusHeaderSpec.forActivity(
          context,
          view,
          storageSeverity: storageSeverity,
        );
    return Semantics(
      container: true,
      liveRegion: true,
      child: TimelineActivitySection(
        header: TimelineActivityRow(
          label: spec.label,
          icon: spec.icon,
          iconColor: spec.iconColor,
          labelColor: spec.labelColor,
          labelWidget: spec.labelWidget,
          indicatorStyle: spec.indicatorStyle,
          isIssue: spec.isIssue,
          active: spec.active,
          emphasized: spec.emphasized,
          expandable: false,
          header: true,
          tooltip: spec.tooltip,
          meta: spec.meta,
          metaKey: const ValueKey('conversation-activity-trailing-meta'),
        ),
      ),
    );
  }
}

/// 当前文本的唯一呈现入口；正文读取与窗口翻页仍由连接层负责。
class ConversationResponseView extends StatelessWidget {
  const ConversationResponseView({
    required this.child,
    this.startedAt,
    this.finishedAt,
    this.active = true,
    this.now,
    super.key,
  });
  final Widget child;
  final int? startedAt;
  final int? finishedAt;
  final bool active;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) => TimelineActivitySection(
    maxBodyHeight: 196,
    followOutput: active,
    header: TimelineActivityClock.fromUnixSeconds(
      startedAt: startedAt,
      finishedAt: finishedAt,
      running: active,
      now: now,
      builder: (context, seconds) {
        final spec = LiveStatusHeaderSpec.forActivity(
          context,
          const ConversationActivityView(
            identity: 'response',
            kind: ConversationActivityKind.responding,
          ),
          seconds: seconds,
        );
        return TimelineActivityRow(
          label: spec.label,
          icon: spec.icon,
          iconColor: spec.iconColor,
          labelColor: spec.labelColor,
          indicatorStyle: spec.indicatorStyle,
          active: active,
          emphasized: active,
          header: true,
          expandable: false,
          meta: spec.meta,
          tooltip: spec.tooltip,
        );
      },
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
