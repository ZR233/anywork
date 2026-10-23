import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/settings/presentation_api.dart' as settings;
import '../l10n/app_localizations.dart';
import '../l10n/studio_l10n.dart';
import '../platform/error_log.dart';
import 'app_graph.dart';
import 'bootstrap/startup_boundary.dart';
import 'bootstrap/startup_view_model.dart';
import 'lifecycle/application_lifecycle_boundary.dart';
import 'lifecycle/shutdown_overlay.dart';
import 'routing/application_router.dart';
import 'theme/material3_theme.dart';

/// A concrete graph is injected before any feature VM is built. This root owns
/// the only router and injects Settings' real public Screen/guard in its scope.
/// The desktop host builder supplies the real platform-owned tray host;
/// this widget does not recreate its static controller or native exit owner.
class AnyworkApp extends ConsumerStatefulWidget {
  const AnyworkApp({required this.graph,
    required this.desktopHostBuilder, super.key});
  final AppGraph graph;
  final Widget Function(BuildContext context, Widget child) desktopHostBuilder;

  @override
  ConsumerState<AnyworkApp> createState() => _AnyworkAppState();
}

class _AnyworkAppState extends ConsumerState<AnyworkApp> {
  late final _graph = widget.graph;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // Construct one router after this Graph's ProviderContainer is installed.
    // U1 alone owns the complete leave request/Mode lifetime/save guard; the
    // app forwards its original Future without another confirmation or writer.
    _router = createApplicationRouter(
      exitCoordinator: _graph.exitCoordinator,
      settingsScreen: (_) => const settings.SettingsScreen(),
      confirmLeaveSettings: (context) => settings.confirmLeaveSettings(context, ref),
    );
    // Explicit lifecycle action, never VM build or a Provider getter. The VM
    // presents typed bootstrap/admission errors without restarting on rebuild.
    unawaited(Future<void>.sync(() => ref.read(startupViewModelProvider.notifier).retry())
      .catchError((Object error, StackTrace stack) {
        recordDartError(error, stack, stage: 'application-bootstrap');
      }));
  }

  @override
  void didUpdateWidget(AnyworkApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.graph, _graph)) {
      throw StateError('Replacing an application owner requires unmounting its original app.');
    }
  }

  @override
  void dispose() {
    _router.dispose();
    // Repository/Container cleanup belongs to the same exit coordinator. UI
    // disposal is not native join or permission to clear drafts and permits.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ApplicationLifecycleBoundary(
    host: _graph.host, coordinator: _graph.exitCoordinator,
    child: MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: pureStudioTheme(), themeMode: ThemeMode.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router, restorationScopeId: 'anywork-app',
      builder: (context, child) => Theme(
        data: pureStudioTheme(locale: Localizations.localeOf(context)),
        child: widget.desktopHostBuilder(context,
          // Replace the entire Router, not a visual cover over Settings. This
          // really unmounts paused/offstage routes before display close joins.
          ApplicationShutdownBoundary(child: ApplicationStartupBoundary(
            child: child ?? const SizedBox.shrink())))),
    ),
  );
}
