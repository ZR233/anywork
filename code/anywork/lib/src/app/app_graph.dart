import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../infrastructure/frb/studio_api.dart';
import '../infrastructure/frb/studio_update_api.dart';
import '../platform/clipboard_image_reader.dart';
import '../platform/studio_platform.dart';
import '../platform/error_log.dart';
import '../presentation/view_models/timeline_session_owner.dart';

/// The application composition root is the only place that knows both the
/// transport implementation and the SDK-only Client.
class AppGraph {
  AppGraph({
    required StudioTransport transport,
    String? clientId,
    StudioUpdateApi? updateApi,
    bool updatesEnabled = false,
  }) {
    final staged = <String, StagedClipboardImage>{};
    final stager = const SystemClipboardImageStager();
    client = AnyworkClient(
      transport: transport,
      clientId: clientId ?? 'app-${identityHashCode(this)}',
      updateApi: updateApi,
      updatesEnabled: updatesEnabled,
      clipboardImageStager: (Uint8List bytes) async {
        final image = await stager.stage(bytes);
        staged[image.path] = image;
        return image.path;
      },
      clipboardImageCleanup: (path) async {
        final image = staged[path];
        if (image == null) return;
        await image.dispose();
        staged.remove(path);
      },
    );
    client.updates.attach();
    timeline = TimelineSessionOwner(client: client);
  }

  factory AppGraph.production() => AppGraph(
    transport: FrbStudioTransport(),
    updateApi: const FrbStudioUpdateApi(),
    updatesEnabled:
        isWindowsPlatform &&
        (const bool.fromEnvironment('dart.vm.product') ||
            const bool.fromEnvironment('ANYWORK_DRIVER')) &&
        !const bool.fromEnvironment('ANYWORK_DEMO'),
  );
  factory AppGraph.demo({bool driver = false}) => AppGraph(
    transport: driver
        ? DriverDemoStudioTransport(lspActivityLoop: true)
        : DemoStudioTransport(lspActivityLoop: true),
  );

  ValueListenable<StudioStartupPhase> get startupProgress =>
      FrbStudioTransport.startupProgress;
  ValueListenable<StartupRecoveryReport?> get startupRecovery =>
      FrbStudioTransport.startupRecovery;
  void dismissStartupRecovery() =>
      FrbStudioTransport.startupRecovery.value = null;

  /// Client publishes success/failure before this application-level handler
  /// records diagnostics. A route never owns a separate startup Future or flag.
  Future<void> initialize() =>
      client.bootstrap().catchError((Object error, StackTrace stack) {
        recordDartError(
          error,
          stack,
          stage: 'bootstrap',
          correlationId: client.bootstrapState.value.failure?.correlationId,
        );
      });

  Future<void> retryStartup() {
    FrbStudioTransport.retryInitialization();
    return initialize();
  }

  late final AnyworkClient client;
  late final TimelineSessionOwner timeline;
  Future<CloseReport>? _closing;

  Future<CloseReport> close({required DateTime deadline}) =>
      _closing ??= _close(deadline);

  /// 关闭顺序：先同步发布「无展示」促使现存 Chat 子树卸载，再同时收束 Client。
  ///
  /// `timeline.close` 在首次 await 之前同步清空展示元数据；视图卸载后其真实 `dispose`
  /// 才允许 lease 销毁 controller 并观察 stock stream done。树仍借用 controller 时不会
  /// 提前 ACK，重复 close 得到同一个释放结果（design/26 §26.8）。
  Future<CloseReport> _close(DateTime deadline) async {
    final timelineClose = timeline.close(deadline: deadline);
    final clientClose = client.close(deadline: deadline);
    final reports = await Future.wait([timelineClose, clientClose]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }
}

/// Borrowed instance. ProviderScope owns observations, never the application.
final appGraphProvider = Provider<AppGraph>((ref) {
  throw StateError('The application must inject its AppGraph');
});
