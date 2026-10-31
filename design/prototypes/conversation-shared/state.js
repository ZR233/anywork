(() => {
  'use strict';
  const app = window.AnyworkConversation;
  const clone = value => structuredClone(value);
  const runningCount = group => group.members.filter(member => member.status === 'running').length;
  // The model has nothing new to show: no group yet, or the active group has no running member.
  const isWaitingForModel = live => live?.kind === 'waiting'
    || (live?.kind === 'workGroup' && runningCount(live) === 0);
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
    note(text) { this.state.change = text; }
    snapshot(item) {
      if (this.state.history.some(existing => existing.id === item.id)) return;
      this.state.history = [...this.state.history, freeze(clone(item))];
    }
    recordOutcome(live, status, error = '') {
      const interrupted = live?.kind === 'workGroup'
        ? live.members.filter(member => member.status === 'stopped' || member.status === 'failed').length : 0;
      this.snapshot({
        id: (live?.id || this.id('interaction')) + '-outcome', kind: 'outcome', status, sourceId: live?.id,
        subject: !live ? '待回答的问题'
          : live.kind === 'waiting' ? '模型响应'
          : live.kind === 'workGroup' ? `工作组 · ${live.members.length} 步${interrupted ? ` · ${interrupted} 步未完成` : ''}`
          : live.kind === 'textOutput' ? '文本输出' : '上下文压缩',
        error
      });
    }
    halt() {
      clearInterval(this.timer);
      this.timer = null;
      if (this.state) this.state.playing = false;
    }

    load(scenario) {
      this.halt();
      this.urls.forEach(url => URL.revokeObjectURL(url));
      this.urls.clear();
      const spec = app.fixtures.scenarios.find(item => item.id === scenario);
      if (!spec) throw new Error('Unknown scenario: ' + scenario);
      this.state = {
        scenario, history: [], live: null, pending: null, draft: '', attachments: [],
        context: 42, playing: false, running: false, resumable: false, retryCompression: false,
        queue: [], cursor: 0, change: ''
      };
      if (!spec?.empty) app.fixtures.history().forEach(item => this.snapshot(item));
      if (spec?.at) {
        this.state.queue = app.fixtures.story(this.id('group'));
        const target = this.state.queue.findIndex(event => event.label === spec.at);
        if (target < 0) throw new Error('Unknown story frame: ' + spec.at);
        while (this.state.cursor <= target) this.advance();
      } else if (spec?.live === 'compacting') {
        this.startCompression();
      } else if (spec?.pending) {
        const sealed = app.fixtures.group(this.id('group'), true);
        sealed.members = sealed.members.slice(0, 2);
        sealed.elapsed = 4;
        this.snapshot(sealed);
        this.state.pending = clone(spec.pending);
        this.state.pending.id = this.id('interaction');
        this.note('提问到达 · 此前的工作组已整组移入时间线');
      } else if (spec?.outcome) {
        this.state.live = app.fixtures.group(this.id('group'));
        if (spec.outcome === 'failed') this.fail(); else this.stop();
      } else if (scenario === 'receipts') {
        this.snapshot({ id: this.id('receipt'), kind: 'receipt', type: 'questions', title: '用户已回答',
          subtitle: '2 个问题', content: '### 工作组默认如何展示？\n默认折叠，按需展开\n\n### 重点检查哪些场景？\n长文本与代码、停止与继续\n\n敏感回答已隐藏' });
        this.note('问答已完成 · 时间线保留只读回执，敏感回答已隐藏');
      }
      this.state.running = Boolean(this.state.live || this.state.pending);
      this.emit('reset');
    }

    startCompression() {
      this.state.live = { id: this.id('compression'), kind: 'compacting', elapsed: 0 };
      this.state.queue = [{ type: 'tick' }, { type: 'tick' }, { type: 'finishCompression' }, { type: 'finishTurn' }];
      this.state.cursor = 0;
      this.state.running = true;
      this.note('开始压缩 · 状态栏单行显示');
    }
    compact() {
      if (this.state.live || this.state.pending || !this.state.history.length) return;
      this.state.resumable = false;
      this.state.retryCompression = false;
      this.startCompression();
      this.emit('live');
      this.play();
    }
    // Ends the status bar item. A work group always moves to the timeline as one finished whole.
    seal(status = 'completed', error = '') {
      const live = this.state.live;
      if (!live) return null;
      if (live.kind === 'workGroup') {
        live.members.forEach(member => {
          if (member.status !== 'running') return;
          member.status = status === 'completed' ? 'completed' : 'stopped';
          member.targets?.forEach(target => { if (target.status === 'running') target.status = member.status; });
        });
        if (live.members.length) this.snapshot({ id: live.id, kind: 'workGroup', status, elapsed: live.elapsed, members: live.members });
      } else if (live.kind === 'textOutput') {
        if (live.text.trim()) this.snapshot({ id: live.id, kind: 'text', status, error, text: live.text });
      } else if (live.kind === 'compacting' && status === 'completed') {
        this.snapshot({ id: live.id, kind: 'compression', status: 'completed' });
        this.state.context = 18;
      }
      this.state.live = null;
      return live;
    }
    // Information that cannot join the active group closes it first.
    closeGroupFor(reason) {
      const live = this.state.live;
      if (live?.kind === 'workGroup') {
        if (runningCount(live)) throw new Error('A work group with running members cannot be closed by ' + reason);
        this.seal();
        return true;
      }
      if (live?.kind === 'waiting') this.state.live = null;
      else if (live) throw new Error('The status bar must be idle before ' + reason);
      return false;
    }

    apply(event) {
      const live = this.state.live;
      switch (event.type) {
        case 'tick': break;
        case 'waitForModel':
          if (live?.kind === 'workGroup') break;
          if (live) throw new Error('A live item must end before waiting for the model');
          this.state.live = { id: event.id, kind: 'waiting', elapsed: 0 };
          this.state.running = true;
          this.note(this.state.history.at(-1)?.kind === 'text' ? '正文已进入时间线 · 继续等待模型' : '新轮次 · 尚无信息，显示「思考中」');
          break;
        case 'addMember': {
          if (live && live.kind !== 'waiting' && live.kind !== 'workGroup') throw new Error('Members join only the active work group');
          if (live?.kind !== 'workGroup') {
            this.state.live = { id: event.groupId, kind: 'workGroup', status: 'running', elapsed: live?.elapsed || 0, members: [] };
          }
          const group = this.state.live;
          group.members.push(clone(event.member));
          this.state.running = true;
          this.note(group.members.length === 1 ? '新工作组 · 首个成员插入状态栏' : `插入成员 · 当前工作组共 ${group.members.length} 步`);
          break;
        }
        case 'memberDone':
          if (live?.kind === 'workGroup') {
            const member = live.members.find(item => item.id === event.id);
            if (member && member.status === 'running') {
              member.status = 'completed';
              if (member.kind === 'command') {
                member.exitCode = 0;
                member.output += member.target.startsWith('cargo test')
                  ? '\ntest result: ok. 24 passed; 0 failed\nProcess exited with code 0' : '\nProcess exited with code 0';
              }
              member.targets?.forEach(target => { target.status = 'completed'; target.report = target.report.replace('正在检查', '已检查'); });
              this.note(runningCount(live) ? '成员完成 · 打勾后留在当前工作组' : '组内成员全部完成 · 等待下一条信息决定去向');
            }
          }
          break;
        case 'appendCommand':
          if (live?.kind === 'workGroup') {
            const command = live.members.find(item => item.kind === 'command' && item.status === 'running');
            if (command) command.output += '\n' + event.line;
          }
          break;
        case 'startText': {
          const moved = this.closeGroupFor('text output');
          this.state.live = { id: event.id, kind: 'textOutput', text: '', elapsed: 0 };
          this.state.running = true;
          this.note(moved ? '正文开始 · 工作组整组移入时间线' : '开始输出正文');
          break;
        }
        case 'appendText':
          if (live?.kind === 'textOutput') live.text += event.text;
          break;
        case 'finishText':
          if (live?.kind === 'textOutput') { this.seal(); this.note('正文结束 · 整段移入时间线'); }
          break;
        case 'finishCompression':
          if (live?.kind === 'compacting' && (!event.id || event.id === live.id)) { this.seal(); this.note('压缩成功 · 时间线追加完成记录'); }
          break;
        case 'finishTurn': {
          if (live && live.kind !== 'compacting' && isWaitingForModel(live)) {
            const moved = this.closeGroupFor('turn end');
            this.note(moved ? '轮次结束 · 工作组移入时间线，状态栏收起' : '轮次结束 · 状态栏收起');
          } else if (!live) this.note('轮次结束 · 状态栏收起');
          if (!this.state.live) {
            this.state.running = false;
            this.state.resumable = false;
            this.state.retryCompression = false;
            this.halt();
          }
          break;
        }
        default: throw new Error('Unknown demo event: ' + event.type);
      }
    }

    advance() {
      const event = this.state.queue[this.state.cursor];
      if (!event) return false;
      const live = this.state.live;
      if (live) {
        live.elapsed++;
        live.members?.forEach(member => { if (member.status === 'running') member.elapsed++; });
      }
      this.state.cursor++;
      this.apply(event);
      while (!this.state.live && ['waitForModel', 'startText', 'addMember', 'finishTurn'].includes(this.state.queue[this.state.cursor]?.type)) {
        this.apply(this.state.queue[this.state.cursor++]);
      }
      return true;
    }
    step() {
      if (this.disposed || this.state.pending) return;
      if (!this.advance()) { this.halt(); this.emit('playback'); return; }
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
    finishInterrupted(status, message) {
      const pending = this.state.pending;
      const ended = this.seal(status, message);
      if (pending) this.snapshot({
        id: pending.id, kind: 'receipt', title: status === 'failed' ? '交互未完成' : '交互已取消', subtitle: pending.title,
        content: status === 'failed' ? message : '本轮已停止，没有提交决定。'
      });
      this.recordOutcome(ended, status, message);
      this.state.pending = null;
      this.state.queue = [];
      this.state.cursor = 0;
      this.state.running = false;
    }
    stop() {
      if (!this.state.live && !this.state.pending) return;
      this.halt();
      this.finishInterrupted('stopped', '');
      this.state.resumable = true;
      this.state.retryCompression = false;
      this.note('已停止 · 当前内容结束并移入时间线，附停止记录');
      this.emit('stop');
    }
    fail() {
      const live = this.state.live;
      if (!live && !this.state.pending) return;
      this.halt();
      const compacting = live?.kind === 'compacting';
      const message = compacting ? '压缩服务暂时不可用。原历史已保留，可以重试。'
        : !live ? '交互已中断，尚未提交决定。'
        : isWaitingForModel(live) ? '等待模型响应时连接中断，可以继续。'
        : live.kind === 'textOutput' ? '文本输出连接中断。已保留接收到的内容，可以继续。'
        : '示例命令退出码 1：检查未通过，已保留当前结果。';
      const command = live?.members?.find(item => item.status === 'running' && item.kind === 'command');
      if (command) {
        command.status = 'failed';
        command.exitCode = 1;
        command.output += '\nerror: example assertion failed\nProcess exited with code 1';
      }
      this.finishInterrupted('failed', message);
      this.state.resumable = !compacting;
      this.state.retryCompression = compacting;
      this.note('执行失败 · 当前内容结束并移入时间线，附失败记录');
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
