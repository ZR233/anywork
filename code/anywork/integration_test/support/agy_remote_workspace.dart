import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywork_client/studio_client.dart';
import 'package:path/path.dart' as p;

// An independent SSH observer, not a replacement for Studio's remote executor.
// Only the explicitly provisioned synthetic fixture is read here. Business
// writes/commands must go through the live ACP agent's anywork_ tools.
final class AgyRemoteWorkspace {
  AgyRemoteWorkspace._(this.alias, this.target, this.path);

  final String alias;
  final String target;
  final String path;
  late final String _challenge;

  static AgyRemoteWorkspace? fromEnvironment() {
    final alias = Platform.environment['ANYWORK_AGY_SSH_ALIAS'];
    final target = Platform.environment['ANYWORK_AGY_SSH_TARGET'];
    if (alias == null && target == null) return null;
    if (Platform.environment['ANYWORK_AGY_LIVE'] != '1') {
      throw StateError('Remote acceptance requires ANYWORK_AGY_LIVE=1');
    }
    if (alias == null ||
        alias.trim().isEmpty ||
        target == null ||
        !RegExp(r'^[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+$').hasMatch(target)) {
      throw StateError(
        'Supply an existing ANYWORK_AGY_SSH_ALIAS and explicit '
        'user@host ANYWORK_AGY_SSH_TARGET',
      );
    }
    final path = Platform.environment['ANYWORK_AGY_PROJECT'];
    if (path == null ||
        !p.posix.isAbsolute(path) ||
        p.posix.normalize(path) != path ||
        !p.posix.basename(path).startsWith('anywork-agy-')) {
      throw StateError(
        'ANYWORK_AGY_PROJECT must name a canonical, dedicated '
        'remote anywork-agy-* fixture, not a local path',
      );
    }
    return AgyRemoteWorkspace._(alias, target, path);
  }

