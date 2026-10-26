import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run test_driver/request_shutdown.dart <vm-url>',
    );
    exitCode = 64;
    return;
  }

  final driver = await FlutterDriver.connect(
    dartVmServiceUrl: arguments.single,
    printCommunication: false,
    logCommunicationToFile: false,
  ).timeout(const Duration(seconds: 15));
  var shutdownFailed = false;
  late final String response;
  try {
    response = await driver
        .requestData('shutdown')
        .timeout(const Duration(seconds: 30));
    final report = jsonDecode(response);
    if (report is! Map || report['shutdown'] != 'completed') {
      throw StateError('native GUI shutdown did not complete: $response');
    }
  } on Object {
    shutdownFailed = true;
    rethrow;
  } finally {
    try {
      await driver.close().timeout(const Duration(seconds: 10));
    } on Object catch (error) {
      if (!shutdownFailed) rethrow;
      stderr.writeln('Driver connection cleanup failed: ${error.runtimeType}');
    }
  }
  stdout.writeln(response);
}
