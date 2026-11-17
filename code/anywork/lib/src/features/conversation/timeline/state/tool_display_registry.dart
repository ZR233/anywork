import 'dart:convert';

/// 精确契约登记同时拥有匹配资格、行语义和正文策略，不按工具名称猜测。
enum ToolDisplayCategory {
  read,
  edit,
  create,
  delete,
  copy,
  move,
  command,
  stdin,
  search,
  fetch,
  agent,
  message,
  plan,
  planRead,
  workflow,
  workflowRead,
  lsp,
  image,
  wait,
  generic,
}

enum ToolDetailKind {
  standard,
  patch,
  lspQuery,
  lspCapabilities,
  lspStatus,
  web,
  image,
}

enum ToolInputBody { none, patch, fileContent }

/// 当前契约的正文编码；只有明确文本与 LSP 的非标准文本允许直接显示。
enum ToolOutputFormat { structured, text, lsp }

enum ToolAcceptance { pending, accepted, rejected }

final class ToolAcceptanceProjection {
  const ToolAcceptanceProjection(this.state, {this.code, this.reason});
  final ToolAcceptance state;
  final String? code;
  final String? reason;
}

enum ToolWebAction { search, open, find, other }

ToolWebAction timelineToolWebAction(String arguments) {
  try {
    return switch (_arguments(arguments)) {
      {'find': final List entries} when entries.isNotEmpty =>
        ToolWebAction.find,
      {'open': final List entries} when entries.isNotEmpty =>
        ToolWebAction.open,
      {'search_query': final List entries} when entries.isNotEmpty =>
        ToolWebAction.search,
      {'image_query': final List entries} when entries.isNotEmpty =>
        ToolWebAction.search,
      _ => ToolWebAction.other,
    };
  } on FormatException {
    return ToolWebAction.other;
  }
}

sealed class ToolDetailValue {
  const ToolDetailValue();
}

final class ToolDetailText extends ToolDetailValue {
  const ToolDetailText(this.title, this.text, {this.code = false});
  final String title;
  final String text;
  final bool code;
}

final class ToolDetailLink extends ToolDetailValue {
  const ToolDetailLink(this.title, this.url);
  final String title;
  final String url;
}

final class ToolDetailUnavailable extends ToolDetailValue {
  const ToolDetailUnavailable(this.reason);
  final String reason;
}

typedef ToolDetailDecoder = List<ToolDetailValue> Function(String text);
typedef ToolResultDecoder = List<ToolDetailValue> Function(Object? result);
typedef ToolAcceptanceDecoder = ToolAcceptanceProjection Function(
  Object? result,
);

final class ToolDisplaySpec {
  const ToolDisplaySpec(
    this.category, {
    this.kind = ToolDetailKind.standard,
    this.inputBody = ToolInputBody.none,
    this.input = _noDetails,
    this.output = _diagnosticResult,
    this.outputFormat = ToolOutputFormat.structured,
    this.artifacts = _noDetails,
    this.omitSuccessOutput = false,
    this.acceptanceDecoder,
    this.rejectionLabel = '操作未接纳',
    this.targetFields = const [],
    this.sessionNote = false,
    this.elapsed = false,
  });
  final ToolDisplayCategory category;
  final ToolDetailKind kind;
  final ToolInputBody inputBody;
  final ToolDetailDecoder input;
  final ToolResultDecoder output;
  final ToolOutputFormat outputFormat;
  final ToolDetailDecoder artifacts;
  final bool omitSuccessOutput;
  final ToolAcceptanceDecoder? acceptanceDecoder;
  final String rejectionLabel;
  final List<String> targetFields;
  final bool sessionNote;
  final bool elapsed;

  bool get isLsp => switch (kind) {
    ToolDetailKind.lspQuery ||
    ToolDetailKind.lspCapabilities ||
    ToolDetailKind.lspStatus => true,
    _ => false,
  };

  bool readsOutput(String status, {String output = ''}) =>
      !omitSuccessOutput ||
      status != 'succeeded' ||
      (requiresAcceptance &&
          decodeAcceptance(output).state != ToolAcceptance.accepted);

  bool get requiresAcceptance => acceptanceDecoder != null;

