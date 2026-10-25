import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/studio_l10n.dart';
import '../../platform/error_log.dart';
import '../app_bindings.dart';
import '../theme/material3_theme.dart';
import 'startup_boundary.dart';
import 'startup_view_model.dart';

/// The launch root exists before any graph. Assembly hands off only a complete
/// real application; until then the existing startup VM/boundary owns all
/// loading, failure and explicit retry presentation. This scope has no domain
/// overrides or native resources and is unmounted when the real root installs.
ProviderScope createApplicationLaunch({
  required Future<void> Function() assemble,
}) => ProviderScope(
  // The assembly transaction includes runApp's synchronous widget handoff;
  // it cannot release rollback responsibility merely by returning a widget.
  overrides: [applicationAssemblyProvider.overrideWithValue(assemble)],
  child: const _ApplicationLaunchBoundary(),
);

class _ApplicationLaunchBoundary extends ConsumerStatefulWidget {
  const _ApplicationLaunchBoundary();

  @override
  ConsumerState<_ApplicationLaunchBoundary> createState() =>
      _ApplicationLaunchBoundaryState();
}

class _ApplicationLaunchBoundaryState
    extends ConsumerState<_ApplicationLaunchBoundary> {
  @override
  void initState() {
    super.initState();
    // Lifecycle starts one explicit attempt. A rebuild never reassembles; a
    // failed attempt remains in StartupViewModel until its existing retry fires.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        Future<void>.sync(
          () => ref.read(startupViewModelProvider.notifier).retry(),
        ).catchError((Object error, StackTrace stack) {
          recordDartError(error, stack, stage: 'application-bootstrap');
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => context.l10n.appTitle,
    debugShowCheckedModeBanner: false,
    theme: pureStudioTheme(),
    themeMode: ThemeMode.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => Theme(
      data: pureStudioTheme(locale: Localizations.localeOf(context)),
      child: child!,
    ),
    home: const ApplicationStartupBoundary(child: SizedBox.shrink()),
  );
}
