import 'package:anywork_client/lsp_ports.dart';

import '../../../../rust/api/studio/products/read/lsp.dart' as native;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import '../source_converters.dart';

LspReadHeader lspReadHeaderFromBridge(native.BridgeLspReadHeader value) =>
    LspReadHeader(
      lspServers: typedListFromBridge(value.lspServers),
      activeLspServers: typedListFromBridge(value.activeLspServers),
    );

LspActivityRead lspActivityFromBridge(native.BridgeLspActivityRead value) =>
    switch (value) {
      native.BridgeLspActivityRead_Idle() => const LspActivityRead.idle(),
      native.BridgeLspActivityRead_Busy(
        :final title,
        :final message,
        :final percentage,
      ) =>
        LspActivityRead.busy(
          title: nullableReadText(title),
          message: nullableReadText(message),
          percentage: percentage,
        ),
      native.BridgeLspActivityRead_Indexing(
        :final title,
        :final message,
        :final percentage,
      ) =>
        LspActivityRead.indexing(
          title: nullableReadText(title),
          message: nullableReadText(message),
          percentage: percentage,
        ),
    };

LspServerStateRead lspServerStateFromBridge(
  native.BridgeLspServerStateRead value,
) => switch (value) {
  native.BridgeLspServerStateRead_Checking(:final message) =>
    LspServerStateRead.checking(message: readTextFromBridge(message)),
  native.BridgeLspServerStateRead_Disabled(:final message) =>
    LspServerStateRead.disabled(message: readTextFromBridge(message)),
  native.BridgeLspServerStateRead_Unavailable(:final checkedAt, :final error) =>
    LspServerStateRead.unavailable(
      checkedAt: exactI64(BigInt.from(checkedAt), 'LSP checked Unix seconds'),
      error: sourceErrorReadFromBridge(error),
    ),
  native.BridgeLspServerStateRead_Available(
    :final checkedAt,
    :final diagnosticCount,
    :final activity,
  ) =>
    LspServerStateRead.available(
      checkedAt: exactI64(BigInt.from(checkedAt), 'LSP checked Unix seconds'),
      diagnosticCount: exactU64(diagnosticCount, 'LSP diagnostic count'),
      activity: lspActivityFromBridge(activity),
    ),
};

LspServerRead lspServerReadFromBridge(native.BridgeLspServerRead value) =>
    LspServerRead(
      id: readTextFromBridge(value.id),
      displayName: readTextFromBridge(value.displayName),
      extensions: typedListFromBridge(value.extensions),
      languageIds: typedListFromBridge(value.languageIds),
      state: lspServerStateFromBridge(value.state),
    );

LspEntityRead lspEntityFromBridge(native.BridgeLspEntityRead value) =>
    LspEntityRead(
      reference: entityRefFromBridge(value.reference),
      value: lspServerReadFromBridge(value.value),
    );

LspEntryPage lspEntriesFromBridge(native.BridgeLspEntryPage value) =>
    LspEntryPage(
      collection: collectionRefFromBridge(value.collection),
      offset: exactU64(value.offset, 'LSP entries offset'),
      items: value.items.map(entityRefFromBridge).toList(growable: false),
      nextOffset: nullableU64(value.nextOffset, 'LSP next entries offset'),
    );

LspServerReadPage lspServersFromBridge(native.BridgeLspServerReadPage value) =>
    LspServerReadPage(
      listId: exactU64(value.listId, 'LSP server list'),
      offset: exactU64(value.offset, 'LSP servers offset'),
      total: exactU64(value.total, 'LSP server total'),
      items: value.items.map(lspServerReadFromBridge).toList(growable: false),
      nextOffset: nullableU64(value.nextOffset, 'LSP next servers offset'),
    );