  ToolAcceptanceProjection decodeAcceptance(String text) {
    if (text.trim().isEmpty || acceptanceDecoder == null) {
      return const ToolAcceptanceProjection(ToolAcceptance.pending);
    }
    try {
      return acceptanceDecoder!(_structuredResult(text));
    } on FormatException {
      return const ToolAcceptanceProjection(ToolAcceptance.pending);
    }
  }

  bool outputRejected(String output) {
    return requiresAcceptance &&
        decodeAcceptance(output).state == ToolAcceptance.rejected;
  }

  List<ToolDetailValue> decodeInput(String text) => _decode(input, text);

  List<ToolDetailValue> acceptanceDetails(
    ToolAcceptanceProjection projection,
  ) => switch (projection.state) {
    ToolAcceptance.pending => const [
      ToolDetailUnavailable('接纳回执不可用：窗口不完整或格式错误'),
    ],
    ToolAcceptance.accepted => const [],
    ToolAcceptance.rejected => List.unmodifiable([
      ToolDetailText(
        rejectionLabel,
        projection.code ?? projection.reason ?? '操作未接纳',
      ),
      if (projection.code != null && projection.reason != null)
        ToolDetailText('原因', projection.reason!),
    ]),
  };
  List<ToolDetailValue> decodeOutput(String text) {
    if (text.trim().isEmpty) return const [];
    return _decode((text) {
      final result = switch (outputFormat) {
        ToolOutputFormat.structured => _structuredResult(text),
        ToolOutputFormat.text => text,
        ToolOutputFormat.lsp => _lspResult(text),
      };
      final projection = acceptanceDecoder?.call(result);
      return projection != null && projection.state != ToolAcceptance.pending
          ? acceptanceDetails(projection)
          : output(result);
    }, text);
  }

  static List<ToolDetailValue> _decode(ToolDetailDecoder decoder, String text) {
    try {
      return List.unmodifiable(decoder(text));
    } on FormatException catch (error) {
      return [ToolDetailUnavailable('工具内容格式错误：${error.message}')];
    } on RangeError {
      return const [ToolDetailUnavailable('工具内容格式错误：数值超出有效范围')];
    }
  }
}

