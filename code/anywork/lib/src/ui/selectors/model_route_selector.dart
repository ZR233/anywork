import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/studio_l10n.dart';
import '../branding/account_brand.dart';
import '../menus/studio_menu_label.dart';
import 'model_capability_card.dart';
import 'model_selection_option.dart';

export 'model_selection_option.dart';

typedef ModelSelectionOptionKeyBuilder = Key Function(
  ModelSelectionOption option,
);

/// Account-grouped, controlled model picker. Its owner supplies eligible options
/// and handles asynchronous action outcomes; the View never selects a fallback,
/// computes model policy or interprets a command result.
class ModelRouteSelector extends StatefulWidget {
  ModelRouteSelector({
    required List<ModelSelectionOption> options,
    required this.accountId,
    required this.modelId,
    required this.onSelected,
    required this.fieldLabel,
    required this.selectorKey,
    this.unresolvedLabel,
    this.enabled = true,
    this.tooltip,
    this.onBlockedTap,
    this.labelMaxWidth = 180,
    this.optionKeyBuilder,
    super.key,
  }) : options = List.unmodifiable(options);

  final List<ModelSelectionOption> options;
  final String accountId;
  final String modelId;
  final FutureOr<void> Function(ModelSelectionOption option) onSelected;
  final String fieldLabel;
  final Key selectorKey;
  final String? unresolvedLabel;
  final bool enabled;
  final String? tooltip;
  final VoidCallback? onBlockedTap;
  final double labelMaxWidth;
  final ModelSelectionOptionKeyBuilder? optionKeyBuilder;

  @override
  State<ModelRouteSelector> createState() => _ModelRouteSelectorState();
}

class _ModelRouteSelectorState extends State<ModelRouteSelector> {
  final MenuController _controller = MenuController();
  final FocusNode _triggerFocus = FocusNode(debugLabel: 'model-route-trigger');
  final GlobalKey _selectedRowKey = GlobalKey(debugLabel: 'model-selected-row');

  @override
  void dispose() {
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.options
        .where(
          (option) =>
              option.accountId == widget.accountId &&
              option.modelId == widget.modelId,
        )
        .firstOrNull;
    final selectedLabel =
        selected?.displayName ??
        widget.unresolvedLabel ??
        (widget.modelId.isEmpty && widget.options.isEmpty
            ? context.l10n.modelTextFilterEmpty
            : widget.modelId);
    final canSelect = widget.enabled && widget.options.isNotEmpty;
    final viewport = MediaQuery.sizeOf(context);
    final menuSize = Size(
      math.min(420.0, math.max(0.0, viewport.width - 24)),
      math.min(480.0, math.max(0.0, viewport.height - 32)),
    );
    final contentWidth = math.max(0.0, menuSize.width - 32);

    return MenuAnchor(
      key: widget.selectorKey,
      controller: _controller,
      childFocusNode: _triggerFocus,
      style: MenuStyle(maximumSize: WidgetStatePropertyAll(menuSize)),
      alignmentOffset: const Offset(6, 6),
      onOpen: _keepSelectedItemVisible,
      menuChildren: _menuChildren(context, contentWidth, selected),
      child: Tooltip(
        message: widget.tooltip ?? widget.unresolvedLabel ?? widget.fieldLabel,
        child: Semantics(
          button: true,
          enabled: canSelect || widget.onBlockedTap != null,
          label: widget.fieldLabel,
          child: TextButton(
            focusNode: _triggerFocus,
            onPressed: canSelect
                ? () {
                    if (_controller.isOpen) {
                      _controller.close();
                    } else {
                      _controller.open();
                    }
                  }
                : widget.onBlockedTap,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              side: BorderSide.none,
            ),
            child: StudioMenuLabel(
              label: selectedLabel,
              enabled: canSelect,
              maxWidth: widget.labelMaxWidth,
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
    final groups = <String, List<ModelSelectionOption>>{};
    for (final option in widget.options) {
      groups.putIfAbsent(option.accountId, () => []).add(option);
    }
    return [
      for (final group in groups.values) ...[
        _AccountHeading(option: group.first, width: contentWidth),
        for (final option in group)
          _modelRow(context, option, selected, contentWidth),
      ],
    ];
  }

  Widget _modelRow(
    BuildContext context,
    ModelSelectionOption option,
    ModelSelectionOption? selected,
    double contentWidth,
  ) {
    final isSelected = option == selected;
    final routeToken = jsonEncode(<String>[option.accountId, option.modelId]);
    final modalities = option.descriptor.capabilities.input
        .map((capability) => capability.modality)
        .toSet();
    final row = MenuItemButton(
      key:
          widget.optionKeyBuilder?.call(option) ??
          ValueKey<String>('model-$routeToken'),
      overflowAxis: Axis.vertical,
      onPressed: widget.enabled ? () => _select(option) : null,
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: isSelected
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
                        key: ValueKey<String>('model-$routeToken-capabilities'),
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          for (final modality in modalities)
                            ModelCapabilityCard(modality: modality),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return isSelected ? KeyedSubtree(key: _selectedRowKey, child: row) : row;
  }

  void _select(ModelSelectionOption option) {
    // Smart/VM owns the future and its error presentation. No catch/report-as-
    // success path lives in the View, and no result changes this selection.
    final result = widget.onSelected(option);
    if (result is Future<void>) unawaited(result);
  }

  void _keepSelectedItemVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.isOpen) return;
      final context = _selectedRowKey.currentContext;
      final renderObject = context?.findRenderObject();
      final scrollable = context == null ? null : Scrollable.maybeOf(context);
      if (renderObject == null ||
          !renderObject.attached ||
          scrollable == null ||
          !scrollable.position.hasContentDimensions) {
        return;
      }
      scrollable.position.ensureVisible(renderObject, duration: Duration.zero);
    });
  }
}

class _AccountHeading extends StatelessWidget {
  const _AccountHeading({required this.option, required this.width});

  final ModelSelectionOption option;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Semantics(
          header: true,
          child: Row(
            children: [
              AccountBrandMark(
                iconKey: option.accountIconKey,
                fallbackName: option.accountName,
                size: 14,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  option.accountName,
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
}
