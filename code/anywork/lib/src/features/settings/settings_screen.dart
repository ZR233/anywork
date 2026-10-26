import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'accounts/connectors/accounts_connector.dart';
import 'agents/connectors/agent_profiles_connector.dart';
import 'bots/connectors/bots_settings_connector.dart';
import 'connectors/settings_failure_text.dart';
import 'connectors/settings_navigation_connector.dart';
import 'connectors/settings_project_context.dart';
import 'general/connectors/general_settings_connector.dart';
import 'general/view_models/settings_readiness_view_model.dart';
import 'instructions/connectors/instructions_connector.dart';
import 'lsp/connectors/lsp_connector.dart';
import 'mcp/connectors/mcp_connector.dart';
import 'modes/connectors/mode_editor_connector.dart';
import 'security/views/security_view.dart';
import 'skills/connectors/skills_connector.dart';
import 'ssh/connectors/ssh_connector.dart';
import 'state/settings_navigation_state.dart';
import 'statistics/connectors/statistics_connector.dart';
import 'view_models/settings_navigation_view_model.dart';
import 'views/settings_view.dart';

/// Settings composition only. Canonical data and all editable raw stay in the
/// real feature VMs; the application's injected GoRouter owns route removal.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({this.initialTab, super.key});
  final SettingsTab? initialTab;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final Object _readinessEntry = Object();
  SettingsReadinessViewModel? _readinessOwner;
  bool _entryScheduled =
      false; // Coalesce UI lifecycle callbacks, not tab state.

  @override
  void initState() {
    super.initState();
    _scheduleEnter();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab == widget.initialTab) return;
    _scheduleEnter();
  }

  void _scheduleEnter() {
    if (_entryScheduled) return;
    _entryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entryScheduled = false;
      if (mounted) unawaited(_enter());
    });
  }

  Future<void> _enter() async {
    if (!mounted || ModalRoute.of(context)?.isActive != true) return;
    if (_readinessOwner == null) {
      final readiness = ref.read(settingsReadinessViewModelProvider.notifier);
      _readinessOwner = readiness;
      unawaited(readiness.enter(_readinessEntry));
    }
    final initialTab = widget.initialTab;
    final owner = ref.read(settingsNavigationViewModelProvider.notifier);
    final before = ref.read(settingsNavigationViewModelProvider);
    if (!before.isLoading &&
        !before.hasError &&
        before.asData?.value.visible == true) {
      // A changed route prop is a new tab intent: begin it before any await,
      // so a later click cannot be overwritten by a delayed initialization.
      if (initialTab case final tab?) {
        await selectSettingsTab(context, ref, tab);
      }
      return;
    }
    final ready = ref.read(settingsNavigationViewModelProvider.future);
    try {
      await ready;
    } on StudioFailure {
      return;
    } // Render the original initialization error.
    if (!mounted ||
        widget.initialTab != initialTab ||
        ModalRoute.of(context)?.isActive != true ||
        !identical(
          ref.read(settingsNavigationViewModelProvider.notifier),
          owner,
        )) {
      return;
    }
    final current = ref.read(settingsNavigationViewModelProvider).asData?.value;
    // Another explicit entry/navigation which won while initializing is not
    // replayed. A parent rebuild with the same prop does not cancel this entry.
    if (current != null && !current.visible) owner.enter(initialTab);
  }

  void _back() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    // GoRouter 18's pop invokes its existing onExit. Never confirm here and
    // then pop: that would create a second confirmation/handoff path.
    GoRouter.of(context).pop();
  }

  @override
  void dispose() {
    _readinessOwner?.leave(_readinessEntry);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigation = ref.watch(settingsNavigationViewModelProvider);
    final readiness = ref.watch(settingsReadinessViewModelProvider);
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: readiness.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) {
              if (error is! StudioFailure) {
                Error.throwWithStackTrace(error, stack);
              }
              return Center(child: SelectableText(settingsFailureText(error)));
            },
            data: (ready) => !ready.ready
                ? Center(
                    child: ready.error == null
                        ? const CircularProgressIndicator()
                        : SelectableText(settingsFailureText(ready.error!)),
                  )
                : navigation.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stack) {
                      if (error is! StudioFailure) {
                        Error.throwWithStackTrace(error, stack);
                      }
                      return Center(
                        child: SelectableText(settingsFailureText(error)),
                      );
                    },
                    data: (state) => SettingsView(
                      state: state,
                      panels: {
                        for (final tab in SettingsTab.values)
                          if (state.visited.contains(tab)) tab: _panel(tab),
                      },
                      onSelect: (tab) =>
                          unawaited(selectSettingsTab(context, ref, tab)),
                      onBack: _back,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _panel(SettingsTab tab) => switch (tab) {
    SettingsTab.accounts => const AccountsConnector(),
    SettingsTab.agents => const AgentProfilesConnector(),
    SettingsTab.modes => const ModeEditorConnector(),
    SettingsTab.instructions => const InstructionsConnector(),
    SettingsTab.skills => SettingsProjectContext(
      builder: (projectId) => SkillsConnector(projectId: projectId),
    ),
    SettingsTab.mcp => const McpConnector(),
    SettingsTab.lsp => SettingsProjectContext(
      builder: (projectId) => LspConnector(projectId: projectId),
    ),
    SettingsTab.ssh => const SshConnector(),
    SettingsTab.statistics => const StatisticsConnector(),
    SettingsTab.security => const SecurityView(),
    SettingsTab.general => const GeneralSettingsConnector(),
    SettingsTab.bots => const BotsSettingsConnector(),
  };
}
