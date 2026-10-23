import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import 'profile_native_pin.dart';
import 'scripted_feed.dart';

/// An explicitly empty, ready native Recovery version for the role scenarios.
/// This supplies only read materials; it never implements Recovery operations,
/// role policy or a Repository. Unexpected capabilities fail rather than fall back.
final class ProfileRecoveryPort implements RecoveryPort {
  static const origin = ProductReadOrigin(ownerEpoch: 'profile-role-recovery', incarnation: 1);
  static const reference = RecoveryReadRef(entry: 1, revision: 1);
  static const collection = ProductCollectionRef(entry: 2, revision: 1, total: 0);
  final feed = ScriptedFeed<RecoveryFrame>(feedId: 'profile-role-recovery',
    sequenceOf: (frame) => frame is RecoveryData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! RecoveryData);

  Future<void> establish(RecoveryRepository recovery) async {
    final reading = recovery.loadIssuesPage();
    await feed.listened.future;
    feed.emit(RecoveryFrame.data(deliverySequence: 1,
      event: RecoveryEvent.baseline(
        identity: profileIdentity(feed.feedId, origin, ProductResource.recovery),
        stamp: profileStamp(origin, 1), value: RecoveryBaseline(
          header: RecoveryHeader(source: profileSource(1), reference: reference), collection: collection))));
    await reading;
    await feed.acknowledged(1);
  }

  @override
  Future<FeedConnection<RecoveryFrame>> openRecovery() async => feed;
  @override
  Future<RecoveryReadConnection> openRecoveryRead(RecoveryReadRef reference,
    {required ProductReadOrigin origin}) async {
    if (origin != ProfileRecoveryPort.origin || reference != ProfileRecoveryPort.reference) {
      throw StateError('Unscripted native Recovery version');
    }
    return _EmptyRecoveryPin();
  }
  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(ProductSourceStatusRef reference,
    {required ProductReadOrigin origin}) async {
    if (origin != ProfileRecoveryPort.origin || reference != const ProductSourceStatusRef(entry: 9, revision: 1)) {
      throw StateError('Unscripted native Recovery source');
    }
    return ProfileSourcePin(1);
  }
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unscripted Recovery capability: ${invocation.memberName}');
}

final class _EmptyRecoveryPin extends ProfileNativePin implements RecoveryReadConnection {
  _EmptyRecoveryPin() : super('profile-role-recovery-read');
  @override
  Future<RecoveryReadHeader> header() async {
    admit();
    return const RecoveryReadHeader(issues: TypedListRef(listId: 1, total: 0));
  }
  @override
  Future<RecoveryEntryPage> entries({int offset = 0, int limit = 32}) async {
    admit();
    if (offset != 0 || limit < 1) throw StateError('Unscripted empty Recovery page');
    return RecoveryEntryPage(collection: ProfileRecoveryPort.collection, offset: 0,
      items: const [], nextOffset: null);
  }
}
