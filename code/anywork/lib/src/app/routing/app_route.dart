import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/modes/modes.dart'
    show ModeDetailPage, ModeWorkspacePage, confirmLeaveModeEditor;
import '../../features/settings/accounts/connectors/account_create_connector.dart';
import '../../features/settings/accounts/connectors/account_details_connector.dart';
import '../../features/settings/accounts/connectors/account_edit_connector.dart';
import '../../features/settings/accounts/connectors/account_model_connector.dart';
import '../../features/settings/accounts/connectors/account_navigation.dart';
import '../../features/settings/accounts/state/account_presentations.dart';
import '../../features/settings/accounts/state/account_view_state.dart';
import '../../features/settings/settings_bots_chat_page.dart' show BotChatPage;
import '../../features/settings/settings_bots_tab.dart' show BotDetailsPage;
import '../../features/settings/settings_page.dart';
import '../../features/settings/settings_section.dart';
import '../../features/shell/studio_shell.dart';
import '../../presentation/providers/client_provider.dart';

part 'app_route.g.dart';

const _studioRouteName = 'studio';
const _settingsRouteName = 'settings';
const _accountCreateRouteName = 'settings.account-create';
const _accountDetailsRouteName = 'settings.account-details';
const _accountEditRouteName = 'settings.account-edit';
const _accountModelRouteName = 'settings.account-model';
const _modeWorkspaceRouteName = 'mode-workspace';
const _modeDetailRouteName = 'mode-detail';
const _botDetailsRouteName = 'bot-details';
const _botChatRouteName = 'bot-chat';

String _encodeSettingsSection(SettingsSection value) =>
    _$SettingsSectionEnumMap[value]!;

SettingsSection _decodeSettingsSection(String value) =>
    _$SettingsSectionEnumMap._$fromName(value) ??
    (throw GoException('Invalid settings section query value: "$value".'));

String _encodeAccountModelTab(AccountModelTab value) =>
    _$AccountModelTabEnumMap[value]!;

