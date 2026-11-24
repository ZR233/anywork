import 'package:material_ui/material_ui.dart';

/// Shares the footer's remaining height between live activity and read-only
/// details without taking space from the actionable composer below it.
class ConversationActivityViewport extends StatefulWidget {
  const ConversationActivityViewport({
    required this.children,
    this.fixedActivity,
    super.key,
  });

  final List<Widget> children;
  final Widget? fixedActivity;

  @override
  State<ConversationActivityViewport> createState() =>
      _ConversationActivityViewportState();
}

class _ConversationActivityViewportState
    extends State<ConversationActivityViewport> {
  final _scroll = ScrollController(keepScrollOffset: false);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fixedActivity = widget.fixedActivity;
    if (fixedActivity == null) return _buildScrollableContent();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(flex: 2, child: fixedActivity),
        if (widget.children.isNotEmpty)
          Flexible(child: _buildScrollableContent()),
      ],
    );
  }

  Widget _buildScrollableContent() => Scrollbar(
    controller: _scroll,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: _scroll,
      primary: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widget.children,
      ),
    ),
  );
}
