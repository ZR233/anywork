part of 'studio_api.dart';

// The Client owns observation disposal. This adapter owns no registry, producer,
// replay cache or second runtime, and never turns local release into a command.
class FrbAcpBusinessPort implements acp_business.AcpBusinessPort {
  const FrbAcpBusinessPort();

  @override
  Future<acp_business.AcpSessionObservationPort> open(
    acp_business.OpenAcpSessionRequestView request,
  ) async {
    final wire = acp_mapper.acpOpenToFrb(request);
    await FrbStudioTransport.ensureReady();
    return _FrbAcpBusinessObservation(
      await _acpBusinessCall(
        () => frb_acp_business.openAcpSession(request: wire),
        command: 'open',
      ),
    );
  }

  @override
  Future<acp_business.AcpRunIdView> prompt(
    acp_business.AcpPromptRequestView request,
  ) async {
    final wire = frb_acp_types.BridgeAcpPromptRequest(
      target: acp_mapper.acpTargetToFrb(request.target),
      content: request.content.map(acp_mapper.acpContentToFrb).toList(),
    );
    await FrbStudioTransport.ensureReady();
    return acp_mapper.acpRunFromFrb(
      await _acpBusinessCall(
        () => frb_acp_business.promptAcpSession(request: wire),
        command: 'prompt',
      ),
    );
  }

  @override
  Future<acp_business.AcpRunIdView> replace(
    acp_business.AcpReplaceRequestView request,
  ) async {
    final wire = frb_acp_types.BridgeAcpReplaceRequest(
      target: acp_mapper.acpTargetToFrb(request.target),
      run: acp_mapper.acpRunToFrb(request.run),
      content: request.content.map(acp_mapper.acpContentToFrb).toList(),
    );
    await FrbStudioTransport.ensureReady();
    return acp_mapper.acpRunFromFrb(
      await _acpBusinessCall(
        () => frb_acp_business.replaceAcpSession(request: wire),
        command: 'replace',
      ),
    );
  }

  @override
  Future<void> interrupt(acp_business.AcpInterruptRequestView request) async {
    final wire = frb_acp_types.BridgeAcpInterruptRequest(
      target: acp_mapper.acpTargetToFrb(request.target),
      run: acp_mapper.acpRunToFrb(request.run),
    );
    await FrbStudioTransport.ensureReady();
    await _acpBusinessCall(
      () => frb_acp_business.interruptAcpSession(request: wire),
      command: 'interrupt',
    );
  }

  @override
  Future<void> configure(acp_business.AcpConfigureRequestView request) async {
    final wire = frb_acp_types.BridgeAcpConfigureRequest(
      target: acp_mapper.acpTargetToFrb(request.target),
      configId: frb_acp_types.BridgeAcpConfigId(value: request.configId.value),
      value: acp_mapper.acpConfigValueToFrb(request.value),
    );
    await FrbStudioTransport.ensureReady();
    await _acpBusinessCall(
      () => frb_acp_business.configureAcpSession(request: wire),
      command: 'configure',
    );
  }

  @override
  Future<void> setMode(acp_business.AcpSetModeRequestView request) async {
    final wire = frb_acp_types.BridgeAcpSetModeRequest(
      target: acp_mapper.acpTargetToFrb(request.target),
      modeId: frb_acp_types.BridgeAcpModeId(value: request.modeId.value),
    );
    await FrbStudioTransport.ensureReady();
    await _acpBusinessCall(
      () => frb_acp_business.setAcpSessionMode(request: wire),
      command: 'setMode',
    );
  }

  @override
  Future<void> answerPermission(
    acp_business.AcpPermissionAnswerRequestView request,
  ) async {
    final wire = frb_acp_types.BridgeAcpPermissionAnswerRequest(
      target: acp_mapper.acpTargetToFrb(request.target),
      permissionId: frb_acp_types.BridgeAcpPermissionId(
        instance: request.permissionId.instance,
        sequence: request.permissionId.sequence,
      ),
      optionId: request.optionId == null
          ? null
          : frb_acp_types.BridgeAcpPermissionOptionId(
              value: request.optionId!.value,
            ),
    );
    await FrbStudioTransport.ensureReady();
    await _acpBusinessCall(
      () => frb_acp_business.answerAcpPermission(request: wire),
      command: 'answerPermission',
    );
  }

