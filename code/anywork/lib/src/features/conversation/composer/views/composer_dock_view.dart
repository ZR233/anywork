import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';

class ComposerDockView extends StatelessWidget {
  const ComposerDockView({
    required this.compact,
    required this.additionalDiagnostics,
    required this.childInteractions,
    required this.content,
    super.key,
  });

  final bool compact;
  final List<Widget> additionalDiagnostics;
  final Widget? childInteractions;
  final Widget content;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 4, 12, 6)
          : const EdgeInsets.fromLTRB(12, 7, 12, 12),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: StudioLayout.conversationWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...additionalDiagnostics, ?childInteractions, content],
          ),
        ),
      ),
    ),
  );
}
