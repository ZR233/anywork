import 'package:anywork_client/resources_ports.dart';

import '../domain/lsp_values.dart';
import 'lsp_port.dart';
import 'lsp_reads.dart';

/// Runs only inside the original LSP pin/use registered by the Repository.
final class LspReader {
  LspReader(this.scope);
  final LspReadConnection scope;

  Future<String> text(ReadText value) => materializeReadText(
    value,
    read: (field, offset) => scope.text(field, offset: offset),
  );

  Future<SourceStateError> _error(SourceStateErrorRead value) async =>
      SourceStateError(
        code: await text(value.code),
        message: await text(value.message),
        retryable: value.retryable,
      );

  Future<List<String>> strings(TypedListRef ref) async {
    if (ref.listId < 0 || ref.total < 0)
      throw resourceProtocol('Invalid LSP string-list reference.');
    final values = <String>[];
    var offset = 0;
    while (offset < ref.total) {
      final page = await scope.strings(ref.listId, offset: offset);
      final items = List.of(page.items);
      final end = offset + items.length;
      if (page.listId != ref.listId ||
          page.offset != offset ||
          page.total != ref.total ||
          items.isEmpty ||
          items.length > 32 ||
          end > ref.total ||
          page.nextOffset != (end == ref.total ? null : end)) {
        throw resourceProtocol('LSP string page changed its frozen list.');
      }
      for (final item in items) {
        values.add(await text(item.value));
      }
      offset = end;
    }
    return List.unmodifiable(values);
  }

  Future<LspServer> server(LspServerRead value) async => LspServer(
    id: await text(value.id),
    displayName: await text(value.displayName),
    extensions: await strings(value.extensions),
    languageIds: await strings(value.languageIds),
    state: await state(value.state),
  );

  Future<LspServerState> state(LspServerStateRead value) async =>
      switch (value) {
        CheckingLspServerStateRead(:final message) => LspServerState.checking(
          message: await text(message),
        ),
        DisabledLspServerStateRead(:final message) => LspServerState.disabled(
          message: await text(message),
        ),
        UnavailableLspServerStateRead(:final checkedAt, :final error) =>
          LspServerState.unavailable(
            checkedAt: checkedAt,
            error: await _error(error),
          ),
        AvailableLspServerStateRead(
          :final checkedAt,
          :final diagnosticCount,
          :final activity,
        ) =>
          LspServerState.available(
            checkedAt: checkedAt,
            diagnosticCount: diagnosticCount,
            activity: await _activity(activity),
          ),
      };

  Future<LspActivity> _activity(LspActivityRead value) async => switch (value) {
    IdleLspActivityRead() => const LspActivity.idle(),
    BusyLspActivityRead(:final title, :final message, :final percentage) =>
      LspActivity.busy(
        title: title == null ? null : await text(title),
        message: message == null ? null : await text(message),
        percentage: percentage,
      ),
    IndexingLspActivityRead(:final title, :final message, :final percentage) =>
      LspActivity.indexing(
        title: title == null ? null : await text(title),
        message: message == null ? null : await text(message),
        percentage: percentage,
      ),
  };
}
