(() => {
  'use strict';
  const app = window.AnyworkConversation = window.AnyworkConversation || {};
  const text = [
    '已经把会话内容拆成两个清楚的区域：**上方阅读历史，下方关注当前执行**。',
    '',
    '### 这轮细化',
    '- 历史保留完整文本和完整工作组，耗时与结果固定。',
    '- 工具可以并行执行，在同一个工作组内查看进展。',
    '- 所有结束的内容都可以展开、选择与复制。',
    '',
    '```dart',
    'final history = completedItems;',
    'final current = activeWorkGroup ?? streamingText ?? compacting;',
    '```',
    '',
    '| 内容 | 何时进入历史 |',
    '| --- | --- |',
    '| 文本输出 | 当前这段输出结束 |',
    '| 思考工作组 | 整组结束 |',
    '| 上下文压缩 | 压缩成功 |',
    '',
    '> 你可以在输出期间向上阅读，新的内容不会抢走阅读位置。',
    '',
    '接下来可以继续细化工具详情，或者在输入框里补充你的要求。'
  ].join('\n');

  function group(id = 'group-active', terminal = false) {
    return {
      id, kind: 'workGroup', status: terminal ? 'completed' : 'running', elapsed: terminal ? 18 : 12,
      summary: '核对交互细节，补齐状态切换与历史回执',
      members: [
        { id: id + '-thinking', kind: 'thinking', title: '梳理历史与当前执行的边界', status: 'completed', elapsed: 3,
          content: '先固定**完整工作组**的边界，再检查并行工具和用户交互。组内工具先完成时不拆组，整组结束后一起成为历史。' },
        { id: id + '-read', kind: 'read', title: '读取文件', target: 'timeline_view.dart', status: 'completed', elapsed: 1,
          path: 'code/anywork/lib/src/features/timeline/timeline_view.dart',
          content: '已读取时间线、实时活动栏与输入区的组合结构。\n阅读列共用中心轴；历史与当前执行分别持有滚动区域。' },
        { id: id + '-command', kind: 'command', title: '执行命令', target: 'cargo test -p pl-core --features sqlite',
          status: terminal ? 'completed' : 'running', elapsed: terminal ? 8 : 5,
          cwd: '~/work/anywork', exitCode: terminal ? 0 : null,
          output: 'Compiling pl-core\nrunning 24 tests\ntest completed_group_enters_history ... ok\ntest streaming_text_stays_in_live_area ... ok' + (terminal ? '\ntest result: ok. 24 passed; 0 failed\nProcess exited with code 0' : '') },
        { id: id + '-search', kind: 'search', title: '搜索交互约定', target: '历史阅读 · 实时输出', status: 'completed', elapsed: 2,
          queries: ['完整工作组何时进入历史', '手动阅读时暂停跟随输出'],
          results: [
            { title: 'HTML details：原生折叠', description: '使用标准 summary 和 details 展开过程与结果。', url: 'https://developer.mozilla.org/zh-CN/docs/Web/HTML/Element/details' },
            { title: 'HTML dialog：对话框与焦点', description: '详情按需打开，关闭后返回原触发位置。', url: 'https://developer.mozilla.org/zh-CN/docs/Web/HTML/Element/dialog' }
          ] },
        { id: id + '-edit', kind: 'edit', title: '修改文件', target: 'conversation_activity_bar.dart', status: 'completed', elapsed: 2,
          path: 'code/anywork/lib/src/features/timeline/conversation_activity_bar.dart',
          files: [
            { name: 'conversation_activity_bar.dart', added: 12, removed: 4,
              diff: '@@ 当前执行与历史分离 @@\n- renderTimeline(activeItems);\n+ renderTimeline(completedItems);\n+ renderLiveStatus(currentActivity);\n \n+ onWorkGroupCompleted(appendHistory);' },
            { name: 'timeline_view.dart', added: 6, removed: 2,
              diff: '@@ 历史阅读 @@\n- scrollToBottomOnEveryUpdate();\n+ if (followingLatest) scrollToLatest();\n+ else showNewHistoryCount();' }
          ] },
        { id: id + '-wait', kind: 'wait', title: '等待子智能体', target: 'explorer · reviewer',
          status: terminal ? 'completed' : 'running', elapsed: terminal ? 7 : 4,
          rule: '等待两个成员都返回结果',
          targets: [
            { name: 'explorer', task: '交互边界核对', status: 'completed', report: '已确认历史只接收封口后的完整内容。' },
            { name: 'reviewer', task: '细节与可读性检查', status: terminal ? 'completed' : 'running', report: terminal ? '完成工具详情与窄窗口检查。' : '正在检查长内容与滚动反馈。' }
          ] }
      ]
    };
  }

  function history() {
    const old = group('group-history', true);
    old.summary = '确认时间线与当前执行的职责';
    return [
      { id: 'message-user-1', kind: 'user', text: '细化 timeline 和实时状态栏，历史只放已经确定的内容，整体风格保持现在这样。', time: '14:32' },
      old,
      { id: 'message-assistant-1', kind: 'text', status: 'completed', time: '14:34',
        text: '我会先整理历史阅读与当前执行的层级。\n\n历史中的正文直接铺开，过程默认折叠；正在发生的内容统一留在输入框上方。' },
      { id: 'compression-history', kind: 'compression', status: 'completed', time: '14:35' },
      { id: 'message-user-2', kind: 'user', text: '把主要操作逻辑体现完整，同样的结构尽量模块化复用。', time: '14:36' }
    ];
  }

  const questions = {
    id: 'questions', kind: 'questions', title: '确认两个阅读偏好', index: 0,
    questions: [
      { title: '工作组默认如何展示？', description: '决定历史阅读时的初始密度。', multiple: false,
        options: ['默认折叠，按需展开', '默认展开全部过程'] },
      { title: '重点检查哪些场景？', description: '可以多选，也可以补充自己的要求。', multiple: true,
        options: ['长文本与代码', '并行工具与等待', '停止与继续'], secret: true }
    ],
    answers: [[], []], others: ['', ''], secret: ''
  };
  const scenarios = [
    { id: 'workgroup', label: '活跃工作组', hint: '组内有已完成与进行中的工具。整组结束后才进入历史。', live: 'workGroup' },
    { id: 'thinking', label: '思考中', hint: '尚无工作信息或正文，只显示不可展开的「思考中」。收到信息后切换到工作组。', waiting: true },
    { id: 'after-text', label: '文本结束后等待', hint: '完整正文已进入历史，轮次尚未结束。等待模型响应时显示不可展开的「思考中」。', waiting: true, afterText: true },
    { id: 'text', label: '实时文本', hint: '正文结束后整段进入历史；轮次仍在等待响应时，实时区切换为「思考中」。', live: 'textOutput' },
    { id: 'compacting', label: '正在压缩', hint: '成功后，历史追加一行「已完成压缩」。', live: 'compacting' },
    { id: 'questions', label: '等待回答', hint: '待处理问题在停靠区，回答后变成只读回执。', pending: questions },
    { id: 'stopped', label: '已停止', hint: '停止记录以折叠行保留在历史中，输入区原主按钮切换为继续图标。', outcome: 'stopped' },
    { id: 'failed', label: '执行失败', hint: '失败原因在历史元素中按需展开，仍可通过原主按钮继续。', outcome: 'failed' },
    { id: 'idle', label: '历史阅读', hint: '展开历史过程、复制正文，或开始下一轮。' },
    { id: 'empty', label: '空会话', hint: '输入第一条消息，开始完整演示。', empty: true }
  ];

  // This is a repeatable, local-only task story, shared by every entry page.
  function textEvents(offset = 0) {
    return Array.from({ length: Math.ceil((text.length - offset) / 32) }, (_, index) =>
      ({ type: 'appendText', text: text.slice(offset + index * 32, offset + (index + 1) * 32) }));
  }

  function responseEvents(waitId, offset = 0) {
    return [
      ...textEvents(offset),
      { type: 'finishText' },
      { type: 'waitForModel', id: waitId },
      { type: 'tick' }, { type: 'tick' },
      { type: 'finishTurn' }
    ];
  }

  function story(id) {
    const active = group(id);
    active.elapsed = 1;
    active.members.forEach(member => { member.status = 'running'; member.elapsed = 0; });
    const complete = active.members.map(member => ({ type: 'memberDone', id: member.id }));
    return [
      { type: 'waitForModel', id },
      { type: 'tick' }, { type: 'tick' },
      { type: 'startGroup', group: active },
      { type: 'memberDone', id: id + '-thinking' },
      { type: 'memberDone', id: id + '-read' },
      { type: 'appendCommand', line: 'test history_is_immutable ... ok' },
      { type: 'memberDone', id: id + '-search' },
      { type: 'memberDone', id: id + '-edit' },
      ...complete,
      { type: 'finishGroup' },
      { type: 'startText', id: id + '-text' },
      { type: 'tick' },
      ...responseEvents(id + '-after-text')
    ];
  }

  app.fixtures = { text, group, history, questions, scenarios, textEvents, responseEvents, story };
})();
