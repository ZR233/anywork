import 'package:anywork_client/studio_client.dart';

/// A presentation of independent facts, not a new delivery ledger. No local
/// body-preview/omission flag participates in channel integrity or acceptance.
final class AudienceItemDeliveryProjection {
  const AudienceItemDeliveryProjection({
    required this.status,
    required this.displayRevision,
    required this.currentRevisionAccepted,
    required this.historicalRevisionAccepted,
    required this.ledger,
  });
  final BotAudienceItemStatus status;
  final int displayRevision;
  final bool currentRevisionAccepted;
  final bool historicalRevisionAccepted;
  final BotItemLedgerSummary? ledger;

  factory AudienceItemDeliveryProjection.fromStatus(
    BotAudienceItemStatus status, {
    required int displayRevision,
  }) {
    final ledger = switch (status.delivery) {
      BotItemDeliveryKnown(:final ledger) => ledger,
      BotItemDeliveryNotProjected() => null,
    };
    final revision = switch (ledger?.accepted) {
      BotItemPresentationText(:final revision) ||
      BotItemPresentationFile(:final revision) => revision,
      BotItemPresentationNone() || null => null,
    };
    final canonical = status.canonical;
    return AudienceItemDeliveryProjection(
      status: status,
      displayRevision: displayRevision,
      ledger: ledger,
      currentRevisionAccepted:
          canonical is BotAudienceCanonicalItemPresent &&
          canonical.revision == displayRevision &&
          revision == displayRevision,
      historicalRevisionAccepted:
          revision != null &&
          (canonical is! BotAudienceCanonicalItemPresent ||
              canonical.revision != revision ||
              displayRevision != revision),
    );
  }
}
