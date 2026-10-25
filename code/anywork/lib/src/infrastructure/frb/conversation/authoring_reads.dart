import 'package:anywork_client/conversation_ports.dart';

import '../../../rust/api/studio/conversation/read/authoring.dart' as native;
import '../shared/adapter_failure.dart';
import 'authoring_converters.dart';
import 'identity_converters.dart';
import 'thread_read_connection.dart';
import 'value_read_converters.dart';

final class FrbTodoReadConnection
    extends FrbThreadTextReadConnection<native.BridgeTodoRead>
    implements TodoReadConnection {
  FrbTodoReadConnection({
    required String threadId,
    required TodoReadRef reference,
    required super.origin,
  }) : super(
         resource: 'todo-read',
         diagnosticPrefix: 'authoring-read',
         diagnosticLabel: 'Authoring read',
         facet: ThreadFacet.authoring,
         sourceRevision: reference.revision,
         open: () => native.openTodoRead(
           threadId: threadId,
           reference: todoRefToBridge(reference),
           origin: facetStampToBridge(origin),
         ),
         identityOf: (handle) => handle.identity(),
         requestNativeClose: (handle) => handle.requestClose(),
         closeNative: (handle) => handle.close(),
         retryNativeClose: (handle) => handle.retryClose(),
         disposeNative: (handle) => handle.dispose(),
         readText: (handle, field, offset, bytes) =>
             handle.text(fieldId: field, offset: offset, maxBytes: bytes),
       );

  @override
  Future<TodoReadHeader> header() => query(
    (handle, scope) async =>
        todoHeaderFromBridge(await handle.header(), expectedScope: scope),
  );

  @override
  Future<TodoItemPage> items({int offset = 0, int limit = 32}) =>
      pageQuery(offset, limit, (handle, scope, nativeOffset) async {
        final page = todoItemPageFromBridge(
          await handle.items(offset: nativeOffset, limit: limit),
          expectedScope: scope,
        );
        requireThreadReadPage(
          diagnosticPrefix: 'authoring-read',
          requestedOffset: offset,
          limit: limit,
          offset: page.offset,
          total: page.total,
          count: page.items.length,
          nextOffset: page.nextOffset,
          indices: page.items.map((item) => item.index),
        );
        return page;
      });
}

final class FrbWorkflowReadConnection
    extends FrbThreadTextReadConnection<native.BridgeWorkflowRead>
    implements WorkflowReadConnection {
  FrbWorkflowReadConnection({
    required String threadId,
    required WorkflowReadRef reference,
    required super.origin,
  }) : super(
         resource: 'workflow-read',
         diagnosticPrefix: 'authoring-read',
         diagnosticLabel: 'Authoring read',
         facet: ThreadFacet.authoring,
         sourceRevision: reference.revision,
         open: () => native.openWorkflowRead(
           threadId: threadId,
           reference: workflowRefToBridge(reference),
           origin: facetStampToBridge(origin),
         ),
         identityOf: (handle) => handle.identity(),
         requestNativeClose: (handle) => handle.requestClose(),
         closeNative: (handle) => handle.close(),
         retryNativeClose: (handle) => handle.retryClose(),
         disposeNative: (handle) => handle.dispose(),
         readText: (handle, field, offset, bytes) =>
             handle.text(fieldId: field, offset: offset, maxBytes: bytes),
       );

  @override
  Future<WorkflowReadHeader> header() => query((handle, scope) async {
    // Native already bound Mode ID/revision/hash to this original run. Never
    // fetch a current Mode or replace absent/frozen display fields here.
    final header = workflowHeaderFromBridge(
      await handle.header(),
      expectedScope: scope,
    );
    if (header.revision != scope.sourceRevision) {
      throw adapterProtocol('workflow-read-header-revision');
    }
    return header;
  });
}

final class FrbPlanDocumentReadConnection
    extends FrbThreadReadConnection<native.BridgePlanDocumentRead>
    implements PlanDocumentReadConnection {
  FrbPlanDocumentReadConnection({
    required String threadId,
    required PlanDocumentRef reference,
    required super.origin,
  }) : _reference = reference,
       super(
         resource: 'plan-document-read',
         diagnosticPrefix: 'authoring-read',
         facet: ThreadFacet.authoring,
         // This scope pins the Authoring capture; document.version is an
         // independent identity, not its sourceRevision clock.
         sourceRevision: origin.revision,
         open: () => native.openPlanDocumentRead(
           threadId: threadId,
           reference: planDocumentRefToBridge(reference),
           origin: facetStampToBridge(origin),
         ),
         identityOf: (handle) => handle.identity(),
         requestNativeClose: (handle) => handle.requestClose(),
         closeNative: (handle) => handle.close(),
         retryNativeClose: (handle) => handle.retryClose(),
         disposeNative: (handle) => handle.dispose(),
       );

  final PlanDocumentRef _reference;

  @override
  Future<PlanDocumentReadHeader> header() => query((handle, scope) async {
    final header = planDocumentHeaderFromBridge(
      await handle.header(),
      expectedScope: scope,
    );
    _requireDocument(header.version, header.contentHash);
    return header;
  });

  @override
  Future<PlanDocumentValue> document() => query((handle, scope) async {
    final value = planDocumentFromBridge(
      await handle.document(),
      expectedScope: scope,
    );
    _requireDocument(value.version, value.contentHash);
    return value;
  });

  void _requireDocument(int version, String contentHash) {
    if (version != _reference.version ||
        contentHash != _reference.contentHash) {
      throw adapterProtocol('plan-document-read-identity');
    }
  }
}
