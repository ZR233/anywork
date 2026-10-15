import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

class _SettingsTransport extends RecordingDemoTransport {
  final entered = <OperationId, Completer<void>>{};
  final released = <OperationId, Completer<void>>{};
  final calls = <OperationId>[];

  Completer<void> entry(OperationId id) =>
      entered.putIfAbsent(id, Completer<void>.new);
  Completer<void> release(OperationId id) =>
      released.putIfAbsent(id, Completer<void>.new);

  @override
  Future<SettingsCommandReply> applySettingsField(
    int revision,
    SettingsFieldCommand command, {
    required OperationId operationId,
  }) async {
    calls.add(operationId);
    entry(operationId).complete();
    await release(operationId).future;
    return super.applySettingsField(
      revision,
      command,
      operationId: operationId,
    );
  }
}

void main() {
  test(
    'old Settings ACK cannot clear newer intent and never rereads bootstrap',
    () async {
      final transport = _SettingsTransport();
      final client = AnyworkClient(transport: transport, clientId: 'settings');
      await client.bootstrap();
      final commands = client.settingsCommands;
      final first = commands.applySettingsField(
        const GeneralFollowActiveTurnCommand(false),
        mutationKey: 'follow',
      );
      final x = client.mutations.latest('settings:follow')!;
      final second = commands.applySettingsField(
        const GeneralFollowActiveTurnCommand(true),
        mutationKey: 'follow',
      );
      final y = client.mutations.latest('settings:follow')!;
      expect(x.id, isNot(y.id));
      await transport.entry(x.id).future;
      transport.release(x.id).complete();
      await first;
      await transport.entry(y.id).future;
      expect(x.state.value.observed, isTrue);
      expect(client.settings.state.commands['follow']?.isPending, isTrue);
      expect(client.mutations.latest('settings:follow')?.id, y.id);
      transport.release(y.id).complete();
      await second;
      expect(y.state.value.observed, isTrue);
      expect(client.settings.state.commands.containsKey('follow'), isFalse);
      expect(transport.bootstrapCalls, 1);
      expect(transport.calls, [x.id, y.id]);
      expect((await client.close()).complete, isTrue);
    },
  );
}
