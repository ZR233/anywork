import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import 'startup_values.dart';

abstract interface class StartupRepository {
  ReadonlyLatestValue<StartupState> get state;
  OperationTicket<RuntimeReady> start();
  Future<StartupRecovery?> readRecovery(RuntimeStartupReadRef reference);
  Future<StartupActiveTurnPage> readActiveTurns(
    RuntimeStartupReadRef reference, {
    int offset = 0,
    int limit = 32,
  });
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
