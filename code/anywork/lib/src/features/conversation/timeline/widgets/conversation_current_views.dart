import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import 'timeline_markdown.dart';

/// A bounded current-content window. The supplied text is already accepted by
/// its owner; this view never starts a query or retains a resource handle.
class ConversationCurrentWindowView extends StatelessWidget {
  const ConversationCurrentWindowView({
    required this.id,
    required this.text,
    this.label,
    this.error,
    this.offset,
    this.end,
    this.availableThrough,
    this.onFirst,
    this.onNext,
    super.key,
  });

  final String id;
  final String text;
  final String? label;
  final Object? error;
  final int? offset;
  final int? end;
  final int? availableThrough;
  final VoidCallback? onFirst;
  final VoidCallback? onNext;

  bool get _hasRange =>
      offset != null && end != null && availableThrough != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasEarlier = _hasRange && offset! > 0;
    final hasLater = _hasRange && end! < availableThrough!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label case final label?)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                label,
                style: context.text.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ),
          if (error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                error.toString(),
                key: ValueKey('current-window-error:$id'),
                style: context.text.bodySmall?.copyWith(
                  color: colors.error,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          TimelineMarkdown(
            id: 'current:$id',
            text: text,
            style: context.text.bodySmall?.copyWith(
              color: colors.onSurface,
              fontSize: 12.5,
              height: 1.48,
            ),
            onLink: (_) {},
            isSafeLink: (_) => false,
            imageBuilder: (_, url) => Text(url),
          ),
          if (hasEarlier || hasLater)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 2,
                children: [
                  Text(
                    '字节 $offset–$end / $availableThrough',
                    style: context.text.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  if (hasEarlier && onFirst != null)
                    TextButton(
                      onPressed: onFirst,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('第一段'),
                    ),
                  if (hasLater && end! > offset! && onNext != null)
                    TextButton(
                      onPressed: onNext,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('下一段'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
