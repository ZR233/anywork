import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/plan_view_model.dart';
import '../views/plan_view.dart';
import '../widgets/conversation_markdown.dart';
import 'markdown_connector.dart';

class PlanConnector extends ConsumerWidget {
  const PlanConnector({required this.threadId, super.key});
  final String threadId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = planViewModelProvider(threadId);
    final value = ref.watch(provider);
    return value.when(loading: () => const SizedBox.shrink(),
      error: (error, stack) => const Icon(Icons.error_outline),
      data: (state) => PlanView(state: state,
        onToggle: () => ref.read(provider.notifier).toggle(),
        onRetry: () => ref.read(provider.notifier).loadDocument().ignore(),
        documentBuilder: (_, markdown) => MarkdownConnector(
          id: 'plan:$threadId:${state.document!.version}:${state.document!.contentHash}',
          text: markdown, surface: MarkdownSurface.panel)));
  }
}
