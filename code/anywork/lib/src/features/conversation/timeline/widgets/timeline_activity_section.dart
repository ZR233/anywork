import 'package:material_ui/material_ui.dart';

import '../../../../shared/latest_scroll.dart';

/// 实时区共同布局：标题保留自然高度，正文在父级实际余量内滚动。
class TimelineActivitySection extends StatelessWidget {
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ClipRect(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight),
            child: header,
          ),
          if (body case final content?)
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxBodyHeight),
                child: _ActivityBody(
                  followOutput: followOutput,
                  child: content,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ActivityBody extends StatefulWidget {
  const _ActivityBody({required this.followOutput, required this.child});

  final bool followOutput;
  final Widget child;

  @override
  State<_ActivityBody> createState() => _ActivityBodyState();
}

class _ActivityBodyState extends State<_ActivityBody> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey<LatestScrollViewportState>();
  final _selection = GlobalKey<SelectionAreaState>();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LatestScrollViewport(
    key: _viewport,
    controller: _scroll,
    enabled: widget.followOutput,
    onClearSelection: () =>
        _selection.currentState?.selectableRegion.clearSelection(),
    child: SingleChildScrollView(
      controller: _scroll,
      primary: false,
      child: SelectionArea(
        key: _selection,
        onSelectionChanged: (selection) => _viewport.currentState?.setSelection(
          selection?.plainText.isNotEmpty ?? false,
        ),
        child: widget.child,
      ),
    ),
  );
}
