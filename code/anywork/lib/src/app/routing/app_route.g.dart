// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_route.dart';

// **************************************************************************
// GoRouterGenerator
// **************************************************************************

List<RouteBase> get $appRoutes => [$studioRoute];

RouteBase get $studioRoute => GoRouteData.$route(
  path: '/',
  name: 'studio',
  hasOverriddenOnExit: false,
  factory: $StudioRoute._fromState,
  routes: [
    GoRouteData.$route(
      path: 'settings',
      name: 'settings',
      hasOverriddenOnExit: true,
      factory: $SettingsRoute._fromState,
      routes: [
        GoRouteData.$route(
          path: 'modes/:modeId',
          name: 'mode-workspace',
          hasOverriddenOnExit: true,
          factory: $ModeWorkspaceRoute._fromState,
          routes: [
            GoRouteData.$route(
              path: 'details',
              name: 'mode-detail',
              hasOverriddenOnExit: false,
              factory: $ModeDetailRoute._fromState,
            ),
          ],
        ),
      ],
    ),
    GoRouteData.$route(
      path: 'bots/:botId',
      name: 'bot-details',
      hasOverriddenOnExit: false,
      factory: $BotDetailsRoute._fromState,
    ),
    GoRouteData.$route(
      path: 'bots/:botId/chats/:chatId/threads/:threadId',
      name: 'bot-conversation',
      hasOverriddenOnExit: false,
      factory: $BotConversationRoute._fromState,
    ),
    GoRouteData.$route(
      path: 'bots/:botId/chats/:chatId/platform',
      name: 'bot-platform-tools',
      hasOverriddenOnExit: false,
      factory: $BotPlatformToolsRoute._fromState,
    ),
  ],
);

mixin $StudioRoute on GoRouteData {
  static StudioRoute _fromState(GoRouterState state) => const StudioRoute();

  @override
  String get location => GoRouteData.$location('/');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $SettingsRoute on GoRouteData {
  static SettingsRoute _fromState(GoRouterState state) => const SettingsRoute();

  @override
  String get location => GoRouteData.$location('/settings');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $ModeWorkspaceRoute on GoRouteData {
  static ModeWorkspaceRoute _fromState(GoRouterState state) =>
      ModeWorkspaceRoute(modeId: state.pathParameters['modeId']!);

  ModeWorkspaceRoute get _self => this as ModeWorkspaceRoute;

  @override
  String get location => GoRouteData.$location(
    '/settings/modes/${Uri.encodeComponent(_self.modeId)}',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $ModeDetailRoute on GoRouteData {
  static ModeDetailRoute _fromState(GoRouterState state) => ModeDetailRoute(
    modeId: state.pathParameters['modeId']!,
    stage: state.uri.queryParameters['stage'],
    edge: state.uri.queryParameters['edge'],
  );

  ModeDetailRoute get _self => this as ModeDetailRoute;

  @override
  String get location => GoRouteData.$location(
    '/settings/modes/${Uri.encodeComponent(_self.modeId)}/details',
    queryParams: {
      if (_self.stage != null) 'stage': _self.stage,
      if (_self.edge != null) 'edge': _self.edge,
    },
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $BotDetailsRoute on GoRouteData {
  static BotDetailsRoute _fromState(GoRouterState state) =>
      BotDetailsRoute(botId: state.pathParameters['botId']!);

  BotDetailsRoute get _self => this as BotDetailsRoute;

  @override
  String get location =>
      GoRouteData.$location('/bots/${Uri.encodeComponent(_self.botId)}');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $BotConversationRoute on GoRouteData {
  static BotConversationRoute _fromState(GoRouterState state) =>
      BotConversationRoute(
        botId: state.pathParameters['botId']!,
        chatId: state.pathParameters['chatId']!,
        threadId: state.pathParameters['threadId']!,
      );

  BotConversationRoute get _self => this as BotConversationRoute;

  @override
  String get location => GoRouteData.$location(
    '/bots/${Uri.encodeComponent(_self.botId)}/chats/${Uri.encodeComponent(_self.chatId)}/threads/${Uri.encodeComponent(_self.threadId)}',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $BotPlatformToolsRoute on GoRouteData {
  static BotPlatformToolsRoute _fromState(GoRouterState state) =>
      BotPlatformToolsRoute(
        botId: state.pathParameters['botId']!,
        chatId: state.pathParameters['chatId']!,
      );

  BotPlatformToolsRoute get _self => this as BotPlatformToolsRoute;

  @override
  String get location => GoRouteData.$location(
    '/bots/${Uri.encodeComponent(_self.botId)}/chats/${Uri.encodeComponent(_self.chatId)}/platform',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}
