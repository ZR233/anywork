import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_graph.dart';
import '../../app/public_artifact_actions.dart';
import 'observe_client.dart';

final publicArtifactSaveProvider = Provider.autoDispose
    .family<PublicArtifactSaveState?, PublicArtifactActionKey>((ref, key) {
      final owner = ref.read(appGraphProvider).artifacts;
      late final PublicArtifactSaveState? current;
      current = observeClient(ref, owner.source, (next) {
        if (next[key] != current) ref.invalidateSelf();
      })[key];
      return current;
    });