  Future<void> verifyFixture() async {
    final canonical = await _read('pwd -P');
    if (canonical.trim() != path) {
      throw StateError('Remote project path must be canonical');
    }
    if (await _read('cat README.md') !=
        'Disposable ACP live acceptance workspace. No private data.\n') {
      throw StateError('Remote fixture ownership marker differs');
    }
    // This challenge is never sent in the prompt: a successful independent
    // readback cannot be produced solely from the instructions given to agy.
    _challenge = (await _read('cat input-token.txt')).trim();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(_challenge)) {
      throw StateError('Remote fixture needs a fresh synthetic 64-hex token');
    }
    await _read(
      'test ! -e result.txt && test ! -e command-cwd.txt && '
      'test ! -e command-system.txt && test ! -e stdin.proc && '
      'test ! -e cancel.proc && test ! -e shutdown.proc && '
      'test ! -e child-result.txt && git rev-parse --git-dir >/dev/null',
    );
  }

  Future<void> verifyServer(List<SshServer> servers) async {
    final matches = servers.where((server) => server.alias == alias).toList();
    if (matches.length != 1 ||
        '${matches.single.username}@${matches.single.hostName}' != target ||
        matches.single.port != 22) {
      throw StateError(
        'The existing Studio SSH alias must identify the explicit '
        'user@host target on port 22; no SSH configuration is written',
      );
    }
  }

  String prompt(String marker, String childProfile) =>
      'This is an explicitly authorized disposable remote fixture. Use only '
      'the Host MCP anywork_ file and command tools, never your built-in local '
      'filesystem or terminal and never raw ssh. Do not install anything, log in, '
      'open tunnels, access credentials, or modify outside the current remote '
      'workspace. Read input-token.txt with anywork_exec_command in the current '
      'workspace. Write result.txt with the advertised anywork_ file/patch tools '
      'with its token as line 1 and $marker as line 2, each newline-terminated. '
      'Run one small remote shell command in the workspace: '
      '`pwd -P > command-cwd.txt; uname -s > command-system.txt`. '
      'Then exercise the real task lifecycle using the advertised tool schemas. '
      'Start anywork_exec_command with interactive=true, cwd=".", '
      'timeoutSeconds=300, command=${jsonEncode(processCommand('stdin'))}. '
      'It blocks for input and must return a real task receipt. Use '
      'anywork_list_tool_tasks to recover/confirm that exact taskId; never infer '
      'a taskId from a call ID. Send exactly ${jsonEncode('$marker-stdin\n')} '
      'once with anywork_write_stdin, closeStdin=true. Check acceptedBytes and '
      'closeState, then anywork_wait on that exact taskId and '
      'anywork_get_tool_task(resultCursor=0) until its original terminal '
      'payload is available. No replay of accepted input. '
      'Start another anywork_exec_command with cwd=".", timeoutSeconds=300, '
      'command=${jsonEncode(processCommand('cancel'))}. Recover/confirm its '
      'real taskId via anywork_list_tool_tasks. Read cancel.proc and '
      'cancel-child.proc with anywork_exec_command to observe both process '
      'identities before cancelling; absent markers are a failure, not a reason '
      'to replay the command. Cancel that task using '
      'anywork_cancel_tool_task, then anywork_wait on the same taskId and read '
      'its original cancelled payload with anywork_get_tool_task(resultCursor=0). '
      'Cancellation acknowledgement alone is not process exit. '
      'Next call anywork_list_agent_profiles and use the ACP profile '
      '${jsonEncode(childProfile)} for exactly one real anywork_spawn_agent. '
      'Do not pass Native modelSelection, writablePaths or review options. '
      'Give the child this self-contained task: use only Host MCP anywork_ '
      'tools, read input-token.txt with anywork_exec_command in its remote '
      'workspace; write child-result.txt with an advertised file/patch tool, '
      'with the token on line 1 and $marker-child on line 2, '
      'newline-terminated; reply with $marker-child and do not delegate. '
      'Use the actual spawned agentId with anywork_wait_agent. Wait for a '
      'nonempty original report, checking gap=false, cursor and original '
      'generation/run/completionSequence against current.lastCompleted; a '
      'spawn receipt is not completion. Close that child with '
      'anywork_close_agent only after reading its report. '
      'Finally start a third anywork_exec_command with cwd=".", '
      'timeoutSeconds=300, command=${jsonEncode(processCommand('shutdown'))}. '
      'Confirm its actual taskId via anywork_list_tool_tasks and call '
      'anywork_wait on it with timeoutMs=1. It must remain running; do not '
      'cancel this last task. The integration test will close this ACP member '
      'and independently check that its owned remote process tree exits. '
      'Do not merely describe these actions. After the other tools succeed reply '
      'with exactly $marker and nothing else.';

  String processCommand(String kind) {
    final script = kind == 'stdin'
        ? 'cat /proc/\$\$/stat > stdin.proc; '
              'cat > stdin-value.txt; printf "eof\\n" > stdin-eof.txt'
        : 'cat /proc/\$\$/stat > $kind.proc; '
              'sleep 300 & child=\$!; '
              'cat /proc/\$child/stat > $kind-child.proc; wait "\$child"';
    return 'sh -c ${_quote(script)}';
  }

  Future<Map<String, Object?>> verifyResult(String marker) async {
    if (await _read('cat result.txt') != '$_challenge\n$marker\n') {
      throw StateError('Independent SSH readback did not match file challenge');
    }
    if ((await _read('cat command-cwd.txt')).trim() != path ||
        (await _read('cat command-system.txt')).trim() != 'Linux') {
      throw StateError(
        'Independent SSH readback did not match command location',
      );
    }
    if (await _read('cat child-result.txt') != '$_challenge\n$marker-child\n' ||
        await _read('cat stdin-value.txt') != '$marker-stdin\n' ||
        await _read('cat stdin-eof.txt') != 'eof\n') {
      throw StateError('Independent child/STDIN/EOF readback did not match');
    }
    final exited = <Map<String, Object?>>[];
    for (final name in ['stdin', 'cancel', 'cancel-child']) {
      final identity = LinuxProcessIdentity.parse(
        await _read('cat $name.proc'),
      );
      await _verifyProcess(identity, running: false);
      exited.add(identity.evidence);
    }
    for (final name in ['shutdown', 'shutdown-child']) {
      final identity = LinuxProcessIdentity.parse(
        await _read('cat $name.proc'),
      );
      await _verifyProcess(identity, running: true);
      _shutdownProcesses.add(identity);
    }
    return {
      'remotePath': path,
      'fileChallengeMatched': true,
      'commandCwdMatched': true,
      'commandSystem': 'Linux',
      'childFileChallengeMatched': true,
      'stdinValueMatched': true,
      'stdinEofObserved': true,
      'independentExitedProcesses': exited,
      'runningBeforeClose': _shutdownProcesses.map((p) => p.evidence).toList(),
      'observer': 'independent BatchMode/StrictHostKeyChecking SSH readback',
    };
  }

  final List<LinuxProcessIdentity> _shutdownProcesses = [];

  Future<List<Map<String, Object?>>> verifyClosedProcesses() async {
    if (_shutdownProcesses.length != 2) {
      throw StateError('Missing pre-close remote process identities');
    }
    for (final identity in _shutdownProcesses) {
      await _verifyProcess(identity, running: false);
    }
    return _shutdownProcesses.map((p) => p.evidence).toList();
  }

  Future<void> _verifyProcess(
    LinuxProcessIdentity identity, {
    required bool running,
  }) async {
    final observed = await _read(
      'if test -r /proc/${identity.pid}/stat; then '
      'cat /proc/${identity.pid}/stat; fi',
    );
    final same =
        observed.isNotEmpty &&
        identity.sameProcess(LinuxProcessIdentity.parse(observed));
    if (same != running) {
      throw StateError(
        'Remote owned process ${identity.pid} '
        'did not satisfy running=$running',
      );
    }
  }

  Future<String> _read(String command) async {
    final process = await Process.start('ssh', [
      '-T',
      '-x',
      '-a',
      '-o',
      'ClearAllForwardings=yes',
      '-o',
      'BatchMode=yes',
      '-o',
      'StrictHostKeyChecking=yes',
      '-o',
      'ConnectTimeout=5',
      '-o',
      'ConnectionAttempts=1',
      target,
      'cd -- ${_quote(path)} && ($command)',
    ]);
    await process.stdin.close();
    final output = process.stdout.transform(utf8.decoder).join();
    final error = process.stderr.transform(utf8.decoder).join();
    try {
      final status = await process.exitCode.timeout(
        const Duration(seconds: 10),
      );
      final stdout = await output;
      final stderr = await error;
      if (status != 0) {
        throw StateError(
          'Independent SSH fixture check failed ($status): $stderr',
        );
      }
      return stdout;
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      await Future.wait([output, error]);
      rethrow;
    }
  }
}

