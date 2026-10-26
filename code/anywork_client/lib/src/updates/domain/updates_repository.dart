import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import 'update_values.dart';
import 'updates_state.dart';

abstract interface class UpdatesRepository {
  UpdateControls get controls;
  ReadonlyLatestValue<UpdatesState> get state;
  OperationTicket<Unit> check();
  OperationTicket<UpdatePreparationResult> prepare();
  OperationTicket<Unit> cancelPreparation();
  Future<void> loadValue();
  Future<UpdateSummary> loadSummary();
  Future<UpdateDetails> loadDetails();
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
