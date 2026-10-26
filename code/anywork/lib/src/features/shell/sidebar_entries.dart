import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import 'state/shell_chrome_state.dart';

/// Dumb navigation composition. The project/Thread list is the Workspace
/// feature's real connector, not a copied list or a second directory query.
class ShellNavigationView extends StatelessWidget {
  const ShellNavigationView({
    required this.projectDirectory,
    this.bots = const ShellBotsEntry(),
    this.onOpenBots,
    super.key,
  });

  final Widget projectDirectory;
  final ShellBotsEntry bots;
  final VoidCallback? onOpenBots;

  @override
  Widget build(BuildContext context) {
    final failure = bots.failure;
    final summary = bots.summary;
    final unknown = !bots.current || summary == null;
    final status = failure == null
        ? [?summary, if (unknown) context.l10n.modelDetailUnknown].join(' · ')
        : '${failure.message}\n${failure.code}';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: ListTile(
            key: const ValueKey('shell-feishu-bots-entry'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: Icon(
              Icons.smart_toy_outlined,
              color: failure == null
                  ? context.colors.onSurfaceVariant
                  : context.colors.error,
            ),
            title: Text(context.l10n.settingsBotsTitle),
            subtitle: Tooltip(
              message: status,
              child: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            trailing: onOpenBots == null
                ? const Icon(Icons.help_outline, size: 18)
                : const Icon(Icons.chevron_right, size: 18),
            onTap: onOpenBots,
          ),
        ),
        const Divider(height: 1),
        Expanded(child: projectDirectory),
      ],
    );
  }
}