const toolDisplayRegistry = <String, ToolDisplaySpec>{
  'generic@1': ToolDisplaySpec(
    ToolDisplayCategory.generic,
    output: _textResult,
    outputFormat: ToolOutputFormat.text,
  ),
  'builtin.exec@2': ToolDisplaySpec(
    ToolDisplayCategory.command,
    input: _command,
    output: _executionResult,
    targetFields: ['command'],
    elapsed: true,
  ),
  'builtin.write_stdin@1': ToolDisplaySpec(
    ToolDisplayCategory.stdin,
    input: _stdin,
    output: _executionResult,
  ),
  'builtin.read_session_note@1': ToolDisplaySpec(
    ToolDisplayCategory.read,
    output: _noteResult,
    sessionNote: true,
  ),
  'builtin.search_session_note@1': ToolDisplaySpec(
    ToolDisplayCategory.search,
    input: _query,
    output: _searchResult,
    targetFields: ['query'],
  ),
  'builtin.write_session_note@1': ToolDisplaySpec(
    ToolDisplayCategory.edit,
    input: _content,
    omitSuccessOutput: true,
    sessionNote: true,
  ),
  'builtin.apply_session_note_patch@1': ToolDisplaySpec(
    ToolDisplayCategory.edit,
    input: _notePatch,
    omitSuccessOutput: true,
    sessionNote: true,
  ),
  'builtin.stat_path@1': ToolDisplaySpec(
    ToolDisplayCategory.read,
    input: _path,
    output: _statResult,
    targetFields: ['path'],
  ),
  'builtin.write_file@1': ToolDisplaySpec(
    ToolDisplayCategory.edit,
    input: _file,
    inputBody: ToolInputBody.fileContent,
    omitSuccessOutput: true,
    targetFields: ['path'],
  ),
  'builtin.apply_patch@1': ToolDisplaySpec(
    ToolDisplayCategory.edit,
    kind: ToolDetailKind.patch,
    inputBody: ToolInputBody.patch,
    omitSuccessOutput: true,
  ),
  'builtin.create_directory@1': ToolDisplaySpec(
    ToolDisplayCategory.create,
    input: _path,
    omitSuccessOutput: true,
    targetFields: ['path'],
  ),
  'builtin.delete_path@1': ToolDisplaySpec(
    ToolDisplayCategory.delete,
    input: _delete,
    omitSuccessOutput: true,
    targetFields: ['path'],
  ),
  'builtin.copy_path@1': ToolDisplaySpec(
    ToolDisplayCategory.copy,
    input: _transfer,
    omitSuccessOutput: true,
    targetFields: ['from', 'to'],
  ),
  'builtin.move_path@1': ToolDisplaySpec(
    ToolDisplayCategory.move,
    input: _transfer,
    omitSuccessOutput: true,
    targetFields: ['from', 'to'],
  ),
  'builtin.spawn_agent@1': ToolDisplaySpec(
    ToolDisplayCategory.agent,
    input: _agent,
    output: _agentResult,
    targetFields: ['taskSummary'],
    omitSuccessOutput: true,
    acceptanceDecoder: _spawnAcceptance,
    rejectionLabel: '任务输入未接纳',
  ),
  'builtin.send_message@1': ToolDisplaySpec(
    ToolDisplayCategory.message,
    input: _message,
    output: _agentResult,
    omitSuccessOutput: true,
  ),
  'builtin.wait@1': ToolDisplaySpec(
    ToolDisplayCategory.wait,
    output: _waitResult,
  ),
  'builtin.sleep@1': ToolDisplaySpec(
    ToolDisplayCategory.wait,
    input: _sleep,
    output: _textResult,
    outputFormat: ToolOutputFormat.text,
    omitSuccessOutput: true,
  ),
  'builtin.view_image@1': ToolDisplaySpec(
    ToolDisplayCategory.image,
    kind: ToolDetailKind.image,
    input: _path,
    omitSuccessOutput: true,
    targetFields: ['path'],
  ),
  'builtin.show_files@1': ToolDisplaySpec(
    ToolDisplayCategory.image,
    input: _caption,
    output: _mediaResult,
  ),
  'builtin.lsp_query@1': ToolDisplaySpec(
    ToolDisplayCategory.lsp,
    kind: ToolDetailKind.lspQuery,
    outputFormat: ToolOutputFormat.lsp,
    targetFields: ['filePath', 'query', 'languageId'],
  ),
  'builtin.lsp_capabilities@1': ToolDisplaySpec(
    ToolDisplayCategory.lsp,
    kind: ToolDetailKind.lspCapabilities,
    outputFormat: ToolOutputFormat.lsp,
    targetFields: ['languageId'],
  ),
  'builtin.lsp_status@1': ToolDisplaySpec(
    ToolDisplayCategory.lsp,
    kind: ToolDetailKind.lspStatus,
    outputFormat: ToolOutputFormat.lsp,
  ),
  'builtin.plan_current@1': ToolDisplaySpec(
    ToolDisplayCategory.planRead,
    output: _planResult,
  ),
  'builtin.plan_next@1': ToolDisplaySpec(
    ToolDisplayCategory.planRead,
    output: _planResult,
  ),
  'builtin.plan_history@1': ToolDisplaySpec(
    ToolDisplayCategory.planRead,
    output: _planResult,
  ),
  'builtin.plan_submit@1': ToolDisplaySpec(
    ToolDisplayCategory.plan,
    input: _plan,
    output: _planResult,
  ),
  'builtin.plan_restart@1': ToolDisplaySpec(
    ToolDisplayCategory.plan,
    input: _reason,
    output: _planResult,
  ),
  'builtin.workflow_current@1': ToolDisplaySpec(
    ToolDisplayCategory.workflowRead,
    output: _workflowResult,
  ),
  'builtin.workflow_next@1': ToolDisplaySpec(
    ToolDisplayCategory.workflowRead,
    output: _workflowResult,
  ),
  'builtin.workflow_graph@1': ToolDisplaySpec(
    ToolDisplayCategory.workflowRead,
    output: _workflowResult,
  ),
  'builtin.workflow_history@1': ToolDisplaySpec(
    ToolDisplayCategory.workflowRead,
    output: _workflowResult,
  ),
  'builtin.workflow_transition@1': ToolDisplaySpec(
    ToolDisplayCategory.workflow,
    input: _workflowTransition,
    omitSuccessOutput: true,
    acceptanceDecoder: _workflowAcceptance,
    rejectionLabel: '工作流变更未接纳',
  ),
  'builtin.workflow_restart@1': ToolDisplaySpec(
    ToolDisplayCategory.workflow,
    input: _reason,
    omitSuccessOutput: true,
    acceptanceDecoder: _workflowAcceptance,
    rejectionLabel: '工作流变更未接纳',
  ),
  'builtin.web_search@1': ToolDisplaySpec(
    ToolDisplayCategory.search,
    kind: ToolDetailKind.web,
    input: _web,
    output: _textResult,
    outputFormat: ToolOutputFormat.text,
    artifacts: _webArtifacts,
  ),
  'builtin.deepseek_web_search@1': ToolDisplaySpec(
    ToolDisplayCategory.search,
    input: _queries,
    output: _textResult,
    outputFormat: ToolOutputFormat.text,
    artifacts: _webArtifacts,
  ),
  'builtin.deepseek_web_fetch@1': ToolDisplaySpec(
    ToolDisplayCategory.fetch,
    input: _url,
    output: _textResult,
    outputFormat: ToolOutputFormat.text,
    targetFields: ['url'],
  ),
};

