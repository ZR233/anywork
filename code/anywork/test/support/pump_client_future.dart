import 'package:flutter_test/flutter_test.dart';

/// Stream cancellation can return the SDK's Zone.root null future. Advance
/// both queues without sleeping or awaiting a FakeAsync owner inside runAsync.
Future<void> pumpClientUntil(
  WidgetTester tester,
  bool Function() ready,
  String stage,
) async {
  for (var frame = 0; frame < 128; frame++) {
    if (ready()) return;
    await tester.runAsync(() async {});
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Client did not settle: $stage');
}

Future<T> pumpClientFuture<T>(
  WidgetTester tester,
  Future<T> future,
  String stage,
) async {
  var complete = false;
  T? value;
  Object? failure;
  StackTrace? trace;
  future.then<void>(
    (result) {
      value = result;
      complete = true;
    },
    onError: (Object error, StackTrace stack) {
      failure = error;
      trace = stack;
      complete = true;
    },
  );
  await pumpClientUntil(tester, () => complete, stage);
  if (failure case final error?) Error.throwWithStackTrace(error, trace!);
  return value as T;
}
