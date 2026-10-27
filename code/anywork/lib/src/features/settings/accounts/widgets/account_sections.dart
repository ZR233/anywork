import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';

export 'account_billing_control.dart';
export 'account_menu_button.dart';

/// A near-white warm surface scoped to account groups, not an app theme.
Color accountGroupSurface(BuildContext context) => Color.lerp(
  Theme.of(context).colorScheme.surfaceContainerLowest,
  Colors.white,
  .76,
)!;

ButtonStyle accountActionButtonStyle(BuildContext context) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(0, 42)),
  visualDensity: VisualDensity.standard,
  textStyle: WidgetStatePropertyAll(
    Theme.of(context).textTheme.bodyLarge
        ?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
  ),
);

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
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (actions.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          color: accountGroupSurface(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 16),
              child: child,
            ),
          ),
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
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              );
              final value = AccountSelectableText(
                fact.value,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(fontSize: 16),
              );
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
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            color: Theme.of(context).colorScheme.error,
          ),
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
    this.prefixIcon,
    super.key,
  });
  final AccountTextPresentation value;
  final String label;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool obscure;
  final int maxLines;
  final TextInputType? keyboardType;
  final Widget? prefixIcon;

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
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 16),
      decoration: InputDecoration(
        labelStyle: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(fontSize: 16),
        prefixIcon: widget.prefixIcon,
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
