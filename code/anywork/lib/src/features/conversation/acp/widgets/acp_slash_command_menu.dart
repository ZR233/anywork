import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../state/acp_view_state.dart';

/// Matches an ACP `/` slash-command query at the start of the composer draft.
///
/// Only triggers on the leading token (before any whitespace or newline) so
/// prose file paths such as `lib/main.dart` or mid-sentence `/` never pop the
/// command drawer unexpectedly.
String? matchAcpSlashTrigger(String draft) {
  if (!draft.startsWith('/')) return null;
  for (var i = 1; i < draft.length; i++) {
    final unit = draft.codeUnitAt(i);
    if (unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D) {
      return null;
    }
  }
  return draft.substring(1);
}

int? _scoreSlashCommand(AcpSlashCommandPresentation command, String query) {
  final name = command.name.toLowerCase();
  if (name == query) return 0;
  if (name.startsWith(query)) return 2;
  final segments = name.split(RegExp(r'[-_/:]'));
  if (segments.any((part) => part.startsWith(query))) return 4;
  if (name.contains(query)) return 6;
  final desc = command.description.toLowerCase();
  if (desc.contains(query)) return 20;
  return null;
}

/// Ranks [commands] against a leading slash [query] while preserving server
/// order within each relevance tier.
List<AcpSlashCommandPresentation> rankAcpSlashCommands(
  List<AcpSlashCommandPresentation> commands,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return List.unmodifiable(commands);
  final scored = <({AcpSlashCommandPresentation cmd, int score, int index})>[];
  for (var i = 0; i < commands.length; i++) {
    final score = _scoreSlashCommand(commands[i], normalized);
    if (score != null) {
      scored.add((cmd: commands[i], score: score, index: i));
    }
  }
  scored.sort((a, b) {
    final byScore = a.score.compareTo(b.score);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });
  return [for (final item in scored) item.cmd];
}

/// Floating command palette anchored above the ACP composer when typing `/`.
class AcpSlashCommandMenu extends StatefulWidget {
  const AcpSlashCommandMenu({
    super.key,
    required this.commands,
    required this.highlightedIndex,
    required this.onHighlightedChanged,
    required this.onSelect,
  });

  final List<AcpSlashCommandPresentation> commands;
  final int highlightedIndex;
  final ValueChanged<int> onHighlightedChanged;
  final ValueChanged<AcpSlashCommandPresentation> onSelect;

  @override
  State<AcpSlashCommandMenu> createState() => _AcpSlashCommandMenuState();
}

class _AcpSlashCommandMenuState extends State<AcpSlashCommandMenu> {
  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _rowKeys = [];

  @override
  void didUpdateWidget(covariant AcpSlashCommandMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightedIndex != oldWidget.highlightedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealHighlighted());
    }
  }

  void _revealHighlighted() {
    if (!mounted ||
        widget.highlightedIndex < 0 ||
        widget.highlightedIndex >= _rowKeys.length) {
      return;
    }
    final ctx = _rowKeys[widget.highlightedIndex].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: const Duration(milliseconds: 90),
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    _rowKeys.length = 0;
    for (var i = 0; i < widget.commands.length; i++) {
      _rowKeys.add(GlobalKey());
    }

    return Padding(
      key: const ValueKey('acp-slash-menu'),
      padding: const EdgeInsets.only(bottom: 8),
      child: StudioPanel(
        backgroundColor: colors.surfaceContainerLowest,
        borderColor: colors.outlineVariant,
        radius: StudioRadii.md,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: widget.commands.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.terminal_rounded,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.acpSlashMenuNoMatches,
                        style: context.text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Text(
                        l10n.acpSlashMenuLabel,
                        style: context.text.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < widget.commands.length; i++)
                              _SlashCommandRow(
                                key: _rowKeys[i],
                                rowKey: ValueKey(
                                  'acp-slash-item:${widget.commands[i].name}',
                                ),
                                command: widget.commands[i],
                                highlighted: i == widget.highlightedIndex,
                                onHover: () => widget.onHighlightedChanged(i),
                                onTap: () =>
                                    widget.onSelect(widget.commands[i]),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SlashCommandRow extends StatelessWidget {
  const _SlashCommandRow({
    super.key,
    required this.rowKey,
    required this.command,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final Key rowKey;
  final AcpSlashCommandPresentation command;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Material(
        color: highlighted ? colors.surfaceContainerHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        child: InkWell(
          key: rowKey,
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Text(
                  '/${command.name}',
                  style: context.text.labelMedium?.copyWith(
                    fontFamily: studioCodeFontFamily,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                if (command.inputHint case final hint?) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Text(
                      hint,
                      style: context.text.labelSmall?.copyWith(
                        fontFamily: studioCodeFontFamily,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (command.description.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      command.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
