import 'dart:async';

import 'package:anywork/src/infrastructure/frb/drafts/attachment_admission_port.dart';
import 'package:anywork/src/infrastructure/frb/products/workspace/agent_read_connection.dart';
import 'package:anywork/src/rust/api/studio/draft_commands/handles.dart'
    as handles;
import 'package:anywork/src/rust/api/studio/observation.dart' as primitive;
import 'package:anywork/src/rust/api/studio/products/identity.dart'
    as identity_wire;
import 'package:anywork/src/rust/api/studio/products/references.dart'
    as references;
import 'package:anywork/src/rust/api/studio/products/read/agent_directory.dart'
    as wire;
import 'package:anywork/src/rust/api/studio/types/attachment.dart'
    as attachment;
import 'package:anywork/src/rust/api/studio/types/chat.dart' as lifecycle;
import 'package:anywork/src/rust/api/studio/types/delegation.dart'
    as delegation;
import 'package:anywork/src/rust/api/studio/types/error.dart' as errors;
import 'package:anywork/src/rust/api/studio/types/runtime.dart' as runtime;
import 'package:anywork/src/rust/frb_generated.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter_test/flutter_test.dart';

final class _DirectoryHandle
    implements wire.BridgeAgentDirectoryReadConnection {
  final entities = <identity_wire.BridgeProductEntityRef>[];
  bool disposed = false;
  @override
  identity_wire.BridgeProductReadScopeIdentity identity() =>
      identity_wire.BridgeProductReadScopeIdentity(
        scopeId: 'directory-scope',
        ownerEpoch: 'directory-owner',
        incarnation: BigInt.from(3),
        version: identity_wire.BridgeProductReadVersion.value(
          entry: BigInt.one,
          revision: BigInt.from(7),
        ),
      );
  @override
  Future<wire.BridgeAgentDirectoryEntityRead> entity({
    required identity_wire.BridgeProductEntityRef reference,
  }) async {
    entities.add(reference);
    return wire.BridgeAgentDirectoryEntityRead(
      reference: reference,
      value: wire.BridgeAgentDirectoryEntryRead(
        id: const primitive.BridgeReadText.inline(text: 'member'),
        threadId: const primitive.BridgeReadText.inline(text: 'child'),
        rootThreadId: const primitive.BridgeReadText.inline(text: 'root'),
        path: const primitive.BridgeReadText.inline(text: 'root/child'),
        parentPath: const primitive.BridgeReadText.inline(text: 'root'),
        role: const primitive.BridgeReadText.inline(text: 'executor'),
        task: const primitive.BridgeReadText.inline(text: 'prepare'),
        summary: null,
        delegationMode: delegation.BridgeDelegationMode.profile,
        delegationPreference: delegation.BridgeDelegationPreference.balanced,
        frozenModel: null,
        depth: 1,
        state: const wire.BridgeAgentStateRead.idle(budgetPause: null),
        execution: const runtime.BridgeAgentExecution(
          id: 'preparing-without-turn',
          phase: runtime.BridgeAgentExecutionPhase.preparing,
          turnId: null,
        ),
        canStop: true,
        awaitingScheduling: true,
        updatedAt: -42,
      ),
    );
  }

  @override
  void requestClose() {}
  @override
  Future<lifecycle.BridgeFeedCloseReport> close() async =>
      const lifecycle.BridgeFeedCloseReport(
        feedId: 'directory-scope',
        outcome: lifecycle.BridgeFeedCloseOutcome.clean(),
      );
  @override
  Future<lifecycle.BridgeFeedCloseReport> retryClose() => close();
  @override
  void dispose() => disposed = true;
  @override
  bool get isDisposed => disposed;
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw StateError('Unscripted native directory ${invocation.memberName}');
}

final class _Api implements RustLibApi {
  final directory = _DirectoryHandle();
  final admissionEntered = Completer<void>();
  final admission = Completer<handles.BridgeAttachmentAdmission>();
  attachment.BridgeAttachmentAdmissionContext? context;
  List<attachment.BridgeAttachmentDraftSource>? sources;
  String? operation;
  @override
  Future<wire.BridgeAgentDirectoryReadConnection>
  crateApiStudioProductsReadAgentDirectoryOpenAgentDirectoryRead({
    required references.BridgeAgentDirectoryReadRef reference,
    required identity_wire.BridgeProductReadOrigin origin,
  }) async {
    expect(
      (
        reference.entry,
        reference.revision,
        origin.ownerEpoch,
        origin.incarnation,
      ),
      (BigInt.one, BigInt.from(7), 'directory-owner', BigInt.from(3)),
    );
    return directory;
  }

