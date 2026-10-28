import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/settings/accounts/connectors/account_create_connector.dart';
import '../../features/settings/accounts/connectors/account_details_connector.dart';
import '../../features/settings/accounts/connectors/account_edit_connector.dart';
import '../../features/settings/accounts/connectors/account_model_connector.dart';
import '../../features/settings/accounts/connectors/account_navigation.dart';
import '../../features/settings/accounts/state/account_presentations.dart';
import '../../features/settings/accounts/state/account_view_state.dart';
import '../../features/settings/mode_editor/mode_editor_dialogs.dart';
import '../../features/settings/settings_page.dart';
import '../../features/settings/settings_section.dart';
import '../../features/shell/studio_shell.dart';

part 'app_route.g.dart';

const _studioRouteName = 'studio';
const _settingsRouteName = 'settings';
const _accountCreateRouteName = 'settings.account-create';
const _accountDetailsRouteName = 'settings.account-details';
const _accountEditRouteName = 'settings.account-edit';
const _accountModelRouteName = 'settings.account-model';

@TypedGoRoute<StudioRoute>(
  path: '/',
  name: _studioRouteName,
  routes: <TypedGoRoute<GoRouteData>>[
    TypedGoRoute<SettingsRoute>(
      path: 'settings',
      name: _settingsRouteName,
      routes: <TypedGoRoute<GoRouteData>>[
        TypedGoRoute<AccountCreateRoute>(
          path: 'accounts/new',
          name: _accountCreateRouteName,
        ),
        TypedGoRoute<AccountDetailsRoute>(
          path: 'accounts/:kind/:accountId',
          name: _accountDetailsRouteName,
          routes: <TypedGoRoute<GoRouteData>>[
            TypedGoRoute<AccountEditRoute>(
              path: 'edit',
              name: _accountEditRouteName,
            ),
            TypedGoRoute<AccountModelRoute>(
              path: 'models/:modelId',
              name: _accountModelRouteName,
            ),
          ],
        ),
      ],
    ),
  ],
)
class StudioRoute extends GoRouteData with $StudioRoute {
  const StudioRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const StudioShell();
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute({this.section = SettingsSection.accounts});

  final SettingsSection section;

  @override
  Future<bool> onExit(BuildContext context, GoRouterState state) =>
      confirmLeaveModeEditor(context);

  @override
  Widget build(BuildContext context, GoRouterState state) => SettingsPage(
    section: section,
    routeVisible:
        state.uri.path == Uri.parse(const SettingsRoute().location).path,
  );
}

class AccountCreateRoute extends GoRouteData with $AccountCreateRoute {
  const AccountCreateRoute();

  AccountEditorEntryKey _entry(GoRouterState state) =>
      AccountEditorEntryKey.creating(routeEntryId: state.pageKey.value);

  @override
  Future<bool> onExit(BuildContext context, GoRouterState state) =>
      confirmLeaveAccountEditorEntry(context, _entry(state));

  @override
  Widget build(BuildContext context, GoRouterState state) => SettingsPage(
    section: SettingsSection.accounts,
    accountChild: AccountCreateConnector(entry: _entry(state)),
  );
}

class AccountDetailsRoute extends GoRouteData with $AccountDetailsRoute {
  const AccountDetailsRoute({required this.kind, required this.accountId});

  final AccountKind kind;
  final String accountId;

  AccountDisplayKey get _account =>
      AccountDisplayKey(kind: kind, id: accountId);

  @override
  Future<bool> onExit(BuildContext context, GoRouterState state) {
    final source = _guardedEditorEntryForDetailsExit(context, state);
    if (!source.valid) return false;
    return confirmLeaveAccountContext(
      context,
      _account,
      guardedEditorEntry: source.entry,
    );
  }

  @override
  Widget build(BuildContext context, GoRouterState state) => SettingsPage(
    section: SettingsSection.accounts,
    accountChild: AccountDetailsConnector(account: _account),
  );
}

class AccountEditRoute extends GoRouteData with $AccountEditRoute {
  const AccountEditRoute({
    required this.kind,
    required this.accountId,
    this.focusModelId,
    this.addModel = false,
  });

  final AccountKind kind;
  final String accountId;
  final String? focusModelId;
  final bool addModel;

