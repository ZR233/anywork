import 'dart:async';

import 'package:anywork_client/model_directory.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/models/studio_models.dart';
import '../l10n/studio_l10n.dart';
import 'account_brand.dart';
import 'studio_driver_keys.dart';
import 'studio_menu_label.dart';

/// A catalog model paired with its account-instance identity for selection.
///
/// Display names are presentation only. Equality deliberately follows the
/// canonical route identity: account ID plus configured modelId.
class ModelSelectionOption {
  const ModelSelectionOption({
    required this.accountId,
    required this.accountName,
    required this.descriptor,
    this.accountIconKey,
  });

  final String accountId;
  final String accountName;
  final String? accountIconKey;
  final AccountModelView descriptor;

  String get modelId => descriptor.modelId;

  String get displayName => descriptor.displayName.isEmpty
      ? descriptor.modelId
      : descriptor.displayName;

  List<String> get reasoningEfforts => descriptor.reasoningEfforts;

  String get defaultReasoningEffort => descriptor.defaultReasoningEffort;

  List<ModelInputCapabilityView> get inputCapabilities =>
      descriptor.inputCapabilities;

  @override
  bool operator ==(Object other) =>
      other is ModelSelectionOption &&
      other.accountId == accountId &&
      other.modelId == modelId;

  @override
  int get hashCode => Object.hash(accountId, modelId);
}

/// Localize backend-owned exclusions without evaluating capabilities or budgets again.
String? modelTextFilterMessage(BuildContext context, AccountModelView? model) {
  if (model == null) return null;
  if (model.matchesType(ModelType.text)) {
    return model.enabled ? null : context.l10n.settingsModelDisabled;
  }
  final exclusions = model.supportFor(ModelType.text)?.exclusions;
  final reasons = exclusions == null
      ? context.l10n.settingsModelParametersUnknown
      : exclusions
            .map(
              (reason) => switch (reason) {
                ModelTypeExclusion.textInputUnsupported =>
                  context.l10n.modelTextInputUnsupported,
                ModelTypeExclusion.textOutputUnsupported =>
                  context.l10n.modelTextOutputUnsupported,
                ModelTypeExclusion.contextParametersInvalid =>
                  context.l10n.modelContextParametersInvalid,
                ModelTypeExclusion.inputBudgetExhausted =>
                  context.l10n.modelInputBudgetExhausted,
                ModelTypeExclusion.contextWindowUnknown =>
                  context.l10n.modelContextWindowUnknown,
              },
            )
            .join(' / ');
  return context.l10n.modelTextFilterExcluded(
    model.displayName.isEmpty ? model.modelId : model.displayName,
    reasons,
  );
}

/// Queries the canonical type classification; presentation only deduplicates routes.
List<ModelSelectionOption> buildModelSelectionOptions(
  List<ModelSelectionAccount> accounts, {
  ModelType? type,
}) {
  return {
    for (final account in accounts)
      for (final model in account.modelsFor(type: type))
        if (model.modelId.isNotEmpty)
          (account.id, model.modelId): ModelSelectionOption(
            accountId: account.id,
            accountName: account.name,
            accountIconKey: account.iconKey,
            descriptor: model,
          ),
  }.values.toList(growable: false);
}

typedef ModelSelectionOptionKeyBuilder = Key Function(
  ModelSelectionOption option,
);

/// Shared compact model picker for session routes and Agent settings.
///
/// The menu is a plain Material [MenuAnchor] with [MenuItemButton] rows:
/// anchoring, window clamping, keyboard navigation, Escape and outside-tap
/// closes, and focus handling are framework behavior. This widget only owns
/// presentation (account-grouped rows, capability cards, selected hints) and
/// reports a selection; it never chooses a fallback route or persists the
/// result. Callers own the surrounding field description and validation hints
/// because the trigger itself carries no form decoration.
class ModelRouteSelector extends StatefulWidget {
  const ModelRouteSelector({
    required this.options,
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
  });

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

  /// Caps the quiet trigger label so long model names ellipsize instead of
  /// stretching the surrounding row.
  final double labelMaxWidth;
  final ModelSelectionOptionKeyBuilder? optionKeyBuilder;

  @override
  State<ModelRouteSelector> createState() => _ModelRouteSelectorState();
}

class _ModelRouteSelectorState extends State<ModelRouteSelector> {
  final MenuController _controller = MenuController();
  final FocusNode _triggerFocus = FocusNode(debugLabel: 'model-route-trigger');

  @override
  void dispose() {
    _triggerFocus.dispose();
    super.dispose();
  }

  /// Scroll anchor attached to the selected row so opening the menu can bring
  /// it into view. Retargeted on every build; the menu is transient, so a key
  /// moving between rows never needs element-stable topology.
  final GlobalKey _selectedRowKey = GlobalKey(debugLabel: 'model-selected-row');

  @override
  Widget build(BuildContext context) {
    final selected = _findOption(
      widget.options,
      widget.accountId,
      widget.modelId,
    );
    final selectedLabel =
        selected?.displayName ??
        widget.unresolvedLabel ??
        (widget.modelId.isEmpty && widget.options.isEmpty
            ? context.l10n.modelTextFilterEmpty
            : widget.modelId);
    final canSelect = widget.enabled && widget.options.isNotEmpty;
    final menuSize = _menuSize(context);
    final contentWidth = math.max(0.0, menuSize.width - 32);

    return MenuAnchor(
      key: widget.selectorKey,
      controller: _controller,
      childFocusNode: _triggerFocus,
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
    final tooltip =
        widget.tooltip ?? widget.unresolvedLabel ?? widget.fieldLabel;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: widget.enabled || widget.onBlockedTap != null,
        label: tooltip,
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
    );
  }

  List<Widget> _menuChildren(
    BuildContext context,
    double contentWidth,
    ModelSelectionOption? selected,
  ) {
    final children = <Widget>[];
    for (final group in _groups()) {
      children.add(_accountHeading(context, contentWidth, group));
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

  /// Reports a row selection after [MenuItemButton] performs its normal close
  /// and trigger-focus restoration. An async Bridge command must not become an
  /// unobserved future; the repository owns user-facing failure state, so
  /// unexpected programmer errors stay diagnosable through FlutterError.
  void _select(ModelSelectionOption option) {
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

  List<_AccountModelGroup> _groups() {
    final groups = <String, _AccountModelGroup>{};
    for (final option in widget.options) {
      groups
          .putIfAbsent(option.accountId, () => _AccountModelGroup(option))
          .options
          .add(option);
    }
    return groups.values.toList(growable: false);
  }

  Key _optionKey(ModelSelectionOption option) =>
      widget.optionKeyBuilder?.call(option) ??
      StudioDriverKeys.modelOption(option.accountId, option.modelId);

  static ModelSelectionOption? _findOption(
    List<ModelSelectionOption> options,
    String accountId,
    String modelId,
  ) {
    return options
        .where(
          (option) =>
              option.accountId == accountId && option.modelId == modelId,
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

  static Widget _accountHeading(
    BuildContext context,
    double contentWidth,
    _AccountModelGroup group,
  ) {
    return SizedBox(
      width: contentWidth,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Semantics(
          header: true,
          child: Row(
            children: [
              AccountBrandMark(
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
                    option.accountId,
                    option.modelId,
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

class _AccountModelGroup {
  _AccountModelGroup(ModelSelectionOption option)
    : name = option.accountName,
      iconKey = option.accountIconKey;

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
