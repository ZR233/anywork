import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../../../../shared/studio_menu_label.dart';
import '../state/acp_view_state.dart';

IconData _categoryIcon(AcpConfigCategoryKind category) => switch (category) {
  AcpConfigCategoryKind.mode => Icons.layers_outlined,
  AcpConfigCategoryKind.model => Icons.auto_awesome_outlined,
  AcpConfigCategoryKind.modelConfig => Icons.tune_rounded,
  AcpConfigCategoryKind.thoughtLevel => Icons.psychology_outlined,
  AcpConfigCategoryKind.other ||
  AcpConfigCategoryKind.unspecified => Icons.tune_rounded,
};

/// Inline composer toolbar for ACP dynamic session configuration (`configOptions`
/// or legacy `modes`).
///
/// Preserves exact server array order, renders leading controls inline using
/// quiet [MenuAnchor] + [StudioMenuLabel] triggers and compact boolean toggle
/// pills, and collects extra controls into a single "More settings" popover
/// when space is constrained. Never optimistically mutates or rolls back values.
class AcpConfigurationBar extends StatelessWidget {
  const AcpConfigurationBar({
    super.key,
    required this.state,
    required this.onSelectValue,
    required this.onBooleanChanged,
    required this.onSelectLegacyMode,
  });

  final AcpConfigurationViewState state;
  final void Function(String configId, String valueId) onSelectValue;
  final void Function(String configId, bool value) onBooleanChanged;
  final ValueChanged<String> onSelectLegacyMode;

  @override
  Widget build(BuildContext context) {
    if (!state.isVisible) return const SizedBox.shrink();
    final l10n = context.l10n;
    final interactive = state.enabled && !state.pending;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final inlineBudget = maxWidth >= 560
            ? 3
            : maxWidth >= 380
            ? 2
            : 1;
        final controls = state.controls;
        final inlineCount = controls.length <= inlineBudget
            ? controls.length
            : inlineBudget;
        final inlineControls = controls.take(inlineCount).toList();
        final overflowControls = controls.skip(inlineCount).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.errorMessage case final error?)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: StudioInlineMessage(
                  icon: Icons.error_outline_rounded,
                  message: l10n.acpConfigFailed(error),
                  color: context.colors.error,
                ),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final control in inlineControls)
                  _buildControlWidget(
                    context,
                    control: control,
                    interactive: interactive,
                    maxLabelWidth: maxWidth < 360 ? 150 : 190,
                  ),
                if (overflowControls.isNotEmpty)
                  _OverflowSettingsAnchor(
                    controls: overflowControls,
                    interactive: interactive,
                    onSelectValue: onSelectValue,
                    onBooleanChanged: onBooleanChanged,
                    onSelectLegacyMode: onSelectLegacyMode,
                  ),
                if (state.pending)
                  StudioPill(label: l10n.acpConfigApplying, icon: Icons.sync),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildControlWidget(
    BuildContext context, {
    required AcpConfigControlPresentation control,
    required bool interactive,
    required double maxLabelWidth,
  }) => switch (control) {
    final AcpSelectConfigControl select => _SelectConfigAnchor(
      key: ValueKey(AcpViewKeyValues.configControl(select.id)),
      control: select,
      interactive: interactive,
      maxLabelWidth: maxLabelWidth,
      onSelected: (valueId) => onSelectValue(select.id, valueId),
    ),
    final AcpBooleanConfigControl toggle => _BooleanConfigChip(
      key: ValueKey(AcpViewKeyValues.configControl(toggle.id)),
      control: toggle,
      interactive: interactive,
      onChanged: (next) => onBooleanChanged(toggle.id, next),
    ),
    final AcpLegacyModeConfigControl mode => _LegacyModeAnchor(
      key: const ValueKey(AcpViewKeyValues.configLegacyMode),
      control: mode,
      interactive: interactive,
      maxLabelWidth: maxLabelWidth,
      onSelected: onSelectLegacyMode,
    ),
  };
}

class _SelectConfigAnchor extends StatelessWidget {
  const _SelectConfigAnchor({
    super.key,
    required this.control,
    required this.interactive,
    required this.maxLabelWidth,
    required this.onSelected,
  });

