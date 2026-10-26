import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../presentation/model_route_presentation.dart';
import '../view_models/conversation_view_model.dart';
import '../view_models/thread_status_view_model.dart';
import 'read_demand_mount.dart';

/// Public Smart seam for live route controls. The builder receives immutable
/// props and source-bound actions, not either feature's private VM or handles.
class ConversationModelRouteConnector extends ConsumerWidget {
  const ConversationModelRouteConnector({
    required this.threadId,
    required this.builder,
    super.key,
  });
  final String threadId;
  final Widget Function(
    ConversationModelRouteProps props,
    ThreadModelRouteWriter? write,
    Future<void> Function() retryRead,
  )
  builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = threadStatusViewModelProvider(threadId);
    final value = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final metadata = ref.watch(
      conversationViewModelProvider(threadId)
          .select((value) => value.value?.metadata),
    );
    return ReadDemandMount(
      identity: ('input-model-route', threadId),
      begin: vm.beginModelRouteDemand,
      child: value.when(
        loading: () => const SizedBox.shrink(),
        error: (error, stack) => Text(error.toString()),
        data: (_) => builder(
          vm.modelRouteProps(metadata),
          vm.captureModelRouteWriter(metadata),
          vm.retryModelRouteRead,
        ),
      ),
    );
  }
}
