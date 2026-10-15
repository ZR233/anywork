import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_graph.dart';

final anyworkClientProvider = Provider<AnyworkClient>(
  (ref) => ref.read(appGraphProvider).client,
);
