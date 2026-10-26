import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';

String accountBillingLabel(AppLocalizations l10n, AccountBilling billing) =>
    switch (billing) {
      AccountBilling.unknown => l10n.settingsBillingUnknown,
      AccountBilling.metered => l10n.settingsBillingMetered,
      AccountBilling.subscription => l10n.settingsBillingSubscription,
      AccountBilling.noCharge => l10n.settingsNoCharge,
    };

String accountConnectionLabel(AppLocalizations l10n, AccountConnection value) =>
    switch (value) {
      AccountConnection.automatic => l10n.accountsAutomatic,
      AccountConnection.http => l10n.accountsHttp,
      AccountConnection.webSocket => l10n.accountsWebSocket,
    };

/// Account-domain section, not a replacement design system.
class AccountSection extends StatelessWidget {
  const AccountSection({
    required this.title,
    required this.child,
    this.actions = const [],
    super.key,
  });
  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (actions.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ],
    ),
  );
}

/// A selectable value owns only its text-scroll storage. The local PageStorage
/// boundary stops ancestor page/ExpansionTile keys from identifying this offset.
class AccountSelectableText extends StatefulWidget {
  const AccountSelectableText(this.data, {this.style, super.key});
  final String data;
  final TextStyle? style;

  @override
  State<AccountSelectableText> createState() => _AccountSelectableTextState();
}

class _AccountSelectableTextState extends State<AccountSelectableText> {
  final PageStorageBucket _scrollStorage = PageStorageBucket();

  @override
  Widget build(BuildContext context) => PageStorage(
    bucket: _scrollStorage,
    child: SelectableText(
      widget.data,
      key: const PageStorageKey<String>('account-selectable-text-scroll'),
      style: widget.style,
    ),
  );
}

class AccountFacts extends StatelessWidget {
  const AccountFacts({required this.facts, super.key});
  final List<AccountDisplayFact> facts;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final fact in facts)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final label = Text(
                fact.label,
                style: Theme.of(context).textTheme.bodySmall,
              );
              final value = AccountSelectableText(fact.value);
              return constraints.maxWidth < 460
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [label, const SizedBox(height: 4), value],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 180, child: label),
                        Expanded(child: value),
                      ],
                    );
            },
          ),
        ),
    ],
  );
}

class AccountInlineError extends StatelessWidget {
  const AccountInlineError({required this.message, this.onRetry, super.key});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Icon(
          Icons.error_outline,
          size: 18,
          color: Theme.of(context).colorScheme.error,
        ),
        Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            child: Text(AppLocalizations.of(context).accountsRetry),
          ),
      ],
    ),
  );
}

/// Controller owns only Flutter editing geometry/composing, never a business draft.
/// External raw values remain authoritative; change callbacks contain raw input.
class AccountRawTextField extends StatefulWidget {
  const AccountRawTextField({
    required this.value,
    required this.label,
    required this.onChanged,
    this.enabled = true,
    this.obscure = false,
    this.maxLines = 1,
    this.keyboardType,
    super.key,
  });
  final AccountTextPresentation value;
  final String label;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool obscure;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  State<AccountRawTextField> createState() => _AccountRawTextFieldState();
}

class _AccountRawTextFieldState extends State<AccountRawTextField> {
  // Keep input geometry in this field's lifetime, never in an ancestor's
  // expansion-bool or page-scroll entry. Flutter owns the inner ScrollController.
  final PageStorageBucket _scrollStorage = PageStorageBucket();
  late final TextEditingController _controller = TextEditingController(
    text: widget.value.raw,
  );
  bool _reveal = false;

  @override
  void didUpdateWidget(covariant AccountRawTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An unrelated rebuild must not replace active IME composing geometry.
    // A changed external raw value is an intentional authoritative update.
    if (oldWidget.value.raw != widget.value.raw &&
        _controller.text != widget.value.raw) {
      final oldSelection = _controller.selection;
      final length = widget.value.raw.length;
      _controller.value = TextEditingValue(
        text: widget.value.raw,
        selection: oldSelection.isValid
            ? TextSelection(
                baseOffset: oldSelection.baseOffset.clamp(0, length),
                extentOffset: oldSelection.extentOffset.clamp(0, length),
              )
            : TextSelection.collapsed(offset: length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageStorage(
    bucket: _scrollStorage,
    child: TextField(
      key: const PageStorageKey<String>('account-input-scroll'),
      controller: _controller,
      onChanged: widget.onChanged,
      enabled: widget.enabled,
      obscureText: widget.obscure && !_reveal,
      autocorrect: !widget.obscure,
      enableSuggestions: !widget.obscure,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.value.error,
        helperText: widget.value.helper,
        errorMaxLines: 4,
        helperMaxLines: 4,
        suffixIcon: widget.obscure
            ? IconButton(
                tooltip: _reveal
                    ? AppLocalizations.of(context).accountsHideCredential
                    : AppLocalizations.of(context).accountsShowCredential,
                onPressed: () => setState(() => _reveal = !_reveal),
                icon: Icon(
                  _reveal
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              )
            : null,
      ),
    ),
  );
}

class AccountBillingControl extends StatelessWidget {
  const AccountBillingControl({
    required this.value,
    required this.onChanged,
    required this.onReset,
    super.key,
  });
  final AccountBillingPresentation value;
  final ValueChanged<AccountBilling> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountFacts(
          facts: [
            AccountDisplayFact(
              label: l10n.settingsBillingEffective,
              value: accountBillingLabel(l10n, value.effective),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              value.billingKindOverride == null
                  ? l10n.settingsBillingAutomatic
                  : l10n.settingsBillingOverride,
            ),
            for (final billing in value.allowedOverrides)
              ChoiceChip(
                label: Text(accountBillingLabel(l10n, billing)),
                selected: value.billingKindOverride == billing,
                onSelected: value.saving ? null : (_) => onChanged(billing),
              ),
            if (value.billingKindOverride != null)
              TextButton.icon(
                onPressed: value.saving ? null : onReset,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: Text(l10n.settingsModelAutoCompactRestore),
              ),
          ],
        ),
        if (value.saving) const LinearProgressIndicator(),
        if (value.error != null) AccountInlineError(message: value.error!),
        const SizedBox(height: 8),
        Text(
          l10n.accountsBillingDisclaimer,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
