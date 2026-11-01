import 'dart:io';

import 'package:anywork/src/platform/terminal_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Run the actual generated shell command against a capture function. No
  // terminal, SSH connection, automation permission or user directory is touched.
  test(
    'macOS local terminal keeps shell metacharacters inside the path',
    () async {
      const directory = r"/tmp/a'b;$(touch unexpected) space";
      final plan = buildHostTerminalLaunchPlan(
        executable: '/usr/bin/osascript',
        program: HostTerminalProgram.macTerminal,
        target: const LocalHostTerminalTarget(directory: directory),
      );
      final result = await Process.run('/bin/sh', [
        '-c',
        'cd() { printf "%s" "\$1"; }; clear() { :; }; '
            '${plan.arguments.last}',
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, directory);
    },
    skip: Platform.isWindows,
  );

  test('macOS SSH terminal preserves the alias and remote command', () async {
    const remotePath = r"/work/a'b;$(touch unexpected) space";
    final plan = buildHostTerminalLaunchPlan(
      executable: '/usr/bin/osascript',
      program: HostTerminalProgram.macTerminal,
      target: const RemoteSshTerminalTarget(
        alias: 'dev-host',
        remotePath: remotePath,
      ),
    );
    final result = await Process.run('/bin/sh', [
      '-c',
      'ssh() { printf "%s\\000" "\$@"; }; ${plan.arguments.last}',
    ]);
    expect(result.exitCode, 0);
    expect(
      result.stdout,
      '-t\u0000dev-host\u0000${buildRemoteSshRemoteCommand(remotePath)}\u0000',
    );
  }, skip: Platform.isWindows);
}
