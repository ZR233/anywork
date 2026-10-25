import 'dart:async';

import 'package:flutter/material.dart';
import 'package:anywork_client/studio_client.dart' show ModelRouteQueries;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/model_route_selector.dart';
import '../../shared/studio_driver_keys.dart';
import '../../shared/studio_menu_label.dart';
import 'status_view.dart';

/// One row of a [_QuietSelectorMenu].
class _QuietMenuItem<T> {
  const _QuietMenuItem({
    required this.value,
    required this.child,
    this.enabled = true,
    this.selected = false,
    this.itemKey,
  });

  /// The value reported through [StudioMenuLabel]-style selectors when this
  /// row is activated.
  final T value;

  /// Row content inside the menu.
  final Widget child;

  /// Whether the row can be activated.
  final bool enabled;

  /// Marks the row as the current choice.
  final bool selected;

  /// Stable interaction key for the row.
  final Key? itemKey;
}

/// Quiet-label menu shared by the mode, workspace and effort selectors.
///
/// Plain Material [MenuAnchor] composition: anchoring, keyboard navigation,
/// Escape/outside-tap closes and focus handling are framework behavior. This
/// widget only contributes the borderless [StudioMenuLabel] trigger look and
/// the selected-row presentation.
class _QuietSelectorMenu<T> extends StatefulWidget {
  const _QuietSelectorMenu({
    required this.tooltip,
    required this.items,
    required this.child,
    this.onSelected,
    this.enabled = true,
    this.onBlockedTap,
    super.key,
  });

  /// Tooltip and semantics label for the trigger.
  final String tooltip;

  /// Current rows; refreshed with every owner rebuild, including while open.
  final List<_QuietMenuItem<T>> items;

  /// Reported with the activated row's value.
  final ValueChanged<T>? onSelected;

  /// Quiet-label trigger content.
  final Widget child;

  /// Whether rows can be activated and the trigger can open the menu.
  final bool enabled;

  /// Invoked instead of opening when [enabled] is false.
  final VoidCallback? onBlockedTap;

  @override
  State<_QuietSelectorMenu<T>> createState() => _QuietSelectorMenuState<T>();
}

class _QuietSelectorMenuState<T> extends State<_QuietSelectorMenu<T>> {
  final MenuController _controller = MenuController();
  final FocusNode _triggerFocus = FocusNode(
    debugLabel: 'session-selector-trigger',
  );

  bool get _canOpen => widget.enabled && widget.items.isNotEmpty;

  @override
  void dispose() {
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _controller,
      // RawMenuAnchor transfers focus here on pointer-open. Without the same
      // node on the trigger, Escape still reaches the previously focused input.
      childFocusNode: _triggerFocus,
      alignmentOffset: const Offset(6, 6),
      menuChildren: [for (final item in widget.items) _buildRow(context, item)],
      child: _buildTrigger(),
    );
  }

  Widget _buildTrigger() {
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: widget.enabled || widget.onBlockedTap != null,
        label: widget.tooltip,
        child: TextButton(
          focusNode: _triggerFocus,
          onPressed: _canOpen
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
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, _QuietMenuItem<T> item) {
    final selected = item.selected;
    return MenuItemButton(
      key: item.itemKey,
      // Vertical overflow hands finite width to rows with flexible content,
      // the same axis Material popup menus use.
      overflowAxis: Axis.vertical,
      onPressed: widget.enabled && item.enabled
          ? () => widget.onSelected?.call(item.value)
          : null,
      style: selected
          ? ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
            )
          : null,
      child: Semantics(selected: selected, child: item.child),
    );
  }
}

/// 选择器被锁定时向用户说明原因：优先交给宿主提示区，否则就地弹一次 SnackBar。
void _explainSelection(
  BuildContext context,
  ValueChanged<String>? onExplain,
  String message,
) {
  if (onExplain case final callback?) {
    callback(message);
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message), showCloseIcon: true));
}

/// 根会话的模式选择器；起始页传新会话草稿，状态栏传当前 Thread 的 mode。
class SessionModeSelector extends ConsumerWidget {
  const SessionModeSelector({
    required this.mode,
    required this.onSelected,
    this.enabled = true,
    this.snapshotDisplayName,
    this.usesSnapshot = false,
    this.lockedHint,
    this.onExplain,
    super.key,
  });

  final ThreadModeId mode;
  final ValueChanged<ThreadModeId> onSelected;
  final bool enabled;
  final String? snapshotDisplayName;
  final bool usesSnapshot;

  /// 禁用原因；缺省按“运行或工作流活动期间无法切换”解释。
  final String? lockedHint;

