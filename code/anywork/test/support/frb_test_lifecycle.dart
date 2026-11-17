import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/frb_generated.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

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
