sealed class AccountIdentity {
  const AccountIdentity(this.accountId);
  const factory AccountIdentity.native(String accountId) =
      NativeAccountIdentity;
  const factory AccountIdentity.acp(String accountId) = AcpAccountIdentity;

  final String accountId;

  @override
  bool operator ==(Object other) =>
      other is AccountIdentity &&
      runtimeType == other.runtimeType &&
      accountId == other.accountId;
  @override
  int get hashCode => Object.hash(runtimeType, accountId);
}

final class NativeAccountIdentity extends AccountIdentity {
  const NativeAccountIdentity(super.accountId);
}

final class AcpAccountIdentity extends AccountIdentity {
  const AcpAccountIdentity(super.accountId);
}

final class AccountModelIdentity {
  const AccountModelIdentity({required this.account, required this.modelId});
  final NativeAccountIdentity account;
  final String modelId;
  String get accountId => account.accountId;

  @override
  bool operator ==(Object other) =>
      other is AccountModelIdentity &&
      account == other.account &&
      modelId == other.modelId;
  @override
  int get hashCode => Object.hash(account, modelId);
}
