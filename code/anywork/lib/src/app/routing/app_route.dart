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
import '../../features/settings/settings_bots_tab.dart'
    show BotChatPage, BotDetailsPage;
import '../../features/settings/settings_page.dart';
import '../../features/settings/settings_section.dart';
import '../../features/shell/studio_shell.dart';
import '../../presentation/providers/client_provider.dart';

part 'app_route.g.dart';

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
  name: StudioRoute.name,
  routes: <TypedGoRoute<GoRouteData>>[
    TypedGoRoute<SettingsRoute>(
      path: 'settings',
      name: SettingsRoute.name,
      routes: <TypedGoRoute<GoRouteData>>[
        TypedGoRoute<AccountCreateRoute>(
          path: 'accounts/new',
          name: AccountCreateRoute.name,
        ),
        TypedGoRoute<AccountDetailsRoute>(
          path: 'accounts/:kind/:accountId',
          name: AccountDetailsRoute.name,
          routes: <TypedGoRoute<GoRouteData>>[
            TypedGoRoute<AccountEditRoute>(
              path: 'edit',
              name: AccountEditRoute.name,
            ),
            TypedGoRoute<AccountModelRoute>(
              path: 'models/:modelId',
              name: AccountModelRoute.name,
            ),
          ],
        ),
        TypedGoRoute<ModeWorkspaceRoute>(
          path: 'modes/:modeId',
          name: ModeWorkspaceRoute.name,
          routes: <TypedGoRoute<GoRouteData>>[
            TypedGoRoute<ModeDetailRoute>(
              path: 'details',
              name: ModeDetailRoute.name,
            ),
          ],
        ),
      ],
    ),
    TypedGoRoute<BotDetailsRoute>(
      path: 'bots/:botId',
      name: BotDetailsRoute.name,
    ),
    TypedGoRoute<BotConversationRoute>(
      path: 'bots/:botId/chats/:chatId/threads/:threadId',
      name: BotConversationRoute.name,
    ),
    TypedGoRoute<BotPlatformToolsRoute>(
      path: 'bots/:botId/chats/:chatId/platform',
      name: BotPlatformToolsRoute.name,
    ),
  ],
)
class StudioRoute extends GoRouteData with $StudioRoute {
  static const name = 'studio';

  const StudioRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const StudioShell();
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  static const name = 'settings';

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
        key: state.pageKey,
        restorationId: 'settings-page',
        child: SettingsPage(
          section: section,
          routeVisible:
              state.uri.path == Uri.parse(const SettingsRoute().location).path,
        ),
      );
}

class AccountCreateRoute extends GoRouteData with $AccountCreateRoute {
  static const name = 'settings.account-create';

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
  static const name = 'settings.account-details';

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
  static const name = 'settings.account-edit';

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
  static const name = 'settings.account-model';

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
/// The exit guard only decides the editor source whose opening identity
/// matches [modeId]; the Settings parent re-checks whatever source is still
/// unsettled when the whole Settings match is removed.
class ModeWorkspaceRoute extends GoRouteData with $ModeWorkspaceRoute {
  static const name = 'mode-workspace';

  const ModeWorkspaceRoute({required this.modeId});

  final String modeId;

  @override
  Future<bool> onExit(BuildContext context, GoRouterState state) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final editingId = container
        .read(anyworkClientProvider)
        .modeEditor
        .openedModeId;
    if (editingId != modeId) return true;
    return confirmLeaveModeEditor(context);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      MaterialPage<void>(
        key: state.pageKey,
        restorationId: 'mode-workspace-page',
        child: ModeWorkspacePage(modeId: modeId),
      );
}

/// Narrow-width detail page for a workspace selection.
///
/// The stage/edge selection is local to this page and never opens or resets a
/// mode editor source for the guard.
class ModeDetailRoute extends GoRouteData with $ModeDetailRoute {
  static const name = 'mode-detail';