List<ToolDetailValue> _noDetails(String _) => const [];
ToolAcceptanceProjection _workflowAcceptance(Object? result) =>
    switch (result) {
      {'accepted': true} => const ToolAcceptanceProjection(
        ToolAcceptance.accepted,
      ),
      {'accepted': false} && final Map<String, dynamic> rejected =>
        ToolAcceptanceProjection(
          ToolAcceptance.rejected,
          code: rejected['code'] is String ? rejected['code'] as String : null,
          reason: rejected['recoveryAction'] is String
              ? rejected['recoveryAction'] as String
              : null,
        ),
      _ => const ToolAcceptanceProjection(ToolAcceptance.pending),
    };

ToolAcceptanceProjection _spawnAcceptance(Object? result) => switch (result) {
  {'messageAccepted': true} => const ToolAcceptanceProjection(
    ToolAcceptance.accepted,
  ),
  {'messageAccepted': false} => const ToolAcceptanceProjection(
    ToolAcceptance.rejected,
    reason: '初始任务输入未接纳',
  ),
  _ => const ToolAcceptanceProjection(ToolAcceptance.pending),
};

Map<String, dynamic> _arguments(String text) => switch (jsonDecode(text)) {
  final Map<String, dynamic> value => value,
  _ => throw const FormatException('预期工具输入对象'),
};

List<ToolDetailValue> _field(
  Map<String, dynamic> data,
  String key,
  String title, {
  bool code = false,
  bool required = false,
}) {
  return switch (data[key]) {
    final String value when value.trim().isNotEmpty || key == 'content' => [
      ToolDetailText(title, value, code: code),
    ],
    null || '' when !required => const [],
    _ => throw FormatException('缺少或无效的$title'),
  };
}

List<ToolDetailValue> _command(String text) =>
    _field(_arguments(text), 'command', '程序', code: true, required: true);
List<ToolDetailValue> _stdin(String text) =>
    _field(_arguments(text), 'chars', '标准输入', code: true);
List<ToolDetailValue> _query(String text) =>
    _field(_arguments(text), 'query', '查询', required: true);
List<ToolDetailValue> _path(String text) =>
    _field(_arguments(text), 'path', '文件', required: true);
List<ToolDetailValue> _content(String text) =>
    _field(_arguments(text), 'content', '内容', code: true, required: true);
List<ToolDetailValue> _notePatch(String text) =>
    _field(_arguments(text), 'patch', '修改片段', code: true, required: true);
List<ToolDetailValue> _file(String text) {
  final data = _arguments(text);
  return [
    ..._field(data, 'path', '文件', required: true),
    ToolDetailText('写入方式', switch (data['mode']) {
      'create' => '新建文件',
      'overwrite' => '覆盖文件',
      'append' => '追加内容',
      _ => throw const FormatException('缺少或无效的写入方式'),
    }),
    ..._field(data, 'content', '内容', code: true, required: true),
  ];
}