  @override
  Future<acp_business.AcpListSessionsResponseView> list(
    acp_business.AcpListRequestView request,
  ) async {
    final wire = frb_acp_types.BridgeAcpListRequest(
      target: acp_mapper.acpTargetToFrb(request.target),
      cwd: request.request.cwd,
      cursor: request.request.cursor,
      meta: acp_mapper.acpMetaToFrb(request.request.meta),
    );
    await FrbStudioTransport.ensureReady();
    return acp_mapper.acpListFromFrb(
      await _acpBusinessCall(
        () => frb_acp_business.listAcpSessions(request: wire),
      ),
    );
  }

  @override
  Future<acp_business.AcpBusinessSnapshotView> snapshot(
    acp_business.AcpSessionTargetView target,
  ) async {
    final wire = acp_mapper.acpTargetToFrb(target);
    await FrbStudioTransport.ensureReady();
    return acp_mapper.acpSnapshotFromFrb(
      await _acpBusinessCall(
        () => frb_acp_business.acpSessionSnapshot(target: wire),
      ),
    );
  }

  @override
  Future<acp_business.AcpBusinessCloseView> closeMember(
    acp_business.AcpSessionTargetView target,
  ) async {
    final wire = acp_mapper.acpTargetToFrb(target);
    await FrbStudioTransport.ensureReady();
    return acp_mapper.acpCloseFromFrb(
      await _acpBusinessCall(
        () => frb_acp_business.closeAcpSession(target: wire),
        command: 'closeMember',
      ),
    );
  }
}

Object _acpBusinessError(frb_acp_types.BridgeAcpBusinessError error) =>
    switch (error) {
      frb_acp_types.BridgeAcpBusinessError_Runtime(:final field0) =>
        _studioFailure(field0),
      frb_acp_types.BridgeAcpBusinessError_Business(:final field0) =>
        acp_mapper.acpFailureFromFrb(field0),
      frb_acp_types.BridgeAcpBusinessError_Unsupported(:final typeName) =>
        acp_business.AcpUnsupportedPayload(typeName),
    };

Future<T> _acpBusinessCall<T>(
  Future<T> Function() call, {
  String? command,
}) async {
  try {
    return await call();
  } on frb_acp_types.BridgeAcpBusinessError catch (error, stack) {
    Error.throwWithStackTrace(_acpBusinessError(error), stack);
  } on frb.BridgeError catch (error, stack) {
    Error.throwWithStackTrace(_studioFailure(error), stack);
  } catch (error, stack) {
    // A known RPC/business rejection is never an unknown outcome. Only bridge
    // execution failures after dispatch qualify; local programming errors and
    // read/cleanup errors retain their identity and are never retried here.
    if (command != null &&
        (error is PanicException || error is AnyhowException)) {
      Error.throwWithStackTrace(
        acp_business.AcpCommandOutcomeUnknown(command: command, cause: error),
        stack,
      );
    }
    rethrow;
  }
}

class _FrbAcpBusinessObservation
    implements acp_business.AcpSessionObservationPort {
  _FrbAcpBusinessObservation(this._handle);
  final frb_acp_feed.BridgeAcpSessionObservation _handle;

  @override
  Future<acp_business.AcpSessionFrameView?> next() async {
    final frame = await _acpBusinessCall(_handle.next);
    return frame == null ? null : acp_mapper.acpFrameFromFrb(frame);
  }

  @override
  void requestClose() {
    try {
      _handle.requestClose();
    } on frb_acp_types.BridgeAcpBusinessError catch (error, stack) {
      Error.throwWithStackTrace(_acpBusinessError(error), stack);
    } on frb.BridgeError catch (error, stack) {
      Error.throwWithStackTrace(_studioFailure(error), stack);
    }
  }

  @override
  Future<void> close() => _acpBusinessCall(_handle.close);
}
