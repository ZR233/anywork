import 'package:anywork_client/resources_ports.dart';

import '../domain/lsp_state.dart';
import 'lsp_frames.dart';
import 'lsp_reads.dart';

abstract interface class LspPort {
  Future<FeedConnection<LspFrame>> openLsp();
  Future<LspReadConnection> openLspRead(
    LspReadRef reference, {
    required ProductReadOrigin origin,
  });
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  });
  Future<LspReadTarget> probe(String projectId);
  Future<LspReadTarget> repair(String projectId, String serverId);
  Future<LspReadTarget> resetServer(String projectId, String serverId);
  Future<LspReadTarget> resetWorkspace(String projectId);
}

abstract interface class LspReadConnection {
  Future<LspReadHeader> header();
  Future<LspEntryPage> entries({int offset = 0, int limit = 32});
  Future<LspEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupServer(String serverId);
  Future<LspServerReadPage> servers(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<TextReadPage> strings(int listId, {int offset = 0, int limit = 32});
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
