/// Typed ACP transport values and the explicit Repository assembly factories.
library;

export 'acp.dart';
export 'src/acp/data/acp_frames.dart';
export 'src/acp/data/acp_port.dart' show AcpPort;
export 'src/acp/data/acp_reads.dart';
export 'src/acp/data/acp_repository.dart'
    show createAcpAuthRepository, createAcpInstallRepository;
