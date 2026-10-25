import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';

/// One label/value readout inside a web-search card. The 180 px column keeps
/// the same three-across rhythm the status wrap had before the refactor.
class WebSearchStatusValue extends StatelessWidget {
  const WebSearchStatusValue({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
