import 'package:flutter/material.dart';

import '../../../../shared/studio_driver_keys.dart';

class PlanDetailView extends StatefulWidget {
  const PlanDetailView({
    super.key,
    required this.identity,
    required this.title,
    required this.body,
    required this.awaitingConfirmation,
    required this.onClose,
    this.onToggleReadingMode,
    this.fullWidth = false,
  });
  final String identity;
  final String title;
  final Widget body;
  final bool awaitingConfirmation;
  final VoidCallback onClose;
  final VoidCallback? onToggleReadingMode;
  final bool fullWidth;
  @override
  State<PlanDetailView> createState() => _PlanDetailViewState();
}

class _PlanDetailViewState extends State<PlanDetailView> {
  final ScrollController _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    key: StudioDriverKeys.planDetails,
    builder: (context, constraints) {
      final header = SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      key: StudioDriverKeys.planDetailsTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      widget.awaitingConfirmation ? '等待确认' : '已批准',
                      key: StudioDriverKeys.planDetailsStatus,
                    ),
                  ],
                ),
              ),
              if (widget.onToggleReadingMode != null) ...[
                IconButton(
                  key: StudioDriverKeys.planDetailsReadingMode,
                  visualDensity: VisualDensity.standard,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  tooltip: widget.fullWidth ? '并排阅读' : '全宽阅读',
                  onPressed: widget.onToggleReadingMode,
                  icon: Icon(
                    widget.fullWidth
                        ? Icons.vertical_split_outlined
                        : Icons.open_in_full,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                key: StudioDriverKeys.planDetailsClose,
                visualDensity: VisualDensity.standard,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: '关闭',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      );
      final body = Padding(
        padding: const EdgeInsets.all(18),
        child: widget.body,
      );
      Widget scroll(Widget child) => Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          key: StudioDriverKeys.planDetailsScroll,
          controller: _scroll,
          primary: false,
          child: child,
        ),
      );
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: SelectionArea(
          child: constraints.maxHeight < 260
              ? scroll(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [header, const Divider(height: 1), body],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const Divider(height: 1),
                    Expanded(child: scroll(body)),
                  ],
                ),
        ),
      );
    },
  );
}