  final AcpSelectConfigControl control;
  final bool interactive;
  final double maxLabelWidth;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final menuWidth = (MediaQuery.sizeOf(context).width - 32).clamp(
      200.0,
      340.0,
    );
    final menuHeight = (MediaQuery.sizeOf(context).height - 64).clamp(
      160.0,
      460.0,
    );

    final children = <Widget>[
      if (control.description case final desc? when desc.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: SizedBox(
            width: menuWidth - 28,
            child: Text(
              desc,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      if (control.description != null && control.description!.trim().isNotEmpty)
        const Divider(height: 1),
      for (final choice in control.flatOptions)
        _buildChoiceItem(context, choice, menuWidth),
      for (var g = 0; g < control.groups.length; g++) ...[
        if (g > 0) const Divider(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Text(
            control.groups[g].name,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final choice in control.groups[g].options)
          _buildChoiceItem(context, choice, menuWidth),
      ],
    ];

    return MenuAnchor(
      crossAxisUnconstrained: false,
      style: MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(menuWidth, menuHeight)),
      ),
      menuChildren: children,
      builder: (context, controller, _) {
        final button = TextButton(
          onPressed: interactive
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: StudioMenuLabel(
            leading: Icon(_categoryIcon(control.category), size: 15),
            label: '${control.name} · ${control.currentLabel}',
            enabled: interactive,
            maxWidth: maxLabelWidth,
          ),
        );
        final tooltip = control.description?.trim();
        if (tooltip == null || tooltip.isEmpty) {
          return button;
        }
        return Tooltip(message: tooltip, child: button);
      },
    );
  }

  Widget _buildChoiceItem(
    BuildContext context,
    AcpSelectChoicePresentation choice,
    double menuWidth,
  ) {
    final selected = choice.value == control.currentValue;
    return MenuItemButton(
      key: ValueKey(AcpViewKeyValues.configChoice(control.id, choice.value)),
      leadingIcon: Icon(
        selected ? Icons.check_rounded : null,
        size: 16,
        color: context.colors.primary,
      ),
      onPressed: interactive ? () => onSelected(choice.value) : null,
      child: SizedBox(
        width: (menuWidth - 64).clamp(120.0, 280.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              choice.name,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (choice.description case final desc? when desc.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  desc,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BooleanConfigChip extends StatelessWidget {
  const _BooleanConfigChip({
    super.key,
    required this.control,
    required this.interactive,
    required this.onChanged,
  });

  final AcpBooleanConfigControl control;
  final bool interactive;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = control.currentValue;
    final colors = context.colors;
    final bg = active
        ? StudioTone.brand.background(context)
        : colors.surfaceContainerLow;
    final fg = active
        ? StudioTone.brand.foreground(context)
        : colors.onSurfaceVariant;

    final pill = Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        side: BorderSide(
          color: active
              ? colors.primary.withValues(alpha: 0.45)
              : colors.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        onTap: interactive ? () => onChanged(!active) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 14,
                color: interactive
                    ? (active ? colors.primary : colors.onSurfaceVariant)
                    : colors.onSurface.withValues(alpha: 0.38),
              ),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  control.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelMedium?.copyWith(
                    color: interactive
                        ? fg
                        : colors.onSurface.withValues(alpha: 0.38),
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final tooltip = control.description?.trim();
    if (tooltip == null || tooltip.isEmpty) return pill;
    return Tooltip(message: tooltip, child: pill);
  }
}

class _LegacyModeAnchor extends StatelessWidget {
  const _LegacyModeAnchor({
    super.key,
    required this.control,
    required this.interactive,
    required this.maxLabelWidth,
    required this.onSelected,
  });

  final AcpLegacyModeConfigControl control;
  final bool interactive;
  final double maxLabelWidth;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final menuWidth = (MediaQuery.sizeOf(context).width - 32).clamp(
      200.0,
      320.0,
    );
    return MenuAnchor(
      crossAxisUnconstrained: false,
      style: MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(menuWidth, 400)),
      ),
      menuChildren: [
        for (final mode in control.modes)
          MenuItemButton(
            key: ValueKey(
              AcpViewKeyValues.configChoice(control.id, mode.value),
            ),
            leadingIcon: Icon(
              mode.value == control.currentModeId ? Icons.check_rounded : null,
              size: 16,
              color: context.colors.primary,
            ),
            onPressed: interactive ? () => onSelected(mode.value) : null,
            child: SizedBox(
              width: (menuWidth - 64).clamp(120.0, 260.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(mode.name),
                  if (mode.description case final desc?
                      when desc.trim().isNotEmpty)
                    Text(
                      desc,
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: control.description ?? l10n.acpConfigModeFallbackLabel,
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
            leading: const Icon(Icons.layers_outlined, size: 15),
            label:
                '${l10n.acpConfigModeFallbackLabel} · ${control.currentModeLabel}',
            enabled: interactive,
            maxWidth: maxLabelWidth,
          ),
        ),
      ),
    );
  }
}

class _OverflowSettingsAnchor extends StatelessWidget {
  const _OverflowSettingsAnchor({
    required this.controls,
    required this.interactive,
    required this.onSelectValue,
    required this.onBooleanChanged,
    required this.onSelectLegacyMode,
  });

  final List<AcpConfigControlPresentation> controls;
  final bool interactive;
  final void Function(String configId, String valueId) onSelectValue;
  final void Function(String configId, bool value) onBooleanChanged;
  final ValueChanged<String> onSelectLegacyMode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sheetWidth = (MediaQuery.sizeOf(context).width - 32).clamp(
      220.0,
      340.0,
    );
    return MenuAnchor(
      key: const ValueKey(AcpViewKeyValues.configOverflow),
      crossAxisUnconstrained: false,
      style: MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(sheetWidth, 440)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
      ),
      menuChildren: [
        for (var i = 0; i < controls.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          SizedBox(
            width: sheetWidth - 24,
            child: _OverflowControlItem(
              control: controls[i],
              interactive: interactive,
              onSelectValue: onSelectValue,
              onBooleanChanged: onBooleanChanged,
              onSelectLegacyMode: onSelectLegacyMode,
            ),
          ),
        ],
      ],
      builder: (context, controller, _) => TextButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: StudioMenuLabel(
          leading: const Icon(Icons.tune_rounded, size: 15),
          label: l10n.acpConfigMoreCountLabel(controls.length),
          enabled: true,
          maxWidth: 150,
        ),
      ),
    );
  }
}

class _OverflowControlItem extends StatelessWidget {
  const _OverflowControlItem({
    required this.control,
    required this.interactive,
    required this.onSelectValue,
    required this.onBooleanChanged,
    required this.onSelectLegacyMode,
  });

  final AcpConfigControlPresentation control;
  final bool interactive;
  final void Function(String configId, String valueId) onSelectValue;
  final void Function(String configId, bool value) onBooleanChanged;
  final ValueChanged<String> onSelectLegacyMode;

  @override
  Widget build(BuildContext context) => switch (control) {
    final AcpSelectConfigControl select => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SelectConfigAnchor(
          key: ValueKey(AcpViewKeyValues.configControl(select.id)),
          control: select,
          interactive: interactive,
          maxLabelWidth: 240,
          onSelected: (valueId) => onSelectValue(select.id, valueId),
        ),
        if (select.description case final desc? when desc.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Text(
              desc,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    ),
    final AcpBooleanConfigControl toggle => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                toggle.name,
                style: context.text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (toggle.description case final desc?
                  when desc.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    desc,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Switch(
          key: ValueKey(AcpViewKeyValues.configControl(toggle.id)),
          value: toggle.currentValue,
          onChanged: interactive
              ? (next) => onBooleanChanged(toggle.id, next)
              : null,
        ),
      ],
    ),
    final AcpLegacyModeConfigControl mode => _LegacyModeAnchor(
      key: const ValueKey(AcpViewKeyValues.configLegacyMode),
      control: mode,
      interactive: interactive,
      maxLabelWidth: 240,
      onSelected: onSelectLegacyMode,
    ),
  };
}
