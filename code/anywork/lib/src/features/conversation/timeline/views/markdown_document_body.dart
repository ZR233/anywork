import 'package:material_ui/material_ui.dart';

import 'plan_document_theme.dart';

/// Shared, width-following document body for Plan and user-selected Markdown.
/// Scrolling and selection are owned by the enclosing reading surface.
class MarkdownDocumentBody extends StatelessWidget {
  const MarkdownDocumentBody({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.all(constraints.maxWidth < 520 ? 20 : 24),
        child: PlanDocumentTheme(
          child: DefaultTextStyle.merge(
            softWrap: true,
            overflow: TextOverflow.visible,
            child: child,
          ),
        ),
      ),
    ),
  );
}
