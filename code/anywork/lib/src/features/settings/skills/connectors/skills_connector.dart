import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../../state/settings_action.dart';
import '../../state/settings_navigation_state.dart';
import '../../view_models/collection_values.dart';
import '../../view_models/read_values.dart';
import '../../view_models/settings_navigation_view_model.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_form_layout.dart';
import '../../widgets/settings_pane.dart';
import '../state/skills_view_state.dart';
import '../view_models/skill_names.dart';
import '../view_models/skills_preferences_view_model.dart';
import '../view_models/skills_view_model.dart';
import '../views/skills_view.dart';

class SkillsConnector extends ConsumerStatefulWidget {
  const SkillsConnector({required this.projectId, super.key});
  final String? projectId;
  @override
  ConsumerState<SkillsConnector> createState() => _SkillsConnectorState();
}

class _SkillsConnectorState extends ConsumerState<SkillsConnector> {
  String? _searchSyncProject;
  String? _watchedProject;
  @override
  void didUpdateWidget(covariant SkillsConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldProject = _watchedProject;
    if (oldProject != null && oldProject != widget.projectId) {
      // Explicit target replacement ends the already watched old query borrow.
      // No Session/job is cancelled, and dispose never starts this operation.
      ref.read(skillsViewModelProvider(oldProject).notifier).setVisible(false);
      _watchedProject = null;
    }
  }