List<ToolDetailValue> _transfer(String text) {
  return switch (_arguments(text)) {
    {
      'from': final String from,
      'to': final String to,
      'collision': final String collision,
    } =>
      [
        ToolDetailText('文件', '$from → $to'),
        ToolDetailText('目标已存在时', switch (collision) {
          'failIfExists' => '拒绝覆盖',
          'overwrite' => '覆盖',
          _ => throw const FormatException('无效的目标冲突处理方式'),
        }),
      ],
    _ => throw const FormatException('缺少来源或目标文件'),
  };
}

List<ToolDetailValue> _agent(String text) {
  final data = _arguments(text);
  return [
    ..._field(data, 'taskSummary', '任务', required: true),
    ..._field(data, 'profileId', '协作角色', required: true),
    ..._field(data, 'message', '任务说明', required: true),
  ];
}

List<ToolDetailValue> _delete(String text) {
  final data = _arguments(text);
  return [
    ..._field(data, 'path', '文件', required: true),
    ToolDetailText('删除对象', switch (data['mode']) {
      'file' => '文件',
      'emptyDirectory' => '空目录',
      'recursiveDirectory' => '目录及其内容',
      _ => throw const FormatException('缺少或无效的删除对象类型'),
    }),
  ];
}

List<ToolDetailValue> _message(String text) =>
    _field(_arguments(text), 'message', '消息');
List<ToolDetailValue> _caption(String text) =>
    _field(_arguments(text), 'caption', '说明');
List<ToolDetailValue> _reason(String text) =>
    _field(_arguments(text), 'reason', '原因');
List<ToolDetailValue> _workflowTransition(String text) =>
    switch (_arguments(text)) {
      {
        'completion': {
          'reason': final String reason,
          'summary': final String summary,
          'evidence': final List evidence,
        },
      } =>
        [
          ToolDetailText('原因', reason),
          ToolDetailText('阶段结果', summary),
          for (final record in evidence)
            switch (record) {
              final String value => ToolDetailText('依据', value),
              _ => throw const FormatException('无效的阶段完成依据'),
            },
        ],
      _ => const [ToolDetailUnavailable('缺少阶段完成说明')],
    };
List<ToolDetailValue> _plan(String text) {
  return _field(_arguments(text), 'plan', '计划内容', required: true);
}

List<ToolDetailValue> _sleep(String text) => switch (_arguments(text)) {
  {'durationMs': final num ms} => [ToolDetailText('等待', '${ms / 1000} 秒')],
  _ => throw const FormatException('缺少等待时长'),
};
List<ToolDetailValue> _queries(String text) => switch (_arguments(text)) {
  {'queries': final List queries} => [
    for (final query in queries)
      switch (query) {
        final String value => ToolDetailText('查询', value),
        _ => throw const FormatException('无效的搜索词'),
      },
  ],
  _ => throw const FormatException('缺少搜索词'),
};
List<ToolDetailValue> _url(String text) => switch (_arguments(text)) {
  {'url': final String url} => [ToolDetailLink('网页', url)],
  _ => throw const FormatException('缺少网页地址'),
};

List<ToolDetailValue> _web(String text) {
  final data = _arguments(text);
  final values = <ToolDetailValue>[];
  for (final MapEntry(:key, :value) in data.entries) {
    if (value is! List) continue;
    for (final command in value) {
      values.addAll(switch ((key, command)) {
        ('search_query' || 'image_query', {'q': final String query}) => [
          ToolDetailText('查询', query),
        ],
        ('open', {'ref_id': final String url}) => [ToolDetailLink('网页', url)],
        ('find', {'ref_id': final String url, 'pattern': final String query}) =>
          [ToolDetailLink('网页', url), ToolDetailText('查找', query)],
        ('weather', {'location': final String location}) => [
          ToolDetailText('天气', location),
        ],
        ('click', {'ref_id': final String ref, 'id': final int link}) => [
          ToolDetailText('打开页面链接', '$ref · 链接 $link'),
        ],
        ('finance', {'ticker': final String ticker}) => [
          ToolDetailText('行情', ticker),
        ],
        ('sports', {'league': final String league}) => [
          ToolDetailText('赛事', league),
        ],
        ('time', {'utc_offset': final String offset}) => [
          ToolDetailText('时区', offset),
        ],
        (
          'screenshot',
          {'ref_id': final String ref, 'pageno': final int page},
        ) =>
          [ToolDetailText('页面截图', '$ref · 第 ${page + 1} 页')],
        _ => throw const FormatException('无法识别的网页查询'),
      });
    }
  }
  return values.isEmpty ? [const ToolDetailUnavailable('未提供可展示的网页查询')] : values;
}

