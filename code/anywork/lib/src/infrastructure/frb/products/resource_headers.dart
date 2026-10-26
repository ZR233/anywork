import 'package:anywork_client/lsp.dart';
import 'package:anywork_client/mcp.dart';
import 'package:anywork_client/skills.dart';

import '../../../rust/api/studio/products/feed/lsp.dart' as lsp;
import '../../../rust/api/studio/products/feed/mcp.dart' as mcp;
import '../../../rust/api/studio/products/feed/skills.dart' as skills;
import '../shared/read_converters.dart';
import 'resource_references.dart';
import 'source_converters.dart';

McpHeader mcpHeaderFromBridge(mcp.BridgeMcpHeader value) => McpHeader(
  source: observedHeaderFromBridge(value.source),
  reference: value.reference == null
      ? null
      : mcpReadRefFromBridge(value.reference!),
);

LspHeader lspHeaderFromBridge(lsp.BridgeLspHeader value) => LspHeader(
  source: observedHeaderFromBridge(value.source),
  reference: value.reference == null
      ? null
      : lspReadRefFromBridge(value.reference!),
);

SkillsHeader skillsHeaderFromBridge(skills.BridgeSkillsHeader value) =>
    SkillsHeader(
      source: observedHeaderFromBridge(value.source),
      reference: value.reference == null
          ? null
          : skillsReadRefFromBridge(value.reference!),
      catalogRevision: nullableU64(
        value.catalogRevision,
        'Skills catalog revision',
      ),
      complete: value.complete,
    );
