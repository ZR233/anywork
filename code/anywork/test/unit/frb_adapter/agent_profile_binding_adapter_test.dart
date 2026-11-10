import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/types/session_directory.dart'
    as frb;
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Agent Profile binding adapter', () {
    test('Native save binding preserves route and instructions', () {
      const binding = NativeAgentBindingView(
        route: NewThreadModelRoute(
          accountId: 'account-native',
          modelId: 'model-native',
          effort: 'high',
        ),
        systemInstructions: 'Use the selected Native profile instructions.',
      );

      final wire = agentBindingToFrb(binding);
      expect(
        wire,
        isA<frb.BridgeAgentBinding_Native>()
            .having(
              (value) => value.route?.accountId,
              'accountId',
              'account-native',
            )
            .having((value) => value.route?.modelId, 'modelId', 'model-native')
            .having((value) => value.route?.effort, 'effort', 'high')
            .having(
              (value) => value.systemInstructions,
              'systemInstructions',
              'Use the selected Native profile instructions.',
            ),
      );
      expect(agentBindingFromFrb(wire), binding);
    });

    test('ACP profile binding round-trips only its account identity', () {
      const binding = AcpAgentBindingView(accountId: 'acp-account');

      final wire = agentBindingToFrb(binding);
      expect(wire, isA<frb.BridgeAgentBinding_Acp>());
      expect(agentBindingFromFrb(wire), binding);
    });

    test('Native directory binding leaves profile instructions absent', () {
      const binding = NativeAgentBindingView(
        route: NewThreadModelRoute(
          accountId: 'account-directory',
          modelId: 'model-directory',
        ),
      );

      final wire = agentBindingToFrb(binding);
      expect(
        wire,
        isA<frb.BridgeAgentBinding_Native>().having(
          (value) => value.systemInstructions,
          'systemInstructions',
          isNull,
        ),
      );
    });
  });
}
