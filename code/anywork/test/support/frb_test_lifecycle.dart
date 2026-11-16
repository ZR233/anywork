import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/handlers/chat.dart' as wire;
import 'package:anywork/src/rust/api/studio/types/chat.dart' as dto;
import 'package:anywork/src/rust/frb_generated.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_fixtures.dart';
import 'test_app_lifecycle.dart';

final class TestFrbStudioTransport extends FrbStudioTransport
    implements TestLifecycleOwner {
  factory TestFrbStudioTransport({RustLibApi? mockApi}) {
    if (mockApi != null) RustLib.initMock(api: mockApi);
    final root = ClientScope(owner: 'frb-adapter-test');
    final runtime = FrbRuntimeOwner(startupScope: root.child('startup'))
      ..debugOverrideInitialization(() async {});
    addTearDown(() async {
      final report = await root.close(budget: testCloseBudget());
      expect(report.complete, isTrue, reason: '${report.unresolved}');
      // Keep the mock installed if scope cleanup fails: retained native handles
      // must not outlive their FRB entrypoint. Do not split this into tearDowns,
      // since the test runner still runs later callbacks after a cleanup failure.
      if (mockApi != null) RustLib.dispose();
    });
    return TestFrbStudioTransport._(root, runtime);
  }

  TestFrbStudioTransport._(this.lifecycleRoot, FrbRuntimeOwner runtime)
    : super(
        runtime: runtime,
        contentScope: lifecycleRoot.child('content'),
        progressScope: lifecycleRoot.child('progress'),
      );

  @override
  final ClientScope lifecycleRoot;
}

Future<FrbConversationFeed> testFrbConversationFeed(
  wire.BridgeConversationFeed native,
) async {
  final transport = TestFrbStudioTransport(mockApi: _FeedApi(native));
  return await transport.openConversationFeed(
    native.threadId(),
    scope: const ChatScope(queryClass: AllChatClasses()),
    demand: chatDemand,
  ) as FrbConversationFeed;
}

final class _FeedApi implements RustLibApi {
  _FeedApi(this.native);
  final wire.BridgeConversationFeed native;
  @override
  Future<wire.BridgeConversationFeed>
  crateApiStudioHandlersChatOpenConversationFeed({
    required String threadId,
    required dto.BridgeChatScope scope,
    required dto.BridgeReadDemand demand,
  }) async => native;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected feed API: ${invocation.memberName}');
}
