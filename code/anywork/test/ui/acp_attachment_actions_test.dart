import 'dart:async';

import 'package:anywork/src/features/conversation/acp/view_models/acp_conversation_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'acp_components_support.dart';

void main() {
  testWidgets('附件选择取消不改草稿，异步错误归入原 thread 草稿', (tester) async {
    final harness = await AcpComponentHarness.create();
    addTearDown(() => harness.close(tester));
    final original = harness.client.drafts.composer('thread');
    original.updateDraft('原草稿');
    final actions = AcpConversationActions(harness.client, 'thread');
    await actions.pickLocalAttachments(() async => []);
    expect(original.state.draft, '原草稿');
    expect(original.state.failure, isNull);

    final picker = Completer<List<String>>();
    final pending = actions.pickLocalAttachments(() => picker.future);
    final other = harness.client.drafts.composer('other-thread');
    other.updateDraft('另一草稿');
    final error = StateError('picker failed');
    picker.completeError(error);
    await pending;
    expect(original.state.draft, '原草稿');
    expect(original.state.failure, same(error));
    expect(other.state.draft, '另一草稿');
    expect(other.state.failure, isNull);
    expect(harness.port.calls.map((call) => call.$1), ['open']);
  });
}
