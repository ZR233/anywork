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
  const circularRingSvg = (className = '') => `
    <svg class="cv-exec-ring ${escape(className)}" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <circle class="cv-exec-ring-track" cx="12" cy="12" r="9.2"></circle>
      <circle class="cv-exec-ring-arc" cx="12" cy="12" r="9.2"></circle>
    </svg>`;
  const spinner = (className = '') => circularRingSvg(className);

  const restingCatSvg = () => `
    <svg class="cv-live-icon cv-resting-cat-svg" viewBox="0 0 64 64" fill="none" aria-hidden="true">
      <path class="cv-cat-body" d="M 7.6 28.63 C 6.3 26.19 6.4 23.75 8.4 20.09 C 7.9 17.53 8.5 12.65 9.7 11.06 C 12.1 11.19 14.1 13.50 15.7 15.70 Q 17.5 15.21 18.9 15.70 C 20.7 12.89 22.4 10.82 23.9 10.45 C 25.3 13.02 25.8 16.07 25.9 18.75 C 31.6 12.41 38.1 11.67 43.1 15.21 C 48.6 18.87 50.6 25.46 50.6 36.20 M 4.3 34.0 L 43.4 34.0 Q 45.8 34.0 45.8 36.2 M 50.6 34.0 L 54.2 34.0 M 6.1 33.76 C 5.6 27.41 13.2 27.05 13.6 33.76 M 12.1 26.19 Q 13.9 27.90 15.5 26.19 M 19.1 26.19 Q 21.0 27.90 22.6 26.19 M 21.5 33.76 C 21.3 28.51 27.1 26.92 28.8 30.83 M 36.5 33.76 C 33.7 32.41 34.9 27.66 39.0 25.95"></path>
      <g class="cv-cat-tail">
        <path class="cv-cat-tail-path" d="M 45.8 37.2 C 45.5 43.6 43.2 50.8 38.8 55.4 C 37.6 56.7 39.6 58.6 41.2 57.2 C 46.8 52.2 49.8 44.2 50.6 37.2"></path>
      </g>
    </svg>`;

  const writingSvg = () => `
    <svg class="cv-live-icon cv-writing-svg" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <g class="cv-writing-paper">
        <line x1="3" y1="6.5" x2="11" y2="6.5"></line>
        <line x1="3" y1="12.5" x2="8" y2="12.5"></line>
        <line x1="3" y1="20.5" x2="19" y2="20.5"></line>
      </g>
      <g class="cv-writing-pen">
        <g transform="translate(10 18) rotate(-45)">
          <path d="M 0 0 L 3.3 -1.55 L 3.3 1.55 Z" fill="currentColor"></path>
          <rect x="4.1" y="-1.55" width="8.8" height="3.1" rx="0.6" fill="currentColor"></rect>
          <rect x="13.6" y="-1.55" width="1.4" height="3.1" rx="0.6" fill="currentColor"></rect>
        </g>
      </g>
    </svg>`;

  const compactingZipSvg = () => `
    <svg class="cv-live-icon cv-compacting-zip-svg" viewBox="0 0 64 64" fill="none" aria-hidden="true">
      <g class="cv-zip-pack">
        <rect class="cv-zip-box-fill" x="10.5" y="7.5" width="43" height="49" rx="9.5"></rect>
        <rect class="cv-zip-box-stroke" x="10.5" y="7.5" width="43" height="49" rx="9.5"></rect>
        <line class="cv-zip-clamp" x1="17.5" y1="12.2" x2="24.0" y2="12.2"></line>
        <line class="cv-zip-clamp" x1="40.0" y1="12.2" x2="46.5" y2="12.2"></line>
        <line class="cv-zip-clamp" x1="18.5" y1="51.8" x2="45.5" y2="51.8"></line>
        <line class="cv-zip-seam" x1="32" y1="9" x2="32" y2="33"></line>
        <line class="cv-zip-seam" x1="32" y1="33" x2="28.8" y2="43"></line>
        <line class="cv-zip-seam" x1="32" y1="33" x2="35.2" y2="43"></line>
        <rect class="cv-zip-tooth" x="26.9" y="13.0" width="6.2" height="3.0" rx="1.1"></rect>
        <rect class="cv-zip-tooth" x="30.9" y="17.5" width="6.2" height="3.0" rx="1.1"></rect>
        <rect class="cv-zip-tooth" x="26.9" y="22.0" width="6.2" height="3.0" rx="1.1"></rect>
        <rect class="cv-zip-tooth" x="30.9" y="26.5" width="6.2" height="3.0" rx="1.1"></rect>
        <rect class="cv-zip-tooth is-lower-left" x="25.9" y="31.0" width="6.2" height="3.0" rx="1.1"></rect>
        <rect class="cv-zip-tooth is-lower-right" x="32.2" y="35.5" width="6.2" height="3.0" rx="1.1"></rect>
        <g class="cv-zip-slider">
          <rect class="cv-zip-slider-body" x="27.2" y="30.0" width="9.6" height="7.4" rx="2.4"></rect>
          <rect class="cv-zip-pull-ring" x="29.1" y="37.3" width="5.8" height="6.4" rx="2.6"></rect>
        </g>
      </g>
    </svg>`;

  const activityIndicator = (style = 'restingCat') => {
    const resolved = ['restingCat', 'circularProgress', 'writing', 'compactingZip'].includes(style)
      ? style
      : 'restingCat';
    const body = resolved === 'circularProgress'
      ? circularRingSvg('is-header-exec')
      : resolved === 'writing'
        ? writingSvg()
        : resolved === 'compactingZip'
          ? compactingZipSvg()
          : restingCatSvg();
    return `<span class="cv-activity-indicator" data-style="${escape(resolved)}" aria-hidden="true">${body}</span>`;
  };

  function icons(root) {
    if (window.lucide) {
      window.lucide.createIcons({ root, icons: window.lucide.icons, attrs: { 'stroke-width': 1.7 } });
    }
  }

  function button(label, name, action, className = '') {
    const element = node(`<button type="button" class="cv-button ${escape(className)}">${name ? icon(name) : ''}<span>${escape(label)}</span></button>`);
    element.addEventListener('click', action);
    icons(element);
    return element;
  }

  const statusLabel = status => ({
    running: '进行中',
    completed: '已完成',
    stopped: '已停止',
    failed: '失败',
    stopping: '正在停止',
    waiting: '等待调度',
    idle: '空闲'
  })[status] || '';

  const selectedInside = element => {
    const selection = window.getSelection();
    return selection && !selection.isCollapsed && (element.contains(selection.anchorNode) || element.contains(selection.focusNode));
  };

  function renderInlineMarkdown(value) {
    const singleLine = String(value ?? '').replace(/[\r\n]+/g, ' ').trim();
    if (!singleLine) return '';
    const headingMatch = singleLine.match(/^#{1,6}\s+(.*)$/);
    const normalized = headingMatch ? `**${headingMatch[1].trim()}**` : singleLine;
    if (window.marked?.parseInline && window.DOMPurify?.sanitize) {
      return window.DOMPurify.sanitize(window.marked.parseInline(normalized, { gfm: true, async: false }), {
        ALLOWED_TAGS: ['strong', 'b', 'em', 'i', 'code', 'del', 's'],
        ALLOWED_ATTR: []
      });
    }
    return escape(normalized);
  }

  class SelectableContent {
    constructor(element, render) {
      this.element = element;
      this.render = render;
      this.value = null;
      this.pending = null;
    }
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

  const kinds = {
    thinking: { icon: 'brain', label: '思考' },
    read: { icon: 'file-text', label: '读取' },
    readImage: { icon: 'images', label: '图片' },
    command: { icon: 'terminal', label: '命令' },
    search: { icon: 'search', label: '搜索' },
    edit: { icon: 'file-pen-line', label: '修改' },
    wait: { icon: 'users', label: '等待' }
  };

  function renderImageThumbStrip(images, actions) {
    const strip = node('<div class="cv-image-strip" role="list" aria-label="已查看的图片缩略图"></div>');
    const validImages = (images || []).filter(img => !img.failed && img.url);
    const previewList = validImages.map((img, idx) => ({
      id: img.id,
      name: img.label || `图片 ${idx + 1}`,
      sourceLabel: validImages.length > 1 ? `已查看图片 (${idx + 1}/${validImages.length})` : '已查看图片',
      dimensions: img.dimensions || '',
      caption: img.caption || '',
      url: img.url
    }));

    (images || []).forEach((img, index) => {
      if (img.failed || !img.url) {
        strip.append(node(`
          <div
            class="cv-read-thumb is-failed"
            role="listitem"
            aria-label="图片读取失败"
            title="${escape(img.errorHint || '图片读取失败')}">
            <span>失败</span>
          </div>
        `));
        return;
      }
      const label = img.label || `图片 ${index + 1}`;
      const thumb = node(`
        <button
          type="button"
          class="cv-read-thumb"
          role="listitem"
          title="点击查看大图"
          aria-label="查看大图：${escape(label)}">
          <img src="${escape(img.url)}" alt="${escape(label)}">
        </button>
      `);
      thumb.addEventListener('click', () => actions.previewImage?.(previewList, img.id, thumb));
      strip.append(thumb);
    });
    return strip;
  }

  const describe = member => member.kind === 'thinking'
    ? '思考：' + (member.summary || member.title)
    : member.kind === 'readImage'
      ? member.title
      : member.title + (member.target ? ' ' + member.target : '');

  function groupText(group) {
    return [
      `工作组 · ${group.members.length} 步 · ${group.elapsed}s`,
      ...group.members.map(member => [
        `${member.summary || member.title}${member.kind !== 'readImage' && member.target ? ' · ' + member.target : ''} · ${statusLabel(member.status)} · ${member.elapsed}s`,
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
        <span class="cv-member-meta cv-tabular"></span><span class="cv-sr-only"></span>
      </${member.kind === 'thinking' ? 'div' : 'summary'}>`);
      this.symbol = this.head.querySelector('.cv-member-symbol');
      this.label = this.head.querySelector('.cv-member-label');
      this.meta = this.head.querySelector('.cv-member-meta');
      this.statusText = this.head.querySelector('.cv-sr-only');
      this.verb = node(`<span class="cv-member-verb">${escape(member.title)}</span>`);
      this.label.append(this.verb);
      if (member.kind !== 'readImage' && member.target) {
        this.label.append(node(`<code class="cv-target" title="${escape(member.path || member.target)}">${escape(member.target)}</code>`));
      }
      this.chevron = node(`<span class="cv-chevron">${icon('chevron-right')}</span>`);
      this.label.append(this.chevron);
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
          this.log.textContent = value;
        });
        this.exit = node('<div class="cv-detail-meta"></div>');
        this.body.append(this.log, this.exit);
      } else if (member.kind === 'read') {
        this.body.append(
          node(`<div class="cv-file-path">${escape(member.path)}</div>`),
          node(`<pre class="cv-file-preview">${escape(member.content)}</pre>`)
        );
        this.body.append(button('查看全文', 'maximize-2', () => actions.detail(member.target, member.content, member.path), 'cv-quiet'));
      } else if (member.kind === 'readImage') {
        this.body.append(renderImageThumbStrip(member.images || [], actions));
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
      const thinking = member.kind === 'thinking';
      const hasContent = Boolean(member.content?.trim());
      const elapsed = Number.isFinite(member.elapsed) && member.elapsed >= 0
        ? member.elapsed < 1 ? '不到 1 秒'
          : member.elapsed < 60 ? `${member.elapsed} 秒`
          : `${Math.floor(member.elapsed / 60)} 分${member.elapsed % 60 ? ` ${member.elapsed % 60} 秒` : ''}`
        : null;
      const summaryText = thinking ? member.summary?.trim() : '';
      const label = thinking
        ? (elapsed ? `思考了 ${elapsed}` : member.status === 'running' ? '思考中' : '思考结束')
        : member.title;
      if (summaryText) {
        const rendered = renderInlineMarkdown(summaryText);
        if (this.verbHtml !== rendered) {
          this.verbHtml = rendered;
          this.verb.innerHTML = rendered;
        }
        this.verb.title = this.verb.textContent;
      } else {
        this.verbHtml = null;
        if (this.verb.textContent !== label) this.verb.textContent = label;
        this.verb.title = label;
      }
      if (thinking) {
        const expandable = hasContent;
        this.chevron.hidden = !expandable;
        if (expandable !== (this.node.tagName === 'DETAILS')) {
          const replacement = document.createElement(expandable ? 'details' : 'section');
          for (const attribute of this.node.attributes) replacement.setAttribute(attribute.name, attribute.value);
          const heading = document.createElement(expandable ? 'summary' : 'div');
          heading.className = this.head.className;
          heading.append(...this.head.childNodes);
          this.head.replaceWith(heading);
          this.head = heading;
          replacement.append(...this.node.childNodes);
          this.node.replaceWith(replacement);
          this.node = replacement;
        }
        this.body.hidden = !hasContent;
        this.markdown.update(member.content || '');
      }
      if (this.status !== member.status) {
        this.status = member.status;
        if (member.status === 'running') {
          this.symbol.innerHTML = spinner();
        } else {
          const kindIcon = kinds[member.kind]?.icon || 'wrench';
          this.symbol.innerHTML = icon(member.status === 'failed' ? 'circle-alert' : member.status === 'stopped' ? 'square' : kindIcon);
          icons(this.symbol);
        }
        this.node.dataset.status = member.status;
        this.statusText.textContent = statusLabel(member.status);
      }
      const interrupted = member.status === 'failed' || member.status === 'stopped' ? statusLabel(member.status) + ' · ' : '';
      this.meta.textContent = thinking ? '' : interrupted + member.elapsed + 's';
      if (this.logContent) {
        this.logContent.update(member.output);
        this.exit.textContent = member.exitCode === null ? '正在接收输出' : '退出码 ' + member.exitCode;
      }
      if (this.targets) {
        const signature = JSON.stringify(member.targets);
        if (signature !== this.signature) {
          this.signature = signature;
          this.targets.replaceChildren(...member.targets.map(target => {
            const targetIcon = target.status === 'failed'
              ? 'circle-alert'
              : target.status === 'stopped'
                ? 'square'
                : (target.icon || 'git-fork');
            const sym = target.status === 'running' ? spinner() : icon(targetIcon);
            const row = node(`<div class="cv-wait-target"><span class="cv-status-symbol" data-status="${escape(target.status)}">${sym}</span><div><b>${escape(target.name)}</b><span>${escape(target.task)}</span></div><span class="cv-wait-state">${statusLabel(target.status)}</span></div>`);
            if (target.status === 'completed') row.append(button('查看报告', 'arrow-up-right', () => this.actions.detail(target.name + ' 的报告', target.report), 'cv-quiet'));
            return row;
          }));
          icons(this.targets);
        }
      }
    }
    flush() { this.logContent?.flush(); this.markdown?.flush(); }
  }

  function groupHeading(mode = 'history', indicatorStyle = 'restingCat') {
    return node(`<summary class="cv-group-heading">
      ${mode === 'live' ? activityIndicator(indicatorStyle) : ''}<span class="cv-group-title"></span>
      ${mode === 'live' ? '<span class="cv-group-current" hidden></span>' : ''}
      <span class="cv-group-meta cv-tabular"></span><span class="cv-chevron">${icon('chevron-right')}</span>
    </summary>`);
  }

  function groupElapsedLabel(seconds, prefix) {
    if (!Number.isFinite(seconds) || seconds < 0) return '';
    const whole = Math.floor(seconds);
    if (whole === 0) return `${prefix}不到 1 秒`;
    const minutes = Math.floor(whole / 60);
    const remainder = whole % 60;
    if (!minutes) return `${prefix} ${remainder} 秒`;
    return `${prefix} ${minutes} 分${remainder ? ` ${remainder} 秒` : ''}`;
  }

  function groupDigest(group) {
    const digest = node('<span class="cv-group-digest"></span>');
    Object.entries(kinds).forEach(([kind, info]) => {
      const count = group.members.filter(member => member.kind === kind).length;
      if (count) digest.append(node(`<span class="cv-kind-chip" title="${escape(info.label)} ${count}" aria-label="${escape(info.label)} ${count}">${icon(info.icon)}<span aria-hidden="true">${count}</span></span>`));
    });
    ['failed', 'stopped'].forEach(status => {
      const count = group.members.filter(member => member.status === status).length;
      if (count) digest.append(node(`<span class="cv-issue-chip" data-status="${status}">${count} 步${escape(statusLabel(status))}</span>`));
    });
    return digest;
  }

  class WorkGroupView {
    constructor(group, mode, actions, expanded = false) {
      this.mode = mode;
      this.actions = actions;
      this.node = node(`<details class="cv-work-group cv-group-${escape(mode)}" data-history-kind="workGroup"><div class="cv-group-rail"></div></details>`);
      this.node.prepend(groupHeading(mode));
      this.node.open = expanded;
      this.indicator = this.node.querySelector('.cv-activity-indicator');
      this.title = this.node.querySelector('.cv-group-title');
      this.currentStep = this.node.querySelector('.cv-group-current');
      this.meta = this.node.querySelector('.cv-group-meta');
      this.rail = this.node.querySelector('.cv-group-rail');
      this.members = [];
      if (mode === 'history') {
        this.title.textContent = groupElapsedLabel(group.elapsed, '工作了') || '工作记录';
        this.meta.append(groupDigest(group));
        const footer = node('<div class="cv-group-actions"></div>');
        footer.append(button('复制工作记录', 'copy', () => actions.copy(groupText(this.current)), 'cv-quiet'));
        this.node.append(footer);
      }
      this.update(group);
      icons(this.node);
    }
    update(group) {
      this.current = group;
      const follow = this.rail.scrollHeight - this.rail.scrollTop - this.rail.clientHeight < 22;
      const added = group.members.slice(this.members.length).map(member => new MemberView(member, this.mode, this.actions));
      added.forEach(view => { this.members.push(view); this.rail.append(view.node); });
      this.members.forEach((view, index) => view.update(group.members[index]));
      if (added.length && follow) this.rail.scrollTop = this.rail.scrollHeight;
      this.node.dataset.status = group.status;
      if (this.mode !== 'live') return;
      const running = group.members.filter(member => member.status === 'running');
      const runningExec = running.some(member => member.kind === 'command');
      const latestThought = group.members
        .filter(member => member.kind === 'thinking' && member.summary?.trim())
        .at(-1)?.summary?.trim();
      const indicatorStyle = (!latestThought && runningExec) ? 'circularProgress' : 'restingCat';
      if (this.indicator && this.indicator.dataset.style !== indicatorStyle) {
        const nextIndicator = node(activityIndicator(indicatorStyle));
        this.indicator.replaceWith(nextIndicator);
        this.indicator = nextIndicator;
      }
      this.node.dataset.phase = running.length ? 'working' : 'thinking';
      if (latestThought) {
        const rendered = renderInlineMarkdown(latestThought);
        if (this.titleHtml !== rendered) {
          this.titleHtml = rendered;
          this.title.innerHTML = rendered;
        }
        this.title.title = this.title.textContent;
      } else {
        this.titleHtml = null;
        const fallbackTitle = running.length
          ? (runningExec ? describe(running.find(member => member.kind === 'command')) : describe(running[0]))
          : '思考中';
        if (this.title.textContent !== fallbackTitle) this.title.textContent = fallbackTitle;
        this.title.title = fallbackTitle;
      }
      if (this.currentStep) {
        this.currentStep.textContent = '';
        this.currentStep.hidden = true;
      }
      this.meta.textContent = groupElapsedLabel(group.elapsed, '执行了');
    }
    flush() { this.members.forEach(member => member.flush()); }
  }

  function historyItem(item, actions) {
    if (item.kind === 'workGroup') return new WorkGroupView(item, 'history', actions).node;
    if (item.kind === 'imageRead') {
      const images = item.images || [];
      const titleText = item.title || `查看了 ${images.length} 张图片`;
      const element = node(`
        <details class="cv-timeline-step cv-image-read" data-history-kind="imageRead">
          <summary class="cv-timeline-step-summary">
            <span class="cv-timeline-step-icon">${icon('images')}</span>
            <span class="cv-timeline-step-label">${escape(titleText)}</span>
            <span class="cv-chevron">${icon('chevron-down')}</span>
          </summary>
        </details>
      `);
      element.open = Boolean(item.expanded);
      element.append(renderImageThumbStrip(images, actions));
      return element;
    }
    if (item.kind === 'commandStep') {
      const element = node(`
        <details class="cv-timeline-step cv-command-step" data-history-kind="commandStep">
          <summary class="cv-timeline-step-summary">
            <span class="cv-timeline-step-icon">${icon('square-terminal')}</span>
            <span class="cv-timeline-step-label">${escape(item.title || '运行了命令')}</span>
            <span class="cv-chevron">${icon('chevron-down')}</span>
          </summary>
          <div class="cv-command-step-body">
            <div class="cv-detail-meta"><code>$ ${escape(item.command || '')}</code><span>退出码 ${escape(item.exitCode ?? 0)}</span></div>
            <pre class="cv-terminal">${escape(item.output || '')}</pre>
          </div>
        </details>
      `);
      element.open = Boolean(item.expanded);
      return element;
    }
    if (item.kind === 'outcome') {
      const element = node(`<details class="cv-history-outcome cv-group-history" data-history-kind="outcome" data-status="${escape(item.status)}"><div class="cv-group-rail"></div></details>`);
      const heading = groupHeading();
      const title = item.status === 'failed' ? '执行失败' : '已停止';
      heading.querySelector('.cv-group-title').textContent = title;
      element.prepend(heading);
      const body = element.querySelector('.cv-group-rail');
      const explanation = item.error || (item.subject === '上下文压缩'
        ? '上下文压缩已停止，原始历史保持不变。'
        : item.subject === '模型响应' ? '等待模型响应已停止，可以通过主按钮继续。'
        : '本次执行已停止，已保留停止前生成的内容。');
      body.append(
        node(`<div class="cv-detail-meta">${escape(item.subject)}</div>`),
        node(`<p class="${item.status === 'failed' ? 'cv-group-error' : 'cv-outcome-description'}">${escape(explanation)}</p>`)
      );
      if (item.status === 'failed' && item.subject === '上下文压缩') {
        body.append(node('<p class="cv-outcome-description">压缩可通过底部上下文详情重新发起。</p>'));
      }
      body.append(button('复制说明', 'copy', () => actions.copy([title, item.subject, explanation].join('\n')), 'cv-quiet'));
      return element;
    }
    if (item.kind === 'compression') {
      return node(`<div class="cv-compression-receipt" data-history-kind="compression">${icon('check')}<span>已完成压缩</span>${item.time ? `<time>${escape(item.time)}</time>` : ''}</div>`);
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
      const imageFiles = (item.attachments || []).filter(f => f.kind === 'image' && f.url);
      const otherFiles = (item.attachments || []).filter(f => !(f.kind === 'image' && f.url));
      if (imageFiles.length) {
        const thumbs = node('<div class="cv-history-thumbs"></div>');
        imageFiles.forEach(img => {
          const btn = node(`
            <button
              type="button"
              class="cv-att-thumb-btn is-history-thumb"
              title="${escape(img.name)} · 点击弹层查看大图"
              aria-label="查看图片大图 ${escape(img.name)}">
              <img src="${escape(img.url)}" alt="${escape(img.name)}">
              <span class="cv-att-thumb-zoom" aria-hidden="true">${icon('zoom-in')}</span>
            </button>
          `);
          btn.addEventListener('click', () => actions.previewImage?.(imageFiles, img.id, btn));
          thumbs.append(btn);
        });
        content.append(thumbs);
      }
      if (item.text) {
        content.append(node(`<div class="cv-user-text">${escape(item.text)}</div>`));
      }
      if (otherFiles.length) {
        const files = node('<div class="cv-history-files"></div>');
        otherFiles.forEach(file => {
          const itemNode = file.url
            ? node(`<a href="${escape(file.url)}" target="_blank" rel="noopener noreferrer">${icon('paperclip')}${escape(file.name)}</a>`)
            : node(`<span>${icon('paperclip')}${escape(file.name)}</span>`);
          files.append(itemNode);
        });
        content.append(files);
      }
    } else {
      new MarkdownView(content, actions).update(item.text);
    }
    const footer = element.querySelector('.cv-message-footer');
    if (item.hideFooter) {
      footer.remove();
    } else {
      const authorLabel = item.kind === 'user' ? (item.author || '你') : (item.author || '糊来帮');
      footer.append(node(`<span>${escape(authorLabel)}${item.time ? ' · ' + escape(item.time) : ''}</span>`));
      footer.append(button('复制', 'copy', () => actions.copy(item.text), 'cv-quiet'));
    }
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
      const controller = this.controller;
      const hasStashedDraft = Boolean(controller.state.draft.trim() || controller.state.attachments.length);
      const key = [pending.id, pending.index, hasStashedDraft].join(':');
      if (key === this.key) return;
      this.key = key;
      this.node.replaceChildren();
      const header = node(`<div class="cv-dock-header"><span class="cv-dock-symbol">${icon('message-circle-question')}</span><div><b>${escape(pending.title)}</b><span>待决提问期间输入框暂时收起，回答后会保留为只读历史回执</span></div></div>`);
      header.append(button('停止', 'square', () => controller.stop(), 'cv-quiet'));
      this.node.append(header);
      if (hasStashedDraft) {
        this.node.append(node(`<div class="cv-draft-stash-note">${icon('info')}<span>你未发送的输入草稿已自动暂存，提交答案或跳过后将原样恢复。</span></div>`));
      }
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
      const other = node(`<label class="cv-field-label">补充说明（可选）<input class="cv-text-input" type="text" value="${escape(pending.others[pending.index])}" placeholder="也可以写下你的补充要求"></label>`);
      other.querySelector('input').addEventListener('input', event => controller.pendingText('other', event.target.value));
      this.node.append(other);
      if (question.secret) {
        const secret = node(`<label class="cv-field-label">敏感备注（可选）<input class="cv-text-input" type="password" autocomplete="off" value="${escape(pending.secret)}" placeholder="内容不会进入历史回执或复制结果"></label>`);
        secret.querySelector('input').addEventListener('input', event => controller.pendingText('secret', event.target.value));
        this.node.append(secret);
      }
      const footer = node('<div class="cv-dock-footer"></div>');
      footer.append(button('跳过', '', () => controller.resolve('skip'), 'cv-quiet'));
      const previous = button('上一题', 'chevron-left', () => controller.questionPage(-1), 'cv-tonal');
      previous.disabled = pending.index === 0;
      footer.append(previous, pending.index === pending.questions.length - 1
        ? button('提交答案', 'check', () => controller.resolve('answer'), 'cv-primary')
        : button('下一题', 'chevron-right', () => controller.questionPage(1), 'cv-primary'));
      this.node.append(footer);
      icons(this.node);
    }
  }

  app.ui = {
    escape,
    node,
    icon,
    spinner,
    activityIndicator,
    icons,
    button,
    statusLabel,
    MarkdownView,
    WorkGroupView,
    PendingView,
    historyItem,
    groupText,
    selectedInside
  };
})();
