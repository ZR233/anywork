import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import 'account_sections.dart';

String acpActionLabel(AppLocalizations l10n, AcpAccountAction action) =>
    switch (action) {
      AcpAccountAction.prepare => l10n.acpInstallStart,
      AcpAccountAction.cancelPreparation => l10n.acpInstallCancel,
      AcpAccountAction.usePrepared => l10n.acpInstallUsePrepared,
      AcpAccountAction.check => l10n.acpAuthCheck,
      AcpAccountAction.login => l10n.acpAuthLogin,
      AcpAccountAction.verify => l10n.accountsVerifySignIn,
      AcpAccountAction.cancelAuthentication => l10n.acpAuthCancel,
      AcpAccountAction.retry => l10n.acpAuthRetry,
      AcpAccountAction.openGuide => l10n.acpAccountInstallOpen,
      AcpAccountAction.openTerms => l10n.acpAccountTermsOpen,
    };

class AcpAccountPanel extends StatelessWidget {
  const AcpAccountPanel({
    required this.value,
    required this.onAction,
    required this.onLoginMethodChanged,
    super.key,
  });
  final AcpAccountPresentation value;
  final ValueChanged<AcpAccountAction> onAction;
  final ValueChanged<String> onLoginMethodChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(value.status, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          l10n.acpAccountNoApiKeyHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (value.message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: AccountSelectableText(value.message!),
          ),
        if (value.phase == AcpPresentationPhase.preparing ||
            value.progress != null) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: value.progress),
        ],
        if (value.progressLabel != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(value.progressLabel!),
          ),
        AccountFacts(facts: value.facts),
        if (value.error != null) AccountInlineError(message: value.error!),
        if (value.loginMethods.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(l10n.acpAuthMethodSelectHint),
          for (final method in value.loginMethods)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                onPressed: value.canSelectLoginMethod
                    ? () => onLoginMethodChanged(method.id)
                    : null,
                child: Row(
                  children: [
                    Icon(
                      value.selectedLoginMethod == method.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(method.label)),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (value.hasPrimaryAction)
              FilledButton(
                key: ValueKey<String>(
                  AccountViewKeyValues.acpAction(value.primaryAction!.name),
                ),
                onPressed: () => onAction(value.primaryAction!),
                child: Text(acpActionLabel(l10n, value.primaryAction!)),
              ),
            for (final action in value.availableActions.where(
              (action) =>
                  action != AcpAccountAction.openGuide &&
                  action != AcpAccountAction.openTerms &&
                  (!value.hasPrimaryAction || action != value.primaryAction),
            ))
              OutlinedButton(
                key: ValueKey<String>(
                  AccountViewKeyValues.acpAction(action.name),
                ),
                onPressed: () => onAction(action),
                child: Text(acpActionLabel(l10n, action)),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final action in value.availableActions.where(
              (action) =>
                  action == AcpAccountAction.openGuide ||
                  action == AcpAccountAction.openTerms,
            ))
              TextButton.icon(
                key: ValueKey<String>(
                  AccountViewKeyValues.acpAction(action.name),
                ),
                onPressed: () => onAction(action),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(acpActionLabel(l10n, action)),
              ),
          ],
        ),
      ],
    );
  }
}