  void _syncSearch(
    String projectId,
    SkillsPreferencesState preferences,
    SkillsViewState? catalog,
  ) {
    if (catalog == null || _searchSyncProject == projectId) return;
    if (catalog.searchQuery == preferences.queryRaw.trim() &&
        ref.read(skillsViewModelProvider(projectId).notifier).isVisible) {
      return;
    }
    _searchSyncProject = projectId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_searchSyncProject == projectId) _searchSyncProject = null;
      if (!mounted || widget.projectId != projectId) return;
      final navigation = ref
          .read(settingsNavigationViewModelProvider)
          .asData
          ?.value;
      if (navigation?.visible != true ||
          navigation?.tab != SettingsTab.skills) {
        return;
      }
      final raw = ref
          .read(skillsPreferencesViewModelProvider)
          .asData
          ?.value
          .queryRaw;
      final provider = skillsViewModelProvider(projectId);
      if (raw != null && ref.read(provider).asData != null) {
        final vm = ref.read(provider.notifier);
        vm.setVisible(true);
        vm.requestSearch(raw);
      }
    });
  }

  /// Page shell for the states that have no view state yet: heading, discover
  /// entry, filter toolbar and the 16/14 opening rhythm stay on screen; loading
  /// and failure are content-area rows.
  Widget _shell(BuildContext context, List<Widget> children) =>
      SettingsPane.scrolling(
        title: context.l10n.settingsSkillsTitle,
        subtitle: context.l10n.settingsSkillsSubtitle,
        trailing: FilledButton.icon(
          key: StudioDriverKeys.skillsDiscover,
          onPressed: null,
          icon: const Icon(Icons.travel_explore),
          label: Text(context.l10n.settingsDiscover),
        ),
        // `SettingsSearchField` has no `enabled` flag and the shared widget must not
        // change here, so the input is made non-interactive instead of silently
        // accepting text that cannot reach a view model yet. The real, editable
        // field is rendered by `SkillsView` as soon as preferences data exists.
        toolbar: AbsorbPointer(
          child: SettingsSearchField(
            hintText: context.l10n.settingsFilterSkills,
            onChanged: (_) {},
          ),
        ),
        children: [
          const SizedBox(height: 16),
          const SizedBox(height: 14),
          ...children,
        ],
      );

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(skillsPreferencesViewModelProvider);
    final visible = ref.watch(
      settingsNavigationViewModelProvider.select(
        (value) =>
            value.asData?.value.visible == true &&
            value.asData?.value.tab == SettingsTab.skills,
      ),
    );
    final id = widget.projectId;
    final catalog = id == null || !visible
        ? null
        : ref.watch(skillsViewModelProvider(id));
    _watchedProject = visible ? id : null;
    final failure = catalog?.asError;
    if (failure != null && failure.error is! StudioFailure) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
    return preferences.when(
      loading: () => _shell(context, const [LinearProgressIndicator()]),
      error: (error, stack) {
        if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
        return _shell(context, [
          SettingsInlineError(message: settingsFailureText(error)),
        ]);
      },
      data: (preferences) {
        final state = catalog?.asData?.value;
        if (id != null && visible) _syncSearch(id, preferences, state);
        final preferencesVM = ref.read(
          skillsPreferencesViewModelProvider.notifier,
        );
        final vm = id == null || state == null
            ? null
            : ref.read(skillsViewModelProvider(id).notifier);
        final settings = displayReadValue(preferences.source.skillsSettings);
        final rows = _rows(preferences, state);
        final source = state?.source;
        final current = preferencesVM.currentSettings;
        final warnings = source == null
            ? <String>[]
            : displayReadValue(source.warnings) ?? [];
        final issues =
            state?.cleanupReports
                .expand((report) => report.unresolved)
                .expand((resource) => resource.issues)
                .toList() ??
            <FeedCloseIssue>[];
        Future<void> refresh() async {
          await Future.wait<void>([
            preferencesVM.refresh(),
            if (vm != null) vm.refresh(),
          ]);
          if (id != null &&
              failure != null &&
              mounted &&
              widget.projectId == id) {
            ref.invalidate(skillsViewModelProvider(id));
          }
        }

        return SkillsView(
          queryRaw: preferences.queryRaw,
          rows: rows,
          disabledNames: {
            for (final row in rows)
              if (skillNameDisabled(settings?.disabled ?? [], row.name))
                row.name,
          },
          hasProject: id != null,
          configurationKnown: settings != null,
          canEdit:
              current != null &&
              !(preferences.disabledAction?.preventsResubmission ?? false),
          discovering: state?.discoverAction?.pending ?? false,
          canDiscover:
              vm != null &&
              !(state?.discoverAction?.preventsResubmission ?? false),
          catalogIncomplete: source?.projection.header?.complete == false,
          searchTruncated: state?.search?.truncated ?? false,
          knownEmpty:
              source != null &&
              source.projection.header?.complete == true &&
              collectionComplete(
                source.skills,
                source.projection.stamp?.origin,
              ),
          hasMore:
              source != null &&
              !collectionComplete(
                source.skills,
                source.projection.stamp?.origin,
              ),
          reading:
              preferences.reading.isNotEmpty ||
              (state?.reading.isNotEmpty ?? false),
          warnings: warnings,
          errors: [
            if (failure?.error case StudioFailure error)
              settingsFailureText(error),
            for (final error in preferences.readIssues.values)
              settingsFailureText(error),
            if (_readError(preferences.source.skillsSettings) case final error?)
              settingsFailureText(error),
            if (preferences.source.projection.sync.error case final error?)
              settingsFailureText(error),
            if (source?.projection.sync.error case final error?)
              settingsFailureText(error),
            if (source != null) ...[
              for (final error in state!.readIssues.values)
                settingsFailureText(error),
              for (final error in state.cleanupErrors)
                settingsFailureText(error),
              if (displayCollection(source.skills)?.error case final error?)
                settingsFailureText(error),
              if (_readError(source.warnings) case final error?)
                settingsFailureText(error),
            ],
            if (state?.searchError case final error?)
              settingsFailureText(error),
            ..._errors(preferences.disabledAction),
            ..._errors(state?.discoverAction),
            for (final issue in issues)
              '${issue.diagnostic.message} [${issue.diagnostic.stage}/${issue.diagnostic.code}: '
                  '${issue.diagnostic.correlationId}] · ${issue.recovery.name}',
          ],
          onQuery: preferencesVM.setQuery,
          onEnabled: (name, enabled) =>
              unawaited(preferencesVM.setEnabled(name, enabled)),
          onDiscover: () {
            if (vm != null) unawaited(vm.discover());
          },
          onRefresh: () => unawaited(refresh()),
          onMore: () {
            if (vm != null) unawaited(vm.loadMore());
          },
        );
      },
    );
  }

  List<SettingsSkillRow> _rows(
    SkillsPreferencesState preferences,
    SkillsViewState? state,
  ) {
    final query = preferences.queryRaw.trim();
    if (query.isNotEmpty) {
      final result = state?.search;
      if (state?.searchQuery != query ||
          result == null ||
          result.projectId != state?.projectId ||
          result.catalogRevision !=
              state?.source.projection.header?.catalogRevision) {
        return [];
      }
      return [
        for (final summary in result.matches)
          SettingsSkillRow.catalog(summary: summary),
      ];
    }
    final byName = <String, SettingsSkillRow>{};
    if (state != null) {
      for (final summary in displayCollectionRows(state.source.skills)) {
        byName[skillNameKey(summary.name)] = SettingsSkillRow.catalog(
          summary: summary,
        );
      }
    }
    final disabled =
        displayReadValue(preferences.source.skillsSettings)?.disabled ??
        <String>[];
    for (final name in [...?state?.activeNames?.names, ...disabled]) {
      byName.putIfAbsent(
        skillNameKey(name),
        () => SettingsSkillRow.nameOnly(value: name),
      );
    }
    return byName.values.toList()..sort(
      (left, right) =>
          skillNameKey(left.name).compareTo(skillNameKey(right.name)),
    );
  }

  List<String> _errors(SettingsAction? action) => [
    if (action?.error case final error?) settingsFailureText(error),
    if (action?.observationError case final error?) settingsFailureText(error),
    if (action?.operation?.evidenceError case final error?)
      settingsFailureText(error),
  ];
  StudioFailure? _readError<T, R>(ReadValue<T, R>? read) => switch (read) {
    FailedReadValue<T, R>(:final error) => error,
    _ => null,
  };
}
