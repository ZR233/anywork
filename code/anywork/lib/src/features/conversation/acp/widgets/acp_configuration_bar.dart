import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/composer_configuration_bar.dart';
import '../../../../shared/studio_chrome.dart';
import '../../../../shared/studio_menu_label.dart';
import '../state/acp_view_state.dart';

String _currentLabel(AcpConfigControlPresentation control) => switch (control) {
  AcpSelectConfigControl(:final currentLabel) => currentLabel,
  AcpLegacyModeConfigControl(:final currentModeLabel) => currentModeLabel,
  AcpBooleanConfigControl(:final name) => name,
};

Key _controlKey(AcpConfigControlPresentation control) =>
    control is AcpLegacyModeConfigControl
    ? const ValueKey(AcpViewKeyValues.configLegacyMode)
    : ValueKey(AcpViewKeyValues.configControl(control.id));

String _controlName(
  BuildContext context,
  AcpConfigControlPresentation control,
) => switch (control) {
  AcpSelectConfigControl(:final name) => name,
  AcpBooleanConfigControl(:final name) => name,
  AcpLegacyModeConfigControl() => context.l10n.acpConfigModeFallbackLabel,
};

String _controlTooltip(
  BuildContext context,
  AcpConfigControlPresentation control,
) {
  final description = control.description?.trim();
  final name = _controlName(context, control);
  return description == null || description.isEmpty
      ? name
      : '$name\n$description';
}

bool _isCommon(AcpConfigControlPresentation control) => switch (control) {
  AcpLegacyModeConfigControl() => true,
  AcpSelectConfigControl(:final category) =>
    category == AcpConfigCategoryKind.mode ||
        category == AcpConfigCategoryKind.model ||
        category == AcpConfigCategoryKind.thoughtLevel,
  AcpBooleanConfigControl() => false,
};

/// Presents server-owned configuration without inferring categories or values.
class AcpConfigurationBar extends StatelessWidget {
  const AcpConfigurationBar({
    super.key,
    required this.state,
    required this.onSelectValue,
    required this.onBooleanChanged,
    required this.onSelectLegacyMode,
    this.disabledTooltip,
    this.leadingEntries = const [],
  });

  final AcpConfigurationViewState state;
  final void Function(String configId, String valueId) onSelectValue;
  final void Function(String configId, bool value) onBooleanChanged;
  final ValueChanged<String> onSelectLegacyMode;
  final String? disabledTooltip;
  final List<ComposerConfigurationEntry> leadingEntries;

  @override
  Widget build(BuildContext context) {
    final interactive = state.enabled && !state.pending;
    final commonCategories = <AcpConfigCategoryKind>{};
    final inlineIds = <String>{};
    for (final control in state.controls) {
      if (!_isCommon(control)) continue;
      final category = switch (control) {
        AcpSelectConfigControl(:final category) => category,
        AcpLegacyModeConfigControl() => AcpConfigCategoryKind.mode,
        AcpBooleanConfigControl() => null,
      };
      if (category != null && commonCategories.add(category)) {
        inlineIds.add(control.id);
      }
    }
    final lockedMessage = state.pending
        ? context.l10n.acpConfigApplying
        : disabledTooltip ?? context.l10n.acpComposerBlockerNotReady;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.errorMessage case final error?)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: StudioInlineMessage(
              icon: Icons.error_outline_rounded,
              message: context.l10n.acpConfigFailed(error),
              color: context.colors.error,
            ),
          ),
        ComposerConfigurationBar(
          moreTooltip: context.l10n.acpConfigMoreLabel,
          entries: [
            ...leadingEntries,
            for (final control in state.controls)
              ComposerConfigurationEntry(
                id: control.id,
                measureInlineWidth: inlineIds.contains(control.id)
                    ? (context) => _inlineLabel(
                        control,
                        interactive,
                      ).measureWidth(context)
                    : null,
                inline: inlineIds.contains(control.id)
                    ? _SelectConfigAnchor(
                        key: _controlKey(control),
                        control: control,
                        interactive: interactive,
                        tooltip: interactive
                            ? _controlTooltip(context, control)
                            : lockedMessage,
                        menuChildren: _choices(control, interactive),
                      )
                    : null,
                menuItem: Tooltip(
                  key: _controlKey(control),
                  message: interactive
                      ? _controlTooltip(context, control)
                      : lockedMessage,
                  child: control is AcpBooleanConfigControl
                      ? CheckboxMenuButton(
                          value: control.currentValue,
                          onChanged: interactive
                              ? (value) {
                                  if (value != null) {
                                    onBooleanChanged(control.id, value);
                                  }
                                }
                              : null,
                          child: Text(control.name),
                        )
                      : SubmenuButton(
                          menuChildren: interactive
                              ? _choices(control, interactive)
                              : const [],
                          child: Text(
                            '${_controlName(context, control)} · ${_currentLabel(control)}',
                          ),
                        ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _choices(
    AcpConfigControlPresentation control,
    bool interactive,
  ) {
    final (flat, groups, current) = switch (control) {
      AcpSelectConfigControl(
        :final flatOptions,
        :final groups,
        :final currentValue,
      ) =>
        (flatOptions, groups, currentValue),
      AcpLegacyModeConfigControl(:final modes, :final currentModeId) => (
        modes,
        const <AcpSelectGroupPresentation>[],
        currentModeId,
      ),
      AcpBooleanConfigControl() => (
        const <AcpSelectChoicePresentation>[],
        const <AcpSelectGroupPresentation>[],
        '',
      ),
    };
    Widget choice(AcpSelectChoicePresentation option) => Tooltip(
      message: option.description ?? option.name,
      child: MenuItemButton(
        key: ValueKey(AcpViewKeyValues.configChoice(control.id, option.value)),
        onPressed: interactive
            ? () => control is AcpLegacyModeConfigControl
                  ? onSelectLegacyMode(option.value)
                  : onSelectValue(control.id, option.value)
            : null,
        leadingIcon: Icon(
          option.value == current ? Icons.check_rounded : null,
          size: 16,
        ),
        child: Text(option.name),
      ),
    );
    return [
      for (final option in flat) choice(option),
      for (final group in groups)
        SubmenuButton(
          key: ValueKey(('acp-config-group', control.id, group.id)),
          menuChildren: [for (final option in group.options) choice(option)],
          child: Text(group.name),
        ),
    ];
  }
}

StudioMenuLabel _inlineLabel(
  AcpConfigControlPresentation control,
  bool interactive,
) => StudioMenuLabel(
  label: _currentLabel(control),
  enabled: interactive,
  maxWidth: 160,
);

class _SelectConfigAnchor extends StatelessWidget {
  const _SelectConfigAnchor({
    super.key,
    required this.control,
    required this.interactive,
    required this.tooltip,
    required this.menuChildren,
  });

  final AcpConfigControlPresentation control;
  final bool interactive;
  final String tooltip;
  final List<Widget> menuChildren;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: menuChildren,
    builder: (context, controller, _) => Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: interactive && menuChildren.isNotEmpty
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: _inlineLabel(control, interactive),
      ),
    ),
  );
}
