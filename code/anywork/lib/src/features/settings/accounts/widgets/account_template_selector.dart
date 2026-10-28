import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/account_brand.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import 'account_identity.dart';
import 'account_sections.dart';
import 'account_usage_view.dart';

/// One searchable template directory for both account owners. Selection is an
/// intent; the Connector resolves the old draft before replacing the editor.
class AccountTemplateSelector extends StatefulWidget {
  const AccountTemplateSelector({
    required this.templates,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    super.key,
  });
  final List<AccountTemplatePresentation> templates;
  final AccountTemplateKey? selected;
  final ValueChanged<AccountTemplateKey> onSelected;
  final bool enabled;

  @override
  State<AccountTemplateSelector> createState() =>
      _AccountTemplateSelectorState();
}

class _AccountTemplateSelectorState extends State<AccountTemplateSelector> {
  final TextEditingController _search = TextEditingController();
  AccountTemplatePresentation? get _selection =>
      widget.templates.where((item) => item.key == widget.selected).firstOrNull;

  @override
  void initState() {
    super.initState();
    _search.text = _selection?.name ?? '';
  }

  @override
  void didUpdateWidget(covariant AccountTemplateSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousName = oldWidget.templates
        .where((item) => item.key == oldWidget.selected)
        .firstOrNull
        ?.name;
    if (oldWidget.selected != widget.selected ||
        previousName != _selection?.name) {
      _search.text = _selection?.name ?? '';
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _metadata(BuildContext context, AccountTemplateContent content) {
    switch (content) {
      case AcpAccountTemplateContent():
        return const SizedBox.shrink();
      case NativeAccountTemplateContent(
        :final defaultBilling,
        :final protocolLabel,
        :final defaultEndpoint,
        :final supportsModelDiscovery,
        :final supportsUsageQuery,
      ):
        final l10n = AppLocalizations.of(context);
        final theme = Theme.of(context);
        final labelStyle = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
        final valueStyle = theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        );
        final facts = <({String label, Widget value})>[
          (
            label: l10n.accountsTemplateProtocol,
            value: AccountSelectableText(protocolLabel, style: valueStyle),
          ),
          (
            label: l10n.accountsTemplateDefaultBilling,
            value: AccountBillingBadge(billing: defaultBilling),
          ),
          (
            label: l10n.accountsTemplateCapabilities,
            value: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supportsModelDiscovery
                      ? l10n.accountsTemplateDiscoverySupported
                      : l10n.accountsTemplateDiscoveryUnsupported,
                  style: valueStyle,
                ),
                const SizedBox(height: 4),
                Text(switch (supportsUsageQuery) {
                  true => l10n.accountsTemplateUsageSupported,
                  false => l10n.accountsTemplateUsageUnsupported,
                  null => l10n.accountsTemplateUsageUnknown,
                }, style: valueStyle),
              ],
            ),
          ),
        ];
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.accountsTemplateDefaultEndpoint, style: labelStyle),
              const SizedBox(height: 4),
              AccountSelectableText(defaultEndpoint, style: valueStyle),
              const Divider(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth >=
                          660 * MediaQuery.textScalerOf(context).scale(1)
                      ? facts.length
                      : 1;
                  return Wrap(
                    runSpacing: 16,
                    children: [
                      for (var i = 0; i < facts.length; i++)
                        Container(
                          width: (constraints.maxWidth / columns)
                              .floorToDouble(),
                          padding: EdgeInsetsDirectional.only(
                            start: i % columns == 0 ? 0 : 16,
                            end: columns == 1 ? 0 : 16,
                          ),
                          decoration: BoxDecoration(
                            border: i % columns == 0
                                ? null
                                : BorderDirectional(
                                    start: BorderSide(
                                      color: theme.colorScheme.outlineVariant,
                                    ),
                                  ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(facts[i].label, style: labelStyle),
                              const SizedBox(height: 6),
                              facts[i].value,
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final template = _selection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownMenu<AccountTemplateKey>(
          key: const ValueKey('account-template-selector'),
          controller: _search,
          expandedInsets: EdgeInsets.zero,
          enabled: widget.enabled,
          enableFilter: true,
          enableSearch: true,
          requestFocusOnTap: true,
          menuHeight: 360,
          initialSelection: widget.selected,
          label: Text(l10n.settingsAccountTemplate),
          dropdownMenuEntries: [
            for (final kind in AccountKind.values)
              for (final template in widget.templates.where(
                (template) => template.key.kind == kind,
              ))
                DropdownMenuEntry(
                  value: template.key,
                  label: template.name,
                  labelWidget: Text(
                    template.name,
                    key: ValueKey(
                      AccountViewKeyValues.template(
                        template.key.kind.name,
                        template.key.id,
                      ),
                    ),
                  ),
                  leadingIcon: AccountBrandMark(
                    fallbackName: template.name,
                    iconKey: template.iconKey,
                    size: 28,
                  ),
                  trailingIcon: Text(
                    kind == AccountKind.native
                        ? l10n.accountsTemplateNativeGroup
                        : l10n.accountsTemplateAcpGroup,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
          ],
          onSelected: (value) {
            // Material updates its text before this callback. Do not show an
            // unaccepted template while the owner resolves unsaved changes.
            _search.text = _selection?.name ?? '';
            if (value != null && value != widget.selected) {
              widget.onSelected(value);
            }
          },
        ),
        if (template != null) ...[
          const SizedBox(height: 12),
          Card.filled(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AccountIdentity(
                    name: template.name,
                    iconKey: template.iconKey,
                  ),
                  if (template.description case final description?) ...[
                    const SizedBox(height: 8),
                    AccountSelectableText(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  _metadata(context, template.content),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
