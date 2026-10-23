import 'package:anywork/src/infrastructure/frb/shared/bridge_failure.dart';
import 'package:anywork/src/rust/api/studio/types/error.dart' as wire;
import 'package:anywork_client/resources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native SSH authentication evidence, including false and unknown, crosses the typed boundary', () {
    for (final offered in <bool?>[false, true, null]) {
      final failure = bridgeFailure(wire.BridgeError(
        code: wire.BridgeErrorCode.permissionDenied,
        message: 'Remote host rejected credentials',
        retryable: false,
        correlationId: 'ssh-auth',
        details: wire.BridgeErrorDetails.sshAuthentication(passwordOffered: offered),
      ));
      expect(failure.code, StudioFailureCode.permissionDenied);
      expect(failure.retryable, isFalse);
      expect(failure.correlationId, 'ssh-auth');
      expect(failure.details, isA<SshAuthenticationFailureDetails>());
      expect((failure.details as SshAuthenticationFailureDetails).passwordOffered, offered,
        reason: 'False is evidence, and null must not be fabricated as true');
    }
  });

  test('diagnostic wording and untyped exceptions never fabricate SSH authentication evidence', () {
    final withoutDetails = bridgeFailure(const wire.BridgeError(
      code: wire.BridgeErrorCode.unavailable,
      message: 'SSH authentication required or failed: Permission denied',
      retryable: true,
      correlationId: 'network-with-auth-words',
      details: null,
    ));
    expect(withoutDetails.code, StudioFailureCode.unavailable);
    expect(withoutDetails.details, isNull);
    final untyped = bridgeFailure(StateError(
      'SSH authentication required or failed: Permission denied'));
    expect(untyped.code, StudioFailureCode.protocol);
    expect(untyped.details, isNull);
    expect(untyped.message, isNot(contains('Permission denied')),
      reason: 'The raw exception is not rendered into a domain diagnostic');
  });
}
