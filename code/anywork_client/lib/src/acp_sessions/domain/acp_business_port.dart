import 'acp_business_models.dart';
import 'acp_session_payloads.dart';

/// A pull resource for exactly one admitted open and its original observation.
///
/// Delivers Accepted first, Settled once, and original events in source order.
/// Load events may precede Settled. A resident resource without an observation
/// delivers only Accepted and Settled. End of resource is `null`, not prompt
/// completion; transport failures must remain failures.
abstract interface class AcpSessionObservationPort {
  /// Pulls one original frame without starting a background forwarding producer.
  ///
  /// Concurrent calls must fail Busy rather than queue. Dropping the returned
  /// Dart Future does not cancel the operation; use [requestClose] or [close].
  Future<AcpSessionFrameView?> next();

  /// Signals release of this observation and wakes a pending [next].
  ///
  /// This is idempotent and must not interrupt or close the business member.
  /// Completion of release is reported by [close], not by this synchronous call.
  void requestClose();

  /// Joins release of this resource, including any pending [next].
  ///
  /// Release must not depend on a consumer continuing to pull frames or on the
  /// business preparation/prompt completing. Failures remain visible for retry.
  Future<void> close();
}

/// The independent ACP business boundary implemented by an application adapter.
///
/// Commands are sent once; typed business failures and unknown transport
/// outcomes propagate unchanged. No Native commands, implicit retry, automatic
/// load, login or local configuration fallback are permitted. Official payload
/// variants not representable here must fail with [AcpUnsupportedPayload].
abstract interface class AcpBusinessPort {
  /// Admits open and returns its resource before waiting for product Settled.
  Future<AcpSessionObservationPort> open(OpenAcpSessionRequestView request);
  Future<AcpRunIdView> prompt(AcpPromptRequestView request);
  Future<AcpRunIdView> replace(AcpReplaceRequestView request);
  Future<void> interrupt(AcpInterruptRequestView request);
  Future<void> configure(AcpConfigureRequestView request);
  Future<void> setMode(AcpSetModeRequestView request);
  Future<void> answerPermission(AcpPermissionAnswerRequestView request);
  Future<AcpListSessionsResponseView> list(AcpListRequestView request);
  Future<AcpBusinessSnapshotView> snapshot(AcpSessionTargetView target);
  Future<AcpBusinessCloseView> closeMember(AcpSessionTargetView target);
}