AccountModelTab _decodeAccountModelTab(String value) =>
    _$AccountModelTabEnumMap._$fromName(value) ??
    (throw GoException('Invalid account model tab query value: "$value".'));

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
        TypedGoRoute<ModeWorkspaceRoute>(
          path: 'modes/:modeId',
          name: _modeWorkspaceRouteName,
          routes: <TypedGoRoute<GoRouteData>>[
            TypedGoRoute<ModeDetailRoute>(
              path: 'details',
              name: _modeDetailRouteName,
            ),
          ],
        ),
        TypedGoRoute<BotDetailsRoute>(
          path: 'bots/:botId',
          name: _botDetailsRouteName,
          routes: <TypedGoRoute<GoRouteData>>[
            TypedGoRoute<BotChatRoute>(path: 'chat', name: _botChatRouteName),
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
  const SettingsRoute({
    @TypedQueryParameter<SettingsSection>(
      encoder: _encodeSettingsSection,
      decoder: _decodeSettingsSection,
    )
    this.section = SettingsSection.accounts,
  });

  final SettingsSection section;

  @override
  Future<bool> onExit(BuildContext context, GoRouterState state) =>
      confirmLeaveModeEditor(context);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      MaterialPage<void>(
        restorationId: 'settings-page',
        child: SettingsPage(
          section: section,
          routeVisible:
              state.uri.path == Uri.parse(const SettingsRoute().location).path,
        ),
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
  Future<bool> onExit(BuildContext context, GoRouterState state) async {
    final source = _guardedEditorEntryForDetailsExit(context, state);
    if (!source.valid) return false;
    return await confirmLeaveAccountContext(
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
    @TypedQueryParameter<AccountModelTab>(
      encoder: _encodeAccountModelTab,
      decoder: _decodeAccountModelTab,
    )
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

/// Full-screen workspace for one task mode.
///
/// The exit guard only decides the already-open editor source whose document
/// id matches [modeId]; the Settings parent re-checks whatever source is still
/// unsettled when the whole Settings match is removed.
class ModeWorkspaceRoute extends GoRouteData with $ModeWorkspaceRoute {
  const ModeWorkspaceRoute({required this.modeId});

  final String modeId;

  @override
  Future<bool> onExit(BuildContext context, GoRouterState state) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final editingId = container
        .read(anyworkClientProvider)
        .modeEditor
        .state
        .document
        ?.definition
        .id;
    if (editingId != modeId) return true;
    return confirmLeaveModeEditor(context);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      MaterialPage<void>(
        restorationId: 'mode-workspace-page',
        child: ModeWorkspacePage(modeId: modeId),
      );
}

/// Narrow-width detail page for a workspace selection.
///
/// The stage/edge selection is local to this page and never opens or resets a
/// mode editor source for the guard.
class ModeDetailRoute extends GoRouteData with $ModeDetailRoute {
  const ModeDetailRoute({required this.modeId, this.stage, this.edge});

  final String modeId;
  final String? stage;
  final String? edge;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      MaterialPage<void>(
        restorationId: 'mode-detail-page',
        child: ModeDetailPage(modeId: modeId, stage: stage, edge: edge),
      );
}

class BotDetailsRoute extends GoRouteData with $BotDetailsRoute {
  const BotDetailsRoute({
    required this.botId,
    @TypedQueryParameter(name: 'chatId') this.chatId,
  });

  final String botId;
  final String? chatId;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      MaterialPage<void>(
        restorationId: 'bot-details-page',
        child: BotDetailsPage(botId: botId, chatId: chatId),
      );
}

class BotChatRoute extends GoRouteData with $BotChatRoute {
  const BotChatRoute({
    required this.botId,
    @TypedQueryParameter(name: 'chatId') this.chatId = '',
    this.title,
  });

  final String botId;
  final String chatId;
  final String? title;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      MaterialPage<void>(
        restorationId: 'bot-chat-page',
        child: BotChatPage(botId: botId, chatId: chatId, title: title),
      );
}

enum AccountRoutePage { list, create, details, edit, model, other }

final class AccountRouteIdentity {
  const AccountRouteIdentity({
    required this.page,
    required this.location,
    this.account,
    this.model,
    this.tab,
    this.entry,
  });

  final AccountRoutePage page;
  final String location;
  final AccountDisplayKey? account;
  final AccountModelKey? model;
  final AccountModelTab? tab;
  final AccountEditorEntryKey? entry;
}

/// Read-only projection of the router's committed typed destination.
///
/// This does not create or watch any presentation owner and never echoes raw
/// URI/query text. Unknown and unmatched states remain absent.
AccountRouteIdentity? readAccountRouteIdentity(GoRouter router) {
  final state = router.state;
  final routeName = state.topRoute?.name;
  if (routeName == null) return null;

  try {
    return switch (routeName) {
      _studioRouteName => AccountRouteIdentity(
        page: AccountRoutePage.other,
        location: $StudioRoute._fromState(state).location,
      ),
      _settingsRouteName => _settingsIdentity(state),
      _accountCreateRouteName => _createIdentity(state),
      _accountDetailsRouteName => _detailsIdentity(state),
      _accountEditRouteName => _editIdentity(state),
      _accountModelRouteName => _modelIdentity(state),
      _ => null,
    };
  } on Object {
    return null;
  }
}

AccountRouteIdentity _settingsIdentity(GoRouterState state) {
  final destination = $SettingsRoute._fromState(state);
  return AccountRouteIdentity(
    page: destination.section == SettingsSection.accounts
        ? AccountRoutePage.list
        : AccountRoutePage.other,
    location: destination.location,
  );
}

AccountRouteIdentity _createIdentity(GoRouterState state) {
  final destination = $AccountCreateRoute._fromState(state);
  return AccountRouteIdentity(
    page: AccountRoutePage.create,
    location: destination.location,
    entry: AccountEditorEntryKey.creating(routeEntryId: state.pageKey.value),
  );
}

AccountRouteIdentity _detailsIdentity(GoRouterState state) {
  final destination = $AccountDetailsRoute._fromState(state);
  final account = AccountDisplayKey(
    kind: destination.kind,
    id: destination.accountId,
  );
  return AccountRouteIdentity(
    page: AccountRoutePage.details,
    location: destination.location,
    account: account,
  );
}

AccountRouteIdentity _editIdentity(GoRouterState state) {
  final destination = $AccountEditRoute._fromState(state);
  final account = AccountDisplayKey(
    kind: destination.kind,
    id: destination.accountId,
  );
  return AccountRouteIdentity(
    page: AccountRoutePage.edit,
    location: destination.location,
    account: account,
    entry: AccountEditorEntryKey.editing(
      routeEntryId: state.pageKey.value,
      account: account,
    ),
  );
}

AccountRouteIdentity _modelIdentity(GoRouterState state) {
  final destination = $AccountModelRoute._fromState(state);
  final account = AccountDisplayKey(
    kind: destination.kind,
    id: destination.accountId,
  );
  return AccountRouteIdentity(
    page: AccountRoutePage.model,
    location: destination.location,
    account: account,
    model: AccountModelKey(account: account, modelId: destination.modelId),
    tab: destination.tab,
  );
}

/// The settings section represented by a matched typed destination.
///
/// Child account routes are always the Accounts section, mode workspace
/// routes are Work Modes, and bot routes are Bots; SettingsRoute's generated
/// from-state factory owns query decoding for the settings root.
SettingsSection? settingsSectionForMatchedRoute(GoRouterState state) =>
    switch (state.topRoute?.name) {
      _settingsRouteName => $SettingsRoute._fromState(state).section,
      _accountCreateRouteName ||
      _accountDetailsRouteName ||
      _accountEditRouteName ||
      _accountModelRouteName => SettingsSection.accounts,
      _modeWorkspaceRouteName ||
      _modeDetailRouteName => SettingsSection.workModes,
      _botDetailsRouteName || _botChatRouteName => SettingsSection.bots,
      _ => null,
    };

/// Whether the official old route configuration still contains the Settings
/// match. This uses the current match tree, not a URI prefix or saved history.
bool currentMatchesSettings(Iterable<RouteMatchBase> matches) => matches.any(
  (match) =>
      match.route is GoRoute &&
      (match.route as GoRoute).name == _settingsRouteName,
);

/// Whether this state's top matched route is the Settings root itself, as
/// opposed to one of its typed child routes.
bool isSettingsRootMatch(GoRouterState state) =>
    state.topRoute?.name == _settingsRouteName;

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
      .where(
        (match) =>
            match.route is GoRoute &&
            (match.route as GoRoute).name == _accountEditRouteName,
      )
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
        match.route is GoRoute &&
        (match.route as GoRoute).name == _accountDetailsRouteName &&
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
