import 'package:anywork_client/studio_client.dart' show StartSessionDraft;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/models.dart'
    show
        StartSessionDraft,
        StartSessionProjectDraft,
        StartSessionModelIntent,
        overlayStartSessionRoute;

part 'start_session_controller.g.dart';

/// This observer borrows the Client's logical draft across routes.
@riverpod
StartSessionDraft startSessionController(Ref ref) {
  final source = ref.read(anyworkClientProvider).startDraft.source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}