  /// 宿主提示区；缺省就地弹一次可关闭提示。
  final ValueChanged<String>? onExplain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只订阅 Mode catalog 本身；无关领域事件不重建该选择器。
    final discovered = ref.watch(statusModeCatalogProvider);
    final options = discovered.isEmpty
        ? ThreadModeId.values
        : discovered.map((descriptor) => descriptor.mode).toList();
    if (!options.contains(mode)) options.add(mode);
    final selectedLabel = discovered
        .where((descriptor) => descriptor.id == mode.id)
        .firstOrNull
        ?.displayName;
    final deleted =
        discovered.isNotEmpty && !discovered.any((item) => item.id == mode.id);
    return _QuietSelectorMenu<ThreadModeId>(
      key: StudioDriverKeys.sessionMode,
      tooltip: deleted
          ? (usesSnapshot
                ? context.l10n.modeDeletedUsingSnapshot
                : context.l10n.modeDeletedChooseAnother)
          : enabled
          ? context.l10n.statusSessionMode
          : lockedHint ?? context.l10n.statusSessionModeLocked,
      enabled: enabled,
      // 与模型、强度选择器同一规则：锁定必须解释，不能静默吞掉点击。
      onBlockedTap: enabled
          ? null
          : () => _explainSelection(
              context,
              onExplain,
              lockedHint ?? context.l10n.statusSessionModeLocked,
            ),
      onSelected: onSelected,
      items: [
        for (final option in options)
          _QuietMenuItem<ThreadModeId>(
            value: option,
            enabled:
                discovered.any((item) => item.id == option.id) ||
                discovered.isEmpty,
            selected: option == mode,
            itemKey: StudioDriverKeys.sessionModeOption(option.name),
            child: Row(
              children: [
                Icon(sessionModeIcon(option), size: 18),
                const SizedBox(width: 10),
                Text(
                  discovered
                          .where((descriptor) => descriptor.id == option.id)
                          .firstOrNull
                          ?.displayName ??
                      context.compileModeLabel(option),
                ),
              ],
            ),
          ),
      ],
      child: StudioMenuLabel(
        key: StudioDriverKeys.sessionModeLabel,
        label:
            selectedLabel ??
            (deleted
                ? '${snapshotDisplayName ?? context.compileModeLabel(mode)} · ${usesSnapshot ? context.l10n.modeSnapshotBadge : context.l10n.modeDeletedBadge}'
                : context.compileModeLabel(mode)),
        enabled: enabled,
        maxWidth: 96,
      ),
    );
  }
}

typedef ModelSelectionChanged = FutureOr<void> Function(
  String accountId,
  String model,
);

typedef EffortSelectionChanged = FutureOr<void> Function(String effort);

/// 根会话或新建会话草稿的模型选择器。
class ModelRoleSelector extends StatelessWidget {
  const ModelRoleSelector({
    required this.accounts,
    required this.accountId,
    required this.modelId,
    required this.effort,
    this.onModelSelected,
    this.enabled = true,
    this.pending = false,
    this.available = true,
    this.unavailableReason,
    this.blockedReason,
    this.onExplain,
    super.key,
  });

  final List<AccountSettingsView> accounts;
  final String accountId;
  final String modelId;
  final String? effort;

  final ModelSelectionChanged? onModelSelected;
  final bool enabled;

  /// Kept in the projection for status/optimistic rendering. Selection stays
  /// enabled while pending so the coordinator can supersede an older intent.
  final bool pending;
  final bool available;
  final String? unavailableReason;
  final String? blockedReason;
  final ValueChanged<String>? onExplain;

