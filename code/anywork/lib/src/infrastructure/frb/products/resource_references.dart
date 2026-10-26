import 'package:anywork_client/lsp.dart';
import 'package:anywork_client/mcp.dart';
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/skills.dart';

import '../../../rust/api/studio/products/references.dart' as native;
import '../shared/exact_numbers.dart';
import 'identity_converters.dart';

RecoveryReadRef recoveryReadRefFromBridge(native.BridgeRecoveryReadRef value) =>
    RecoveryReadRef(
      entry: exactU64(value.entry, 'recovery read entry'),
      revision: exactU64(value.revision, 'recovery read revision'),
    );
McpReadRef mcpReadRefFromBridge(native.BridgeMcpReadRef value) => McpReadRef(
  entry: exactU64(value.entry, 'MCP read entry'),
  revision: exactU64(value.revision, 'MCP read revision'),
);
LspReadRef lspReadRefFromBridge(native.BridgeLspReadRef value) => LspReadRef(
  entry: exactU64(value.entry, 'LSP read entry'),
  revision: exactU64(value.revision, 'LSP read revision'),
);
SkillsReadRef skillsReadRefFromBridge(native.BridgeSkillsReadRef value) =>
    SkillsReadRef(
      entry: exactU64(value.entry, 'Skills read entry'),
      revision: exactU64(value.revision, 'Skills read revision'),
    );
PersistenceReadRef persistenceReadRefFromBridge(
  native.BridgePersistenceReadRef value,
) => PersistenceReadRef(
  entry: exactU64(value.entry, 'persistence read entry'),
  revision: exactU64(value.revision, 'persistence read revision'),
);
PersistenceQueueReadRef persistenceQueueReadRefFromBridge(
  native.BridgePersistenceQueueReadRef value,
) => PersistenceQueueReadRef(
  entry: exactU64(value.entry, 'persistence queue read entry'),
  revision: exactU64(value.revision, 'persistence queue read revision'),
);

native.BridgeRecoveryReadRef recoveryReadRefToBridge(RecoveryReadRef value) =>
    native.BridgeRecoveryReadRef(
      entry: nativeU64(value.entry, 'recovery read entry'),
      revision: nativeU64(value.revision, 'recovery read revision'),
    );
native.BridgeMcpReadRef mcpReadRefToBridge(McpReadRef value) =>
    native.BridgeMcpReadRef(
      entry: nativeU64(value.entry, 'MCP read entry'),
      revision: nativeU64(value.revision, 'MCP read revision'),
    );
native.BridgeLspReadRef lspReadRefToBridge(LspReadRef value) =>
    native.BridgeLspReadRef(
      entry: nativeU64(value.entry, 'LSP read entry'),
      revision: nativeU64(value.revision, 'LSP read revision'),
    );
native.BridgeSkillsReadRef skillsReadRefToBridge(SkillsReadRef value) =>
    native.BridgeSkillsReadRef(
      entry: nativeU64(value.entry, 'Skills read entry'),
      revision: nativeU64(value.revision, 'Skills read revision'),
    );
native.BridgePersistenceReadRef persistenceReadRefToBridge(
  PersistenceReadRef value,
) => native.BridgePersistenceReadRef(
  entry: nativeU64(value.entry, 'persistence read entry'),
  revision: nativeU64(value.revision, 'persistence read revision'),
);
native.BridgePersistenceQueueReadRef persistenceQueueReadRefToBridge(
  PersistenceQueueReadRef value,
) => native.BridgePersistenceQueueReadRef(
  entry: nativeU64(value.entry, 'persistence queue read entry'),
  revision: nativeU64(value.revision, 'persistence queue read revision'),
);

RecoveryReadTarget recoveryTargetFromBridge(
  native.BridgeRecoveryReadTarget value,
) => RecoveryReadTarget(
  origin: productOriginFromBridge(value.origin),
  reference: recoveryReadRefFromBridge(value.reference),
);
McpReadTarget mcpTargetFromBridge(native.BridgeMcpReadTarget value) =>
    McpReadTarget(
      origin: productOriginFromBridge(value.origin),
      reference: mcpReadRefFromBridge(value.reference),
    );
LspReadTarget lspTargetFromBridge(native.BridgeLspReadTarget value) =>
    LspReadTarget(
      origin: productOriginFromBridge(value.origin),
      reference: lspReadRefFromBridge(value.reference),
    );
SkillsReadTarget skillsTargetFromBridge(native.BridgeSkillsReadTarget value) =>
    SkillsReadTarget(
      origin: productOriginFromBridge(value.origin),
      reference: skillsReadRefFromBridge(value.reference),
    );
PersistenceReadTarget persistenceTargetFromBridge(
  native.BridgePersistenceReadTarget value,
) => PersistenceReadTarget(
  origin: productOriginFromBridge(value.origin),
  reference: persistenceReadRefFromBridge(value.reference),
);
