(() => {
  'use strict';
  const app = window.AnyworkConversation;
  const clone = value => structuredClone(value);
  const isWaitingForModel = live => live?.kind === 'workGroup'
    ? !live.summary.trim() && live.members.length === 0
    : live?.kind === 'textOutput' && !live.text.trim();
  function freeze(value) {
    if (value && typeof value === 'object') {
      Object.values(value).forEach(freeze);
      Object.freeze(value);
    }
    return value;
  }

  class ConversationController extends EventTarget {
    constructor(scenario = 'workgroup') {
      super();
      this.sequence = 0;
      this.timer = null;
      this.urls = new Set();
      this.disposed = false;
      this.load(scenario);
    }

    id(prefix) { return prefix + '-' + (++this.sequence); }
    emit(reason) {
      if (!this.disposed) this.dispatchEvent(new CustomEvent('change', { detail: { reason } }));
    }
    snapshot(item) {
      if (this.state.history.some(existing => existing.id === item.id)) return;
      this.state.history = [...this.state.history, freeze(clone(item))];
    }
    completeMember(group, member) {
      if (this.state.history.some(item => item.members?.some(existing => existing.id === member.id))) return;
      const tail = this.state.history.at(-1);
      const frozenMember = freeze(clone(member));
      // This is a replaceable browser presentation group, never a completion boundary.
      if (tail?.kind === 'workGroup' && tail.sourceId === group.id) {
        this.state.history = [
          ...this.state.history.slice(0, -1),
          freeze({ ...tail, members: [...tail.members, frozenMember] })
        ];
      } else {
        this.snapshot({
          id: member.id, sourceId: group.id, kind: 'workGroup', status: 'completed',
          summary: group.summary, elapsed: member.elapsed, members: [frozenMember]
        });
      }
    }
    publishCompletedMembers(group) {
      group.members.filter(member => member.status !== 'running')
        .forEach(member => this.completeMember(group, member));
      group.members = group.members.filter(member => member.status === 'running');
    }
    recordOutcome(live, status, error = '') {
      this.snapshot({
        id: live.id + '-outcome', kind: 'outcome', status, sourceId: live.id,
        subject: isWaitingForModel(live) ? '模型响应'
          : live.kind === 'workGroup' ? live.summary : live.kind === 'textOutput' ? '文本输出' : '上下文压缩',
        error
      });
    }
    halt() {
      clearInterval(this.timer);
      this.timer = null;
      if (this.state) this.state.playing = false;
    }
    textSteps(offset = 0) {
      return app.fixtures.responseEvents(this.id('group'), offset);
    }
    afterGroup(id) {
      return [{ type: 'finishGroup' }, { type: 'startText', id }, { type: 'tick' }, ...this.textSteps()];
    }

    load(scenario) {
      this.halt();
      this.urls.forEach(url => URL.revokeObjectURL(url));
      this.urls.clear();
      const spec = app.fixtures.scenarios.find(item => item.id === scenario);
      if (!spec && scenario !== 'question-last' && scenario !== 'receipts') throw new Error('Unknown scenario: ' + scenario);
      this.state = {
        scenario, history: [], live: null, pending: null, draft: '', attachments: [],
        context: 42, playing: false, running: false, resumable: false, retryCompression: false,
        queue: [], cursor: 0
      };
      if (!spec?.empty) app.fixtures.history().forEach(item => this.snapshot(item));
      const id = this.id('group');
      if (spec?.waiting) {
        if (spec.afterText) this.snapshot({ id: this.id('text'), kind: 'text', status: 'completed', text: app.fixtures.text });
        this.state.queue = app.fixtures.story(id);
        this.apply(this.state.queue[this.state.cursor++]);
      } else if (spec?.live === 'workGroup') {
        this.state.live = app.fixtures.group(id);
        this.publishCompletedMembers(this.state.live);
        this.state.queue = [
          { type: 'appendCommand', line: 'test each_completed_fact_is_published_immediately ... ok' },
          ...this.state.live.members.filter(item => item.status === 'running').map(item => ({ type: 'memberDone', id: item.id })),
          ...this.afterGroup(this.id('text'))
        ];
      } else if (spec?.live === 'textOutput') {
        this.state.live = { id: this.id('text'), kind: 'textOutput', text: app.fixtures.text.slice(0, 160), elapsed: 4 };
        this.state.queue = this.textSteps(160);
      } else if (spec?.live === 'compacting') {
        this.startCompression();
      } else if (spec?.pending || scenario === 'question-last') {
        this.state.pending = clone(spec?.pending || app.fixtures.questions);
        this.state.pending.id = this.id('interaction');
        if (scenario === 'question-last') {
          this.state.pending.index = 1;
          this.state.pending.answers[0] = ['默认折叠，按需展开'];
        }
        const active = app.fixtures.group(id);
        active.summary = '等待你确认阅读偏好';
        active.members = [active.members[0], {
          id: id + '-input', kind: 'wait', title: '等待用户', target: '你的决定',
          status: 'running', elapsed: 2, rule: '收到决定后继续', targets: []
        }];
        this.state.live = active;
      } else if (spec?.outcome) {
        const old = app.fixtures.group(id);
        old.status = spec.outcome;
        old.error = spec.outcome === 'failed' ? '命令退出码 1：示例断言未通过。已保留全部输出。' : '';
        old.members.forEach(item => {
          if (item.status === 'running') item.status = spec.outcome === 'failed' && item.kind === 'command' ? 'failed' : 'stopped';
        });
        const command = old.members.find(item => item.kind === 'command');
        command.output += '\n' + (old.error || 'Process interrupted by user');
        if (spec.outcome === 'failed') command.exitCode = 1;
        this.snapshot(old);
        this.recordOutcome(old, spec.outcome, old.error);
        this.state.resumable = true;
      } else if (scenario === 'receipts') {
        this.snapshot({ id: this.id('receipt'), kind: 'receipt', type: 'questions', title: '用户已回答',
          subtitle: '2 个问题', content: '### 工作组默认如何展示？\n默认折叠，按需展开\n\n### 重点检查哪些场景？\n长文本与代码、停止与继续\n\n敏感回答已隐藏' });
      }
      this.state.running = Boolean(this.state.live);
      this.emit('reset');
    }

    startCompression() {
      this.state.live = { id: this.id('compression'), kind: 'compacting', elapsed: 0 };
      this.state.queue = [{ type: 'tick' }, { type: 'tick' }, { type: 'finishCompression' }, { type: 'finishTurn' }];
      this.state.cursor = 0;
      this.state.running = true;
    }
    compact() {
      if (this.state.live || !this.state.history.length) return;
      this.state.resumable = false;
      this.state.retryCompression = false;
      this.startCompression();
      this.emit('live');
      this.play();
    }
    seal(status = 'completed', error = '') {
      const live = this.state.live;
      if (!live) return;
      if (live.kind === 'workGroup') {
        live.status = status;
        live.error = error;
        live.members.forEach(member => {
          if (member.status === 'running') member.status = status === 'completed' ? 'completed' : 'stopped';
        });
        this.publishCompletedMembers(live);
      } else if (live.kind === 'textOutput') {
        if (live.text.trim()) this.snapshot({ ...live, kind: 'text', status, error });
      } else if (status === 'completed') {
        this.snapshot({ id: live.id, kind: 'compression', status: 'completed' });
        this.state.context = 18;
      }
      this.state.live = null;
      return live;
    }

    apply(event) {
      const live = this.state.live;
      switch (event.type) {
        case 'tick': break;
        case 'waitForModel':
          if (live) throw new Error('A live item must be sealed before waiting for the model');
          this.state.live = { id: event.id, kind: 'workGroup', status: 'running', summary: '', members: [], elapsed: 0 };
          this.state.running = true;
          break;
        case 'startGroup':
          if (live && !(live.kind === 'workGroup' && live.id === event.group.id && isWaitingForModel(live))) {
            throw new Error('A live item must be sealed before starting a work group');
          }
          this.state.live = clone(event.group);
          this.state.live.elapsed = Math.max(this.state.live.elapsed, live?.elapsed || 0);
          this.publishCompletedMembers(this.state.live);
          this.state.running = true;
          break;
        case 'memberDone':
          if (live?.kind === 'workGroup') {
            const member = live.members.find(item => item.id === event.id);
            if (member && member.status === 'running') {
              member.status = 'completed';
              if (member.kind === 'command') {
                member.exitCode = 0;
                member.output += '\ntest result: ok. 24 passed; 0 failed\nProcess exited with code 0';
              }
              member.targets?.forEach(target => { target.status = 'completed'; target.report = '核对已完成，结果已返回。'; });
              this.publishCompletedMembers(live);
            }
          }
          break;
        case 'appendCommand':
          if (live?.kind === 'workGroup') {
            const command = live.members.find(item => item.kind === 'command' && item.status === 'running');
            if (command) command.output += '\n' + event.line;
          }
          break;
        case 'finishGroup':
          if (live?.kind === 'workGroup' && live.members.every(member => member.status !== 'running')) this.seal();
          break;
        case 'startText':
          if (live) throw new Error('A live item must be sealed before starting text output');
          this.state.live = { id: event.id, kind: 'textOutput', text: '', elapsed: 0 };
          this.state.running = true;
          break;
        case 'appendText':
          if (live?.kind === 'textOutput') live.text += event.text;
          break;
        case 'finishText':
          if (live?.kind === 'textOutput') this.seal();
          break;
        case 'finishCompression':
          if (live?.kind === 'compacting' && (!event.id || event.id === live.id)) this.seal();
          break;
        case 'finishTurn':
          if (isWaitingForModel(live)) this.seal();
          if (!this.state.live) {
            this.state.running = false;
            this.state.resumable = false;
            this.state.retryCompression = false;
            this.halt();
          }
          break;
        default: throw new Error('Unknown demo event: ' + event.type);
      }
    }

    step() {
      if (this.disposed || this.state.pending) return;
      const event = this.state.queue[this.state.cursor];
      if (!event) { this.halt(); this.emit('playback'); return; }
      const live = this.state.live;
      if (live) {
        live.elapsed++;
        live.members?.forEach(member => { if (member.status === 'running') member.elapsed++; });
      }
      this.state.cursor++;
      this.apply(event);
      while (!this.state.live && ['waitForModel', 'startText', 'startGroup', 'finishTurn'].includes(this.state.queue[this.state.cursor]?.type)) {
        this.apply(this.state.queue[this.state.cursor++]);
      }
      if (this.state.cursor >= this.state.queue.length) this.halt();
      this.emit('step');
    }
    play() {
      if (this.disposed || this.state.pending || this.state.cursor >= this.state.queue.length) return;
      this.halt();
      this.state.playing = true;
      this.timer = setInterval(() => this.step(), 900);
      this.emit('playback');
    }
    pause() { this.halt(); this.emit('playback'); }
    stop() {
      if (!this.state.live) return;
      this.halt();
      const ended = this.seal('stopped');
      if (this.state.pending) this.snapshot({
        id: this.state.pending.id, kind: 'receipt', title: '交互已取消',
        subtitle: this.state.pending.title, content: '本轮已停止，没有提交决定。'
      });
      this.recordOutcome(ended, 'stopped');
      this.state.pending = null;
      this.state.queue = [];
      this.state.cursor = 0;
      this.state.running = false;
      this.state.resumable = true;
      this.state.retryCompression = false;
      this.emit('stop');
    }
    fail() {
      if (!this.state.live) return;
      this.halt();
      const compacting = this.state.live.kind === 'compacting';
      const message = compacting ? '压缩服务暂时不可用。原历史已保留，可以重试。'
        : isWaitingForModel(this.state.live) ? '等待模型响应时连接中断，可以继续。'
        : this.state.live.kind === 'textOutput' ? '文本输出连接中断。已保留接收到的内容，可以继续。'
        : this.state.pending ? '交互已中断，尚未提交决定。'
        : '示例命令退出码 1：检查未通过，已保留当前结果。';
      const command = this.state.live.members?.find(item => item.status === 'running' && item.kind === 'command');
      if (command) {
        command.status = 'failed';
        command.exitCode = 1;
        command.output += '\nerror: example assertion failed\nProcess exited with code 1';
      }
      const ended = this.seal('failed', message);
      if (this.state.pending) this.snapshot({ id: this.state.pending.id, kind: 'receipt',
        title: '交互未完成', subtitle: this.state.pending.title, content: message });
      this.recordOutcome(ended, 'failed', message);
      this.state.pending = null;
      this.state.queue = [];
      this.state.cursor = 0;
      this.state.running = false;
      this.state.resumable = !compacting;
      this.state.retryCompression = compacting;
      this.emit('failure');
    }
    beginTask() {
      this.state.resumable = false;
      this.state.retryCompression = false;
      this.state.queue = app.fixtures.story(this.id('group'));
      this.state.cursor = 0;
      this.step();
      this.play();
    }
    resume() { if (!this.state.live && this.state.resumable) this.beginTask(); }
    setDraft(value) { this.state.draft = value; this.emit('draft'); }
    attach(files) {
      for (const file of files) {
        const url = URL.createObjectURL(file);
        this.urls.add(url);
        this.state.attachments.push({ id: this.id('attachment'), name: file.name, type: file.type, url, size: file.size });
      }
      this.emit('draft');
    }
    removeAttachment(id) {
      const item = this.state.attachments.find(attachment => attachment.id === id);
      if (item) { URL.revokeObjectURL(item.url); this.urls.delete(item.url); }
      this.state.attachments = this.state.attachments.filter(attachment => attachment.id !== id);
      this.emit('draft');
    }
    submit() {
      if (this.state.pending || (!this.state.draft.trim() && !this.state.attachments.length)) return;
      const text = this.state.draft;
      const attachments = this.state.attachments;
      if (this.state.live) this.stop();
      this.snapshot({ id: this.id('user'), kind: 'user', text, attachments });
      this.state.draft = '';
      this.state.attachments = [];
      this.beginTask();
    }
    answer(index, values) {
      if (this.state.pending?.kind !== 'questions') return;
      this.state.pending.answers[index] = [...values];
      this.emit('pendingInput');
    }
    pendingText(field, value) {
      if (!this.state.pending) return;
      if (field === 'other') this.state.pending.others[this.state.pending.index] = value;
      else this.state.pending[field] = value;
      this.emit('pendingInput');
    }
    questionPage(direction) {
      const pending = this.state.pending;
      if (pending?.kind !== 'questions') return;
      pending.index = Math.max(0, Math.min(pending.questions.length - 1, pending.index + direction));
      this.emit('pendingPage');
    }
    resolve(decision) {
      const pending = this.state.pending;
      if (!pending) return;
      const receipt = { id: pending.id, kind: 'receipt', type: pending.kind, subtitle: pending.title, title: '', content: '' };
      if (decision === 'answer') {
        receipt.title = '用户已回答';
        receipt.subtitle = pending.questions.length + ' 个问题';
        receipt.content = pending.questions.map((question, index) => {
          const answer = question.secret ? '敏感回答已隐藏'
            : [...pending.answers[index], pending.others[index]].filter(Boolean).join('、') || '未填写';
          return '### ' + question.title + '\n' + answer;
        }).join('\n\n');
        if (pending.secret) receipt.content += '\n\n敏感回答已隐藏';
      } else {
        receipt.title = '已跳过提问';
        receipt.content = '用户选择跳过，未提交回答。';
      }
      this.halt();
      this.seal();
      this.snapshot(receipt);
      this.state.pending = null;
      this.state.running = false;
      this.state.queue = [];
      this.state.cursor = 0;
      this.emit('decision');
      this.beginTask();
    }
    dispose() {
      this.halt();
      this.disposed = true;
      this.urls.forEach(url => URL.revokeObjectURL(url));
      this.urls.clear();
    }
  }
  app.isWaitingForModel = isWaitingForModel;
  app.ConversationController = ConversationController;
})();
