import 'package:anywork_client/studio_client.dart' show ModeEditorState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client_provider.dart';
import 'observe_client.dart';

/// Display-only mirror of the Client-owned mode editor draft.
///
/// The account owns one observer permit. Disposal cancels that observation
/// and releases the permit; it never closes the draft or the Client resource.
final modeEditorStateProvider = Provider.autoDispose<ModeEditorState>((ref) {
  final owner = ref.watch(anyworkClientProvider).modeEditor;
  return observeClient(ref, owner.source, (_) => ref.invalidateSelf());
});
