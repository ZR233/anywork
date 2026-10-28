import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/account_brand.dart';
import 'account_sections.dart';

/// Shared account identity geometry. Layout, never provider identity inference.
enum AccountIdentityLayout { list, header, compact }

enum AccountIdentitySubtitleLayout { selectable, singleLine }

class AccountIdentity extends StatelessWidget {
  const AccountIdentity({
    required this.name,
    this.iconKey,
    this.subtitle,
    this.isDefault = false,
    this.layout = AccountIdentityLayout.list,
    this.subtitleLayout = AccountIdentitySubtitleLayout.selectable,
    this.badge,
    super.key,
  });
  final String name;
  final String? iconKey;
  final String? subtitle;
  final bool isDefault;
  final AccountIdentityLayout layout;
  final AccountIdentitySubtitleLayout subtitleLayout;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final header = layout == AccountIdentityLayout.header;
    final subtitleStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Row(
      children: [
        AccountBrandMark(
          fallbackName: name,
          iconKey: iconKey,
          size: header
              ? 48
              : layout == AccountIdentityLayout.compact
              ? 28
              : 38,
          active: isDefault,
        ),
        SizedBox(width: header ? 14 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    name,
                    style:
                        (header
                                ? Theme.of(context).textTheme.headlineSmall
                                : Theme.of(context).textTheme.titleMedium)
                            ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (isDefault)
                    Chip(
                      label: Text(
                        AppLocalizations.of(context).settingsDefaultBadge,
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      labelStyle: Theme.of(context).textTheme.labelSmall,
                    ),
                  ?badge,
                ],
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                switch (subtitleLayout) {
                  AccountIdentitySubtitleLayout.selectable =>
                    AccountSelectableText(subtitle!, style: subtitleStyle),
                  AccountIdentitySubtitleLayout.singleLine => Tooltip(
                    message: subtitle!,
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                  ),
                },
            ],
          ),
        ),
      ],
    );
  }
}
