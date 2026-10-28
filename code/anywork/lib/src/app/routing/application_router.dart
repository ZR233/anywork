import 'package:go_router/go_router.dart';

import 'app_route.dart';

GoRouter createApplicationRouter() =>
    GoRouter(restorationScopeId: 'anywork-router', routes: $appRoutes);
