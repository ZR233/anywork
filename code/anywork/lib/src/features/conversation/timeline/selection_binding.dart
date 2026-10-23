import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

/// Not identified by Thread ID: A→B→A and a same-ID Session replacement are
/// distinct bindings, with distinct consumer leases and callback completions.
final class TimelineSelectionBinding {
  TimelineSelectionBinding(this.session, this.serial);
  final ConversationSession session;
  final int serial;
  TimelineConsumerLease? consumer;
  Observation? observation;
  int candidateEpoch = 0;
  bool retired = false;
}

final class PendingLiveSwitch {
  PendingLiveSwitch(this.binding, this.serial, this.previousSubscription);
  final TimelineSelectionBinding binding;
  final int serial;
  final String? previousSubscription;
  final Completer<void> result = Completer<void>();
}

/// A selection-only cancellation does not cancel the frozen domain submission.
final class TimelineSelectionChanged implements Exception {
  const TimelineSelectionChanged();
}
