import 'package:material_ui/material_ui.dart';

import '../../composer/views/composer_dock_view.dart';

/// Pure ACP workspace shell layout combining the centered reading stream,
/// docked permission/composer stack (`1040px`), `38px` status bar, and an
/// optional `360px` right-side workflow graph panel while preserving a minimum
/// visible reading budget on short desktop windows.
class AcpWorkspaceView extends StatelessWidget {
  const AcpWorkspaceView({
    super.key,
    required this.readingArea,
    required this.composer,
    required this.statusBar,
    this.permissionDock,
    this.sidePanel,
  });

  final Widget readingArea;
  final Widget? permissionDock;
  final Widget composer;
  final Widget statusBar;
  final Widget? sidePanel;

  static const double _minimumReadingReserve = 96.0;
  static const double _maximumReadingReserve = 200.0;
  static const double _readingReserveFraction = 0.28;
  static const double sidePanelWidth = 360.0;

  double _footerMaxHeight(double viewportHeight) {
    final reserve = (viewportHeight * _readingReserveFraction)
        .clamp(_minimumReadingReserve, _maximumReadingReserve)
        .toDouble();
    final available = viewportHeight - reserve;
    return available > 0 ? available : 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedHeight && constraints.maxHeight < 600;
        final footer = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ComposerDockView(
              compact: compact,
              additionalDiagnostics: const [],
              childInteractions: permissionDock,
              content: composer,
            ),
            statusBar,
          ],
        );

        final boundedFooter = constraints.hasBoundedHeight
            ? ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _footerMaxHeight(constraints.maxHeight),
                ),
                child: SingleChildScrollView(child: footer),
              )
            : footer;

        final mainColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: readingArea),
            boundedFooter,
          ],
        );

        if (sidePanel == null) {
          return mainColumn;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: mainColumn),
            SizedBox(width: sidePanelWidth, child: sidePanel),
          ],
        );
      },
    );
  }
}
