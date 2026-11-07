import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';

/// 实时区共同布局：标题保留自然高度，正文在父级实际余量内滚动。
class TimelineActivitySection extends StatefulWidget {
  const TimelineActivitySection({
    required this.header,
    this.body,
    this.maxBodyHeight = 186,
    this.followOutput = false,
    super.key,
  });
  final Widget header;
  final Widget? body;
  final double maxBodyHeight;
  final bool followOutput;
  @override
  State<TimelineActivitySection> createState() => _SectionState();
}

class _SectionState extends State<TimelineActivitySection> {
  final ScrollController _scroll = ScrollController();
  bool _following = true;
  bool _selected = false;
  bool _followScheduled = false;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _follow() {
    if (!widget.followOutput || !_following || _selected || _followScheduled) {
      return;
    }
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (mounted && _following && !_selected && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _follow();
    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight),
              child: widget.header,
            ),
            if (widget.body != null)
              Flexible(
                fit: FlexFit.loose,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: widget.maxBodyHeight),
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (_) {
                      _follow();
                      return false;
                    },
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if ((notification is ScrollUpdateNotification &&
                                notification.dragDetails != null) ||
                            notification is UserScrollNotification) {
                          final next = notification.metrics.extentAfter < 22;
                          if (_following != next) {
                            setState(() => _following = next);
                          }
                        }
                        return false;
                      },
                      child: Scrollbar(
                        controller: _scroll,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          primary: false,
                          child: SelectionArea(
                            onSelectionChanged: (selection) {
                              _selected =
                                  selection?.plainText.isNotEmpty ?? false;
                              if (_selected && _following) {
                                setState(() => _following = false);
                              }
                            },
                            child: widget.body!,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.followOutput && !_following)
              Flexible(
                fit: FlexFit.loose,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  heightFactor: 1,
                  child: TextButton.icon(
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      setState(() {
                        _selected = false;
                        _following = true;
                      });
                      _follow();
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.arrow_downward, size: 14),
                    label: Text(context.l10n.conversationActivityFollowOutput),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
