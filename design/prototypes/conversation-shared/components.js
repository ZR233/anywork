(() => {
  'use strict';
  const app = window.AnyworkConversation;
  const escape = value => String(value ?? '').replace(/[&<>"']/g, character =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character]);
  function node(html) {
    const template = document.createElement('template');
    template.innerHTML = html.trim();
    if (template.content.childElementCount !== 1) throw new Error('A preview component must have one root element');
    return template.content.firstElementChild;
  }
  const icon = name => `<i data-lucide="${escape(name)}" aria-hidden="true"></i>`;
  function icons(root) {
    window.lucide.createIcons({ root, icons: window.lucide.icons, attrs: { 'stroke-width': 1.65 } });
  }
  function button(label, name, action, className = '') {
    const element = node(`<button type="button" class="cv-button ${escape(className)}">${name ? icon(name) : ''}<span>${escape(label)}</span></button>`);
    element.addEventListener('click', action);
    icons(element);
    return element;
  }
  const statusLabel = status => ({ running: '进行中', completed: '已完成', stopped: '已停止', failed: '失败' })[status] || '';
  const statusIcon = status => ({ running: 'loader-circle', completed: 'check', stopped: 'square', failed: 'circle-alert' })[status] || 'circle';
  const selectedInside = element => {
    const selection = window.getSelection();
    return selection && !selection.isCollapsed && (element.contains(selection.anchorNode) || element.contains(selection.focusNode));
  };

  // A view-only pending render protects text selection; the controller continues receiving output.
  class SelectableContent {
    constructor(element, render) { this.element = element; this.render = render; this.value = null; this.pending = null; }
    update(value) {
      if (value === this.value) return;
      if (selectedInside(this.element)) { this.pending = value; return; }
      this.render(value);
      this.value = value;
      this.pending = null;
    }
    flush() { if (this.pending !== null) this.update(this.pending); }
  }

  class MarkdownView {
    constructor(host, actions) {
      this.node = node('<div class="cv-markdown"></div>');
      host.append(this.node);
      this.content = new SelectableContent(this.node, value => {
        this.node.innerHTML = window.DOMPurify.sanitize(window.marked.parse(value, { gfm: true, async: false }), {
          USE_PROFILES: { html: true },
          FORBID_TAGS: ['img', 'form', 'input', 'button', 'style', 'iframe'],
          FORBID_ATTR: ['style']
        });
        this.node.querySelectorAll('a').forEach(link => {
          const href = link.getAttribute('href');
          let url;
          try { url = href ? new URL(href, location.href) : null; } catch { url = null; }
          if (!url || !['https:', 'http:', 'mailto:'].includes(url.protocol)) link.replaceWith(...link.childNodes);
          else { link.target = '_blank'; link.rel = 'noopener noreferrer'; }
        });
        this.node.querySelectorAll('pre').forEach(pre => {
          const source = pre.querySelector('code')?.textContent || pre.textContent;
          const language = pre.querySelector('code')?.className.replace('language-', '') || '代码';
          const header = node(`<div class="cv-code-header"><span>${escape(language)}</span></div>`);
          header.append(button('复制', 'copy', () => actions.copy(source), 'cv-quiet'));
          const wrap = node('<div class="cv-code"></div>');
          pre.replaceWith(wrap);
          wrap.append(header, pre);
        });
      });
    }
    update(source) { this.source = source; this.content.update(source || ''); }
    flush() { this.content.flush(); }
  }

  function groupText(group) {
    return [
      group.summary,
      ...group.members.map(member => [
        `${member.title}${member.target ? ' · ' + member.target : ''} · ${statusLabel(member.status)} · ${member.elapsed}s`,
        member.content || member.output || member.rule || '',
        ...(member.files || []).map(file => file.name + '\n' + file.diff),
        ...(member.targets || []).map(target => target.name + ' · ' + statusLabel(target.status) + '\n' + target.report)
      ].join('\n')),
      group.error || ''
    ].join('\n\n');
  }

  class MemberView {
    constructor(member, mode, actions) {
      this.mode = mode;
      this.actions = actions;
      this.current = member;
      this.signature = '';
      this.node = node(`<${member.kind === 'thinking' ? 'section' : 'details'} class="cv-member cv-${escape(member.kind)}" data-member-id="${escape(member.id)}"></${member.kind === 'thinking' ? 'section' : 'details'}>`);
      this.head = node(`<${member.kind === 'thinking' ? 'div' : 'summary'} class="cv-member-heading">
        <span class="cv-member-symbol"></span><span class="cv-member-label"></span>
        <span class="cv-member-meta cv-tabular"></span>
      </${member.kind === 'thinking' ? 'div' : 'summary'}>`);
      this.symbol = this.head.querySelector('.cv-member-symbol');
      this.label = this.head.querySelector('.cv-member-label');
      this.meta = this.head.querySelector('.cv-member-meta');
      this.label.append(node(`<span class="cv-member-verb">${escape(member.title)}</span>`));
      if (member.target) this.label.append(node(`<code class="cv-target" title="${escape(member.path || member.target)}">${escape(member.target)}</code>`));
      if (member.kind !== 'thinking') this.label.append(node(`<span class="cv-chevron">${icon('chevron-right')}</span>`));
      this.body = node('<div class="cv-member-body"></div>');
      this.node.append(this.head, this.body);
      if (member.kind === 'thinking') {
        this.markdown = new MarkdownView(this.body, actions);
        this.markdown.update(member.content);
      } else this.buildBody(member);
      icons(this.node);
      this.update(member);
    }
    buildBody(member) {
      const actions = this.actions;
      if (member.kind === 'command') {
        this.body.append(node(`<div class="cv-detail-meta"><span>工作目录 <code>${escape(member.cwd)}</code></span></div>`));
        this.body.firstChild.append(button('复制命令', 'copy', () => actions.copy(this.current.target), 'cv-quiet'));
        this.log = node('<pre class="cv-terminal" tabindex="0" aria-label="命令输出"></pre>');
        this.logContent = new SelectableContent(this.log, value => {
          const follow = this.log.scrollHeight - this.log.scrollTop - this.log.clientHeight < 22;
          this.log.textContent = value;
          if (follow) this.log.scrollTop = this.log.scrollHeight;
        });
        this.exit = node('<div class="cv-detail-meta"></div>');
        this.body.append(this.log, this.exit);
      } else if (member.kind === 'read') {
        this.body.append(node(`<div class="cv-file-path">${escape(member.path)}</div>`),
          node(`<pre class="cv-file-preview">${escape(member.content)}</pre>`));
        this.body.append(button('查看全文', 'maximize-2', () => actions.detail(member.target, member.content, member.path), 'cv-quiet'));
      } else if (member.kind === 'search') {
        const queries = node('<div class="cv-query-list"></div>');
        member.queries.forEach(query => queries.append(node(`<code>${escape(query)}</code>`)));
        this.body.append(queries);
        member.results.forEach(result => this.body.append(node(`<a class="cv-search-result" href="${escape(result.url)}" target="_blank" rel="noopener noreferrer"><strong>${escape(result.title)}</strong><span>${escape(result.description)}</span></a>`)));
      } else if (member.kind === 'edit') {
        const tabs = node('<div class="cv-file-tabs" role="group" aria-label="变更文件"></div>');
        const diff = node('<pre class="cv-diff"></pre>');
        const select = file => {
          tabs.querySelectorAll('button').forEach(tab => tab.setAttribute('aria-pressed', String(tab.dataset.file === file.name)));
          diff.replaceChildren(...file.diff.split('\n').map(line => node(`<span class="${line.startsWith('+') ? 'cv-diff-add' : line.startsWith('-') ? 'cv-diff-remove' : ''}">${escape(line) || ' '}</span>`)));
        };
        member.files.forEach(file => {
          const tab = button(file.name, 'file-code', () => select(file), 'cv-file-tab');
          tab.dataset.file = file.name;
          tab.append(node(`<span class="cv-diff-count"><span>+${file.added}</span> −${file.removed}</span>`));
          tabs.append(tab);
        });
        this.body.append(tabs, diff);
        this.body.append(button('查看完整差异', 'maximize-2', () => actions.detail('文件修改', member.files.map(file => file.name + '\n' + file.diff).join('\n\n'), member.path), 'cv-quiet'));
        select(member.files[0]);
      } else if (member.kind === 'wait') {
        this.body.append(node(`<div class="cv-detail-meta">${escape(member.rule)}</div>`));
        this.targets = node('<div class="cv-wait-targets"></div>');
        this.body.append(this.targets);
      }
    }
    update(member) {
      this.current = member;
      if (this.status !== member.status) {
        this.status = member.status;
        const name = member.status === 'running' ? 'loader-circle' :
          ({ thinking: 'brain', read: 'file-text', command: 'terminal', search: 'search', edit: 'file-pen-line', wait: 'users' })[member.kind];
        this.symbol.innerHTML = icon(member.status === 'failed' ? 'circle-alert' : member.status === 'stopped' ? 'square' : name);
        this.node.dataset.status = member.status;
        icons(this.symbol);
      }
      this.meta.textContent = `${statusLabel(member.status)} · ${member.elapsed}s`;
      if (this.logContent) {
        this.logContent.update(member.output);
        this.exit.textContent = member.exitCode === null ? '正在接收输出' : '退出码 ' + member.exitCode;
      }
      if (this.targets) {
        const signature = JSON.stringify(member.targets);
        if (signature !== this.signature) {
          this.signature = signature;
          this.targets.replaceChildren(...member.targets.map(target => {
            const row = node(`<div class="cv-wait-target"><span class="cv-status-symbol" data-status="${escape(target.status)}">${icon(statusIcon(target.status))}</span><div><b>${escape(target.name)}</b><span>${escape(target.task)}</span></div><span class="cv-wait-state">${statusLabel(target.status)}</span></div>`);
            if (target.status === 'completed') row.append(button('查看报告', 'arrow-up-right', () => this.actions.detail(target.name + ' 的报告', target.report), 'cv-quiet'));
            return row;
          }));
          icons(this.targets);
        }
      }
    }
    flush() { this.logContent?.flush(); this.markdown?.flush(); }
  }

  function groupHeading() {
    return node(`<summary class="cv-group-heading">
      <span class="cv-live-dot" aria-hidden="true"></span><span class="cv-group-title"></span>
      <span class="cv-group-meta cv-tabular"></span><span class="cv-chevron">${icon('chevron-right')}</span>
    </summary>`);
  }

  class WorkGroupView {
    constructor(group, mode, actions, expanded = mode === 'live') {
      this.mode = mode;
      this.node = node(`<details class="cv-work-group cv-group-${escape(mode)}" data-history-kind="workGroup"><div class="cv-group-rail"></div></details>`);
      this.node.prepend(groupHeading());
      this.node.open = expanded;
      this.title = this.node.querySelector('.cv-group-title');
      this.meta = this.node.querySelector('.cv-group-meta');
      this.rail = this.node.querySelector('.cv-group-rail');
      this.members = group.members.map(member => new MemberView(member, mode, actions));
      this.members.forEach(member => this.rail.append(member.node));
      const footer = node('<div class="cv-group-actions"></div>');
      footer.append(button('复制工作记录', 'copy', () => actions.copy(groupText(this.current)), 'cv-quiet'));
      this.node.append(footer);
      this.update(group);
      icons(this.node);
    }
    update(group) {
      this.current = group;
      const tools = group.members.filter(member => member.kind !== 'thinking').length;
      const running = group.members.filter(member => member.status === 'running').length;
      this.title.textContent = this.mode === 'live' ? group.summary : `工作了 ${group.elapsed} 秒 · ${tools} 个工具`;
      this.meta.textContent = this.mode === 'live' ? `${running} 项进行中 · ${group.elapsed}s` : '';
      this.node.dataset.status = group.status;
      this.members.forEach((view, index) => view.update(group.members[index]));
    }
    flush() { this.members.forEach(member => member.flush()); }
  }

  function historyItem(item, actions) {
    if (item.kind === 'workGroup') return new WorkGroupView(item, 'history', actions).node;
    if (item.kind === 'outcome') {
      const element = node(`<details class="cv-history-outcome cv-group-history" data-history-kind="outcome" data-status="${escape(item.status)}"><div class="cv-group-rail"></div></details>`);
      const heading = groupHeading();
      const title = item.status === 'failed' ? '执行失败' : '已停止';
      heading.querySelector('.cv-group-title').textContent = title;
      element.prepend(heading);
      const body = element.querySelector('.cv-group-rail');
      const explanation = item.error || (item.subject === '上下文压缩'
        ? '上下文压缩已停止，原始历史保持不变。'
        : '本次执行已停止，已保留停止前生成的内容。');
      body.append(node(`<div class="cv-detail-meta">${escape(item.subject)}</div>`),
        node(`<p class="${item.status === 'failed' ? 'cv-group-error' : 'cv-outcome-description'}">${escape(explanation)}</p>`));
      if (item.status === 'failed' && item.subject === '上下文压缩') {
        body.append(node('<p class="cv-outcome-description">压缩可通过上下文详情重新发起。</p>'));
      }
      body.append(button('复制说明', 'copy', () => actions.copy([title, item.subject, explanation].join('\n')), 'cv-quiet'));
      return element;
    }
    if (item.kind === 'compression') {
      return node(`<div class="cv-compression-receipt" data-history-kind="compression">${icon('check') }<span>已完成压缩</span>${item.time ? `<time>${escape(item.time)}</time>` : ''}</div>`);
    }
    if (item.kind === 'receipt') {
      const element = node(`<details class="cv-receipt" data-history-kind="receipt"><summary>${icon(item.title.includes('取消') || item.title.includes('跳过') ? 'minus' : 'check-check')}<span><b>${escape(item.title)}</b><small>${escape(item.subtitle)}</small></span><span class="cv-chevron">${icon('chevron-right')}</span></summary><div class="cv-receipt-body"></div></details>`);
      const body = element.querySelector('.cv-receipt-body');
      new MarkdownView(body, actions).update(item.content);
      body.append(button('复制回执', 'copy', () => actions.copy(item.title + '\n' + item.subtitle + '\n' + item.content), 'cv-quiet'));
      return element;
    }
    const element = node(`<article class="cv-message cv-message-${item.kind === 'user' ? 'user' : 'assistant'}" data-history-kind="${escape(item.kind)}">
      <div class="cv-message-content"></div><div class="cv-message-footer"></div></article>`);
    const content = element.querySelector('.cv-message-content');
    if (item.kind === 'user') {
      content.append(node(`<div class="cv-user-text">${escape(item.text)}</div>`));
      if (item.attachments?.length) {
        const files = node('<div class="cv-history-files"></div>');
        item.attachments.forEach(file => {
          const link = node(`<a href="${escape(file.url)}" target="_blank" rel="noopener noreferrer">${icon('paperclip')}${escape(file.name)}</a>`);
          files.append(link);
        });
        content.append(files);
      }
    } else {
      new MarkdownView(content, actions).update(item.text);
    }
    const footer = element.querySelector('.cv-message-footer');
    footer.append(node(`<span>${item.kind === 'user' ? '你' : '糊来帮'}${item.time ? ' · ' + escape(item.time) : ''}</span>`));
    footer.append(button('复制', 'copy', () => actions.copy(item.text), 'cv-quiet'));
    return element;
  }

  class PendingView {
    constructor(host, controller, prefix) {
      this.controller = controller;
      this.prefix = prefix;
      this.node = node('<section class="cv-dock" aria-label="待处理交互"></section>');
      host.append(this.node);
      this.key = '';
    }
    update(pending) {
      this.node.hidden = !pending;
      if (!pending) { this.key = ''; this.node.replaceChildren(); return; }
      const key = [pending.id, pending.index].join(':');
      if (key === this.key) return;
      this.key = key;
      const controller = this.controller;
      this.node.replaceChildren();
      const header = node(`<div class="cv-dock-header"><span class="cv-dock-symbol">${icon('message-circle-question')}</span><div><b>${escape(pending.title)}</b><span>你的回答会保留为历史回执</span></div></div>`);
      header.append(button('停止', 'square', () => controller.stop(), 'cv-quiet'));
      this.node.append(header);
      const question = pending.questions[pending.index];
      this.node.append(node(`<div class="cv-question-heading"><span>问题 ${pending.index + 1} / ${pending.questions.length}</span><span>${question.multiple ? '可多选' : '单选'}</span></div>`));
      this.node.append(node(`<div class="cv-question-title">${escape(question.title)}</div>`));
      this.node.append(node(`<p class="cv-dock-description">${escape(question.description)}</p>`));
      const options = node('<div class="cv-options"></div>');
      question.options.forEach(option => {
        const label = node(`<label class="cv-option"><input type="${question.multiple ? 'checkbox' : 'radio'}" name="${escape(this.prefix)}-question-${pending.index}" value="${escape(option)}" ${pending.answers[pending.index].includes(option) ? 'checked' : ''}><span>${escape(option)}</span></label>`);
        label.querySelector('input').addEventListener('change', () => controller.answer(pending.index, [...options.querySelectorAll('input:checked')].map(input => input.value)));
        options.append(label);
      });
      this.node.append(options);
      const other = node(`<label class="cv-field-label">补充说明（可选）<input class="cv-text-input" type="text" value="${escape(pending.others[pending.index])}" placeholder="也可以写下你的想法"></label>`);
      other.querySelector('input').addEventListener('input', event => controller.pendingText('other', event.target.value));
      this.node.append(other);
      if (question.secret) {
        const secret = node(`<label class="cv-field-label">敏感备注（可选）<input class="cv-text-input" type="password" autocomplete="off" value="${escape(pending.secret)}" placeholder="内容不会进入历史或复制结果"></label>`);
        secret.querySelector('input').addEventListener('input', event => controller.pendingText('secret', event.target.value));
        this.node.append(secret);
      }
      const footer = node('<div class="cv-dock-footer"></div>');
      footer.append(button('跳过', '', () => controller.resolve('skip'), 'cv-quiet'));
      const previous = button('上一题', 'chevron-left', () => controller.questionPage(-1));
      previous.disabled = pending.index === 0;
      footer.append(previous, pending.index === pending.questions.length - 1
        ? button('提交答案', 'check', () => controller.resolve('answer'), 'cv-primary')
        : button('下一题', 'chevron-right', () => controller.questionPage(1), 'cv-primary'));
      this.node.append(footer);
      icons(this.node);
    }
  }

  app.ui = { escape, node, icon, icons, button, statusLabel, MarkdownView, WorkGroupView, PendingView, historyItem, groupText, selectedInside };
})();
