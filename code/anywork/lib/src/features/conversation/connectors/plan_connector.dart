import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/plan_view_model.dart';
import '../views/plan_panel_props.dart';
import '../views/plan_view.dart';
import '../widgets/conversation_markdown.dart';
import 'markdown_connector.dart';

/// Smart connector for the Plan reading panel.
///
/// Reading mode, close and document retry are the only intents; approve and
/// revise stay in Interaction exclusively. [sideBySideFeasible] is a measured
/// layout fact passed down from the reading-area geometry owner.
class PlanPanelConnector extends ConsumerWidget {
  const PlanPanelConnector({
    required this.threadId,
    required this.sideBySideFeasible,
    super.key,
  });
  final String threadId;
  final bool sideBySideFeasible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = planViewModelProvider(threadId);
    final value = ref.watch(provider);
    return value.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const Icon(Icons.error_outline),
      data: (state) => PlanView(
        props: PlanPanelProps(
          state: state,
          sideBySideFeasible: sideBySideFeasible,
          onToggleReading: () =>
              ref.read(provider.notifier).toggleReadingMode(),
          onClose: () => ref.read(provider.notifier).close(),
          onRetry: () => ref.read(provider.notifier).loadDocument().ignore(),
          documentBuilder: (_, markdown) => MarkdownConnector(
            id: 'plan:$threadId:${state.document?.version}:${state.document?.contentHash}',
            text: markdown,
            surface: MarkdownSurface.panel,
          ),
        ),
      ),
    );
  }
}
