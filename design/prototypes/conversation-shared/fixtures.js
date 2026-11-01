(() => {
  'use strict';
  const app = window.AnyworkConversation = window.AnyworkConversation || {};
  const text = [
    '已经把会话内容拆成两个清楚的区域：**上方时间线只放已结束的内容，下方状态栏承载正在进行的工作组**。',
    '',
    '### 这轮细化',
    '- 新工作组先在状态栏中逐个插入成员，完成的成员打勾后留在组内。',
    '- 出现正文、提问或轮次结束等需要新分组的信息时，整组一次移入时间线。',
    '- 时间线里的内容不再变化，可以展开、选择与复制。',
    '',
    '```dart',
    'final timeline = finishedItems;',
    'final statusBar = activeGroup ?? streamingText ?? compacting;',
    '```',
    '',
    '| 内容 | 何时进入时间线 |',
    '| --- | --- |',
    '| 工作组 | 出现需要新分组的信息 |',
    '| 文本输出 | 这段正文结束 |',
    '| 上下文压缩 | 压缩成功 |',
    '',
    '> 你可以在输出期间向上阅读，新的内容不会抢走阅读位置。',
    '',
    '接下来我会再跑一次静态检查，确认分组边界没有遗漏。'
  ].join('\n');
  const closingText = '检查通过，没有新的问题。\n\n状态栏现在只承载**当前工作组**；时间线里的每一项都已结束。';

  function members(id, terminal) {
    const status = terminal ? 'completed' : 'running';
    return [
      { id: id + '-thinking', kind: 'thinking', title: '梳理时间线与状态栏的边界', status: 'completed', elapsed: 3,
        content: '已完成的成员**留在状态栏的当前工作组**。出现正文、提问或轮次结束等新分组信息时，整组一次移入时间线。' },
      { id: id + '-read', kind: 'read', title: '读取文件', target: 'timeline_view.dart', status: 'completed', elapsed: 1,
        path: 'code/anywork/lib/src/features/timeline/timeline_view.dart',
        content: '已读取时间线、状态栏与输入区的组合结构。\n阅读列共用中心轴；时间线与状态栏分别持有滚动区域。' },
      { id: id + '-command', kind: 'command', title: '执行命令', target: 'cargo test -p pl-core --features sqlite',
        status, elapsed: terminal ? 8 : 5, cwd: '~/work/anywork', exitCode: terminal ? 0 : null,
        output: 'Compiling pl-core\nrunning 24 tests\ntest finished_group_enters_timeline ... ok\ntest streaming_text_stays_in_status_bar ... ok' + (terminal ? '\ntest result: ok. 24 passed; 0 failed\nProcess exited with code 0' : '') },
      { id: id + '-search', kind: 'search', title: '搜索交互约定', target: '时间线阅读 · 状态栏', status: 'completed', elapsed: 2,
        queries: ['工作组何时整组进入时间线', '手动阅读时暂停跟随输出'],
        results: [
          { title: 'HTML details：原生折叠', description: '使用标准 summary 和 details 展开过程与结果。', url: 'https://developer.mozilla.org/zh-CN/docs/Web/HTML/Element/details' },
          { title: 'HTML dialog：对话框与焦点', description: '详情按需打开，关闭后返回原触发位置。', url: 'https://developer.mozilla.org/zh-CN/docs/Web/HTML/Element/dialog' }
        ] },
      { id: id + '-edit', kind: 'edit', title: '修改文件', target: 'conversation_activity_bar.dart', status: 'completed', elapsed: 2,
        path: 'code/anywork/lib/src/features/timeline/conversation_activity_bar.dart',
        files: [
          { name: 'conversation_activity_bar.dart', added: 12, removed: 4,
            diff: '@@ 状态栏承载当前工作组 @@\n- renderTimeline(activeItems);\n+ renderTimeline(finishedItems);\n+ renderStatusBar(activeGroup);\n \n+ onGroupBoundary(moveGroupToTimeline);' },
          { name: 'timeline_view.dart', added: 6, removed: 2,
            diff: '@@ 时间线阅读 @@\n- scrollToBottomOnEveryUpdate();\n+ if (followingLatest) scrollToLatest();\n+ else showNewTimelineCount();' }
        ] },
      { id: id + '-wait', kind: 'wait', title: '等待子智能体', target: 'explorer · reviewer',
        status, elapsed: terminal ? 7 : 4, rule: '等待两个成员都返回结果',
        targets: [
          { name: 'explorer', task: '交互边界核对', status: 'completed', report: '已确认时间线只接收整组结束的工作组。' },
          { name: 'reviewer', task: '细节与可读性检查', status, report: terminal ? '完成工具详情与窄窗口检查。' : '正在检查长内容与滚动反馈。' }
        ] }
    ];
  }

  function group(id = 'group-active', terminal = false) {
    return { id, kind: 'workGroup', status: terminal ? 'completed' : 'running', elapsed: terminal ? 18 : 12, members: members(id, terminal) };
  }

  function followUpMembers(id) {
    return [
      { id: id + '-thinking', kind: 'thinking', title: '确认收尾检查', status: 'running', elapsed: 0,
        content: '正文已经结束，这是新的工作组：先在状态栏插入成员，等下一段正文出现时再整组进入时间线。' },
      { id: id + '-command', kind: 'command', title: '执行命令', target: 'cargo flutter analyze', status: 'running', elapsed: 0,
        cwd: '~/work/anywork', exitCode: null, output: 'Analyzing anywork...' }
    ];
  }

  function history() {
    const old = group('group-history', true);
    old.members = old.members.slice(0, 3);
    return [
      { id: 'message-user-1', kind: 'user', text: '细化 timeline 和实时状态栏，时间线只放已经结束的内容，整体风格保持现在这样。', time: '14:32' },
      old,
      { id: 'message-assistant-1', kind: 'text', status: 'completed', time: '14:34',
        text: '我会先整理时间线与状态栏的层级。\n\n时间线中的正文直接铺开，过程默认折叠；正在进行的工作组统一留在输入框上方。' },
      { id: 'compression-history', kind: 'compression', status: 'completed', time: '14:35' },
      { id: 'message-user-2', kind: 'user', text: '把主要操作逻辑体现完整，同样的结构尽量模块化复用。', time: '14:36' }
    ];
  }

  const questions = {
    id: 'questions', kind: 'questions', title: '确认两个阅读偏好', index: 0,
    questions: [
      { title: '工作组默认如何展示？', description: '决定时间线阅读时的初始密度。', multiple: false,
        options: ['默认折叠，按需展开', '默认展开全部过程'] },
      { title: '重点检查哪些场景？', description: '可以多选，也可以补充自己的要求。', multiple: true,
        options: ['长文本与代码', '并行工具与等待', '停止与继续'], secret: true }
    ],
    answers: [[], []], others: ['', ''], secret: ''
  };

  // Live scenarios are frames of the same story; `at` names the event the frame stops after.
  const scenarios = [
    { id: 'thinking', label: '思考中', at: 'thinking',
      hint: '新轮次尚无任何信息，状态栏只显示不可展开的「思考中」与耗时；不生成空工作组。' },
    { id: 'workgroup', label: '工作组进行中', at: 'workgroup',
      hint: '当前工作组位于状态栏：成员逐个插入，完成的打勾留在组内，运行中的继续计时。时间线不出现半成品。' },
    { id: 'group-idle', label: '工作组待交接', at: 'group-idle',
      hint: '成员已全部完成，工作组仍留在状态栏并显示「思考中」。下一条是工具则继续插入本组；是正文、提问或轮次结束则整组移入时间线。' },
    { id: 'text', label: '实时文本', at: 'text',
      hint: '正文开始的一刻，上一工作组已整组移入时间线。正文结束后整段进入时间线。' },
    { id: 'after-text', label: '文本结束后等待', at: 'after-text',
      hint: '完整正文已进入时间线，轮次尚未结束，状态栏显示「思考中」。之后的工具会在状态栏开启新工作组。' },
    { id: 'next-group', label: '新工作组', at: 'next-group',
      hint: '上一组已在时间线中结束；新工作组先在状态栏插入，不会接到时间线里的旧组后面。' },
    { id: 'compacting', label: '正在压缩', live: 'compacting', hint: '单行展示；成功后时间线追加一行「已完成压缩」。' },
    { id: 'questions', label: '等待回答', pending: questions,
      hint: '提问是新分组信息：此前的工作组已整组移入时间线，待处理问题在停靠区，回答后成为只读回执。' },
    { id: 'receipts', label: '问答回执',
      hint: '问题回答或跳过后，在时间线中形成默认折叠的只读回执；敏感回答保持隐藏。' },
    { id: 'stopped', label: '已停止', outcome: 'stopped', hint: '工作组连同未完成成员一起结束并移入时间线，另附折叠的停止记录；主按钮切换为继续。' },
    { id: 'failed', label: '执行失败', outcome: 'failed', hint: '失败成员在组内标记，原因在独立的失败记录中按需展开；仍可通过主按钮继续。' },
    { id: 'idle', label: '时间线阅读', hint: '状态栏收起。展开时间线中的过程、复制正文，或开始下一轮。' },
    { id: 'empty', label: '空会话', hint: '输入第一条消息，开始完整演示。', empty: true }
  ];

  function textEvents(source, label) {
    return Array.from({ length: Math.ceil(source.length / 32) }, (_, index) => ({
      type: 'appendText', text: source.slice(index * 32, (index + 1) * 32), ...(index === 4 && label ? { label } : {})
    }));
  }

  // This is a repeatable, local-only task story, shared by every entry page.
  function story(id) {
    const first = members(id, false).map(member => ({ ...member, status: 'running', elapsed: 0 }));
    first.find(member => member.kind === 'wait').targets[0].status = 'running';
    const add = member => ({ type: 'addMember', groupId: id, member });
    const done = name => ({ type: 'memberDone', id: id + '-' + name });
    const next = id + '-next';
    const [nextThinking, nextCommand] = followUpMembers(next);
    return [
      { type: 'waitForModel', id, label: 'thinking' },
      { type: 'tick' },
      add(first[0]), done('thinking'),
      add(first[1]), done('read'),
      add(first[2]), add(first[3]),
      { type: 'appendCommand', line: 'test history_is_immutable ... ok' },
      done('search'),
      add(first[4]), done('edit'),
      add(first[5]),
      { type: 'appendCommand', line: 'test group_moves_as_a_whole ... ok', label: 'workgroup' },
      done('command'), done('wait'),
      { type: 'tick', label: 'group-idle' }, { type: 'tick' },
      { type: 'startText', id: id + '-text' },
      ...textEvents(text, 'text'),
      { type: 'finishText' },
      { type: 'waitForModel', id: next, label: 'after-text' },
      { type: 'tick' },
      { type: 'addMember', groupId: next, member: nextThinking },
      { type: 'memberDone', id: nextThinking.id },
      { type: 'addMember', groupId: next, member: nextCommand, label: 'next-group' },
      { type: 'appendCommand', line: 'No issues found! (ran in 3.2s)' },
      { type: 'memberDone', id: nextCommand.id },
      { type: 'tick' },
      { type: 'startText', id: next + '-text' },
      ...textEvents(closingText),
      { type: 'finishText' },
      { type: 'finishTurn' }
    ];
  }

  app.fixtures = { text, group, history, questions, scenarios, story };
})();
