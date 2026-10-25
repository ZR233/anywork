import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';

class ReleaseNotesView extends StatelessWidget {
  const ReleaseNotesView({
    required this.opening,
    required this.error,
    required this.onOpen,
    super.key,
  });
  final bool opening;
  final String? error;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton.icon(
        onPressed: opening ? null : onOpen,
        icon: opening
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.open_in_new, size: 16),
        label: Text(context.l10n.settingsStudioUpdateReleaseNotes),
      ),
      if (error case final message?)
        Text(
          context.l10n.settingsStudioUpdateFailed(message),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
