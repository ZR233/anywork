import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../../../../shared/studio_menu_label.dart';
import '../state/acp_view_state.dart';

IconData _categoryIcon(AcpConfigCategoryKind category) => switch (category) {
  AcpConfigCategoryKind.mode => Icons.layers_outlined,
  AcpConfigCategoryKind.model => Icons.auto_awesome_outlined,
  AcpConfigCategoryKind.thoughtLevel => Icons.psychology_outlined,
  _ => Icons.tune_rounded,
};

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
/// existing ACP session owner. Primary slots are category based; all remaining
/// controls and primary slots that do not fit share one tuning menu.
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
      builder: (context, constraints) {
        final primary = state.primaryControls;
        final widths = [
          for (final control in primary) _triggerWidth(context, control),
        ];
        final available = constraints.maxWidth;
        final fullWidth =
            widths.fold(0.0, (sum, width) => sum + width) +
            (primary.length - 1).clamp(0, 2) * 6;
        var visibleCount = primary.length;
        if (state.extraControls.isNotEmpty || fullWidth > available) {
          // Keep the trailing tuning trigger inside this toolbar. The composer
          // reserves its own fixed action button before giving us this width.
          var remaining = available - 48;
          visibleCount = 0;
          for (final width in widths) {
            if (width + 6 > remaining) break;
            remaining -= width + 6;
            visibleCount++;
          }
        }
        final inline = primary.take(visibleCount).toList();
        final hidden = primary.skip(visibleCount).toSet();
        // Use original server ordering inside the tuning menu as well.
        final overflow = state.controls
            .where(
              (control) =>
                  hidden.contains(control) ||
                  state.extraControls.contains(control),
            )
            .toList();
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
            Row(
              children: [
                for (var index = 0; index < inline.length; index++) ...[
                  if (index > 0) const SizedBox(width: 6),
                  SizedBox(
                    width: widths[index],
                    child: _PrimaryConfigAnchor(
                      key: _controlKey(inline[index]),
                      control: inline[index],
                      interactive: interactive,
                      lockedMessage: lockedMessage,
                      onSelected: (value) => _select(inline[index], value),
                    ),
                  ),
                ],
                if (overflow.isNotEmpty) ...[
                  if (inline.isNotEmpty) const SizedBox(width: 6),
                  Flexible(
                    child: _TuningAnchor(
                      controls: overflow,
                      interactive: interactive,
                      lockedMessage: lockedMessage,
                      onSelected: _select,
                      onBooleanChanged: onBooleanChanged,
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  void _select(AcpConfigControlPresentation control, String value) {
    if (control is AcpLegacyModeConfigControl) {
      onSelectLegacyMode(value);
    } else {
      onSelectValue(control.id, value);
    }
  }

  double _triggerWidth(
    BuildContext context,
    AcpConfigControlPresentation control,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: _currentLabel(control),
        style: context.text.labelMedium,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.clamp(16.0, 160.0) + 56;
    painter.dispose();
    return width;
  }
}

class _PrimaryConfigAnchor extends StatelessWidget {
  const _PrimaryConfigAnchor({
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
          leading: Icon(
            control is AcpSelectConfigControl
                ? _categoryIcon((control as AcpSelectConfigControl).category)
                : Icons.layers_outlined,
            size: 15,
          ),
          label: _currentLabel(control),
          enabled: interactive,
          maxWidth: 160,
        ),
      ),
    ),
  );
}

class _TuningAnchor extends StatelessWidget {
  const _TuningAnchor({
    required this.controls,
    required this.interactive,
    required this.lockedMessage,
    required this.onSelected,
    required this.onBooleanChanged,
  });

  final List<AcpConfigControlPresentation> controls;
  final bool interactive;
  final String lockedMessage;
  final void Function(AcpConfigControlPresentation control, String value)
  onSelected;
  final void Function(String id, bool value) onBooleanChanged;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    key: const ValueKey(AcpViewKeyValues.configOverflow),
    menuChildren: [
      for (final control in controls)
        if (control is AcpBooleanConfigControl)
          Tooltip(
            message: _controlTooltip(context, control),
            child: SizedBox(
              width: (MediaQuery.sizeOf(context).width - 48).clamp(
                120.0,
                300.0,
              ),
              child: SwitchListTile(
                key: ValueKey(AcpViewKeyValues.configControl(control.id)),
                dense: true,
                tileColor: context.colors.surfaceContainerLow,
                title: Text(
                  control.name,
                  style: context.text.bodyMedium?.copyWith(
                    color: interactive
                        ? context.colors.onSurface
                        : context.colors.onSurfaceVariant,
                  ),
                ),
                value: control.currentValue,
                onChanged: interactive
                    ? (value) => onBooleanChanged(control.id, value)
                    : null,
              ),
            ),
          )
        else
          SubmenuButton(
            key: _controlKey(control),
            menuChildren: [
              _ChoiceMenu(
                control: control,
                interactive: interactive,
                onSelected: (value) => onSelected(control, value),
              ),
            ],
            child: Tooltip(
              message: _controlTooltip(context, control),
              child: SizedBox(
                width: (MediaQuery.sizeOf(context).width - 112).clamp(
                  80.0,
                  240.0,
                ),
                child: Text(
                  '${_controlName(context, control)} · ${_currentLabel(control)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
    ],
    builder: (context, controller, _) => Tooltip(
      message: interactive ? context.l10n.acpConfigMoreLabel : lockedMessage,
      child: SizedBox(
        width: 48,
        child: TextButton(
          onPressed: interactive
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_rounded, size: 16),
              Icon(Icons.keyboard_arrow_down, size: 14),
            ],
          ),
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
