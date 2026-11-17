import 'package:material_ui/material_ui.dart';

/// Shared input decoration and toolbar geometry. Business owners supply the
/// editor, protocol-specific configuration and qualified actions.
class ComposerInputFrame extends StatelessWidget {
  const ComposerInputFrame({
    super.key,
    required this.body,
    required this.primaryAction,
    this.configuration,
    this.attachmentAction,
    this.creationCard = false,
    this.compact = false,
    this.dragging = false,
  });

  final List<Widget> body;
  final Widget primaryAction;
  final Widget? configuration;
  final Widget? attachmentAction;
  final bool creationCard;
  final bool compact;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(creationCard ? 12 : 14),
      borderSide: BorderSide(
        color: dragging
            ? colors.primary
            : colors.outlineVariant.withValues(alpha: 0.86),
      ),
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...body,
        LayoutBuilder(
          builder: (context, constraints) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (constraints.maxWidth < 540 && configuration != null)
                configuration!,
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ?attachmentAction,
                  const SizedBox(width: 6),
                  Expanded(
                    child: constraints.maxWidth >= 540 && configuration != null
                        ? configuration!
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 8),
                  SizedBox.square(dimension: 34, child: primaryAction),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    return Material(
      type: MaterialType.transparency,
      child: InputDecorator(
        decoration: InputDecoration(
          filled: true,
          fillColor: colors.surfaceContainerLowest,
          contentPadding: compact
              ? const EdgeInsets.fromLTRB(12, 6, 10, 6)
              : const EdgeInsets.fromLTRB(12, 8, 10, 10),
          border: border,
          enabledBorder: border,
        ),
        child: SingleChildScrollView(child: content),
      ),
    );
  }
}
