(() => {
  'use strict';
  const app = window.AnyworkConversation;
  const { node, icon, activityIndicator, icons, button, escape, MarkdownView, WorkGroupView, PendingView, historyItem, selectedInside } = app.ui;
  let instanceSequence = 0;

  class ConversationPreview {
    constructor(root) {
      this.root = root;
      this.id = 'conversation-preview-' + (++instanceSequence);
      this.controller = new app.ConversationController(root.dataset.scenario || 'workgroup');
      this.signal = new AbortController();
      this.historyNodes = new Map();
      this.followHistory = true;
      this.followText = true;
      this.lastRead = 0;
      this.toastTimer = null;
      this.liveView = null;
      this.actions = {
        copy: text => this.copy(text),
        detail: (title, content, path) => this.detail(title, content, path)
      };
      this.build();
      this.controller.addEventListener('change', event => this.render(event.detail.reason), { signal: this.signal.signal });
      document.addEventListener('selectionchange', () => {
        if (this.liveView?.kind === 'textOutput') {
          if (selectedInside(this.liveView.markdown.node)) this.followText = false;
          this.liveView.markdown.flush();
          this.updateTextFollow();
        }
        this.liveView?.group?.flush();
      }, { signal: this.signal.signal });
      root.conversationPreview = this;
      this.render('reset');
    }

    build() {
      const root = this.root;
      const controller = this.controller;
      root.classList.add('cv-preview');
      if (root.dataset.controls === 'false') root.classList.add('cv-no-controls');
      if (root.dataset.embedded === 'true') root.classList.add('cv-embedded');
      root.innerHTML = `<div class="cv-demo-layout">
        <section class="cv-window" aria-label="会话概念预览">
          <header class="cv-window-header"><span class="cv-brand">${icon('sparkles')}</span>
            <div><b>细化会话交互</b><small>pure-lang · 主智能体</small></div></header>
          <div class="cv-history" role="region" aria-label="已结束的时间线" tabindex="0">
            <div class="cv-reading-column"><div class="cv-history-start">今天 · 会话记录</div><div class="cv-history-list"></div></div>
          </div>
          <div class="cv-unread-wrap"></div>
          <div class="cv-bottom"><div class="cv-reading-column">
            <div class="cv-live-host"></div>
            <div class="cv-dock-host"></div>
            <form class="cv-composer" aria-label="消息输入">
              <div class="cv-attachments" hidden></div>
              <textarea aria-label="输入消息" rows="2" placeholder="描述下一步，或补充你的想法…"></textarea>
              <input class="cv-file-input" type="file" multiple hidden>
              <div class="cv-composer-footer"><span class="cv-composer-hint">Enter 发送 · Shift + Enter 换行</span></div>
            </form>
            <footer class="cv-conversation-footer">
              <span class="cv-mode">Auto</span><span>·</span>
              <span class="cv-model">GPT-5.4 · High</span>
              <details class="cv-context"><summary aria-label="上下文详情"><span class="cv-context-ring"></span>上下文</summary>
                <div class="cv-context-popover"><h3>上下文用量</h3><div class="cv-context-value"></div>
                  <p class="cv-context-explanation"></p></div></details>
            </footer>
          </div></div>
          <div class="cv-toast" role="status" hidden></div>
        </section>
        <aside class="cv-side" aria-label="概念稿演示控制" ${root.dataset.controls === 'false' ? 'hidden' : ''}>
          <h2>交互演示</h2><p>先看完整过程，再停下来检查细节。<br>所有内容均为示例，不执行真实任务。</p>
          <label class="cv-select-label" for="${this.id}-scenario">切换场景</label>
          <select class="cv-scenario-select" id="${this.id}-scenario">${app.fixtures.scenarios.map(scenario => `<option value="${escape(scenario.id)}">${escape(scenario.label)}</option>`).join('')}</select>
          <div class="cv-scenario-hint"></div><div class="cv-demo-controls"></div>
          <div class="cv-demo-progress"><span>演示进度</span><span class="cv-step-count cv-tabular"></span></div>
          <progress aria-label="演示进度"></progress><div class="cv-demo-state"></div><div class="cv-demo-failure"></div>
          <div class="cv-guide"><h3>状态栏是当前工作组，时间线只有已结束</h3>
            <ol class="cv-flow" aria-label="工作组生命周期">
              <li><span class="cv-flow-dot cv-active"></span><div><b>思考中</b><p>尚无信息，不可展开。</p></div></li>
              <li><span class="cv-flow-dot cv-active"></span><div><b>状态栏 · 当前工作组</b><p>成员逐个插入；完成的打勾留在组内，下一条仍是工具时继续并入。</p></div></li>
              <li><span class="cv-flow-dot cv-boundary"></span><div><b>出现新分组信息</b><p>正文、提问、轮次结束、停止或失败。</p></div></li>
              <li><span class="cv-flow-dot"></span><div><b>Timeline · 已结束</b><p>整组一次移入，之后不再变化；正文、回执与终态各自独立。</p></div></li>
            </ol>
            <div class="cv-stats"><div class="cv-stats-line"><span>时间线</span><strong class="cv-history-count"></strong></div>
              <div class="cv-stats-line"><span>状态栏</span><strong class="cv-live-label"></strong></div>
              <div class="cv-stats-change"><span>最近变化</span><strong class="cv-last-change"></strong></div></div>
          </div>
        </aside>
      </div>`;
      this.window = root.querySelector('.cv-window');
      this.history = root.querySelector('.cv-history');
      this.historyList = root.querySelector('.cv-history-list');
      this.historyStart = root.querySelector('.cv-history-start');
      this.unread = button('回到最新', 'arrow-down', () => {
        this.followHistory = true;
        this.lastRead = controller.state.history.length;
        this.scrollHistory();
        this.updateUnread();
      }, 'cv-unread');
      this.unread.hidden = true;
      root.querySelector('.cv-unread-wrap').append(this.unread);
      this.liveHost = root.querySelector('.cv-live-host');
      this.pending = new PendingView(root.querySelector('.cv-dock-host'), controller, this.id);
      this.composer = root.querySelector('.cv-composer');
      this.textarea = this.composer.querySelector('textarea');
      this.attachments = root.querySelector('.cv-attachments');
      this.fileInput = root.querySelector('.cv-file-input');
      const footer = this.composer.querySelector('.cv-composer-footer');
      this.attachButton = button('添加附件', 'paperclip', () => this.fileInput.click(), 'cv-quiet cv-icon-only');
      this.attachButton.setAttribute('aria-label', '添加附件');
      footer.prepend(this.attachButton);
      this.mainButton = button('发送', 'arrow-up', () => this.mainAction(), 'cv-primary cv-icon-only cv-main-action');
      footer.append(this.mainButton);
      const sessionInfo = button('会话信息', 'info', () => this.detail('会话信息', '主智能体 · 当前会话\n项目：pure-lang\n模型：GPT-5.4 · High\n\n这是本地概念演示，模型与运行内容均为示例。'), 'cv-quiet cv-icon-only');
      sessionInfo.setAttribute('aria-label', '会话信息');
      root.querySelector('.cv-window-header').append(sessionInfo);
      this.compressButton = button('立即压缩', 'minimize-2', () => controller.compact());
      root.querySelector('.cv-context-popover').append(this.compressButton);
      this.contextValue = root.querySelector('.cv-context-value');
      this.contextExplanation = root.querySelector('.cv-context-explanation');
      this.toastNode = root.querySelector('.cv-toast');
      this.scenarioSelect = root.querySelector('.cv-scenario-select');
      this.playButton = button('播放过程', 'play', () => controller.state.playing ? controller.pause() : controller.play(), 'cv-primary');
      this.stepButton = button('单步', 'step-forward', () => controller.step());
      this.resetButton = button('重置', 'rotate-ccw', () => controller.load(controller.state.scenario));
      root.querySelector('.cv-demo-controls').append(this.playButton, this.stepButton, this.resetButton);
      this.failureButton = button('模拟执行失败', 'circle-alert', () => controller.fail(), 'cv-quiet');
      root.querySelector('.cv-demo-failure').append(this.failureButton);
      this.dialog = node(`<dialog class="cv-dialog"><div class="cv-dialog-header"><h2></h2></div><div class="cv-dialog-body"></div></dialog>`);
      const close = button('关闭', 'x', () => this.dialog.close(), 'cv-quiet cv-icon-only');
      close.setAttribute('aria-label', '关闭详情');
      this.dialog.querySelector('.cv-dialog-header').append(close);
      root.append(this.dialog);
      this.dialog.addEventListener('click', event => {
        if (event.target === this.dialog) {
          const bounds = this.dialog.getBoundingClientRect();
          if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) this.dialog.close();
        }
      });
      this.history.addEventListener('scroll', () => {
        this.followHistory = this.history.scrollHeight - this.history.scrollTop - this.history.clientHeight < 22;
        if (this.followHistory) this.lastRead = controller.state.history.length;
        this.updateUnread();
      }, { passive: true });
      this.history.addEventListener('toggle', () => {
        this.followHistory = this.history.scrollHeight - this.history.scrollTop - this.history.clientHeight < 22;
        this.updateUnread();
      }, true);
      this.scenarioSelect.addEventListener('change', () => controller.load(this.scenarioSelect.value));
      this.textarea.addEventListener('input', () => {
        controller.setDraft(this.textarea.value);
        this.textarea.style.height = 'auto';
        this.textarea.style.height = Math.min(this.textarea.scrollHeight, 120) + 'px';
      });
      this.textarea.addEventListener('keydown', event => {
        if (event.isComposing || event.keyCode === 229) return;
        if (event.key === 'Enter' && !event.shiftKey && !event.ctrlKey && !event.altKey && !event.metaKey) {
          event.preventDefault();
          this.submit();
        } else if (event.key === 'Escape' && controller.state.live) {
          event.preventDefault();
          controller.stop();
        }
      });
      this.fileInput.addEventListener('change', () => {
        controller.attach(this.fileInput.files);
        this.fileInput.value = '';
      });
      this.composer.addEventListener('submit', event => { event.preventDefault(); this.submit(); });
      icons(root);
    }

    mainAction() {
      const state = this.controller.state;
      if (state.draft.trim() || state.attachments.length) this.submit();
      else if (state.live) this.controller.stop();
      else if (state.resumable) this.controller.resume();
    }
    submit() {
      const state = this.controller.state;
      if (this.root.dataset.locked || state.pending || (!state.draft.trim() && !state.attachments.length)) return;
      this.followHistory = true;
      this.controller.submit();
    }
    scrollHistory() { this.history.scrollTop = this.history.scrollHeight; }
    updateUnread() {
      const count = Math.max(0, this.controller.state.history.length - this.lastRead);
      this.unread.hidden = this.followHistory || count === 0;
      this.unread.querySelector('span').textContent = count ? `${count} 项新内容 · 回到最新` : '回到最新';
    }
    updateComposer() {
      const state = this.controller.state;
      this.composer.hidden = Boolean(state.pending);
      if (this.textarea.value !== state.draft) this.textarea.value = state.draft;
      if (!state.draft) this.textarea.style.height = '';
      const hasDraft = Boolean(state.draft.trim() || state.attachments.length);
      this.textarea.disabled = Boolean(this.root.dataset.locked);
      this.attachButton.disabled = Boolean(this.root.dataset.locked);
      if (this.root.dataset.locked) this.textarea.placeholder = this.root.dataset.locked;
      this.mainButton.disabled = Boolean(this.root.dataset.locked) || (!state.live && !state.resumable && !hasDraft);
      const stopping = Boolean(state.live && !hasDraft);
      const continuing = Boolean(!state.live && state.resumable && !hasDraft);
      this.mainButton.classList.toggle('cv-primary', !stopping);
      this.mainButton.classList.toggle('cv-stop', stopping);
      const label = hasDraft ? (state.live || state.resumable ? '发送并继续' : '发送') : stopping ? '停止' : continuing ? '继续' : '发送';
      if (this.mainButton.dataset.label !== label) {
        this.mainButton.dataset.label = label;
        this.mainButton.setAttribute('aria-label', label);
        this.mainButton.innerHTML = icon(stopping ? 'square' : continuing ? 'play' : 'arrow-up');
        icons(this.mainButton);
      }
      const signature = state.attachments.map(item => item.id).join(',');
      if (this.attachmentSignature !== signature) {
        this.attachmentSignature = signature;
        this.attachments.hidden = !state.attachments.length;
        this.attachments.replaceChildren(...state.attachments.map(item => {
          const row = node(`<span class="cv-attachment">${icon('file')}<span class="cv-attachment-name">${escape(item.name)}</span></span>`);
          const remove = button('移除 ' + item.name, 'x', () => this.controller.removeAttachment(item.id), 'cv-quiet cv-icon-only');
          remove.setAttribute('aria-label', '移除 ' + item.name);
          row.append(remove);
          return row;
        }));
        icons(this.attachments);
      }
    }

    renderLive() {
      const state = this.controller.state;
      const live = state.live;
      if (!live) { this.liveHost.replaceChildren(); this.liveView = null; return; }
      const kind = live.kind;
      if (this.liveView?.id !== live.id || this.liveView.kind !== kind) {
        this.liveHost.replaceChildren();
        const surface = node(`<section class="cv-live" data-live-kind="${escape(kind)}" aria-label="当前状态栏"></section>`);
        this.liveHost.append(surface);
        this.liveView = { id: live.id, kind, surface };
        if (kind === 'waiting') {
          surface.append(node(`<div class="cv-thinking-header">${activityIndicator()}<span role="status">思考中</span><span class="cv-tabular" aria-hidden="true"></span></div>`));
        } else if (kind === 'workGroup') {
          this.liveView.group = new WorkGroupView(live, 'live', this.actions);
          surface.append(this.liveView.group.node);
        } else if (kind === 'textOutput') {
          surface.append(node(`<div class="cv-response-header">${activityIndicator()}<span>正在输出</span><span class="cv-tabular"></span></div>`));
          const scroll = node('<div class="cv-response-scroll" tabindex="0" role="region" aria-label="实时文本输出"></div>');
          surface.append(scroll);
          this.liveView.scroll = scroll;
          this.liveView.markdown = new MarkdownView(scroll, this.actions);
          this.followText = true;
          this.liveView.follow = button('跟随输出', 'arrow-down', () => {
            window.getSelection()?.removeAllRanges();
            this.liveView?.markdown.flush();
            this.followText = true;
            scroll.scrollTop = scroll.scrollHeight;
            this.updateTextFollow();
          }, 'cv-quiet cv-response-follow');
          surface.append(this.liveView.follow);
          scroll.addEventListener('scroll', () => {
            this.followText = scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight < 22;
            this.updateTextFollow();
          }, { passive: true });
        } else {
          surface.append(node(`<div class="cv-compressing-header">${activityIndicator()}<span>正在压缩</span><span class="cv-tabular"></span></div>`));
        }
        icons(surface);
      }
      if (kind === 'workGroup') this.liveView.group.update(live);
      else {
        this.liveView.surface.querySelector('.cv-tabular').textContent = live.elapsed + 's';
        if (kind === 'textOutput') {
          if (selectedInside(this.liveView.markdown.node)) this.followText = false;
          this.liveView.markdown.update(live.text);
          if (this.followText) this.liveView.scroll.scrollTop = this.liveView.scroll.scrollHeight;
          this.updateTextFollow();
        }
      }
    }
    updateTextFollow() {
      if (this.liveView?.kind !== 'textOutput') return;
      this.liveView.follow.hidden = this.followText;
    }

    render(reason) {
      const state = this.controller.state;
      if (reason === 'draft') { this.updateComposer(); return; }
      if (reason === 'pendingInput') { this.pending.update(state.pending); return; }
      this.root.dataset.playing = String(state.playing);
      if (reason === 'reset') {
        this.historyList.replaceChildren();
        this.historyNodes.clear();
        this.liveView = null;
        this.liveHost.replaceChildren();
        this.followHistory = true;
        this.lastRead = state.history.length;
        this.dialog.close();
        clearTimeout(this.toastTimer);
        this.toastNode.hidden = true;
      }
      const oldTop = this.history.scrollTop;
      if (state.history.length === 0 && this.historyNodes.size === 0 && !this.historyList.firstChild) {
        const empty = node(`<div class="cv-empty">${icon('sparkles')}<h2>从一个想法开始</h2><p>告诉糊来帮你想完成什么。</p></div>`);
        empty.append(button('帮我细化会话界面', 'arrow-up-right', () => {
          this.controller.setDraft('帮我细化会话界面，完整演示历史和实时状态的切换。');
          this.textarea.focus();
        }));
        if (this.root.dataset.locked) {
          empty.querySelector('h2').textContent = this.root.dataset.locked;
          empty.querySelector('p').textContent = '添加项目后，可以开始新的会话。';
          empty.querySelector('button').remove();
        }
        this.historyList.append(empty);
      }
      if (state.history.length && this.historyList.querySelector('.cv-empty')) this.historyList.replaceChildren();
      state.history.forEach(item => {
        if (this.historyNodes.has(item.id)) return;
        const rendered = historyItem(item, this.actions);
        rendered.dataset.historyId = item.id;
        this.historyNodes.set(item.id, rendered);
        this.historyList.append(rendered);
        icons(rendered);
      });
      this.historyStart.hidden = state.history.length === 0;
      this.renderLive();
      this.pending.update(state.pending);
      this.updateComposer();
      this.contextValue.textContent = state.context + '%';
      this.root.querySelector('.cv-context-ring').style.setProperty('--cv-context-fill', state.context + '%');
      this.compressButton.disabled = Boolean(state.live || state.pending || !state.history.length);
      this.compressButton.querySelector('span').textContent = state.retryCompression ? '重试压缩' : '立即压缩';
      this.contextExplanation.textContent = state.live || state.pending ? '当前正在执行，结束后可以手动压缩。' : state.history.length ? '压缩后仍保留原始历史记录。当前为示例用量。' : '有历史记录后可以压缩上下文。';
      const currentScenario = app.fixtures.scenarios.find(item => item.id === state.scenario);
      this.scenarioSelect.value = currentScenario?.id || (state.scenario === 'question-last' ? 'questions' : 'idle');
      this.root.querySelector('.cv-scenario-hint').textContent = currentScenario?.hint || '查看已经完成的问答回执。';
      const available = !state.pending && state.cursor < state.queue.length;
      this.playButton.disabled = !available;
      this.stepButton.disabled = !available || state.playing;
      const playLabel = state.playing ? '暂停' : '播放过程';
      if (this.playButton.dataset.label !== playLabel) {
        this.playButton.dataset.label = playLabel;
        this.playButton.innerHTML = icon(state.playing ? 'pause' : 'play') + `<span>${playLabel}</span>`;
        icons(this.playButton);
      }
      this.failureButton.disabled = !state.live && !state.pending;
      this.root.querySelector('.cv-step-count').textContent = `${state.cursor} / ${state.queue.length}`;
      const progress = this.root.querySelector('progress');
      progress.max = Math.max(1, state.queue.length);
      progress.value = state.cursor;
      this.root.querySelector('.cv-demo-state').textContent = state.pending ? '等待你的决定' : state.playing ? '正在播放 · 可随时暂停' : available ? '演示已暂停 · 可以单步查看' : '演示结束 · 可以重置或发送新消息';
      this.root.querySelector('.cv-history-count').textContent = state.history.length + ' 项';
      const group = state.live?.kind === 'workGroup' ? state.live : null;
      this.root.querySelector('.cv-live-label').textContent = state.pending ? '收起 · 停靠区等待回答'
        : group ? `工作组 · ${group.members.length} 步${app.isWaitingForModel(group) ? ' · 待交接' : ''}`
        : ({ waiting: '思考中', textOutput: '正在输出', compacting: '正在压缩' })[state.live?.kind] || '收起';
      this.root.querySelector('.cv-last-change').textContent = state.change || '—';
      if (this.followHistory) { this.scrollHistory(); this.lastRead = state.history.length; }
      else this.history.scrollTop = oldTop;
      this.updateUnread();
    }

    async copy(text) {
      try {
        await navigator.clipboard.writeText(text);
        this.toast('已复制');
      } catch {
        this.detail('复制内容', text, '浏览器未允许剪贴板访问，请在下方选择并复制原文。');
      }
    }
    detail(title, content, path = '') {
      this.dialog.querySelector('h2').textContent = title;
      const body = this.dialog.querySelector('.cv-dialog-body');
      body.replaceChildren();
      if (path) body.append(node(`<div class="cv-dialog-path">${escape(path)}</div>`));
      const pre = document.createElement('pre');
      pre.textContent = content;
      body.append(pre);
      if (!this.dialog.open) this.dialog.showModal();
    }
    toast(message) {
      clearTimeout(this.toastTimer);
      this.toastNode.textContent = message;
      this.toastNode.hidden = false;
      this.toastTimer = setTimeout(() => { this.toastNode.hidden = true; }, 1800);
    }
    dispose() {
      this.controller.dispose();
      this.signal.abort();
      clearTimeout(this.toastTimer);
      this.dialog.close();
      this.dialog.remove();
      app.instances.delete(this);
      delete this.root.conversationPreview;
    }
  }

  app.instances = new Set();
  app.mount = root => {
    if (root.conversationPreview) return root.conversationPreview;
    const preview = new ConversationPreview(root);
    app.instances.add(preview);
    return preview;
  };
  const roots = document.querySelectorAll('[data-conversation-preview]');
  if (!window.marked || !window.DOMPurify || !window.lucide) {
    roots.forEach(root => {
      root.textContent = '概念稿依赖未加载。请联网后重新打开页面（Marked / DOMPurify / Lucide）。';
    });
    return;
  }
  roots.forEach(root => app.mount(root));
  const observer = new MutationObserver(() => {
    app.instances.forEach(preview => { if (!preview.root.isConnected) preview.dispose(); });
  });
  observer.observe(document.body, { childList: true, subtree: true });
  window.addEventListener('pagehide', event => {
    if (event.persisted) app.instances.forEach(preview => preview.controller.pause());
    else {
      observer.disconnect();
      app.instances.forEach(preview => preview.dispose());
    }
  });
})();
