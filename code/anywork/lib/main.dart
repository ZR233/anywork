import 'package:anywork_client/workspace_ports.dart' show StartupPort;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/anywork_app.dart';
import 'src/app/bootstrap/application_assembly_failure.dart';
import 'src/app/bootstrap/launch_application.dart';
import 'src/app/composition/application_container.dart';
import 'src/app/composition/native_application_owners.dart';
import 'src/app/lifecycle/exit_participant.dart';
import 'src/platform/desktop_tray_host.dart';

export 'src/app/composition/native_application_owners.dart'
    show NativeApplication;

void main() {
  // bootstrapStudio creates the binding in the same guarded Zone as runApp.
  // Assembly never initializes a parent-Zone binding or eagerly loads FRB.
  _launchProduction();
}

void _launchProduction() {
  runApplication(createApplicationForLaunch);
}

/// Production and Driver choose only their explicit decoration/participants;
/// they receive the same real composition owners from one factory.
Future<NativeApplication> createApplicationForLaunch({
  bool driver = false,
  StartupPort Function(StartupPort port)? decorateStartup,
  List<ApplicationCloseParticipant> additionalParticipants = const [],
}) => createNativeApplicationOwners(
  driver: driver,
  decorateStartup: decorateStartup,
  additionalParticipants: additionalParticipants,
);

/// Binding, Driver extension registration and runApp share bootstrap's Zone.
/// A createContainer callback owns allocations until it returns its container;
/// on a callback throw it must dispose any container not returned to launch.
void runApplication(
  Future<NativeApplication> Function() createApplication, {
  ProviderContainer Function(NativeApplication application)? createContainer,
  void Function()? beforeRun,
}) => bootstrapStudio(
  beforeRun: beforeRun,
  assemble: () async {
    final application = await createApplication();
    ProviderContainer? container;
    try {
      final graph = application.graph;
      container =
          createContainer?.call(application) ??
          createApplicationContainer(graph);
      requireApplicationContainer(container, graph);
      runApp(
        UncontrolledProviderScope(
          container: container,
          child: AnyworkApp(
            graph: graph,
            desktopHostBuilder: (BuildContext context, Widget child) =>
                DesktopTrayHost(
                  controller: application.tray,
                  enabled: true,
                  child: child,
                ),
          ),
        ),
      );
      application.completeLaunch();
    } on Object catch (error, stack) {
      // No widget owns this container before handoff. Stop its observations
      // first; real Repository/presentation cleanup is a separate async join,
      // never exitCoordinator.exit() (which would arm native host termination).
      final report = await application.rollback(
        disposeContainer: container?.dispose,
      );
      if (!report.complete) {
        throw ApplicationAssemblyFailure(
          cause: error,
          stack: stack,
          report: report,
          retryCleanup: application.rollback,
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  },
);
