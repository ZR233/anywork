import 'package:anywork_client/conversation_ports.dart';

import '../../../rust/api/studio/conversation/read/connections.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/exact_numbers.dart';
import 'identity_converters.dart';
import 'interaction_read_converters.dart';
import 'thread_read_connection.dart';

final class FrbInteractionReadConnection
    extends FrbThreadTextReadConnection<native.BridgeInteractionRead>
    implements InteractionReadConnection {
  FrbInteractionReadConnection({
    required String threadId,
    required InteractionReadRef reference,
    required super.origin,
  }) : super(
         resource: 'interaction-read',
         diagnosticPrefix: 'execution-read',
         diagnosticLabel: 'Execution read',
         facet: ThreadFacet.execution,
         sourceRevision: reference.revision,
         open: () => native.openInteractionRead(
           threadId: threadId,
           reference: interactionRefToBridge(reference),
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
  Future<InteractionReadHeader> header() => query((handle, scope) async {
    final header = interactionHeaderFromBridge(
      await handle.header(),
      expectedScope: scope,
    );
    if (header.revision != scope.sourceRevision) {
      throw adapterProtocol('interaction-read-header-revision');
    }
    return header;
  });

  @override
  Future<QuestionPage> questions({int offset = 0, int limit = 32}) =>
      pageQuery(offset, limit, (handle, scope, nativeOffset) async {
        final page = questionPageFromBridge(
          await handle.questions(offset: nativeOffset, limit: limit),
          expectedScope: scope,
        );
        requireThreadReadPage(
          diagnosticPrefix: 'execution-read',
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

  @override
  Future<OptionPage> options(
    int questionIndex, {
    int offset = 0,
    int limit = 32,
  }) => pageQuery(offset, limit, (handle, scope, nativeOffset) async {
    final page = optionPageFromBridge(
      await handle.options(
        questionIndex: nativeU64(questionIndex, 'interaction question index'),
        offset: nativeOffset,
        limit: limit,
      ),
      expectedScope: scope,
    );
    requireThreadReadPage(
      diagnosticPrefix: 'execution-read',
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

  @override
  Future<AnswerEntryPage> answerEntries({int offset = 0, int limit = 32}) =>
      pageQuery(offset, limit, (handle, scope, nativeOffset) async {
        final page = answerEntryPageFromBridge(
          await handle.answerEntries(offset: nativeOffset, limit: limit),
          expectedScope: scope,
        );
        requireThreadReadPage(
          diagnosticPrefix: 'execution-read',
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

  @override
  Future<AnswerValuePage> answerValues(
    int entryIndex, {
    int offset = 0,
    int limit = 32,
  }) => pageQuery(offset, limit, (handle, scope, nativeOffset) async {
    final page = answerValuePageFromBridge(
      await handle.answerValues(
        entryIndex: nativeU64(entryIndex, 'interaction answer entry index'),
        offset: nativeOffset,
        limit: limit,
      ),
      expectedScope: scope,
    );
    requireThreadReadPage(
      diagnosticPrefix: 'execution-read',
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