  AccountEditorEntryKey _entry(GoRouterState state) =>
      AccountEditorEntryKey.editing(
        routeEntryId: state.pageKey.value,
        account: AccountDisplayKey(kind: kind, id: accountId),
      );

  @override
  Future<bool> onExit(BuildContext context, GoRouterState state) =>
      confirmLeaveAccountEditorEntry(context, _entry(state));

  @override
  Widget build(BuildContext context, GoRouterState state) => SettingsPage(
    section: SettingsSection.accounts,
    accountChild: AccountEditConnector(
      entry: _entry(state),
      focusModelId: focusModelId,
      addModel: addModel,
    ),
  );
}

class AccountModelRoute extends GoRouteData with $AccountModelRoute {
  const AccountModelRoute({
    required this.kind,
    required this.accountId,
    required this.modelId,
    this.tab = AccountModelTab.specifications,
  });

  final AccountKind kind;
  final String accountId;
  final String modelId;
  final AccountModelTab tab;

  @override
  Widget build(BuildContext context, GoRouterState state) => SettingsPage(
    section: SettingsSection.accounts,
    accountChild: AccountModelConnector(
      model: AccountModelKey(
        account: AccountDisplayKey(kind: kind, id: accountId),
        modelId: modelId,
      ),
      tab: tab,
    ),
  );
}

/// The settings section represented by a matched typed destination.
///
/// Child account routes are always the Accounts section; SettingsRoute's
/// generated from-state factory owns query decoding for the settings root.
SettingsSection? settingsSectionForMatchedRoute(GoRouterState state) =>
    switch (state.topRoute?.name) {
      _settingsRouteName => $SettingsRoute._fromState(state).section,
      _accountCreateRouteName ||
      _accountDetailsRouteName ||
      _accountEditRouteName ||
      _accountModelRouteName => SettingsSection.accounts,
      _ => null,
    };

/// Whether the official old route configuration still contains the Settings
/// match. This uses the current match tree, not a URI prefix or saved history.
bool currentMatchesSettings(Iterable<RouteMatchBase> matches) =>
    matches.any((match) => match.route.name == _settingsRouteName);

/// Reuses the old, still-current typed Edit match only when it is the direct
/// child responsible for this Details route's joint exit decision.
({bool valid, AccountEditorEntryKey? entry}) _guardedEditorEntryForDetailsExit(
  BuildContext context,
  GoRouterState oldDetailsState,
) {
  final router = GoRouter.of(context);
  final matches = router.routerDelegate.currentConfiguration.matches;
  final oldCurrent = router.state;
  final editMatches = matches
      .where((match) => match.route.name == _accountEditRouteName)
      .toList(growable: false);
  if (editMatches.isEmpty) {
    return oldCurrent.topRoute?.name == _accountEditRouteName
        ? (valid: false, entry: null)
        : (valid: true, entry: null);
  }
  if (editMatches.length != 1) return (valid: false, entry: null);

  final editorMatch = editMatches.single;
  final detailsIndex = matches.indexWhere(
    (match) =>
        match.route.name == _accountDetailsRouteName &&
        match.pageKey == oldDetailsState.pageKey,
  );
  final editorIndex = matches.indexOf(editorMatch);
  if (detailsIndex < 0 ||
      editorIndex != detailsIndex + 1 ||
      oldCurrent.topRoute?.name != _accountEditRouteName ||
      oldCurrent.pageKey != editorMatch.pageKey ||
      !currentMatchesSettings(matches)) {
    return (valid: false, entry: null);
  }

  try {
    final oldDetails = $AccountDetailsRoute._fromState(oldDetailsState);
    final oldEditor = $AccountEditRoute._fromState(oldCurrent);
    if (oldDetails.kind != oldEditor.kind ||
        oldDetails.accountId != oldEditor.accountId) {
      return (valid: false, entry: null);
    }
    return (
      valid: true,
      entry: AccountEditorEntryKey.editing(
        routeEntryId: editorMatch.pageKey.value,
        account: AccountDisplayKey(
          kind: oldEditor.kind,
          id: oldEditor.accountId,
        ),
      ),
    );
  } on Object {
    return (valid: false, entry: null);
  }
}
