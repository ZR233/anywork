// GUI 原生进程驻留内存（RSS）采样件，用于 Timeline 性能的前后对比。
//
// 测量的是什么
//   一个原生 GUI 进程及其全部子进程的 Linux 驻留内存，逐样本读
//   `/proc/<pid>/status` 的 `VmRSS`（当前驻留）与 `VmHWM`（历史最高驻留），
//   再把同一棵树内各进程相加。GUI 把 Rust bridge（`libpl_studio_bridge.so`）
//   和 Flutter 引擎跑在同一个进程里，所以记录值是两者的合计，不是分层拆分。
//
// 不代表什么
//   不是分配器级别的测量，不是任意负载的内存上限，不是跨平台内存峰值，也不
//   可跨场景、跨窗口尺寸或跨机器比较。只用于同一场景、同一机器、同一窗口
//   尺寸下的改动前后对比；单层分配、真实分配峰值和未运行平台仍属未验证。
//
// 用法（在仓库根目录执行；`cargo dart` 会把工作目录切到 code/anywork）：
//   cargo dart test_driver/rss_sampler.dart \
//     --pid-file ../../target/perf-baseline/<run>/gui-pid.txt \
//     --interval-ms 500 \
//     --output ../../target/perf-baseline/<run>/gui-rss.jsonl \
//     --summary ../../target/perf-baseline/<run>/gui-rss-summary.json \
//     --exit-when-gone
//
//   # 直接给 PID（例如 Driver 的 `pid` 请求返回的原生进程号）
//   cargo dart test_driver/rss_sampler.dart --pid 12345 --exit-when-gone \
//     --interval-ms 500 --output ../../target/perf-baseline/run/gui-rss.jsonl
//
//   # 用命令行子串匹配进程（本仓库 profile 构建的可执行文件路径唯一）
//   cargo dart test_driver/rss_sampler.dart \
//     --match 'build/linux/x64/profile/bundle/anywork' ...
//
// 输入
//   --pid <n>                  直接采样该进程号。
//   --pid-file <path>          读取文件里的进程号；配合 --pid-file-timeout-ms
//                              在文件出现前等待（默认 120000ms）。
//   --match <substring>        扫描 /proc/*/cmdline，取唯一包含该子串的进程；
//                              命中不唯一或零命中都报错，不猜进程身份。采样件
//                              自身与祖先链（cargo/dart 包装进程）不会被匹配。
//   --interval-ms <n>          采样间隔，默认 500。
//   --output <path>            必填，JSON Lines，每行一个样本。
//   --summary <path>           可选，结束时写峰值/稳态/分布摘要 JSON。
//   --duration-ms <n>          可选，总采样时长上限。
//   --exit-when-gone           目标进程消失后自动结束（否则持续采样直到
//                              --duration-ms 或 Ctrl-C）。
//
// 相对路径按进程当前工作目录解析；`cargo dart` 下即 code/anywork，因此示例
// 用 `../../target/...`。采样进程不测量自己，也不是被采样进程的子进程，因此
// 不给被测 GUI 增加驻留开销。行为差异只在同一次改动前后对比时才有效。
//
// 退出码：0 正常；64 参数错误；3 进程不存在；4 权限不足；5 等待 pid 文件超时。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _usage = '''
usage: rss_sampler.dart (--pid <n> | --pid-file <path> | --match <substring>)
         --output <jsonl> [--summary <json>]
         [--interval-ms <n>] [--duration-ms <n>] [--exit-when-gone]
         [--pid-file-timeout-ms <n>]