  @override
  Widget build(BuildContext context) {
    final options = modelOptions(accounts);
    final current = modelForRoute(accounts, accountId, modelId);
    final filterMessage = modelTextFilterMessage(context, current?.descriptor);
    final warning = !available || current == null || filterMessage != null;
    // 禁用必须先给出原因：未就绪/提交进行中优先，其次才是空模型目录的筛选说明，
    // 否则点击会被静默吞掉。
    final selectionBlockedReason =
        blockedReason ??
        (!enabled ? context.l10n.statusSelectorsNotReady : null) ??
        (options.isEmpty ? context.l10n.modelTextFilterEmpty : null);
    void explain(String message) =>
        _explainSelection(context, onExplain, message);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (warning)
          SizedBox.square(
            dimension: 32,
            child: IconButton(
              key: const ValueKey('model-route-warning'),
              padding: EdgeInsets.zero,
              tooltip:
                  filterMessage ?? context.l10n.statusModelRouteUnavailable,
              onPressed: () => explain(
                filterMessage ??
                    (unavailableReason?.isNotEmpty == true
                        ? context.l10n.statusModelRouteUnavailableDetail(
                            unavailableReason!,
                          )
                        : context.l10n.statusModelRouteUnavailableFallback),
              ),
              icon: Icon(
                Icons.warning_amber_outlined,
                size: 15,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        if (pending)
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
        ModelRouteSelector(
          selectorKey: StudioDriverKeys.model,
          options: options,
          accountId: accountId,
          modelId: modelId,
          fieldLabel: context.l10n.statusPlannerModel,
          tooltip:
              selectionBlockedReason ??
              filterMessage ??
              context.l10n.statusPlannerModel,
          unresolvedLabel: filterMessage,
          labelMaxWidth: 140,
          // Pending is an optimistic projection, not a lock.  The controller
          // supersedes older route intents by stable target identity, so users
          // can select A -> B -> C without waiting for each Bridge round trip.
          enabled: enabled && selectionBlockedReason == null,
          onBlockedTap: selectionBlockedReason == null
              ? null
              : () => explain(selectionBlockedReason),
          onSelected: (option) async {
            await onModelSelected?.call(option.accountId, option.modelId);
          },
          optionKeyBuilder: (option) =>
              StudioDriverKeys.modelOption(option.accountId, option.modelId),
        ),
      ],
    );
  }
}

/// 根会话或 Mode 默认路由的思考强度选择器。
class ReasoningEffortSelector extends StatelessWidget {
  const ReasoningEffortSelector({
    required this.accounts,
    required this.accountId,
    required this.modelId,
    required this.effort,
    this.onEffortSelected,
    this.enabled = true,
    this.pending = false,
    this.blockedReason,
    this.onExplain,
    super.key,
  });

  final List<AccountSettingsView> accounts;
  final String accountId;
  final String modelId;
  final String? effort;
  final EffortSelectionChanged? onEffortSelected;
  final bool enabled;
  final bool pending;
  final String? blockedReason;
  final ValueChanged<String>? onExplain;

  @override
  Widget build(BuildContext context) {
    final currentModel = modelForRoute(accounts, accountId, modelId);
    final efforts = currentModel?.reasoningEfforts ?? const [];
    final selectedEffort = effort?.isNotEmpty == true
        ? effort
        : ModelRouteQueries.effortAfterModelSelection(
            currentModel?.descriptor,
            null,
          );
    if (selectedEffort == null && efforts.isEmpty) {
      return const SizedBox.shrink();
    }
    final unavailable =
        selectedEffort == null || !efforts.contains(selectedEffort);
    final label = unavailable
        ? context.l10n.settingsAgentRouteUnavailable(
            selectedEffort ?? context.l10n.settingsMissing,
          )
        : selectedEffort;
    final selectionEnabled =
        enabled &&
        currentModel != null &&
        efforts.isNotEmpty &&
        blockedReason == null;
    return _QuietSelectorMenu<String>(
      key: StudioDriverKeys.reasoningEffort,
      tooltip: blockedReason ?? context.l10n.statusReasoningEffort,
      enabled: selectionEnabled,
      // 与模型选择器同一规则：禁用必须解释，不能静默吞掉点击。
      onBlockedTap: blockedReason != null
          ? () => _explainSelection(context, onExplain, blockedReason!)
          : !enabled
          ? () => _explainSelection(
              context,
              onExplain,
              context.l10n.statusSelectorsNotReady,
            )
          : null,
      onSelected: (nextEffort) {
        final result = onEffortSelected?.call(nextEffort);
        if (result is Future<void>) unawaited(result);
      },
      items: [
        for (final effort in efforts)
          _QuietMenuItem<String>(
            value: effort,
            selected: effort == selectedEffort,
            itemKey: StudioDriverKeys.reasoningEffortOption(effort),
            child: Text(effort),
          ),
      ],
      child: _ControlItem(label: label, enabled: selectionEnabled),
    );
  }
}

class _ControlItem extends StatelessWidget {
  const _ControlItem({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StudioMenuLabel(
          key: StudioDriverKeys.reasoningEffortLabel,
          label: label,
          enabled: enabled,
          maxWidth: 140,
        ),
      ],
    );
  }
}

IconData sessionModeIcon(ThreadModeId mode) {
  return mode == ThreadModeId.simple ? Icons.flash_on : Icons.route_outlined;
}

ModelSelectionOption? modelForRoute(
  List<AccountSettingsView> accounts,
  String accountId,
  String modelId,
) {
  final options = buildModelSelectionOptions(accounts);
  return options
      .where(
        (option) => option.accountId == accountId && option.modelId == modelId,
      )
      .firstOrNull;
}

List<ModelSelectionOption> modelOptions(List<AccountSettingsView> accounts) =>
    buildModelSelectionOptions(accounts, type: ModelType.text);
