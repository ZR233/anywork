import 'package:flutter/material.dart';

/// Loads the remaining pages of a bounded settings collection without exposing a
/// pagination control.
///
/// The page renders exactly the records the repository already published; this
/// loader requests the next page from behind the scenes and repeats only after
/// the published set actually changed. Semantics:
///
/// * one request at a time — the next page is asked for only while no read of
///   that collection is in flight, and the post-frame turn re-checks the
///   current widget state before publishing;
/// * a failure stops the chain — [blocked] is true whenever the last attempt
///   recorded an error, so the existing records and the real failure stay
///   visible instead of being retried in a loop;
/// * the same page is never requested twice — the requested page set is
///   identified by [requestedCount], and a page that returns without growth
///   does not schedule another attempt;
/// * nothing is published after disposal — the state checks `mounted` before it
///   calls back, and it never starts a native read of its own.
class AutoPageLoader extends StatefulWidget {
  const AutoPageLoader({
    required this.hasMore,
    required this.loading,
    required this.blocked,
    required this.requestedCount,
    required this.onLoadMore,
    required this.child,
    super.key,
  });

  /// The repository reports a further page that has not been read yet.
  final bool hasMore;

  /// A read of this collection is in flight.
  final bool loading;

  /// The previous attempt for this collection failed.
  final bool blocked;

  /// Identity of the page set that is currently published.
  final int requestedCount;

  /// Starts the next page through the owner's existing read command.
  final VoidCallback onLoadMore;

  final Widget child;

  @override
  State<AutoPageLoader> createState() => _AutoPageLoaderState();
}

class _AutoPageLoaderState extends State<AutoPageLoader> {
  int? _requestedForCount;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant AutoPageLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    if (!widget.hasMore || widget.loading || widget.blocked) return;
    if (_requestedForCount == widget.requestedCount) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.hasMore || widget.loading || widget.blocked) return;
      if (_requestedForCount == widget.requestedCount) return;
      _requestedForCount = widget.requestedCount;
      widget.onLoadMore();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
