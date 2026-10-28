import '../../contracts/stamps.dart';
import '../../commands/mutation_board.dart';
import '../../models/delegation_models.dart';
import '../../observation/latest_value.dart';
import 'account_identity.dart';
import 'account_intents.dart';
import 'account_values.dart';

/// Releasing display demand never cancels a previously admitted mutation.
abstract interface class AccountDemand {
  Future<void> release();
}

/// All settings writes return this operation's frozen failure after admission;
/// errors before admission still throw. A normal return may still be pending.
abstract interface class AccountsRepository {
  ValueObservation<AccountsState> get state;
  ValueObservation<AccountResource<AccountDetails>> details(
    AccountIdentity identity,
  );
  AccountDemand observeSummaries();
  AccountDemand observeDetails(AccountIdentity identity);
  Future<void> loadTemplates();
  Future<OperationState> create(
    CreateAccountCommand command, {
    DraftStamp? draft,
  });
  Future<OperationState> patch(
    PatchAccountCommand command, {
    DraftStamp? draft,
  });
  Future<OperationState> remove(
    NativeAccountIdentity identity, {
    NativeAccountIdentity? replacement,
  });
  Future<OperationState> setDefault(NativeAccountIdentity identity);
  Future<OperationState> setBillingKind(
    NativeAccountIdentity identity,
    BillingKind? kind,
  );
}
