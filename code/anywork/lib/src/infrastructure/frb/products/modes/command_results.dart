import 'package:anywork_client/modes_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/modes.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/receipt_converters.dart';
import '../catalog_references.dart';
import 'document_values.dart';

StudioFailure modeCommandFailure(Object error) {
  try {
    return bridgeFailure(error);
  } on Object catch (mappingError) {
    return adapterFailure(mappingError, operation: 'mode-command-error');
  }
}

Future<ModeDefinitionCommandReply> invokeModeCommand(
  OperationId operation,
  Future<native.BridgeModeDefinitionCommandReply> Function() invoke, {
  String? savedModeId,
}) async {
  final native.BridgeModeDefinitionCommandReply value;
  try {
    value = await invoke();
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(
      CommandDispatchFailure.unknownOutcome(failure: modeCommandFailure(error)),
      stack,
    );
  }

  final CommitReceipt receipt;
  try {
    receipt = commitReceiptFromBridge(value.receipt);
    if (operation.value.isEmpty ||
        receipt.operationId != operation ||
        receipt.requiresIdentityObservation ||
        receipt.targets.length != 1) {
      throw adapterProtocol('mode-command-receipt');
    }
    if (receipt.targets.single
        case ResourceStamp(
          resourceKey: 'thread-mode-catalog',
          ownerEpoch: final epoch,
        )
        when epoch.isNotEmpty && epoch == value.catalog.origin.ownerEpoch) {
      // This receipt is usable independently of converting its read material.
    } else {
      throw adapterProtocol('mode-command-target');
    }
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(
      CommandDispatchFailure.confirmedWithoutUsableReceipt(
        failure: modeCommandFailure(error),
      ),
      stack,
    );
  }

  try {
    final catalog = modeCatalogTargetFromBridge(value.catalog);
    final definition = value.definition == null
        ? null
        : modeDefinitionSnapshotFromBridge(value.definition!);
    if (catalog.origin.ownerEpoch.isEmpty ||
        catalog.origin.incarnation < 1 ||
        savedModeId != null &&
            definition?.document.definition.id.id != savedModeId ||
        savedModeId == null && definition != null) {
      throw adapterProtocol('mode-command-material');
    }
    return ModeDefinitionCommandReply(
      catalog: catalog,
      definition: definition,
      receipt: receipt,
    );
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(
      CommandDispatchFailure.committedButUnobserved(
        receipt: receipt,
        failure: modeCommandFailure(error),
      ),
      stack,
    );
  }
}
