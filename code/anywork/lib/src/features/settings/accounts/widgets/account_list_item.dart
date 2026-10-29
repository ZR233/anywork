import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import 'account_identity.dart';
import 'account_sections.dart';
import 'account_usage_view.dart';

class AccountListItem extends StatelessWidget {
  const AccountListItem({
    required this.value,
    required this.layout,
    this.selected = false,
    super.key,
    required this.onOpen,
    required this.onAction,
  });
  final AccountRowPresentation value;
  final AccountItemLayout layout;
  final bool selected;
  final VoidCallback onOpen;
  final ValueChanged<AccountRowAction> onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final identity = AccountIdentity(
      name: value.name,
      iconKey: value.iconKey,
      isDefault: value.isDefault,
      subtitleLayout: AccountIdentitySubtitleLayout.singleLine,
      subtitle: switch (value.content) {
        NativeAccountRowContent(:final displayEndpoint) => displayEndpoint,
        AcpAccountRowContent() => null,
      },
    );
    final detailTarget = InkWell(
      key: ValueKey<String>(
        AccountViewKeyValues.row(value.key.kind.name, value.key.id),
      ),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            identity,
            if (value.operationError case final error?)
              AccountInlineError(message: error),
          ],
        ),
      ),
    );
    final status = switch (value.content) {
      NativeAccountRowContent(:final billing) => AccountBillingBadge(
        billing: billing,
        labelLayout: layout == AccountItemLayout.columns
            ? AccountStatusLabelLayout.wrap
            : AccountStatusLabelLayout.singleLine,
      ),
      AcpAccountRowContent(:final status) => AccountStatusBadge(
        label: status,
        labelLayout: layout == AccountItemLayout.columns
            ? AccountStatusLabelLayout.wrap
            : AccountStatusLabelLayout.singleLine,
      ),
    };
    final usage = switch (value.content) {
      NativeAccountRowContent(:final usage) => AccountUsageView(
        value: usage,
        density: AccountMetricDensity.summary,
        showUpdated: false,
        onRetry: () => onAction(AccountRowAction.refresh),
      ),
      AcpAccountRowContent() => const SizedBox.shrink(),
    };
    // Menu is a sibling of the detail target: opening/actions never bubble to it.
    final menu = AccountMenuButton(
      buttonKey: ValueKey<String>(
        AccountViewKeyValues.rowMenu(value.key.kind.name, value.key.id),
      ),
      tooltip: l10n.settingsAccountActions,
      menuChildren: [
        for (final action in value.actions)
          MenuItemButton(
            onPressed: () => onAction(action),
            child: Text(switch (action) {
              AccountRowAction.refresh => l10n.settingsRefreshUsage,
              AccountRowAction.setDefault => l10n.settingsSetAsDefaultAccount,
              AccountRowAction.edit => l10n.settingsEditAccount,
              AccountRowAction.delete => l10n.settingsDeleteAccount,
            }),
          ),
      ],
    );
    return ColoredBox(
      color: selected
          ? Theme.of(context).colorScheme.surfaceContainerHigh
          : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: layout == AccountItemLayout.columns
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 7, child: detailTarget),
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: status,
                    ),
                  ),
                  Expanded(flex: 12, child: usage),
                  SizedBox(width: 48, child: menu),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final theme = Theme.of(context).textTheme;
                            final nameWidth = _textWidth(
                              context,
                              value.name,
                              theme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            );
                            final defaultWidth = value.isDefault
                                ? 8 +
                                      32 +
                                      _textWidth(
                                        context,
                                        l10n.settingsDefaultBadge,
                                        theme.labelSmall,
                                      )
                                : 0;
                            final identityWidth =
                                (50 + nameWidth + defaultWidth)
                                    .clamp(
                                      constraints.maxWidth * .6,
                                      constraints.maxWidth,
                                    )
                                    .toDouble();
                            // Material measures the actual status chip before
                            // deciding whether these two children fit in a row.
                            return OverflowBar(
                              alignment: MainAxisAlignment.start,
                              spacing: 8,
                              overflowSpacing: 8,
                              overflowAlignment: OverflowBarAlignment.start,
                              children: [
                                SizedBox(
                                  width: identityWidth,
                                  child: detailTarget,
                                ),
                                status,
                              ],
                            );
                          },
                        ),
                      ),
                      SizedBox(width: 48, child: menu),
                    ],
                  ),
                  if (value.content case NativeAccountRowContent()) ...[
                    const SizedBox(height: 8),
                    usage,
                  ],
                ],
              ),
      ),
    );
  }
}

double _textWidth(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
