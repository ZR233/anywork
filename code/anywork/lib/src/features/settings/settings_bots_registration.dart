part of 'settings_bots_tab.dart';

class _RegistrationPanel extends StatelessWidget {
  const _RegistrationPanel({
    required this.attempt,
    required this.busy,
    required this.canOpenFeishu,
    required this.onCancel,
    required this.onOpenLink,
    required this.onOpenFeishu,
    required this.onCopyLink,
  });

  final BotRegistrationAttempt attempt;
  final bool busy;
  final bool canOpenFeishu;
  final VoidCallback onCancel;
  final ValueChanged<String> onOpenLink;
  final ValueChanged<String> onOpenFeishu;
  final ValueChanged<String> onCopyLink;

  @override
  Widget build(BuildContext context) {
    final status = attempt.status;
    final url = status.verificationUrl;
    final offerClient =
        canOpenFeishu && url != null && feishuRegistrationAppLink(url) != null;
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
              context.l10n.settingsBotsRegistrationStatus(
                _statusLabel(context, status),
              ),
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (status is BotRegistrationPreparing || url != null)
              TextButton(
                key: StudioDriverKeys.botsCancelRegistration,
                onPressed: busy ? null : onCancel,
                child: Text(context.l10n.settingsBotsCancelRegistration),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (url != null) ...[
          LayoutBuilder(
            builder: (context, constraints) {
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
                          onPressed: busy ? null : () => onOpenFeishu(url),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: Text(context.l10n.settingsBotsOpenFeishu),
                        ),
                      TextButton(
                        key: StudioDriverKeys.botsOpenVerificationBrowser,
                        onPressed: busy ? null : () => onOpenLink(url),
                        child: Text(context.l10n.settingsBotsOpenLink),
                      ),
                      TextButton.icon(
                        onPressed: busy ? null : () => onCopyLink(url),
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
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    instructions,
                    const SizedBox(height: 16),
                    _SafeQrView(url: url),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: instructions),
                  const SizedBox(width: 24),
                  _SafeQrView(url: url),
                ],
              );
            },
          ),
        ],
        if (status
            case BotRegistrationFailed(:final message) ||
                BotRegistrationDenied(:final message))
          SettingsInlineError(message: message),
        if (status is BotRegistrationCommitting)
          Text(context.l10n.settingsBotsRegistrationBusy),
      ],
    );
  }

  String _statusLabel(BuildContext context, BotRegistrationStatus status) {
    return switch (status) {
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
}

class _SafeQrView extends StatelessWidget {
  const _SafeQrView({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      height: 168,
      child: PrettyQrView.data(
        data: url,
        errorBuilder: (context, error, stackTrace) {
          return ColoredBox(
            color: context.colors.surfaceContainerHigh,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  context.l10n.settingsBotsQrFailed,
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
