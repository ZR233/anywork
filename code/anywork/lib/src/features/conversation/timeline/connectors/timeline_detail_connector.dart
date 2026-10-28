import 'dart:async';

import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../presentation/view_models/timeline_session_owner.dart';
import '../view_models/timeline_detail_owner.dart';
import '../views/timeline_detail_view.dart';
import '../widgets/timeline_entry_view.dart';

Future<void> openTimelineDetail(
  BuildContext context, {
  required TimelineDisplayLease lease,
  required String itemId,
  required ThreadContentFieldView field,
}) async {
  final owner = TimelineDetailOwner(lease: lease, itemId: itemId, field: field);
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TimelineDetailConnector(owner: owner, field: field),
    );
  } finally {
    await owner.close();
    owner.dispose();
  }
}

class TimelineDetailConnector extends StatefulWidget {
  const TimelineDetailConnector({
    super.key,
    required this.owner,
    required this.field,
  });
  final TimelineDetailOwner owner;
  final ThreadContentFieldView field;
  @override
  State<TimelineDetailConnector> createState() =>
      _TimelineDetailConnectorState();
}

class _TimelineDetailConnectorState extends State<TimelineDetailConnector> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.owner.load());
  }

  Future<void> _close() async {
    try {
      await widget.owner.close();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: ListenableBuilder(
      listenable: widget.owner,
      builder: (context, _) => TimelineDetailView(
        title: timelineFieldLabel(widget.field),
        state: widget.owner.state,
        onClose: () => unawaited(_close()),
        onRetry: () => unawaited(widget.owner.load()),
        onCopy: () {
          if (!widget.owner.canCopy) return;
          unawaited(
            Clipboard.setData(ClipboardData(text: widget.owner.state.text)),
          );
        },
      ),
    ),
  );
}
