import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_driver/flutter_driver.dart';
import '../../code/anywork/test_driver/flutter_driver_session.dart';
import '../../code/anywork/test_driver/pointer_drag.dart';

class ProbeClient implements FlutterDriverClient {
  int calls = 0;
  int closes = 0;
  Duration? deadline;
  bool hang = false;
  Future<void> operation(Duration? timeout) {
    calls++;
    deadline = timeout;
    return hang ? Completer<void>().future : Future<void>.value();
  }
  @override
  Future<void> checkHealth() async {}
  @override
  Future<void> setFrameSync(bool enabled) async {}
  @override
  Future<void> close() async { closes++; }
  @override
  Future<void> scrollBy(SerializableFinder finder, double dy, {bool mouseWheel = false, Duration? timeout}) => operation(timeout);
  @override
  Future<void> dragBy(SerializableFinder finder, {double dx = 0, double dy = 0, PointerDragKind pointerKind = PointerDragKind.touch, Duration? timeout}) => operation(timeout);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('${invocation.memberName}');
}
Future<void> main() async {
  final result = <String, Object?>{};
  for (final name in ['drag-default', 'wheel-default', 'drag-hang']) {
    final fake = ProbeClient()..hang = name == 'drag-hang';
    var connections = 0;
    final session = await FlutterDriverSession.connect(vmServiceUrl: 'fake', connector: (_) async { connections++; return fake; });
    if (!fake.hang) {
      if (name == 'drag-default') {
        await session.dragBy(find.byValueKey('probe'), dy: 10);
      } else {
        await session.scrollBy(find.byValueKey('probe'), 10, mouseWheel: true);
      }
      result[name] = fake.deadline == FlutterDriverSession.tapDeadline;
      await session.close();
    } else {
      try {
        await session.dragBy(find.byValueKey('probe'), dy: 10, timeout: const Duration(milliseconds: 10)).timeout(const Duration(milliseconds: 200));
      } on TimeoutException catch (error) {
        await Future<void>.delayed(Duration.zero);
        result[name] = error.message!.startsWith('dragBy timed out after 10 ms') && fake.closes == 1 && fake.calls == 1 && connections == 1;
      }
      await session.close();
    }
  }
  stdout.writeln(jsonEncode(result));
  if (result.values.any((value) => value != true)) exitCode = 1;
}