  @override
  Future<handles.BridgeAttachmentAdmission>
  crateApiStudioDraftCommandsCommandsBeginAttachmentAdmission({
    required String operationId,
    required attachment.BridgeAttachmentAdmissionContext context,
    required List<attachment.BridgeAttachmentDraftSource> sources,
  }) {
    operation = operationId;
    this.context = context;
    this.sources = sources;
    admissionEntered.complete();
    return admission.future;
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected A2 native API ${invocation.memberName}');
}

void main() {
  late _Api api;
  setUp(() {
    api = _Api();
    RustLib.initMock(api: api);
  });
  tearDown(RustLib.dispose);

  test('the real directory read preserves preparing execution without Turn, canStop and scheduling independently', () async {
    final connection = FrbAgentDirectoryReadConnection(
      const AgentDirectoryReadRef(entry: 1, revision: 7),
      const ProductReadOrigin(ownerEpoch: 'directory-owner', incarnation: 3),
    );
    await connection.opened;
    final entity = await connection.entity(
      const ProductEntityRef(entry: 10, revision: 7),
    );
    expect(entity.reference, const ProductEntityRef(entry: 10, revision: 7));
    expect(
      entity.value.execution,
      const AgentExecution(
        id: 'preparing-without-turn',
        phase: AgentExecutionPhase.preparing,
        turnId: null,
      ),
    );
    expect(entity.value.state, const AgentStateRead.idle(budgetPause: null));
    expect(entity.value.canStop, isTrue);
    expect(
      entity.value.awaitingScheduling,
      isTrue,
      reason: 'Not derived from preparing execution',
    );
    expect(entity.value.updatedAt, -42);
    expect(
      api.directory.entities.single,
      identity_wire.BridgeProductEntityRef(
        entry: BigInt.from(10),
        revision: BigInt.from(7),
      ),
    );
    expect((await connection.close()).outcome, isA<CleanFeedCloseOutcome>());
    expect(api.directory.disposed, isTrue);
  });

  test('attachment admission freezes full selected route including non-default effort and queued sources', () async {
    var selection = const ModelSelection(
      model: AccountModelKey(
        accountId: 'chosen-account',
        modelId: 'chosen-model',
      ),
      effort: 'high',
    );
    final context = AttachmentAdmissionContext.newThread(route: selection);
    final sources = <AttachmentDraftSource>[
      const AttachmentDraftSource.remoteUrl(
        'https://example.test/image.png',
        filename: 'original.png',
      ),
    ];
    final opening = const FrbAttachmentAdmissionPort().begin(
      const OperationId('admission-op'),
      context,
      sources,
    );
    final rejected = expectLater(
      opening,
      throwsA(isA<RejectedCommandDispatchFailure>()),
    );
    await api.admissionEntered.future;
    selection = const ModelSelection(
      model: AccountModelKey(
        accountId: 'later-account',
        modelId: 'later-model',
      ),
      effort: 'low',
    );
    sources[0] = const AttachmentDraftSource.localFile(
      '/changed-after-admission',
    );
    expect(selection.model.modelId, 'later-model');
    expect(api.operation, 'admission-op');
    expect(
      api.context,
      const attachment.BridgeAttachmentAdmissionContext.newThread(
        route: delegation.BridgeNewThreadModelRoute(
          accountId: 'chosen-account',
          modelId: 'chosen-model',
          effort: 'high',
        ),
      ),
    );
    expect(api.sources, const [
      attachment.BridgeAttachmentDraftSource.remoteUrl(
        url: 'https://example.test/image.png',
        filename: 'original.png',
      ),
    ]);
    api.admission.completeError(
      const errors.BridgeError(
        code: errors.BridgeErrorCode.invalidArgument,
        message: 'native admission rejected',
        retryable: false,
        correlationId: 'admission-rejected',
      ),
    );
    await rejected;
  });
}
