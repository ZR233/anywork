import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';

import '../state/content_reference_identity.dart';
import '../widgets/timeline_content_range_view.dart';
import 'timeline_content_connector.dart';

/// One visible Plan document on the original content read lease. State owns the
/// reference; this widget owns only its cancellable, bounded reading demand.
class PlanDocumentConnector extends StatefulWidget {
  const PlanDocumentConnector({
    required this.content,
    required this.reference,
    required this.isCurrent,
    required this.documentBuilder,
    super.key,
  });
  final ConversationContent content;
  final ContentRef reference;
  final bool Function() isCurrent;
  final Widget Function(String) documentBuilder;
  @override
  State<PlanDocumentConnector> createState() => _PlanDocumentConnectorState();
}

class _PlanDocumentConnectorState extends State<PlanDocumentConnector> {
  ConversationQueryScope? _scope;
  late final Object? _attempt = widget.content.currentAttemptId;
  bool _retired = false;
  bool get _active =>
      mounted &&
      !_retired &&
      widget.isCurrent() &&
      !widget.content.isClosed &&
      widget.content.currentAttemptId == _attempt;

  @override
  void didUpdateWidget(covariant PlanDocumentConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.content, widget.content) ||
        contentReferenceIdentity(oldWidget.reference) !=
            contentReferenceIdentity(widget.reference)) {
      throw StateError('A new Plan reference requires a new document subtree');
    }
  }

  @override
  void dispose() {
    _retired = true;
    final scope = _scope;
    scope?.retire();
    // The SDK retains failed close obligations on its original content owner.
    if (scope != null) unawaited(scope.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TimelineBodyReadIntent(
    child: TimelineContentRangeConnector(
      itemId: 'plan-document',
      contentKey: 'plan.document',
      label: '计划文档',
      reference: widget.reference,
      isDisplayActive: () => _active,
      witness: (text, child) =>
          text.isEmpty ? child : widget.documentBuilder(text),
      readContent: (reference, range) {
        if (!_active) throw const StaleConversationScope();
        final scope = _scope ??= widget.content.openScope(generation: 1);
        return scope.readContent(reference: reference, range: range);
      },
    ),
  );
}