List<ToolDetailValue> _textResult(Object? result) => switch (result) {
  final String text when text.trim().isNotEmpty => [ToolDetailText('结果', text)],
  null || '' => const [],
  _ => throw const FormatException('预期文本结果'),
};

Object _structuredResult(String text) {
  Object? value;
  try {
    value = jsonDecode(text);
  } on FormatException {
    throw const FormatException('结构化结果不可用：窗口不完整或格式错误');
  }
  if (value is Map<String, dynamic> || value is List) return value!;
  throw const FormatException('结构化结果不可用：预期结果对象或列表');
}

Object? _lspResult(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}

List<ToolDetailValue> _webArtifacts(String text) {
  final links = <String>{};
  void collect(Object? value) {
    if (links.length >= 6) return;
    switch (value) {
      case final String url
          when const {'http', 'https'}.contains(Uri.tryParse(url)?.scheme):
        links.add(url);
      case final List entries:
        for (final entry in entries) {
          collect(entry);
        }
      case final Map<String, dynamic> object:
        for (final entry in object.values) {
          collect(entry);
        }
      default:
        break;
    }
  }

  try {
    collect(_structuredResult(text));
  } on FormatException {
    // 该字段也允许直接引用一个来源 URL，但不公开其它原始信封。
    if (const {'http', 'https'}.contains(Uri.tryParse(text)?.scheme)) {
      links.add(text);
    }
  }
  return List.unmodifiable([
    for (final url in links) ToolDetailLink('来源', url),
  ]);
}

String? _stream(Object? value) => switch (value) {
  null => null,
  final String text => text,
  {'content': final String text} => text,
  _ => throw const FormatException('程序输出流格式错误'),
};

List<ToolDetailValue> _executionResult(Object? value) {
  if (value is! Map<String, dynamic>) {
    return [const ToolDetailUnavailable('程序结果格式错误')];
  }
  final stdout = _stream(value['stdout']);
  final stderr = _stream(value['stderr']);
  return [
    if (stdout != null && stdout.isNotEmpty)
      ToolDetailText('标准输出', stdout, code: true),
    if (stderr != null && stderr.isNotEmpty)
      ToolDetailText('标准错误', stderr, code: true),
    ..._selectedResult(value, _diagnosticFields, unavailableWhenEmpty: false),
    if (value['inputReceipt'] case final Map<String, dynamic> receipt)
      ..._selectedResult(receipt, const {
        'acceptedBytes': '已接纳输入字节',
        'closeState': '输入关闭状态',
        'outcome': '输入结果',
        'detail': '输入诊断',
      }),
    if (value['exitCode'] case final int code) ToolDetailText('退出码', '$code'),
    if (value['signal'] case final Object signal)
      ToolDetailText('信号', '$signal'),
    if (value['timedOut'] == true) const ToolDetailText('状态', '已超时'),
  ];
}

List<ToolDetailValue> _selectedResult(
  Object? result,
  Map<String, String> fields, {
  bool unavailableWhenEmpty = true,
}) {
  if (result == null) return const [];
  if (result is String) return _textResult(result);
  if (result is List) {
    return [for (final entry in result) ..._selectedResult(entry, fields)];
  }
  if (result is! Map<String, dynamic>) {
    return const [ToolDetailUnavailable('结果内容格式错误')];
  }
  final values = <ToolDetailValue>[];
  for (final MapEntry(key: key, value: title) in fields.entries) {
    switch (result[key]) {
      case final String text when text.trim().isNotEmpty:
        values.add(
          key == 'url'
              ? ToolDetailLink(title, text)
              : ToolDetailText(title, text),
        );
      case final num number:
        values.add(ToolDetailText(title, '$number'));
      case final bool flag:
        values.add(ToolDetailText(title, flag ? '是' : '否'));
      case final List entries:
        if (entries.isEmpty) values.add(ToolDetailText(title, '无'));
        values.addAll([
          for (final entry in entries) ..._selectedResult(entry, fields),
        ]);
      case final Map<String, dynamic> nested:
        values.addAll(_selectedResult(nested, fields));
      case null:
        break;
      default:
        values.add(ToolDetailUnavailable('$title 的内容格式错误'));
    }
  }
  if (unavailableWhenEmpty && values.isEmpty && result.isNotEmpty) {
    values.add(const ToolDetailUnavailable('此结果没有可展示的语义内容'));
  }
  return values;
}

