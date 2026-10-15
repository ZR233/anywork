part of 'timeline_view.dart';

/// This connector observes one projected row. The row block receives immutable
/// props and never reaches back into a provider or another canonical source.
class _TimelineRowConnector extends StatefulWidget {
  const _TimelineRowConnector({
    required this.query,
    required this.builder,
    required this.onChange,
    super.key,
  });
  final TimelineRowQuery query;
  final Widget Function(TimelineRowSnapshot row) builder;
  final VoidCallback onChange;

  @override
  State<_TimelineRowConnector> createState() => _TimelineRowConnectorState();
}

class _TimelineRowConnectorState extends State<_TimelineRowConnector> {
  Observation? _observation;
  TimelineRowSnapshot? _row;
  Object? _bindingError;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _bindingError = null;
    try {
      final watched = widget.query.watchLatest((next) {
        if (!mounted) return;
        if (next != null) widget.onChange();
        setState(() => _row = next);
      });
      _observation = watched.observation;
      _row = watched.value;
    } catch (error) {
      _observation = null;
      _row = null;
      _bindingError = error;
    }
  }

  @override
  void didUpdateWidget(covariant _TimelineRowConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.query, widget.query)) {
      _observation?.cancel();
      _bind();
    }
  }

  @override
  void dispose() {
    // Detach this observer only. Eviction and query closure belong to the lease.
    _observation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bindingError case final error?) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 8),
            Expanded(child: Text(error.toString())),
            TextButton(
              key: const ValueKey('timeline-row-observation-retry'),
              onPressed: () => setState(_bind),
              child: Text(context.l10n.sidebarRetry),
            ),
          ],
        ),
      );
    }
    final row = _row;
    return row == null ? const SizedBox.shrink() : widget.builder(row);
  }
}

extension on _TimelineViewState {
  Widget _buildObservedRow(String itemId) {
    final key = ValueKey<(String?, String)>((widget.threadId, itemId));
    final rows = widget.rowQuery;
    final query = rows.row(itemId);
    if (query == null) return SizedBox.shrink(key: key);
    final threadId = widget.threadId;
    final viewId = widget.viewId;
    return _TimelineRowConnector(
      key: key,
      query: query,
      onChange: () {
        // A row subscription outlives individual reading gestures. Its source
        // must still belong to this view; frame-end corrections separately
        // capture the current reading generation when they are scheduled.
        if (mounted &&
            threadId == widget.threadId &&
            viewId == widget.viewId &&
            identical(rows, widget.rowQuery) &&
            identical(query, rows.row(itemId))) {
          _handleObservedRowChange();
        }
      },
      builder: (snapshot) => _buildRow(snapshot.row, body: snapshot.body),
    );
  }
}
