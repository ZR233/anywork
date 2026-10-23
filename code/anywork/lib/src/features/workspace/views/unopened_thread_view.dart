import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';

class UnopenedThreadView extends StatelessWidget {
  const UnopenedThreadView({required this.threadId, required this.onOpen, super.key});
  final String threadId;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: StudioDriverKeys.unopenedThread,
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(children: [
        Tooltip(message: context.l10n.threadUnopenedTitle,
          child: const Icon(Icons.play_circle_outline, size: 18)),
        const SizedBox(width: 8),
        Expanded(child: Text(context.l10n.threadUnopenedBody,
          style: Theme.of(context).textTheme.labelSmall)),
        KeyedSubtree(key: StudioDriverKeys.openSelectedThread,
          child: FilledButton(key: StudioDriverKeys.openThread(threadId),
            onPressed: onOpen, child: Text(context.l10n.threadOpenAction))),
      ])),
  );
}
