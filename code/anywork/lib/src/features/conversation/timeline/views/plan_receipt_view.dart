import 'package:flutter/material.dart';

import 'plan_document_theme.dart';

/// A frozen, read-only Plan receipt. Data admission and safe body rendering
/// remain with the timeline owner.
class PlanReceiptView extends StatelessWidget {
  const PlanReceiptView({
    super.key,
    required this.label,
    required this.icon,
    required this.children,
    this.documentVersion,
    this.initiallyExpanded = false,
  });

  final String label;
  final IconData icon;
  final int? documentVersion;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      leading: Icon(icon, size: 20),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      shape: Border(
        bottom: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      collapsedShape: Border(
        bottom: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      title: SelectionContainer.disabled(
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            if (documentVersion case final version?)
              Text(
                'v$version',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: PlanDocumentTheme(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
