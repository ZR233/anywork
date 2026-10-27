import '../contracts/stamps.dart';
import '../models/acp_models.dart';
import '../models/acp_install_models.dart';
import '../models_domain/domain/model_directory.dart';
import '../usage/domain/account_usage.dart';
import 'domain/account_identity.dart';
import 'domain/account_values.dart';

sealed class AccountObservationTarget {
  const AccountObservationTarget();
  String get key;
  @override
  bool operator ==(Object other) =>
      other is AccountObservationTarget && key == other.key;
  @override
  int get hashCode => key.hashCode;
}

final class AccountSummariesTarget extends AccountObservationTarget {
  const AccountSummariesTarget();
  @override
  String get key => 'summaries';
}

final class AccountDetailTarget extends AccountObservationTarget {
  const AccountDetailTarget(this.identity);
  final AccountIdentity identity;
  @override
  String get key =>
      'detail:${identity is NativeAccountIdentity ? 'native' : 'acp'}:${identity.accountId}';
}

final class AccountModelsTarget extends AccountObservationTarget {
  const AccountModelsTarget(this.identity);
  final NativeAccountIdentity identity;
  @override
  String get key => 'models:${identity.accountId}';
}

final class AccountUsageTarget extends AccountObservationTarget {
  const AccountUsageTarget();
  @override
  String get key => 'usage';
}

final class AcpAuthTarget extends AccountObservationTarget {
  const AcpAuthTarget();
  @override
  String get key => 'acp-auth';
}

final class AcpInstallTarget extends AccountObservationTarget {
  const AcpInstallTarget();
  @override
  String get key => 'acp-install';
}

sealed class AccountDomainFrame {
  const AccountDomainFrame(this.stamp);
  final ResourceStamp stamp;
  AccountObservationTarget get target;
}

final class AccountSummariesFrame extends AccountDomainFrame {
  AccountSummariesFrame(super.stamp, Iterable<AccountSummary> accounts)
    : accounts = List.unmodifiable(accounts);
  final List<AccountSummary> accounts;
  @override
  AccountObservationTarget get target => const AccountSummariesTarget();
}

final class AccountDetailFrame extends AccountDomainFrame {
  const AccountDetailFrame(
    super.stamp,
    this.identity,
    this.account, {
    this.modelConfiguration,
  });
  final AccountIdentity identity;
  final AccountDetails? account;
  final AccountModelConfiguration? modelConfiguration;
  @override
  AccountObservationTarget get target => AccountDetailTarget(identity);
}

final class AccountModelsFrame extends AccountDomainFrame {
  const AccountModelsFrame(super.stamp, this.identity, this.catalog);
  final NativeAccountIdentity identity;
  final AccountModelCatalog? catalog;
  @override
  AccountObservationTarget get target => AccountModelsTarget(identity);
}

final class AccountUsageFrame extends AccountDomainFrame {
  AccountUsageFrame(super.stamp, Iterable<AccountUsageObservation> accounts)
    : accounts = List.unmodifiable(accounts);
  final List<AccountUsageObservation> accounts;
  @override
  AccountObservationTarget get target => const AccountUsageTarget();
}

final class AcpAuthFrame extends AccountDomainFrame {
  const AcpAuthFrame(super.stamp, this.snapshot);
  final AcpAuthSnapshotView snapshot;
  @override
  AccountObservationTarget get target => const AcpAuthTarget();
}

final class AcpInstallFrame extends AccountDomainFrame {
  const AcpInstallFrame(super.stamp, this.snapshot);
  final AcpInstallSnapshotView snapshot;
  @override
  AccountObservationTarget get target => const AcpInstallTarget();
}
