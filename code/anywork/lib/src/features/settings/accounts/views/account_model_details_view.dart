import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../widgets/account_identity.dart';
import '../widgets/account_model_evaluations.dart';
import '../widgets/account_model_specifications.dart';
import '../widgets/account_sections.dart';

/// A full main-content page. Catalog and readout facts retain their distinct
/// owners; this view never queries or changes a model's identity.
class AccountModelDetailsView extends StatelessWidget {
  const AccountModelDetailsView({
    required this.value,
    required this.accountName,
    required this.onBack,
    required this.onRetry,
    required this.onEnabledChanged,
    required this.onFilterChanged,
    required this.onTabChanged,
    this.iconKey,
    this.tab = AccountModelTab.specifications,
    super.key,
  });
  final AccountModelPresentation value;
  final String accountName;
  final String? iconKey;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<AccountEvaluationFilter> onFilterChanged;
  final AccountModelTab tab;
  final ValueChanged<AccountModelTab> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final identity =
        '${value.key.account.kind.name}:${value.key.account.id}:${value.key.modelId}';
    return _ControlledModelTabs(
      key: ValueKey(identity),
      tab: tab,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: NestedScrollView(
          headerSliverBuilder: (headerContext, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            key: const ValueKey('account-model-back'),
                            onPressed: onBack,
                            icon: const Icon(Icons.arrow_back, size: 18),
                            label: Text(
                              l10n.accountsBackToAccount(accountName),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('account-model-retry'),
                        tooltip: l10n.accountsReadout,
                        onPressed: value.canLoadReadout && !value.readoutLoading
                            ? onRetry
                            : null,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: AccountIdentity(
                          name: value.name,
                          iconKey: iconKey,
                          subtitle: [accountName, ?value.summary].join(' · '),
                          layout: AccountIdentityLayout.header,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Tooltip(
                        message: l10n.settingsModelEnabledHint,
                        child: Semantics(
                          label: l10n.settingsModelEnabled,
                          child: Switch(
                            value: value.enabled,
                            onChanged: value.canToggle && !value.saving
                                ? onEnabledChanged
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (value.readoutLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (value.readoutError != null)
                    AccountInlineError(
                      message: value.readoutError!,
                      onRetry: value.canLoadReadout ? onRetry : null,
                    ),
                  if (value.error != null)
                    AccountInlineError(message: value.error!),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                headerContext,
              ),
              sliver: SliverAppBar(
                pinned: true,
                automaticallyImplyLeading: false,
                toolbarHeight: 0,
                primary: false,
                backgroundColor: Theme.of(context).colorScheme.surface,
                forceElevated: innerBoxIsScrolled,
                bottom: TabBar(
                  controller: controller,
                  onTap: (index) {
                    final selected = AccountModelTab.values[index];
                    if (selected != tab) onTabChanged(selected);
                  },
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(
                      key: const ValueKey('account-model-specs-tab'),
                      text: l10n.accountsSpecsTab,
                    ),
                    Tab(
                      key: const ValueKey('account-model-prices-tab'),
                      text: l10n.accountsPriceTiers,
                    ),
                    Tab(
                      key: const ValueKey('account-model-evaluations-tab'),
                      text: l10n.accountsEvaluations,
                    ),
                  ],
                ),
              ),
            ),
          ],
          body: NotificationListener<ScrollEndNotification>(
            onNotification: (notification) {
              // TabBarView updates its controller before forwarding this
              // notification. Vertical tab-content scrolling is not selection.
              if (notification.depth == 0 &&
                  notification.metrics.axis == Axis.horizontal &&
                  !controller.indexIsChanging) {
                final selected = AccountModelTab.values[controller.index];
                if (selected != tab) onTabChanged(selected);
              }
              return false;
            },
            child: TabBarView(
              controller: controller,
              children: [
                for (final tab in <({String storageKey, Widget child})>[
                  (
                    storageKey: 'model-specs:$identity',
                    child: AccountModelSpecifications(value: value),
                  ),
                  (
                    storageKey: 'model-prices:$identity',
                    child: AccountModelPricing(value: value),
                  ),
                  (
                    storageKey: 'model-evaluations:$identity',
                    child: AccountEvaluationsView(
                      value: value.evaluationSummary,
                      onFilterChanged: onFilterChanged,
                    ),
                  ),
                ])
                  Builder(
                    builder: (innerContext) => CustomScrollView(
                      key: PageStorageKey<String>(tab.storageKey),
                      // Inherit NestedScrollView's primary controller on every
                      // platform so header and tab contents share coordination.
                      slivers: [
                        SliverOverlapInjector(
                          handle:
                              NestedScrollView.sliverOverlapAbsorberHandleFor(
                                innerContext,
                              ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          sliver: SliverToBoxAdapter(child: tab.child),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Owns only Material tab geometry. The caller's typed tab is authoritative;
/// model identity scopes this lifetime without keying the page by selected tab.
class _ControlledModelTabs extends StatefulWidget {
  const _ControlledModelTabs({
    required this.tab,
    required this.builder,
    super.key,
  });
  final AccountModelTab tab;
  final Widget Function(BuildContext context, TabController controller) builder;

  @override
  State<_ControlledModelTabs> createState() => _ControlledModelTabsState();
}

class _ControlledModelTabsState extends State<_ControlledModelTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: AccountModelTab.values.length,
    initialIndex: widget.tab.index,
    vsync: this,
  );

  @override
  void didUpdateWidget(covariant _ControlledModelTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reconcile even an unchanged external value after an unaccepted intent;
    // a controller is not a second navigation/query owner.
    if (_controller.index != widget.tab.index) {
      // TabBarView follows animateTo's indexIsChanging path, not index writes.
      _controller.animateTo(widget.tab.index);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
