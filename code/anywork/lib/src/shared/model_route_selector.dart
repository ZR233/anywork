import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/models/studio_models.dart';
import '../l10n/studio_l10n.dart';
import 'provider_brand.dart';
import 'studio_driver_keys.dart';
import 'studio_menu_label.dart';

/// A catalog model paired with its provider-instance identity for selection.
///
/// Display names are presentation only. Equality deliberately follows the
/// canonical route identity: provider ID plus model slug.
class ModelSelectionOption {
  const ModelSelectionOption({
    required this.providerId,
    required this.providerName,
    required this.descriptor,
    this.providerIconKey,
  });

  final String providerId;
  final String providerName;
  final String? providerIconKey;
  final ProviderModelView descriptor;

  String get model => descriptor.slug;

  String get displayName =>
      descriptor.displayName.isEmpty ? descriptor.slug : descriptor.displayName;

  List<String> get reasoningEfforts => descriptor.reasoningEfforts;

  String get defaultReasoningEffort => descriptor.defaultReasoningEffort;

  List<ModelInputCapabilityView> get inputCapabilities =>
      descriptor.inputCapabilities;

  @override
  bool operator ==(Object other) =>
      other is ModelSelectionOption &&
      other.providerId == providerId &&
      other.model == model;

  @override
  int get hashCode => Object.hash(providerId, model);
}

/// Builds presentation options while leaving each caller in charge of which
/// catalog models (including any existing fallback) are selectable.
List<ModelSelectionOption> buildModelSelectionOptions(
  List<ProviderSettingsView> providers, {
  required List<ProviderModelView> Function(ProviderSettingsView provider)
  modelsForProvider,
}) {
  return [
    for (final provider in providers)
      for (final model in modelsForProvider(provider))
        ModelSelectionOption(
          providerId: provider.id,
          providerName: provider.name,
          providerIconKey: provider.iconKey,
          descriptor: model,
        ),
  ];
}

typedef ModelSelectionOptionKeyBuilder = Key Function(
  ModelSelectionOption option,
);

/// Shared compact model picker for session routes and Agent settings.
///
/// The menu is a plain Material [MenuAnchor] with [MenuItemButton] rows:
/// anchoring, window clamping, keyboard navigation, Escape and outside-tap
/// closes, and focus handling are framework behavior. This widget only owns
/// presentation (provider-grouped rows, capability cards, selected hints) and
/// reports a selection; it never chooses a fallback route or persists the
/// result. Callers own the surrounding field description and validation hints
/// because the trigger itself carries no form decoration.
class ModelRouteSelector extends StatefulWidget {
  const ModelRouteSelector({
    required this.options,
    required this.providerId,
    required this.model,
    required this.onSelected,
    required this.fieldLabel,
    required this.selectorKey,
    this.unresolvedLabel,
    this.showUnresolvedOption = false,
    this.enabled = true,
    this.tooltip,
    this.onBlockedTap,
    this.labelMaxWidth = 180,
    this.optionKeyBuilder,
    super.key,
  });

  final List<ModelSelectionOption> options;
  final String providerId;
  final String model;
  final FutureOr<void> Function(ModelSelectionOption option) onSelected;
  final String fieldLabel;
  final Key selectorKey;
  final String? unresolvedLabel;
  final bool showUnresolvedOption;
  final bool enabled;
  final String? tooltip;
  final VoidCallback? onBlockedTap;

  /// Caps the quiet trigger label so long model names ellipsize instead of
  /// stretching the surrounding row.
  final double labelMaxWidth;
  final ModelSelectionOptionKeyBuilder? optionKeyBuilder;

  @override
  State<ModelRouteSelector> createState() => _ModelRouteSelectorState();
}

class _ModelRouteSelectorState extends State<ModelRouteSelector> {
  final MenuController _controller = MenuController();
  final FocusNode _triggerFocusNode = FocusNode(
    debugLabel: 'model-route-selector',
  );

  /// Scroll anchor attached to the selected row so opening the menu can bring
  /// it into view. Retargeted on every build; the menu is transient, so a key
  /// moving between rows never needs element-stable topology.
  final GlobalKey _selectedRowKey = GlobalKey(debugLabel: 'model-selected-row');

  @override
  void dispose() {
    _triggerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _findOption(
      widget.options,
      widget.providerId,
      widget.model,
    );
    final selectedLabel =
        selected?.displayName ?? widget.unresolvedLabel ?? widget.model;
    final canSelect = widget.enabled && widget.options.isNotEmpty;
    final menuSize = _menuSize(context);
    final contentWidth = math.max(0.0, menuSize.width - 32);

    return MenuAnchor(
      key: widget.selectorKey,
      controller: _controller,
      childFocusNode: _triggerFocusNode,
      style: MenuStyle(maximumSize: WidgetStatePropertyAll(menuSize)),
      alignmentOffset: const Offset(6, 6),
      onOpen: _keepSelectedItemVisible,
      menuChildren: _menuChildren(context, contentWidth, selected),
      child: _buildTrigger(context, canSelect, selectedLabel),
    );
  }

