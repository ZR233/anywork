import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:anywork_client/workspace.dart';
import 'package:flutter/widgets.dart';

import '../../platform/error_log.dart';
import 'application_exit_coordinator.dart';
import 'native_exit_host.dart';

/// Native visibility (including Windows hidden/inactive) is not business exit.
/// Root instances are captured before dispose, so no disposed Ref is accessed.
class ApplicationLifecycleBoundary extends StatefulWidget {
  const ApplicationLifecycleBoundary({
    required this.host, required this.coordinator, required this.child, super.key,
  });
  final NativeExitHost host;
  final ApplicationExitCoordinator coordinator;
  final Widget child;
  @override
  State<ApplicationLifecycleBoundary> createState() => _ApplicationLifecycleBoundaryState();
}

class _ApplicationLifecycleBoundaryState extends State<ApplicationLifecycleBoundary>
    with WidgetsBindingObserver {
  late final _host = widget.host;
  late final _coordinator = widget.coordinator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _host.bind(this, _exit);
    unawaited(_host.configureDiagnostics().catchError(_recordFailure));
  }

  Future<void> _exit() => _coordinator.requestHostExit(ExitIntent.exit);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(_exit().catchError(_recordFailure));
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await _exit().catchError(_recordFailure);
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _host.unbind(this);
    unawaited(_exit().catchError(_recordFailure));
    super.dispose();
  }

  void _recordFailure(Object error, StackTrace stack) {
    recordDartError(error, stack, stage: 'application-lifecycle');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
