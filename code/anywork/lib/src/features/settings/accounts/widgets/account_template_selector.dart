import 'package:material_ui/material_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/account_brand.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = widget.selected?.kind ?? AccountKind.native;
    final native = widget.templates
        .where((template) => template.key.kind == AccountKind.native)
        .toList();
    final acp = widget.templates
        .where(
          (template) =>
              template.key.kind == AccountKind.acp &&
              template.key.id == 'command',
        )
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<AccountKind>(
          segments: [
            ButtonSegment(
              value: AccountKind.native,
              label: Text(l10n.accountsApi),
            ),
            ButtonSegment(
              value: AccountKind.acp,
              label: Text(l10n.accountsAcp),
            ),
          ],
          selected: {kind},
          onSelectionChanged: !widget.enabled
              ? null
              : (selection) {
                  final next = selection.single;
                  if (next == kind) return;
                  final target = next == AccountKind.acp
                      ? acp
                      : native.firstOrNull;
                  if (target != null) {
                    widget.onSelected(target.key);
                  }
                },
        ),
        if (kind == AccountKind.native) ...[
          const SizedBox(height: 20),
          DropdownMenu<AccountTemplateKey>(
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
              for (final template in native)
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
                ),
            ],
            onSelected: (value) {
              _search.text = _selection?.name ?? '';
              if (value != null && value != widget.selected) {
                widget.onSelected(value);
              }
            },
          ),
        ],
      ],
    );
  }
}
