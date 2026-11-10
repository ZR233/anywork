import 'package:material_ui/material_ui.dart';

/// 起始页只负责创建期外壳，内层输入组件由 connector 与运行期共用。
class StartPageComposerView extends StatelessWidget {
  const StartPageComposerView({
    required this.environmentBar,
    required this.composer,
    super.key,
  });

  final Widget environmentBar;
  final Widget composer;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: DecoratedBox(
          key: const ValueKey('start-creation-card'),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [environmentBar, composer],
            ),
          ),
        ),
      ),
    ),
  );
}
