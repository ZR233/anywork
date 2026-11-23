import 'package:material_ui/material_ui.dart';

import '../../../../../app/theme/studio_tokens.dart';
import 'tool_detail_values.dart';

/// Shared neutral container, spacing, and selection boundary for tool details.
class TimelineToolDetailPanel extends StatelessWidget {
  const TimelineToolDetailPanel({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            children[index],
          ],
        ],
      ),
    );
    return SelectionContainer.maybeOf(context) == null
        ? SelectionArea(child: content)
        : content;
  }
}

/// Renders immutable [ToolDetailValue] rows with contrast-safe typography and
/// natural wrapping or horizontal code scrolling.
class TimelineToolSemanticBody extends StatelessWidget {
  const TimelineToolSemanticBody({required this.values, super.key});

  final List<ToolDetailValue> values;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final value in values)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: switch (value) {
            ToolDetailText(:final title, :final text, :final code) => _text(
              context,
              title,
              text,
              code: code,
            ),
            ToolDetailLink(:final title, :final url) => _text(
              context,
              title,
              url,
            ),
            ToolDetailUnavailable(:final reason) => Text(
              reason,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          },
        ),
    ],
  );

  Widget _text(
    BuildContext context,
    String title,
    String text, {
    bool code = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: context.text.labelSmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 4),
      if (code)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            text,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurface,
              fontFamily: studioCodeFontFamily,
              height: 1.5,
            ),
          ),
        )
      else
        Text(
          text,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurface,
            height: 1.5,
          ),
        ),
    ],
  );
}
