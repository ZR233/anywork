import 'package:material_ui/material_ui.dart';

import '../../../l10n/studio_l10n.dart';

Future<void> runStudioUpdateAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.settingsStudioUpdateFailed(error.toString()),
        ),
      ),
    );
  }
}
