import 'package:material_ui/material_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/account_brand.dart';
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

class _TemplateOption {
  const _TemplateOption({
    required this.key,
    required this.valueKeyId,
    required this.label,
    required this.iconKey,
  });

  final AccountTemplateKey key;
  final String valueKeyId;
  final String label;
  final String? iconKey;
}

bool _isGeminiTemplate(AccountTemplateKey? key) =>
    key != null &&
    key.kind == AccountKind.native &&
    (key.id == 'vertex-ai' || key.id == 'gemini');

class _AccountTemplateSelectorState extends State<AccountTemplateSelector> {
  final TextEditingController _search = TextEditingController();

  List<_TemplateOption> _nativeOptions(
    List<AccountTemplatePresentation> templates,
    AccountTemplateKey? selected,
  ) {
    final native = templates
        .where((template) => template.key.kind == AccountKind.native)
        .toList();
    final preferredGeminiKey = native
        .where(
          (template) =>
              template.key.id == 'gemini' || template.key.id == 'vertex-ai',
        )
        .fold<AccountTemplateKey?>(null, (picked, item) {
          if (item.key.id == 'gemini') return item.key;
          return picked ?? item.key;
        });

    final options = <_TemplateOption>[];
    var addedGemini = false;
    for (final template in native) {
      if (_isGeminiTemplate(template.key)) {
        if (addedGemini) continue;
        addedGemini = true;
        options.add(
          _TemplateOption(
            key: _isGeminiTemplate(selected) ? selected! : preferredGeminiKey!,
            valueKeyId: 'gemini',
            label: 'Gemini',
            iconKey: 'gemini',
          ),
        );
        continue;
      }
      options.add(
        _TemplateOption(
          key: template.key,
          valueKeyId: template.key.id,
          label: template.name,
          iconKey: template.iconKey,
        ),
      );
    }
    return options;
  }

  String _selectionLabel(
    List<AccountTemplatePresentation> templates,
    AccountTemplateKey? selected,
  ) {
    final options = _nativeOptions(templates, selected);
    return options.where((item) => item.key == selected).firstOrNull?.label ??
        templates.where((item) => item.key == selected).firstOrNull?.name ??
        '';
  }

  @override
  void initState() {
    super.initState();
    _search.text = _selectionLabel(widget.templates, widget.selected);
  }

  @override
  void didUpdateWidget(covariant AccountTemplateSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousName = _selectionLabel(
      oldWidget.templates,
      oldWidget.selected,
    );
    final nextName = _selectionLabel(widget.templates, widget.selected);
    if (oldWidget.selected != widget.selected || previousName != nextName) {
      _search.text = nextName;
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
    final options = _nativeOptions(widget.templates, widget.selected);
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
                      ? acp?.key
                      : options.firstOrNull?.key;
                  if (target != null) {
                    widget.onSelected(target);
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
              for (final option in options)
                DropdownMenuEntry(
                  value: option.key,
                  label: option.label,
                  labelWidget: Text(
                    option.label,
                    key: ValueKey(
                      AccountViewKeyValues.template(
                        option.key.kind.name,
                        option.valueKeyId,
                      ),
                    ),
                  ),
                  leadingIcon: AccountBrandMark(
                    fallbackName: option.label,
                    iconKey: option.iconKey,
                    size: 28,
                  ),
                ),
            ],
            onSelected: (value) {
              _search.text = _selectionLabel(widget.templates, widget.selected);
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
