import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../state/account_model_details_state.dart';
import '../widgets/account_model_details_content.dart';

class AccountModelDetailsView extends StatelessWidget {
  const AccountModelDetailsView({
    required this.state,
    required this.errors,
    required this.onReload,
    required this.onClose,
    super.key,
  });
  final AccountModelDetailsViewState state;
  final List<String> errors;
  final VoidCallback onReload;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final detail = state.detail;
    final viewport = MediaQuery.sizeOf(context);
    return AlertDialog(
      key: StudioDriverKeys.modelDetailDialog,
      title: Text(
        detail?.descriptor.displayName.isNotEmpty == true
            ? detail!.descriptor.displayName
            : state.entry.model.modelId,
      ),
      content: SizedBox(
        width: (viewport.width - 80).clamp(0, 720).toDouble(),
        height: (viewport.height - 220).clamp(120, 680).toDouble(),
        child: SelectionArea(
          child: ListView(
            children: [
              Text(
                '${state.entry.model.accountId} / ${state.entry.model.modelId}',
              ),
              if (detail != null) Text(detail.accountName),
              const SizedBox(height: 12),
              if (state.reading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(context.l10n.modelDetailLoading),
              ],
              if (state.stale)
                Text(
                  context.l10n.modelDetailStale,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              for (final error in errors)
                SelectableText(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (detail != null)
                AccountModelDetailsContent(
                  detail: detail,
                  billingOverrideKnown: state.billingOverrideKnown,
                  billingOverride: state.billingOverride,
                )
              else if (!state.reading && errors.isEmpty)
                Text(context.l10n.modelDetailUnknown),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: StudioDriverKeys.modelDetailReload,
          onPressed: state.reading ? null : onReload,
          child: Text(context.l10n.modelDetailRetry),
        ),
        TextButton(
          key: StudioDriverKeys.modelDetailClose,
          onPressed: onClose,
          child: Text(context.l10n.modelDetailClose),
        ),
      ],
    );
  }
}
