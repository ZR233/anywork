import 'package:anywork_client/lifecycle.dart';

import '../infrastructure/demo/statistics/demo_statistics_feed.dart';
import '../infrastructure/demo/studio_demo_api.dart';
import '../infrastructure/frb/statistics/frb_statistics_feed.dart';
import '../infrastructure/frb/studio_api.dart';
import '../infrastructure/frb/studio_update_api.dart';
import '../platform/clipboard_image_reader.dart';
import 'app_graph.dart';
import 'frb_startup_host.dart';
import 'studio_startup_host.dart';

/// Production composition root. The only module that names FRB adapters.
AppGraph createProductionAppGraph({
  ClipboardImageStager? clipboardImageStager,
}) {
  final root = ClientScope(owner: 'application');
  final runtime = FrbRuntimeOwner(startupScope: root.child('startup'));
  final content = root.child('transport-content');
  final progress = root.child('shutdown-progress');
  return AppGraph(
    scope: root.child('app'),
    closeLifecycleRoot: (budget) async {
      final report = await root.close(budget: budget);
      runtime.recordLifecycleCloseReport(report);
      return report;
    },
    transport: FrbStudioTransport(
      runtime: runtime,
      contentScope: content,
      progressScope: progress,
    ),
    acpBusinessPort: FrbAcpBusinessPort(ensureReady: runtime.ensureReady),
    statisticsFeed: const FrbStatisticsFeedPort(),
    updateApi: FrbStudioUpdateApi(ensureReady: runtime.ensureReady),
    updatesEnabled:
        const bool.fromEnvironment('dart.vm.product') &&
        !const bool.fromEnvironment('ANYWORK_DEMO'),
    startupHost: FrbStudioStartupHost(runtime),
    clipboardImageStager: clipboardImageStager,
  );
}

/// In-process demo composition. Used by the demo entry and adapter tests.
AppGraph createDemoAppGraph({ClipboardImageStager? clipboardImageStager}) {
  final root = ClientScope(owner: 'demo-application');
  return AppGraph(
    scope: root.child('app'),
    closeLifecycleRoot: (budget) => root.close(budget: budget),
    transport: DemoStudioTransport(
      contentScope: root.child('transport-content'),
      lspActivityLoop: true,
    ),
    statisticsFeed: DemoStatisticsFeedPort(),
    startupHost: ImmediateStudioStartupHost(),
    clipboardImageStager: clipboardImageStager,
  );
}