Samples the Linux resident memory of one GUI native process plus its
descendants from /proc/<pid>/status (VmRSS, VmHWM) and writes one JSON object
per sample. See the file header for what the value does and does not mean.
''';

const int _exitUsage = 64;
const int _exitNoProcess = 3;
const int _exitPermission = 4;
const int _exitPidFileTimeout = 5;

class _Options {
  _Options({
    required this.output,
    required this.summary,
    required this.intervalMs,
    required this.durationMs,
    required this.pidFileTimeoutMs,
    required this.exitWhenGone,
    required this.pid,
    required this.pidFile,
    required this.match,
  });

  final String output;
  final String? summary;
  final int intervalMs;
  final int? durationMs;
  final int pidFileTimeoutMs;
  final bool exitWhenGone;
  final int? pid;
  final String? pidFile;
  final String? match;
}

Never _fail(String message, int code) {
  stderr.writeln('rss_sampler: $message');
  exit(code);
}

int _requireInt(String name, String? value) {
  if (value == null) _fail('$name requires a value', _exitUsage);
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed <= 0) {
    _fail('$name expects a positive integer, got "$value"', _exitUsage);
  }
  return parsed;
}

_Options _parse(List<String> args) {
  int? pid;
  String? pidFile;
  String? match;
  String? output;
  String? summary;
  var intervalMs = 500;
  int? durationMs;
  var pidFileTimeoutMs = 120000;
  var exitWhenGone = false;
  var index = 0;
  while (index < args.length) {
    final flag = args[index];
    String? value() => index + 1 < args.length ? args[index + 1] : null;
    switch (flag) {
      case '--help':
      case '-h':
        stdout.writeln(_usage);
        exit(0);
      case '--pid':
        pid = _requireInt('--pid', value());
        index += 2;
      case '--pid-file':
        pidFile = value();
        if (pidFile == null) _fail('--pid-file requires a value', _exitUsage);
        index += 2;
      case '--pid-file-timeout-ms':
        pidFileTimeoutMs = _requireInt('--pid-file-timeout-ms', value());
        index += 2;
      case '--match':
        match = value();
        if (match == null || match.isEmpty) {
          _fail('--match requires a non-empty value', _exitUsage);
        }
        index += 2;
      case '--interval-ms':
        intervalMs = _requireInt('--interval-ms', value());
        index += 2;
      case '--duration-ms':
        durationMs = _requireInt('--duration-ms', value());
        index += 2;
      case '--output':
        output = value();
        if (output == null) _fail('--output requires a value', _exitUsage);
        index += 2;
      case '--summary':
        summary = value();
        if (summary == null) _fail('--summary requires a value', _exitUsage);
        index += 2;
      case '--exit-when-gone':
        exitWhenGone = true;
        index += 1;
      default:
        _fail('unknown argument "$flag"\n\n$_usage', _exitUsage);
    }
  }
  final selectors = <String>[
    if (pid != null) 'pid',
    if (pidFile != null) 'pid-file',
    if (match != null) 'match',
  ];
  if (selectors.isEmpty) {
    _fail(
      'exactly one of --pid, --pid-file or --match is required\n\n$_usage',
      _exitUsage,
    );
  }
  if (selectors.length > 1) {
    _fail(
      '--pid, --pid-file and --match are mutually exclusive '
      '(got ${selectors.join(', ')})',
      _exitUsage,
    );
  }
  if (output == null) _fail('--output is required\n\n$_usage', _exitUsage);
  return _Options(
    output: output,
    summary: summary,
    intervalMs: intervalMs,
    durationMs: durationMs,
    pidFileTimeoutMs: pidFileTimeoutMs,
    exitWhenGone: exitWhenGone,
    pid: pid,
    pidFile: pidFile,
    match: match,
  );
}

/// `VmRSS`/`VmHWM` for one process, or null when the process is already gone or
/// its `/proc` entry is unreadable.
class _ProcessUsage {
  _ProcessUsage(this.pid, this.rssBytes, this.highWaterBytes);

  final int pid;
  final int rssBytes;
  final int highWaterBytes;
}

int? _firstInteger(String line) {
  final match = RegExp(r'(\d+)').firstMatch(line);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// Reads one process's resident set. Returns null when the process vanished
/// between listing and reading; that is normal for a short-lived child and is
/// never reported as a permission error.
_ProcessUsage? _readProcess(int pid) {
  final String status;
  try {
    status = File('/proc/$pid/status').readAsStringSync();
  } on FileSystemException {
    return null;
  }
  int? rssKb;
  int? highWaterKb;
  for (final line in const LineSplitter().convert(status)) {
    if (line.startsWith('VmRSS:')) {
      rssKb = _firstInteger(line);
    } else if (line.startsWith('VmHWM:')) {
      highWaterKb = _firstInteger(line);
    }
  }
  if (rssKb == null) return null;
  return _ProcessUsage(pid, rssKb * 1024, (highWaterKb ?? rssKb) * 1024);
}

/// Direct children of a process, read from `/proc/<pid>/task/<tid>/children`.
List<int> _children(int pid) {
  final result = <int>[];
  final List<FileSystemEntity> tasks;
  try {
    tasks = Directory('/proc/$pid/task').listSync();
  } on FileSystemException {
    return result;
  }
  for (final task in tasks) {
    final String text;
    try {
      text = File('${task.path}/children').readAsStringSync();
    } on FileSystemException {
      continue;
    }
    for (final token in text.split(RegExp(r'\s+'))) {
      final child = int.tryParse(token);
      if (child != null && child > 0) result.add(child);
    }
  }
  return result;
}

/// The root process plus every descendant, discovered breadth-first so a child
/// created during the walk is still included on the next sample.
List<int> _processTree(int root) {
  final seen = <int>{};
  final pending = <int>[root];
  final ordered = <int>[];
  while (pending.isNotEmpty) {
    final pid = pending.removeLast();
    if (!seen.add(pid)) continue;
    ordered.add(pid);
    pending.addAll(_children(pid));
  }
  return ordered;
}

String _commandLine(int pid) {
  try {
    final bytes = File('/proc/$pid/cmdline').readAsBytesSync();
    return utf8
        .decode(bytes, allowMalformed: true)
        .replaceAll('\u0000', ' ')
        .trim();
  } on FileSystemException {
    return '';
  }
}

String _executable(int pid) {
  try {
    return File('/proc/$pid/exe').resolveSymbolicLinksSync();
  } on FileSystemException {
    return '';
  }
}

/// `PPid` from `/proc/<pid>/status`, or null when the process is gone.
int? _parentPid(int pid) {
  final String status;
  try {
    status = File('/proc/$pid/status').readAsStringSync();
  } on FileSystemException {
    return null;
  }
  for (final line in const LineSplitter().convert(status)) {
    if (line.startsWith('PPid:')) return _firstInteger(line);
  }
  return null;
}

/// The sampler's own process and every ancestor, which are never `--match`
/// candidates: the launcher chain (`cargo dart ... --match <needle>`) carries
/// the needle in its own command line and would otherwise always self-match.
Set<int> _ownAncestry() {
  final ancestry = <int>{pid};
  var current = pid;
  for (var depth = 0; depth < 64; depth += 1) {
    final parent = _parentPid(current);
    if (parent == null || parent <= 1 || !ancestry.add(parent)) break;
    current = parent;
  }
  return ancestry;
}

/// Resolves the unique `/proc/*/cmdline` containing [needle].
///
/// Zero or multiple matches is an error: silently picking one of several GUI
/// processes would corrupt the measurement.
int _resolveByMatch(String needle) {
  final matches = <int>[];
  final excluded = _ownAncestry();
  final List<FileSystemEntity> entries;
  try {
    entries = Directory('/proc').listSync();
  } on FileSystemException catch (error) {
    _fail(
      '/proc is unreadable ($error); this sampler is Linux-only',
      _exitNoProcess,
    );
  }
  for (final entry in entries) {
    final pid = int.tryParse(entry.path.split('/').last);
    if (pid == null || pid <= 0) continue;
    if (excluded.contains(pid)) continue;
    final command = _commandLine(pid);
    if (command.isEmpty) continue;
    if (command.contains(needle)) matches.add(pid);
  }
  if (matches.isEmpty) {
    _fail('no process matches "$needle"', _exitNoProcess);
  }
  if (matches.length > 1) {
    final detail = matches
        .map((pid) => '$pid: ${_commandLine(pid)}')
        .join('\n  ');
    _fail(
      '"$needle" matches ${matches.length} processes; refine it:\n  $detail',
      _exitUsage,
    );
  }
  return matches.single;
}

Future<int> _waitForPidFile(String path, int timeoutMs) async {
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (true) {
    final file = File(path);
    if (file.existsSync()) {
      final text = file.readAsStringSync().trim();
      final pid = int.tryParse(text);
      if (pid != null && pid > 0) return pid;
      _fail(
        'pid file "$path" does not contain a process id (got "$text")',
        _exitUsage,
      );
    }
    if (!DateTime.now().isBefore(deadline)) {
      _fail(
        'pid file "$path" did not appear within ${timeoutMs}ms',
        _exitPidFileTimeout,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// One summed sample of the whole process tree.
class _Sample {
  _Sample({required this.atUnixMillis, required this.processes});

  final int atUnixMillis;
  final List<_ProcessUsage> processes;

  int get rssBytes => processes.fold(0, (sum, usage) => sum + usage.rssBytes);
  int get highWaterBytes =>
      processes.fold(0, (sum, usage) => sum + usage.highWaterBytes);
}

int _median(List<int> values) {
  final sorted = List<int>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) ~/ 2;
}

int _percentile(List<int> values, double fraction) {
  final sorted = List<int>.of(values)..sort();
  if (sorted.length == 1) return sorted.first;
  final rank = (fraction * (sorted.length - 1)).round();
  return sorted[rank.clamp(0, sorted.length - 1)];
}

Future<void> main(List<String> args) async {
  if (!Platform.isLinux) {
    _fail('this sampler reads /proc and supports Linux only', _exitUsage);
  }
  final options = _parse(args);
  final outputFile = File(options.output);
  await outputFile.parent.create(recursive: true);
  final sink = outputFile.openWrite(mode: FileMode.write);

  final int rootPid;
  if (options.pid != null) {
    rootPid = options.pid!;
  } else if (options.pidFile != null) {
    rootPid = await _waitForPidFile(options.pidFile!, options.pidFileTimeoutMs);
  } else {
    rootPid = _resolveByMatch(options.match!);
  }

  final firstRead = _readProcess(rootPid);
  if (firstRead == null) {
    final exists = Directory('/proc/$rootPid').existsSync();
    sink.close();
    if (exists) {
      _fail(
        'cannot read /proc/$rootPid/status (permission denied); '
        'run the sampler as the same user as the GUI',
        _exitPermission,
      );
    }
    _fail('process $rootPid does not exist', _exitNoProcess);
  }

  final rootCommand = _commandLine(rootPid);
  final rootExecutable = _executable(rootPid);
  stdout.writeln(
    'rss_sampler: sampling pid $rootPid (${rootExecutable.isEmpty ? 'exe unknown' : rootExecutable}) '
    'every ${options.intervalMs}ms -> ${outputFile.path}',
  );

  final samples = <_Sample>[];
  final startedAt = DateTime.now();
  var vanished = false;
  while (true) {
    final atUnixMillis = DateTime.now().millisecondsSinceEpoch;
    final tree = _processTree(rootPid);
    final usages = <_ProcessUsage>[];
    for (final pid in tree) {
      final usage = _readProcess(pid);
      if (usage != null) usages.add(usage);
    }
    if (usages.isEmpty) {
      vanished = true;
      if (options.exitWhenGone) break;
    } else {
      final sample = _Sample(atUnixMillis: atUnixMillis, processes: usages);
      samples.add(sample);
      sink.writeln(
        jsonEncode({
          'atUnixMillis': atUnixMillis,
          'rootPid': rootPid,
          'processCount': usages.length,
          'rssBytes': sample.rssBytes,
          'highWaterBytes': sample.highWaterBytes,
          'processes': [
            for (final usage in usages)
              {
                'pid': usage.pid,
                'rssBytes': usage.rssBytes,
                'highWaterBytes': usage.highWaterBytes,
              },
          ],
        }),
      );
      await sink.flush();
      if (!Directory('/proc/$rootPid').existsSync()) {
        vanished = true;
        if (options.exitWhenGone) break;
      }
    }
    if (options.durationMs != null &&
        DateTime.now().difference(startedAt).inMilliseconds >=
            options.durationMs!) {
      break;
    }
    await Future<void>.delayed(Duration(milliseconds: options.intervalMs));
  }
  await sink.flush();
  await sink.close();

  if (samples.isEmpty) {
    stdout.writeln(
      'rss_sampler: no samples were collected (process gone immediately)',
    );
  } else {
    final rss = [for (final sample in samples) sample.rssBytes];
    final highWater = [for (final sample in samples) sample.highWaterBytes];
    // 稳态用后半段样本的中位数；负载爬升体现在前半段，原始序列已完整保留，
    // 便于用别的定义重算。
    final steadyWindow = rss.sublist(rss.length ~/ 2);
    final summary = {
      'rootPid': rootPid,
      'rootCommand': rootCommand,
      'rootExecutable': rootExecutable,
      'intervalMs': options.intervalMs,
      'startedAtUnixMillis': DateTime.fromMillisecondsSinceEpoch(
        samples.first.atUnixMillis,
      ).toUtc().toIso8601String(),
      'endedAtUnixMillis': DateTime.fromMillisecondsSinceEpoch(
        samples.last.atUnixMillis,
      ).toUtc().toIso8601String(),
      'durationMs': samples.last.atUnixMillis - samples.first.atUnixMillis,
      'sampleCount': samples.length,
      'peakRssBytes': rss.reduce((a, b) => a > b ? a : b),
      'steadyRssBytes': _median(steadyWindow),
      'finalRssBytes': rss.last,
      'minRssBytes': rss.reduce((a, b) => a < b ? a : b),
      'p50RssBytes': _percentile(rss, 0.5),
      'p95RssBytes': _percentile(rss, 0.95),
      'maximumSummedHighWaterBytes': highWater.reduce((a, b) => a > b ? a : b),
      'summedHighWaterNote': 'sum of each process VmHWM over time; an upper bound of summed peaks, not a sampled instant',
      'steadyDefinition':
          'median of summed VmRSS over the second half of the samples',
      'measurementNote': 'Rust bridge and Flutter engine share this process; compare the same scenario only',
      'vanishedBeforeExit': vanished,
      'seriesFile': outputFile.path,
    };
    final encoded = '${const JsonEncoder.withIndent('  ').convert(summary)}\n';
    if (options.summary != null) {
      await File(options.summary!).writeAsString(encoded);
    }
    stdout.write(encoded);
  }
  exit(0);
}
