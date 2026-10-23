import 'package:anywork_client/models.dart' show ModelModality;
import 'package:flutter/material.dart';

import '../../l10n/studio_l10n.dart';

/// A display of a catalog-declared input modality, never a capability inference.
class ModelCapabilityCard extends StatelessWidget {
  const ModelCapabilityCard({required this.modality, super.key});

  final ModelModality modality;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 128),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 13, color: colors.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  context.modalityLabel(modality),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _icon => switch (modality) {
    ModelModality.text => Icons.article_outlined,
    ModelModality.image => Icons.image_outlined,
    ModelModality.audio => Icons.graphic_eq,
    ModelModality.video => Icons.movie_outlined,
    ModelModality.file => Icons.attach_file,
  };
}
