import 'package:anywork_client/models.dart' show ModelDescriptor;
import 'package:flutter/foundation.dart';

/// A canonical model paired with account-instance identity, not a model policy.
@immutable
final class ModelSelectionOption {
  const ModelSelectionOption({
    required this.accountId,
    required this.accountName,
    required this.descriptor,
    this.accountIconKey,
  });

  final String accountId;
  final String accountName;
  final String? accountIconKey;
  final ModelDescriptor descriptor;

  String get modelId => descriptor.modelId;

  String get displayName => descriptor.displayName.isEmpty
      ? descriptor.modelId
      : descriptor.displayName;

  /// Route identity deliberately ignores display names and catalog revisions.
  @override
  bool operator ==(Object other) =>
      other is ModelSelectionOption &&
      other.accountId == accountId &&
      other.modelId == modelId;

  @override
  int get hashCode => Object.hash(accountId, modelId);
}
