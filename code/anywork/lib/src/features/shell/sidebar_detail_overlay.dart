part of 'studio_shell.dart';

/// 详情卡期望宽度；超过可用窗口时按真实尺寸收敛，窄抽屉中自动收窄。
const double _sidebarDetailCardWidth = 300.0;

/// 侧栏行的按需悬浮详情宿主。
///
/// 只读提示直接使用 Material [Tooltip.richMessage]：显隐、窗口避让和
/// 安全区收敛都是框架行为。浮层忽略指针、不抢占输入焦点，因此不会
/// 挡住行选择或更多菜单。内容尺寸受当前窗口约束，不另造定位或互斥。
class _SidebarHoverDetail extends StatelessWidget {
  const _SidebarHoverDetail({required this.child, required this.detailBuilder});

  final Widget child;
  final WidgetBuilder detailBuilder;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxWidth = (size.width - 48).clamp(0.0, _sidebarDetailCardWidth);
    return Tooltip(
      richMessage: WidgetSpan(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: size.height * 0.6,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
              child: detailBuilder(context),
            ),
          ),
        ),
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
      ),
      ignorePointer: true,
      child: child,
    );
  }
}

/// 详情卡中的一行：前置标识（图标或状态点）+ 值。
class _SidebarDetailRow extends StatelessWidget {
  const _SidebarDetailRow({
    required this.leading,
    required this.value,
    this.monospace = false,
  });

  final Widget leading;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(dimension: 18, child: Center(child: leading)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              value,
              style: context.text.bodySmall?.copyWith(
                height: 1.3,
                fontFamily: monospace ? studioCodeFontFamily : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 相对更新时间：一分钟内、分钟、小时、天内使用本地化相对文案，
/// 更早的更新回退为既有列表的绝对时间写法（月/日 时:分），不引入新的
/// 日期格式化依赖。
String _relativeUpdatedLabel(BuildContext context, DateTime updatedAt) {
  final age = DateTime.now().difference(updatedAt);
  if (age.isNegative || age.inSeconds < 60) {
    return context.l10n.sidebarDetailUpdatedNow;
  }
  if (age.inMinutes < 60) {
    return context.l10n.sidebarDetailUpdatedMinutesAgo(age.inMinutes);
  }
  if (age.inHours < 24) {
    return context.l10n.sidebarDetailUpdatedHoursAgo(age.inHours);
  }
  if (age.inDays <= 7) {
    return context.l10n.sidebarDetailUpdatedDaysAgo(age.inDays);
  }
  final hour = updatedAt.hour.toString().padLeft(2, '0');
  final minute = updatedAt.minute.toString().padLeft(2, '0');
  return '${updatedAt.month}/${updatedAt.day} $hour:$minute';
}
