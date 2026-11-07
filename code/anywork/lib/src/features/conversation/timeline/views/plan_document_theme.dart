import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// Plan reading typography over the existing Markdown theme. Link, code and
/// table rendering keep the surrounding production configuration.
class PlanDocumentTheme extends StatelessWidget {
  const PlanDocumentTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = GptMarkdownTheme.of(context);
    final text = Theme.of(context).textTheme;
    TextStyle heading(TextStyle? style, double size, double height) =>
        (style ?? text.bodyMedium ?? DefaultTextStyle.of(context).style)
            .copyWith(
              fontSize: size,
              height: height,
              fontWeight: FontWeight.w600,
            );
    TextStyle minorHeading(TextStyle? style) =>
        heading(style, (style?.fontSize ?? 16).clamp(0, 16).toDouble(), 1.5);

    return GptMarkdownTheme(
      gptThemeData: base.copyWith(
        h1: heading(base.h1 ?? text.headlineLarge, 24, 1.4),
        h2: heading(base.h2 ?? text.headlineMedium, 18, 1.5),
        h3: heading(base.h3 ?? text.headlineSmall, 16, 1.5),
        h4: minorHeading(base.h4 ?? text.titleLarge),
        h5: minorHeading(base.h5 ?? text.titleMedium),
        h6: minorHeading(base.h6 ?? text.titleSmall),
        autoAddDividerLineAfterH1: false,
      ),
      child: child,
    );
  }
}