const _diagnosticFields = {
  'error': '错误',
  'message': '说明',
  'reason': '原因',
  'diagnostic': '诊断',
  'detail': '诊断说明',
  'code': '诊断代码',
};
List<ToolDetailValue> _diagnosticResult(Object? result) =>
    _project(result, const {});
List<ToolDetailValue> _project(Object? result, Map<String, String> fields) =>
    _selectedResult(result, {...fields, ..._diagnosticFields});
List<ToolDetailValue> _noteResult(Object? result) => _project(result, const {
  'startLine': '起始行',
  'endLine': '结束行',
  'content': '笔记',
  'text': '笔记',
  'lines': '笔记',
  'line': '行号',
});
List<ToolDetailValue> _searchResult(Object? result) => _project(result, const {
  'responses': '搜索结果',
  'response': '搜索结果',
  'output': '搜索结果',
  'preview': '搜索结果',
  'results': '搜索结果',
  'sources': '来源',
  'matches': '匹配',
  'items': '结果',
  'title': '标题',
  'url': '链接',
  'snippet': '摘要',
  'content': '内容',
  'text': '内容',
  'line': '行号',
  'column': '列号',
  'before': '前文',
  'after': '后文',
  'path': '文件',
  'markdown': '内容',
});
List<ToolDetailValue> _statResult(Object? result) {
  return switch (result) {
    {'exists': final bool exists} && final Map<String, dynamic> stat => [
      ToolDetailText('存在', exists ? '是' : '否'),
      if (stat['type'] case final String type) ToolDetailText('类型', type),
      if (stat['len'] case final int len) ToolDetailText('字节数', '$len'),
      if (stat['readonly'] case final bool readonly)
        ToolDetailText('只读', readonly ? '是' : '否'),
      if (stat['modifiedAt'] case final int modifiedAt)
        ToolDetailText(
          '修改时间',
          DateTime.fromMillisecondsSinceEpoch(modifiedAt).toLocal().toString(),
        ),
    ],
    final Map<String, dynamic> diagnostic => _selectedResult(
      diagnostic,
      _diagnosticFields,
    ),
    _ => const [ToolDetailUnavailable('文件元数据格式错误')],
  };
}

List<ToolDetailValue> _agentResult(Object? result) => _project(result, const {
  'messageAccepted': '任务输入已接纳',
  'status': '状态',
  'state': '状态',
  'report': '汇报',
  'text': '内容',
  'summary': '摘要',
});
List<ToolDetailValue> _waitResult(Object? result) => _project(result, const {
  'tasks': '任务状态',
  'timedOut': '等待超时',
  'messagesReady': '消息已就绪',
  'status': '状态',
  'state': '状态',
});
List<ToolDetailValue> _mediaResult(Object? result) => _project(result, const {
  'caption': '说明',
  'files': '文件',
  'filename': '文件',
  'outcome': '结果',
  'status': '状态',
});
List<ToolDetailValue> _planResult(Object? result) => _project(result, const {
  'state': '计划阶段',
  'document': '计划',
  'markdown': '计划内容',
  'lastRevisionFeedback': '修订反馈',
  'allowedTransitions': '可用操作',
  'transitions': '可用操作',
  'operation': '操作',
  'targetState': '目标阶段',
  'condition': '条件',
  'action': '行动',
  'history': '历史',
  'snapshot': '当前计划',
});
List<ToolDetailValue> _workflowResult(Object? result) {
  if (result case {'currentRun': null}) {
    return const [ToolDetailText('工作流', '尚未开始')];
  }
  return _selectedResult(result, const {
    'title': '工作流',
    'goal': '目标',
    'currentState': '当前阶段',
    'instructions': '阶段说明',
    'completionCriteria': '完成条件',
    'lifecycle': '状态',
    'transitions': '可用转换',
    'guard': '转换条件',
    'history': '历史',
    'summary': '阶段结果',
    'evidence': '依据',
    'definition': '工作流',
    'states': '阶段',
    ..._diagnosticFields,
  });
}
