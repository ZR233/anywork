import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
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

/// Pure configuration toolbar; values and command completion belong to the
/// existing ACP session owner. Every option uses its protocol type and original
/// position; category metadata never allocates or sorts presentation slots.
class AcpConfigurationBar extends StatelessWidget {
  const AcpConfigurationBar({
    super.key,
    required this.state,
    required this.onSelectValue,
    required this.onBooleanChanged,
    required this.onSelectLegacyMode,
    this.disabledTooltip,
  });

  final AcpConfigurationViewState state;
  final void Function(String configId, String valueId) onSelectValue;
  final void Function(String configId, bool value) onBooleanChanged;
  final ValueChanged<String> onSelectLegacyMode;
  final String? disabledTooltip;

  @override
  Widget build(BuildContext context) {
    if (!state.isVisible) return const SizedBox.shrink();
    final interactive = state.enabled && !state.pending;
    final lockedMessage = state.pending
        ? context.l10n.acpConfigApplying
        : disabledTooltip ?? context.l10n.acpComposerBlockerNotReady;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
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
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final control in state.controls)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: control is AcpBooleanConfigControl
                      ? Tooltip(
                          message: interactive
                              ? _controlTooltip(context, control)
                              : lockedMessage,
                          child: MergeSemantics(
                            child: Row(
                              key: _controlKey(control),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    control.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.text.labelMedium,
                                  ),
                                ),
                                Switch(
                                  value: control.currentValue,
                                  onChanged: interactive
                                      ? (value) =>
                                            onBooleanChanged(control.id, value)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        )
                      : _SelectConfigAnchor(
                          key: _controlKey(control),
                          control: control,
                          interactive: interactive,
                          lockedMessage: lockedMessage,
                          onSelected: (value) {
                            if (control is AcpLegacyModeConfigControl) {
                              onSelectLegacyMode(value);
                            } else {
                              onSelectValue(control.id, value);
                            }
                          },
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectConfigAnchor extends StatelessWidget {
  const _SelectConfigAnchor({
    super.key,
    required this.control,
    required this.interactive,
    required this.lockedMessage,
    required this.onSelected,
  });

  final AcpConfigControlPresentation control;
  final bool interactive;
  final String lockedMessage;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      _ChoiceMenu(
        control: control,
        interactive: interactive,
        onSelected: onSelected,
      ),
    ],
    builder: (context, controller, _) => Tooltip(
      message: interactive ? _controlTooltip(context, control) : lockedMessage,
      child: TextButton(
        onPressed: interactive
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: StudioMenuLabel(
          label: _currentLabel(control),
          enabled: interactive,
          maxWidth: 160,
        ),
      ),
    ),
  );
}

class _ChoiceMenu extends StatefulWidget {
  const _ChoiceMenu({
    required this.control,
    required this.interactive,
    required this.onSelected,
  });

  final AcpConfigControlPresentation control;
  final bool interactive;
  final ValueChanged<String> onSelected;

  @override
  State<_ChoiceMenu> createState() => _ChoiceMenuState();
}

class _ChoiceMenuState extends State<_ChoiceMenu> {
  String _query = '';

  bool _matches(AcpSelectChoicePresentation option, [String group = '']) {
    final query = _query.trim().toLowerCase();
    return query.isEmpty ||
        '${option.name}\n${option.value}\n$group'.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final control = widget.control;
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
    final count =
        flat.length +
        groups.fold(0, (sum, group) => sum + group.options.length);
    final width = (MediaQuery.sizeOf(context).width - 48).clamp(120.0, 320.0);
    final height = (MediaQuery.sizeOf(context).height - 96).clamp(120.0, 440.0);
    return SizedBox(
      width: width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Semantics(
                header: true,
                child: Text(
                  _controlName(context, control),
                  style: context.text.titleSmall,
                ),
              ),
            ),
            if (count > 8)
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  key: ValueKey('acp-config-search-${control.id}'),
                  enabled: widget.interactive,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: context.l10n.modeEditorSearchHint,
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    isDense: true,
                  ),
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                primary: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final option in flat)
                      if (_matches(option)) _choice(option, current),
                    for (final group in groups)
                      if (group.options.any(
                        (option) => _matches(option, group.name),
                      )) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: Text(
                            group.name,
                            style: context.text.labelSmall,
                          ),
                        ),
                        for (final option in group.options)
                          if (_matches(option, group.name))
                            _choice(option, current),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choice(AcpSelectChoicePresentation choice, String current) => Tooltip(
    message: choice.description ?? choice.name,
    child: MenuItemButton(
      key: ValueKey(
        AcpViewKeyValues.configChoice(widget.control.id, choice.value),
      ),
      onPressed: widget.interactive
          ? () => widget.onSelected(choice.value)
          : null,
      leadingIcon: Icon(
        choice.value == current ? Icons.check_rounded : null,
        size: 16,
      ),
      child: Text(choice.name, maxLines: 2, overflow: TextOverflow.ellipsis),
    ),
  );
}
