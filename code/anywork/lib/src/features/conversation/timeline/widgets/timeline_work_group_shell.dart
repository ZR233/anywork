import 'package:material_ui/material_ui.dart';

import 'timeline_activity_row.dart';

/// 可复用的时间线工作组／过程组轻量折叠外壳。
///
/// 统一封装基于 `Expansible` 的无内边距标题交互、`PageStorage` 折叠状态记忆、
/// 无障碍展开语义、减少动态效果降级以及展开后的左侧 `TimelineActivityRail` 引导轨。
/// 普通会话（`CompletionRunView`）与 ACP 会话（`AcpTimelineProcessGroupView`）
/// 共用同一视觉与交互骨架，各自保留自身的业务数据与标题语义。
class TimelineWorkGroupShell extends StatefulWidget {
  const TimelineWorkGroupShell({
    required this.headerBuilder,
    required this.bodyBuilder,
    this.initiallyExpanded = false,
    this.onExpandedChanged,
    this.disclosureKey,
    this.storageKey,
    this.railInset = 9.5,
    this.railContentInset = 17.5,
    this.bodyPadding = const EdgeInsets.only(top: 5, bottom: 3),
    this.headerBorderRadius = const BorderRadius.all(Radius.circular(8)),
    super.key,
  });

  final Widget Function(BuildContext context, bool expanded) headerBuilder;
  final WidgetBuilder bodyBuilder;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpandedChanged;
  final Key? disclosureKey;
  final PageStorageKey<Object>? storageKey;
  final double railInset;
  final double railContentInset;
  final EdgeInsetsGeometry bodyPadding;
  final BorderRadius headerBorderRadius;

  @override
  State<TimelineWorkGroupShell> createState() => _TimelineWorkGroupShellState();
}

class _TimelineWorkGroupShellState extends State<TimelineWorkGroupShell> {
  final ExpansibleController _disclosure = ExpansibleController();
  bool _initializedFromStorage = false;
  bool _syncingController = false;

  @override
  void initState() {
    super.initState();
    _disclosure.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedFromStorage) {
      _initializedFromStorage = true;
      _applyStoredOrInitialExpansion();
    }
  }

  @override
  void didUpdateWidget(covariant TimelineWorkGroupShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.storageKey != oldWidget.storageKey) {
      _applyStoredOrInitialExpansion();
    }
  }

  void _applyStoredOrInitialExpansion() {
    final storageKey = widget.storageKey;
    final stored = storageKey == null
        ? null
        : PageStorage.maybeOf(context)
                  ?.readState(context, identifier: storageKey)
              as bool?;
    final targetExpanded = stored ?? widget.initiallyExpanded;
    if (_disclosure.isExpanded == targetExpanded) return;
    _syncingController = true;
    try {
      if (targetExpanded) {
        _disclosure.expand();
      } else {
        _disclosure.collapse();
      }
    } finally {
      _syncingController = false;
    }
  }

  void _changed() {
    if (_syncingController) return;
    final storageKey = widget.storageKey;
    if (storageKey != null) {
      PageStorage.maybeOf(context)
          ?.writeState(context, _disclosure.isExpanded, identifier: storageKey);
    }
    widget.onExpandedChanged?.call(_disclosure.isExpanded);
    setState(() {});
  }

  @override
  void dispose() {
    _disclosure.removeListener(_changed);
    _disclosure.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expansible(
      key: widget.disclosureKey,
      controller: _disclosure,
      maintainState: false,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      headerBuilder: (context, animation) => Semantics(
        button: true,
        expanded: _disclosure.isExpanded,
        child: InkWell(
          onTap: _disclosure.toggle,
          borderRadius: widget.headerBorderRadius,
          child: widget.headerBuilder(context, _disclosure.isExpanded),
        ),
      ),
      bodyBuilder: (context, animation) => !_disclosure.isExpanded
          ? const SizedBox.shrink()
          : Padding(
              padding: widget.bodyPadding,
              child: TimelineActivityRail(
                inset: widget.railInset,
                contentInset: widget.railContentInset,
                child: Builder(builder: widget.bodyBuilder),
              ),
            ),
      expansibleBuilder: (context, header, body, animation) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, body],
      ),
    );
  }
}
