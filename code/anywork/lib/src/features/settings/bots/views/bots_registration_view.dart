import 'package:anywork_client/bots.dart';
import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_feedback.dart';

/// Dumb presentation of the canonical registration attempt.
///
/// The verification link and its QR code are short-lived authorization
/// material: they are only rendered here, and no failure path echoes the raw
/// link or the underlying exception.
class BotsRegistrationView extends StatelessWidget {
  const BotsRegistrationView({
    required this.attempt,
    required this.verificationUrl,
    required this.browserLink,
    required this.clientLink,
    required this.pending,
    required this.editable,
    required this.errors,
    required this.onCancel,
    required this.onOpenLink,
    required this.onOpenFeishu,
    required this.onCopyLink,
    super.key,
  });

  final BotRegistrationAttempt attempt;
  final String? verificationUrl;
  final String? browserLink;
  final String? clientLink;
  final bool pending;
  final bool editable;
  final List<String> errors;
  final VoidCallback onCancel;
  final VoidCallback? onOpenLink;
  final VoidCallback? onOpenFeishu;
  final VoidCallback? onCopyLink;

  @override
  Widget build(BuildContext context) {
    final status = attempt.status;
    final url = verificationUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              key: StudioDriverKeys.botsRegistrationStatus,
              context.l10n.settingsBotsRegistrationStatus(_status(context)),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (status is BotRegistrationPreparing || url != null)
              TextButton(
                key: StudioDriverKeys.botsCancelRegistration,
                onPressed: editable && !pending ? onCancel : null,
                child: Text(context.l10n.settingsBotsCancelRegistration),
              ),
          ],
        ),
        if (pending) const LinearProgressIndicator(),
        for (final error in errors)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SettingsInlineError(message: error),
          ),
        if (url != null) ...[
          const SizedBox(height: 8),
          _instructions(context, url),
        ],
        if (status
            case BotRegistrationFailed(:final message) ||
                BotRegistrationDenied(:final message))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SettingsInlineError(message: message),
          ),
        if (status is BotRegistrationCommitting)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(context.l10n.settingsBotsRegistrationBusy),
          ),
      ],
    );
  }

  Widget _instructions(BuildContext context, String url) {
    final offerClient = clientLink != null;
    final instructions = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          offerClient
              ? context.l10n.settingsBotsContinueHint
              : context.l10n.settingsBotsScanOnlyHint,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (offerClient)
              FilledButton.icon(
                key: StudioDriverKeys.botsOpenFeishu,
                onPressed: editable ? onOpenFeishu : null,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(context.l10n.settingsBotsOpenFeishu),
              ),
            TextButton(
              key: StudioDriverKeys.botsOpenVerificationBrowser,
              onPressed: editable && browserLink != null ? onOpenLink : null,
              child: Text(context.l10n.settingsBotsOpenLink),
            ),
            TextButton.icon(
              onPressed: editable ? onCopyLink : null,
              icon: const Icon(Icons.copy, size: 16),
              label: Text(context.l10n.settingsBotsCopyLink),
            ),
          ],
        ),
        if (offerClient) ...[
          const SizedBox(height: 12),
          Text(context.l10n.settingsBotsScanHint),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final qr = _qr(context, url);
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [instructions, const SizedBox(height: 16), qr],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: instructions),
            const SizedBox(width: 24),
            qr,
          ],
        );
      },
    );
  }

  Widget _qr(BuildContext context, String url) => SizedBox(
    width: 168,
    height: 168,
    child: PrettyQrView.data(
      data: url,
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              context.l10n.settingsBotsQrFailed,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
    ),
  );

  String _status(BuildContext context) => switch (attempt.status) {
    BotRegistrationIdle() => context.l10n.settingsBotsRegIdle,
    BotRegistrationPreparing() => context.l10n.settingsBotsRegPreparing,
    BotRegistrationWaiting() => context.l10n.settingsBotsRegWaiting,
    BotRegistrationSlowDown() => context.l10n.settingsBotsRegSlowDown,
    BotRegistrationCommitting() => context.l10n.settingsBotsRegCommitting,
    BotRegistrationCompleted() => context.l10n.settingsBotsRegCompleted,
    BotRegistrationDenied() => context.l10n.settingsBotsRegDenied,
    BotRegistrationExpired() => context.l10n.settingsBotsRegExpired,
    BotRegistrationCancelled() => context.l10n.settingsBotsRegCancelled,
    BotRegistrationFailed() => context.l10n.settingsBotsRegFailed,
  };
}
