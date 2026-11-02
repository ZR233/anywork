// Thin native-test assembly for shutdown faults. Product, capture, and
// release builds keep lib/main.dart. Each scene enables only the fault it
// needs through ANYWORK_NATIVE_SHUTDOWN_FAULT.
//
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:io';

import 'package:anywork/main.dart' as studio;
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/capture/capture_extension.dart';
import 'package:anywork/src/infrastructure/frb/statistics/frb_statistics_feed.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork_client/studio_ports.dart';

void main() {
  if (const bool.fromEnvironment('dart.vm.product')) {
    throw StateError('Native fault assembly is unavailable in product builds');
  }
  if (const bool.fromEnvironment('ANYWORK_CAPTURE')) {
    throw StateError('Native fault assembly must not enable capture');
  }
  maybeRegisterCaptureExtension();
  final fault = Platform.environment['ANYWORK_NATIVE_SHUTDOWN_FAULT'];
  switch (fault) {
    case 'pending-init':
      FrbStudioTransport.debugOverrideInitialization(
        () => Completer<void>().future,
      );
      studio.bootstrapStudio();
    case 'bridge-load-error':
      FrbStudioTransport.debugOverrideInitialization(() async {
        throw StateError('native-test bridge load failure');
      });
      studio.bootstrapStudio();
    case 'subscription':
      studio.bootstrapStudio(
        graph: AppGraph(
          transport: _FaultSubscriptionTransport(),
          statisticsFeed: const FrbStatisticsFeedPort(),
        ),
      );
    case null:
    case '':
      throw StateError(
        'ANYWORK_NATIVE_SHUTDOWN_FAULT must name pending-init, bridge-load-error, or subscription',
      );
    default:
      throw StateError('Unknown native shutdown fault: $fault');
  }
}

/// Real FRB transport whose shutdown-progress subscription is faulty.
final class _FaultSubscriptionTransport extends FrbStudioTransport {
  @override
  Stream<StudioShutdownProgress> subscribeShutdownProgress() {
    late final StreamController<StudioShutdownProgress> controller;
    controller = StreamController<StudioShutdownProgress>(
      onListen: () {
        controller.addError(
          StateError('native-test shutdown progress subscription failure'),
          StackTrace.current,
        );
      },
      onCancel: () => Completer<void>().future,
    );
    return controller.stream;
  }
}