  Widget _buildTrigger(
    BuildContext context,
    bool canSelect,
    String selectedLabel,
  ) {
    final tooltip = widget.tooltip ?? widget.fieldLabel;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: widget.enabled || widget.onBlockedTap != null,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            focusNode: _triggerFocusNode,
            onTap: canSelect
                ? () {
                    if (_controller.isOpen) {
                      _controller.close();
                    } else {
                      _controller.open();
                    }
                  }
                : widget.onBlockedTap,
            child: ExcludeFocus(
              child: StudioMenuLabel(
                label: selectedLabel,
                enabled: canSelect,
                maxWidth: widget.labelMaxWidth,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _menuChildren(
    BuildContext context,
    double contentWidth,
    ModelSelectionOption? selected,
  ) {
    final children = <Widget>[];
    if (widget.showUnresolvedOption &&
        selected == null &&
        widget.unresolvedLabel != null) {
      children.add(
        _unresolvedEntry(context, contentWidth, widget.unresolvedLabel!),
      );
    }
    for (final group in _groups()) {
      children.add(_providerHeading(context, contentWidth, group));
      for (final option in group.options) {
        final isSelected = option == selected;
        final row = MenuItemButton(
          key: _optionKey(option),
          // Vertical overflow lays the label out with a flex child and hands
          // finite width to rows with Expanded content, the same axis Material
          // popup menus use.
          overflowAxis: Axis.vertical,
          onPressed: () => _select(option),
          style: isSelected
              ? ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(
                    Theme.of(context).colorScheme.surfaceContainerHigh,
                  ),
                )
              : null,
          child: Semantics(
            selected: isSelected,
            child: SizedBox(
              width: contentWidth,
              child: _modelOptionContents(
                context,
                option,
                selected: isSelected,
              ),
            ),
          ),
        );
        children.add(
          isSelected ? KeyedSubtree(key: _selectedRowKey, child: row) : row,
        );
      }
    }
    return children;
  }

  /// Activates a row: closes the menu, restores trigger focus, and reports the
  /// selection. An async Bridge command must not become an unobserved future;
  /// the repository owns user-facing failure state, so unexpected programmer
  /// errors stay diagnosable through FlutterError.
  void _select(ModelSelectionOption option) {
    _controller.close();
    _triggerFocusNode.requestFocus();
    final result = widget.onSelected(option);
    if (result is Future<void>) {
      unawaited(
        result.catchError((Object error, StackTrace stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'anywork model route selector',
              context: ErrorDescription('dispatching a model selection'),
            ),
          );
        }),
      );
    }
  }

  /// Scrolls the menu's own list so the selected row is visible, without
  /// moving any ancestor scrollable (settings pages keep their position).
  void _keepSelectedItemVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _selectedRowKey.currentContext;
      final renderObject = context?.findRenderObject();
      final scrollable = context == null ? null : Scrollable.maybeOf(context);
      if (renderObject == null ||
          !renderObject.attached ||
          scrollable == null ||
          !scrollable.position.hasContentDimensions ||
          !mounted ||
          !_controller.isOpen) {
        return;
      }
      scrollable.position.ensureVisible(renderObject, duration: Duration.zero);
    });
  }

  List<_ProviderModelGroup> _groups() {
    final groups = <String, _ProviderModelGroup>{};
    for (final option in widget.options) {
      groups
          .putIfAbsent(option.providerId, () => _ProviderModelGroup(option))
          .options
          .add(option);
    }
    return groups.values.toList(growable: false);
  }

  Key _optionKey(ModelSelectionOption option) =>
      widget.optionKeyBuilder?.call(option) ??
      StudioDriverKeys.modelOption(option.providerId, option.model);

  static ModelSelectionOption? _findOption(
    List<ModelSelectionOption> options,
    String providerId,
    String model,
  ) {
    return options
        .where(
          (option) => option.providerId == providerId && option.model == model,
        )
        .firstOrNull;
  }

  static Size _menuSize(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    return Size(
      math.min(420.0, math.max(0.0, window.width - 24)),
      math.min(480.0, math.max(0.0, window.height - 32)),
    );
  }

  static Widget _providerHeading(
    BuildContext context,
    double contentWidth,
    _ProviderModelGroup group,
  ) {
    return SizedBox(
      width: contentWidth,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Semantics(
          header: true,
          child: Row(
            children: [
              ProviderBrandMark(
                iconKey: group.iconKey,
                fallbackName: group.name,
                size: 14,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _unresolvedEntry(
    BuildContext context,
    double contentWidth,
    String label,
  ) {
    return SizedBox(
      width: contentWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  static Widget _modelOptionContents(
    BuildContext context,
    ModelSelectionOption option, {
    required bool selected,
  }) {
    final modalities = option.inputCapabilities
        .map((capability) => capability.modality)
        .toSet();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          child: selected
              ? Icon(
                  Icons.check,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                option.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (modalities.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  key: StudioDriverKeys.modelCapabilityTags(
                    option.providerId,
                    option.model,
                  ),
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    for (final modality in modalities)
                      _CapabilityCard(modality: modality),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProviderModelGroup {
  _ProviderModelGroup(ModelSelectionOption option)
    : name = option.providerName,
      iconKey = option.providerIconKey;

  final String name;
  final String? iconKey;
  final List<ModelSelectionOption> options = [];
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.modality});

  final ModelModalityView modality;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelSmall;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 128),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _modalityIcon(modality),
                size: 13,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  context.modalityLabel(modality),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _modalityIcon(ModelModalityView modality) => switch (modality) {
    ModelModalityView.text => Icons.article_outlined,
    ModelModalityView.image => Icons.image_outlined,
    ModelModalityView.audio => Icons.graphic_eq,
    ModelModalityView.video => Icons.movie_outlined,
    ModelModalityView.file => Icons.attach_file,
  };
}