  const ModeDetailRoute({required this.modeId, this.stage, this.edge});

  final String modeId;
  final String? stage;
  final String? edge;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      MaterialPage<void>(
        key: state.pageKey,
        restorationId: 'mode-detail-page',
        child: ModeDetailPage(modeId: modeId, stage: stage, edge: edge),
      );
}

class BotDetailsRoute extends GoRouteData with $BotDetailsRoute {
  const BotDetailsRoute({required this.botId});
  static const name = 'bot-details';
  final String botId;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      BotDetailsPage(key: ValueKey((botId, null)), botId: botId);
}

class BotConversationRoute extends GoRouteData with $BotConversationRoute {
  const BotConversationRoute({
    required this.botId,
    required this.chatId,
    required this.threadId,
  });
  static const name = 'bot-conversation';
  final String botId;
  final String chatId;
  final String threadId;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      BotChatPage(botId: botId, chatId: chatId, threadId: threadId);
}

class BotPlatformToolsRoute extends GoRouteData with $BotPlatformToolsRoute {
  const BotPlatformToolsRoute({required this.botId, required this.chatId});
  static const name = 'bot-platform-tools';
  final String botId;
  final String chatId;

  @override
  Widget build(BuildContext context, GoRouterState state) => BotDetailsPage(
    key: ValueKey((botId, chatId)),
    botId: botId,
    chatId: chatId,
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
      StudioRoute.name => AccountRouteIdentity(
        page: AccountRoutePage.other,
        location: $StudioRoute._fromState(state).location,
      ),
      SettingsRoute.name => _settingsIdentity(state),
      AccountCreateRoute.name => _createIdentity(state),
      AccountDetailsRoute.name => _detailsIdentity(state),
      AccountEditRoute.name => _editIdentity(state),
      AccountModelRoute.name => _modelIdentity(state),
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
/// Child account routes are always the Accounts section and mode workspace
/// routes are Work Modes. Bot routes are outside Settings; SettingsRoute's
/// generated from-state factory owns query decoding for the settings root.
SettingsSection? settingsSectionForMatchedRoute(GoRouterState state) =>
    switch (state.topRoute?.name) {
      SettingsRoute.name => $SettingsRoute._fromState(state).section,
      AccountCreateRoute.name ||
      AccountDetailsRoute.name ||
      AccountEditRoute.name ||
      AccountModelRoute.name => SettingsSection.accounts,
      ModeWorkspaceRoute.name ||
      ModeDetailRoute.name => SettingsSection.workModes,
      _ => null,
    };

/// Whether the official old route configuration still contains the Settings
/// match. This uses the current match tree, not a URI prefix or saved history.
bool currentMatchesSettings(Iterable<RouteMatchBase> matches) => matches.any(
  (match) =>
      match.route is GoRoute &&
      (match.route as GoRoute).name == SettingsRoute.name,
);

/// Whether this state's top matched route is the Settings root itself, as
/// opposed to one of its typed child routes.
bool isSettingsRootMatch(GoRouterState state) =>
    state.topRoute?.name == SettingsRoute.name;

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
            (match.route as GoRoute).name == AccountEditRoute.name,
      )
      .toList(growable: false);
  if (editMatches.isEmpty) {
    return oldCurrent.topRoute?.name == AccountEditRoute.name
        ? (valid: false, entry: null)
        : (valid: true, entry: null);
  }
  if (editMatches.length != 1) return (valid: false, entry: null);

  final editorMatch = editMatches.single;
  final detailsIndex = matches.indexWhere(
    (match) =>
        match.route is GoRoute &&
        (match.route as GoRoute).name == AccountDetailsRoute.name &&
        match.pageKey == oldDetailsState.pageKey,
  );
  final editorIndex = matches.indexOf(editorMatch);
  if (detailsIndex < 0 ||
      editorIndex != detailsIndex + 1 ||
      oldCurrent.topRoute?.name != AccountEditRoute.name ||
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