String _quote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

// /proc stat's command name may contain spaces or parentheses. Fields after
// the last ')' start at field 3; starttime is field 22, not a PID-only identity.
final class LinuxProcessIdentity {
  LinuxProcessIdentity(this.pid, this.startTime, this.parentPid);
  final int pid;
  final String startTime;
  final int parentPid;

  factory LinuxProcessIdentity.parse(String stat) {
    final end = stat.lastIndexOf(')');
    final separator = stat.indexOf(' ');
    if (end < 0 || separator <= 0 || end <= separator) {
      throw StateError('Invalid owned process stat');
    }
    final fields = stat.substring(end + 1).trim().split(RegExp(r'\s+'));
    final pid = int.parse(stat.substring(0, separator));
    if (pid <= 1 ||
        fields.length < 20 ||
        !RegExp(r'^\d+$').hasMatch(fields[19])) {
      throw StateError('Invalid owned process identity');
    }
    return LinuxProcessIdentity(pid, fields[19], int.parse(fields[1]));
  }

  bool sameProcess(LinuxProcessIdentity other) =>
      pid == other.pid && startTime == other.startTime;

  Map<String, Object?> get evidence => {
    'pid': pid,
    'startTime': startTime,
    'parentPid': parentPid,
  };
}

// Observe only descendants of this integration-test GUI, never all machine
// processes or user command lines. No signal is sent by this observer.
final class AgyLocalProcesses {
  final List<LinuxProcessIdentity> _owned = [];

  Future<void> capture(String agyCommand) async {
    if (!Platform.isLinux) {
      throw StateError('Independent /proc acceptance requires Linux host');
    }
    final agyExecutable = await File(agyCommand).resolveSymbolicLinks();
    var sawAgy = false;
    Future<void> descendants(int parent) async {
      // Linux's children file is per thread: Tokio/FRB may spawn from a
      // non-main thread. Inspect only this owned process's task directory.
      final threads = Directory('/proc/$parent/task');
      if (!await threads.exists()) return;
      final ids = <int>{};
      await for (final thread in threads.list()) {
        final children = File(p.posix.join(thread.path, 'children'));
        final text = await _readIfPresent(children);
        if (text == null || text.trim().isEmpty) continue;
        ids.addAll(text.trim().split(RegExp(r'\s+')).map(int.parse));
      }
      for (final child in ids) {
        final stat = File('/proc/$child/stat');
        final text = await _readIfPresent(stat);
        if (text == null) continue;
        final identity = LinuxProcessIdentity.parse(text);
        if (identity.parentPid != parent) continue;
        _owned.add(identity);
        try {
          sawAgy |=
              await Link('/proc/$child/exe').resolveSymbolicLinks() ==
              agyExecutable;
        } on FileSystemException {
          if (await stat.exists()) rethrow;
        }
        await descendants(child);
      }
    }

    await descendants(pid);
    if (!sawAgy) throw StateError('No actual owned agy process was observed');
  }

  List<Map<String, Object?>> get evidence =>
      _owned.map((p) => p.evidence).toList();

  Future<void> verifyClosed() async {
    for (final identity in _owned) {
      final stat = File('/proc/${identity.pid}/stat');
      final text = await _readIfPresent(stat);
      if (text != null &&
          identity.sameProcess(LinuxProcessIdentity.parse(text))) {
        throw StateError(
          'Owned local process ${identity.pid} survived ACP close',
        );
      }
    }
  }
}

Future<String?> _readIfPresent(File file) async {
  try {
    return await file.readAsString();
  } on FileSystemException {
    if (!await file.exists()) return null;
    rethrow;
  }
}
