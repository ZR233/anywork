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
          path: 'accounts/new',
          name: 'settings.account-create',
          hasOverriddenOnExit: true,
          factory: $AccountCreateRoute._fromState,
        ),
        GoRouteData.$route(
          path: 'accounts/:kind/:accountId',
          name: 'settings.account-details',
          hasOverriddenOnExit: true,
          factory: $AccountDetailsRoute._fromState,
          routes: [
            GoRouteData.$route(
              path: 'edit',
              name: 'settings.account-edit',
              hasOverriddenOnExit: true,
              factory: $AccountEditRoute._fromState,
            ),
            GoRouteData.$route(
              path: 'models/:modelId',
              name: 'settings.account-model',
              hasOverriddenOnExit: false,
              factory: $AccountModelRoute._fromState,
            ),
          ],
        ),
      ],
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
  static SettingsRoute _fromState(GoRouterState state) => SettingsRoute(
    section:
        (state.uri.queryParameters['section'] == null
            ? null
            : _decodeSettingsSection(state.uri.queryParameters['section']!)) ??
        SettingsSection.accounts,
  );

  SettingsRoute get _self => this as SettingsRoute;

  @override
  String get location => GoRouteData.$location(
    '/settings',
    queryParams: {
      if (_self.section != SettingsSection.accounts)
        'section': _encodeSettingsSection(_self.section),
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

const _$SettingsSectionEnumMap = {
  SettingsSection.accounts: 'accounts',
  SettingsSection.instructions: 'instructions',
  SettingsSection.workModes: 'work-modes',
  SettingsSection.skills: 'skills',
  SettingsSection.agents: 'agents',
  SettingsSection.mcp: 'mcp',
  SettingsSection.lsp: 'lsp',
  SettingsSection.ssh: 'ssh',
  SettingsSection.statistics: 'statistics',
  SettingsSection.security: 'security',
  SettingsSection.general: 'general',
  SettingsSection.bots: 'bots',
};

mixin $AccountCreateRoute on GoRouteData {
  static AccountCreateRoute _fromState(GoRouterState state) =>
      const AccountCreateRoute();

  @override
  String get location => GoRouteData.$location('/settings/accounts/new');

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

mixin $AccountDetailsRoute on GoRouteData {
  static AccountDetailsRoute _fromState(GoRouterState state) =>
      AccountDetailsRoute(
        kind: _$AccountKindEnumMap._$fromName(state.pathParameters['kind']!)!,
        accountId: state.pathParameters['accountId']!,
      );

  AccountDetailsRoute get _self => this as AccountDetailsRoute;

  @override
  String get location => GoRouteData.$location(
    '/settings/accounts/${Uri.encodeComponent(_$AccountKindEnumMap[_self.kind]!)}/${Uri.encodeComponent(_self.accountId)}',
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

const _$AccountKindEnumMap = {
  AccountKind.native: 'native',
  AccountKind.acp: 'acp',
};

mixin $AccountEditRoute on GoRouteData {
  static AccountEditRoute _fromState(GoRouterState state) => AccountEditRoute(
    kind: _$AccountKindEnumMap._$fromName(state.pathParameters['kind']!)!,
    accountId: state.pathParameters['accountId']!,
    focusModelId: state.uri.queryParameters['focus-model-id'],
    addModel:
        _$convertMapValue(
          'add-model',
          state.uri.queryParameters,
          _$boolConverter,
        ) ??
        false,
  );

  AccountEditRoute get _self => this as AccountEditRoute;

  @override
  String get location => GoRouteData.$location(
    '/settings/accounts/${Uri.encodeComponent(_$AccountKindEnumMap[_self.kind]!)}/${Uri.encodeComponent(_self.accountId)}/edit',
    queryParams: {
      if (_self.focusModelId != null) 'focus-model-id': _self.focusModelId,
      if (_self.addModel != false) 'add-model': _self.addModel.toString(),
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

mixin $AccountModelRoute on GoRouteData {
  static AccountModelRoute _fromState(GoRouterState state) => AccountModelRoute(
    kind: _$AccountKindEnumMap._$fromName(state.pathParameters['kind']!)!,
    accountId: state.pathParameters['accountId']!,
    modelId: state.pathParameters['modelId']!,
    tab:
        (state.uri.queryParameters['tab'] == null
            ? null
            : _decodeAccountModelTab(state.uri.queryParameters['tab']!)) ??
        AccountModelTab.specifications,
  );

  AccountModelRoute get _self => this as AccountModelRoute;

  @override
  String get location => GoRouteData.$location(
    '/settings/accounts/${Uri.encodeComponent(_$AccountKindEnumMap[_self.kind]!)}/${Uri.encodeComponent(_self.accountId)}/models/${Uri.encodeComponent(_self.modelId)}',
    queryParams: {
      if (_self.tab != AccountModelTab.specifications)
        'tab': _encodeAccountModelTab(_self.tab),
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

const _$AccountModelTabEnumMap = {
  AccountModelTab.specifications: 'specifications',
  AccountModelTab.pricing: 'pricing',
  AccountModelTab.evaluations: 'evaluations',
};

extension<T extends Enum> on Map<T, String> {
  T? _$fromName(String? value) =>
      entries.where((element) => element.value == value).firstOrNull?.key;
}

T? _$convertMapValue<T>(
  String key,
  Map<String, String> map,
  T? Function(String) converter,
) {
  final value = map[key];
  return value == null ? null : converter(value);
}

bool _$boolConverter(String value) {
  switch (value) {
    case 'true':
      return true;
    case 'false':
      return false;
    default:
      throw UnsupportedError('Cannot convert "$value" into a bool.');
  }
}
