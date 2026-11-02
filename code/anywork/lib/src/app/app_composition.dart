import '../infrastructure/demo/statistics/demo_statistics_feed.dart';
import '../infrastructure/demo/studio_demo_api.dart';
import '../infrastructure/frb/statistics/frb_statistics_feed.dart';
import '../infrastructure/frb/studio_api.dart';
import '../infrastructure/frb/studio_update_api.dart';
import '../platform/clipboard_image_reader.dart';
import '../platform/studio_platform.dart';
import 'app_graph.dart';
import 'frb_startup_host.dart';
import 'studio_startup_host.dart';

/// Production composition root. The only module that names FRB adapters.
AppGraph createProductionAppGraph({
  ClipboardImageStager? clipboardImageStager,
}) {
  return AppGraph(
    transport: FrbStudioTransport(),
    statisticsFeed: const FrbStatisticsFeedPort(),
    updateApi: const FrbStudioUpdateApi(),
    updatesEnabled:
        isWindowsPlatform &&
        const bool.fromEnvironment('dart.vm.product') &&
        !const bool.fromEnvironment('ANYWORK_DEMO'),
    startupHost: FrbStudioStartupHost(),
    clipboardImageStager: clipboardImageStager,
  );
}

/// In-process demo composition. Used by the demo entry and adapter tests.
AppGraph createDemoAppGraph({ClipboardImageStager? clipboardImageStager}) {
  return AppGraph(
    transport: DemoStudioTransport(lspActivityLoop: true),
    statisticsFeed: DemoStatisticsFeedPort(),
    startupHost: ImmediateStudioStartupHost(),
    clipboardImageStager: clipboardImageStager,
  );
}
