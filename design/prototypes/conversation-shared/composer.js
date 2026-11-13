(() => {
  'use strict';
  const app = window.AnyworkConversation;
  const { escape, node, icon, spinner, icons, statusLabel } = app.ui;

  // 列表只显示短状态词；长说明不参与固定列的排版。
  const agentStatusLabels = {
    running: '运行中', completed: '完成', stopped: '待调度',
    failed: '失败', stopping: '停止中', waiting: '待调度', idle: '空闲',
    queued: '排队中', closing: '关闭中', closed: '已关闭',
    unknown: '未确认', approval: '待批准', input: '待输入'
  };
  const agentStatusDetails = {
    waiting: '已停止，等待主智能体调度',
    stopped: '已停止，等待主智能体调度',
    unknown: '上次操作尚未确认，请检查会话状态后再重试',
    approval: '等待批准工具执行',
    input: '等待用户输入'
  };

  /* ========================================================================
     1. Popover Menu Manager (Single Active Menu + Viewport Auto-Flip)
     ======================================================================== */
  class MenuManager {
    constructor(root, getWindowEl) {
      this.root = root;
      this.getWindowEl = getWindowEl;
      this.openId = null;
      this.projectSearchQuery = '';
      this.modelSearchQuery = '';
    }

    closeAll() {
      if (!this.openId) return;
      this.openId = null;
      this.projectSearchQuery = '';
      this.modelSearchQuery = '';
      this.root.querySelectorAll('.cv-menu').forEach(menu => { menu.hidden = true; });
      this.root.querySelectorAll('[data-menu-trigger][aria-expanded]').forEach(btn => {
        btn.setAttribute('aria-expanded', 'false');
      });
    }

    open(menuId, triggerEl, menuEl, preferUp = false) {
      if (!triggerEl || !menuEl) return;
      this.openId = menuId;
      triggerEl.setAttribute('aria-expanded', 'true');
      menuEl.hidden = false;

      const winEl = this.getWindowEl();
      if (winEl) {
        const winRect = winEl.getBoundingClientRect();
        const trigRect = triggerEl.getBoundingClientRect();
        const spaceBelow = winRect.bottom - trigRect.bottom;
        const spaceAbove = trigRect.top - winRect.top;
        const minBelow = preferUp ? 280 : (menuId === 'project' ? 230 : 210);
        const shouldOpenUp = spaceBelow < minBelow && spaceAbove > spaceBelow;
        menuEl.classList.toggle('open-up', shouldOpenUp);
      }
    }

    toggle(menuId, triggerEl, menuEl, preferUp = false) {
      if (!triggerEl || !menuEl) return;
      const wasOpen = this.openId === menuId && !menuEl.hidden;
      this.closeAll();
      if (wasOpen) return;
      this.open(menuId, triggerEl, menuEl, preferUp);
    }

    restoreIfOpen(menuId, triggerEl, menuEl, preferUp = false) {
      if (this.openId !== menuId) return;
      if (!triggerEl || !menuEl) {
        this.openId = null;
        return;
      }
      this.open(menuId, triggerEl, menuEl, preferUp);
    }
  }

  /* ========================================================================
     2. Shared Studio Shell: Context-Aware Topbar (Sidebar lives in sidebar-shared/)
     ======================================================================== */
  function hostLogoOrIcon(appKey, fallbackIcon) {
    if (window.AnyworkSidebar?.hostAppLogo) {
      return window.AnyworkSidebar.hostAppLogo(appKey);
    }
    return icon(fallbackIcon);
  }

  function renderTopbar(leftHost, rightHost, topbarEl, controller, menuManager, helpers) {
    const s = controller.state;
    const isSession = s.stage === 'session';
    topbarEl.classList.toggle('is-session', isSession);

    if (!isSession) {
      const proj = controller.currentProject();
      leftHost.innerHTML = `
        <button type="button" class="cv-icon-btn" data-shell-action="toggle-sidebar" title="切换项目侧边栏" aria-label="切换项目侧边栏">
          ${icon('panel-left')}
        </button>
        <div class="cv-topbar-crumb">
          <span>新会话</span>
          <span>·</span>
          <strong>${escape(proj ? proj.name : '无项目')}</strong>
          ${proj?.sshAlias ? `<span class="cv-ssh-pill">SSH · ${escape(proj.sshAlias)}</span>` : ''}
        </div>
      `;
      rightHost.innerHTML = '';
      icons(topbarEl);
      return;
    }

    const ft = s.frozenThread;
    const agent = controller.currentAgent();
    const isSubagent = !agent.isRoot;
    const activeAgentsCount = s.agents.length;
    const hasRunningChild = s.agents.some(a => !a.isRoot && a.status === 'running');
    const wsShort = ft.workspaceMode === 'worktree'
      ? `独立工作树${ft.branch ? ' · ' + ft.branch.replace('anywork/', '') : ''}`
      : '本地目录';

    leftHost.innerHTML = `
      <button type="button" class="cv-icon-btn" data-shell-action="toggle-sidebar" title="切换项目侧边栏" aria-label="切换项目侧边栏">
        ${icon('panel-left')}
      </button>
      ${isSubagent ? `
        <button type="button" class="cv-topbar-back-btn" data-shell-action="back-to-root" title="返回主会话">
          ${icon('arrow-left')}
          <span>主会话</span>
        </button>
      ` : ''}
      <div class="cv-topbar-title-wrap">
        ${isSubagent ? `
          <span class="cv-subagent-badge" title="当前正在只读查看子智能体会话">
            ${icon('git-fork')}
            <span>${escape(agent.role)}</span>
          </span>
        ` : ''}
        <strong class="cv-session-title" title="${escape(isSubagent ? agent.title : ft.title)}">
          ${escape(isSubagent ? agent.title : ft.title)}
        </strong>
      </div>
      <div class="cv-frozen-bar" aria-label="创建时固定的会话环境配置">
        <span
          class="cv-frozen-chip ${ft.workspaceMode === 'worktree' ? 'is-worktree' : ''}"
          title="所属项目：${escape(ft.projectName)} · 会话创建时已固定工作区模式（只读）：${escape(ft.workspacePath)}">
          ${icon(ft.workspaceMode === 'worktree' ? 'git-branch' : 'folder')}
          <span>${ft.sshAlias ? `SSH:${escape(ft.sshAlias)} · ` : ''}${escape(wsShort)}</span>
        </span>
        ${!isSubagent ? (ft.backendKind === 'acp' ? `
          <span
            class="cv-frozen-chip is-acp"
            title="外部智能体：${escape(ft.acpAccountName || 'ACP')}">
            <span class="cv-acp-mark is-sm" style="background:${escape(ft.acpColor || '#55798C')}">${escape(ft.acpBadgeText || 'ACP')}</span>
            <span>${escape(ft.acpAccountName || 'Agent')}</span>
          </span>
        ` : `
          <span
            class="cv-frozen-chip cv-frozen-delegation"
            title="子智能体分发：${escape(ft.delegationSummary)}">
            ${icon('sliders-horizontal')}
            <span>${escape(ft.delegationSummary)}</span>
          </span>
        `) : ''}
      </div>
    `;

    const workspacePathForOpen = isSubagent ? agent.workspacePath : ft.workspacePath;

    rightHost.innerHTML = `
      <div class="cv-menu-anchor">
        <button
          type="button"
          class="cv-quiet-trigger is-topbar-btn ${hasRunningChild ? 'has-running-child' : ''}"
          data-menu-trigger="agents"
          aria-haspopup="menu"
          aria-expanded="false"
          title="会话智能体">
          ${icon('users')}
          <span class="cv-tabular">${activeAgentsCount} 个智能体</span>
          <span class="cv-caret">${icon('chevron-down')}</span>
        </button>
        <div class="cv-menu cv-menu-agents align-right" data-menu-panel="agents" role="menu" hidden>
          <div class="cv-menu-head">
            <span>会话智能体</span>
          </div>
          <div class="cv-agent-list">
            ${s.agents.map(ag => {
              const selected = ag.id === s.activeAgentId;
              const canStop = !ag.isRoot && ag.status === 'running';
              const isStopping = !ag.isRoot && ag.status === 'stopping';
              return `
                <div class="cv-agent-row ${selected ? 'is-selected' : ''}">
                  <button type="button" class="cv-agent-select-btn" data-select-agent="${escape(ag.id)}">
                    <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
                    <div class="cv-item-main">
                      <div class="cv-item-title">${escape(ag.title)}</div>
                      <div class="cv-item-sub">${escape(ag.role)} · ${escape(ag.routeLabel)}</div>
                    </div>
                  </button>
                  <span class="cv-agent-state-pill" data-status="${escape(ag.status)}"
                    title="${escape(ag.error || agentStatusDetails[ag.status] || statusLabel(ag.status))}"
                    >${escape(agentStatusLabels[ag.status] || statusLabel(ag.status))}</span>
                  <span class="cv-agent-action-slot">
                    ${canStop ? `
                      <button
                        type="button"
                        class="cv-agent-stop-btn"
                        data-stop-agent="${escape(ag.id)}"
                        title="停止该子智能体（不切换当前页面）"
                        aria-label="停止 ${escape(ag.role)}">
                        ${icon('square')}
                      </button>
                    ` : isStopping ? `
                      <span class="cv-agent-stopping-spin" title="正在停止该子智能体">${spinner()}</span>
                    ` : ''}
                  </span>
                </div>
              `;
            }).join('')}
          </div>
        </div>
      </div>

      <div class="cv-menu-anchor">
        <button
          type="button"
          class="cv-quiet-trigger is-topbar-btn"
          data-menu-trigger="open-ws"
          aria-haspopup="menu"
          aria-expanded="false"
          title="在外部编辑器或终端中打开会话工作区：${escape(workspacePathForOpen)}">
          ${icon('external-link')}
          <span>打开工作区</span>
          <span class="cv-caret">${icon('chevron-down')}</span>
        </button>
        <div class="cv-menu align-right" data-menu-panel="open-ws" role="menu" hidden>
          <div class="cv-menu-head"><span>打开会话工作区</span></div>
          <button type="button" class="cv-menu-item" data-open-ws="VS Code">
            ${hostLogoOrIcon('vscode', 'code')}
            <span class="cv-item-main">在 VS Code 中打开</span>
          </button>
          <button type="button" class="cv-menu-item" data-open-ws="Zed">
            ${hostLogoOrIcon('zed', 'sparkles')}
            <span class="cv-item-main">在 Zed 中打开</span>
          </button>
          <button type="button" class="cv-menu-item" data-open-ws="终端">
            ${hostLogoOrIcon('terminal', 'terminal')}
            <span class="cv-item-main">在终端中打开</span>
          </button>
          <div class="cv-menu-divider"></div>
          <button type="button" class="cv-menu-item" data-copy-ws="${escape(workspacePathForOpen)}">
            ${icon('copy')}
            <span class="cv-item-main">复制工作区路径</span>
          </button>
        </div>
      </div>
    `;

    // Bind topbar menu triggers & actions
    topbarEl.querySelectorAll('[data-menu-trigger]').forEach(trig => {
      const id = trig.dataset.menuTrigger;
      const panel = topbarEl.querySelector(`[data-menu-panel="${id}"]`);
      trig.addEventListener('click', () => menuManager.toggle(id, trig, panel, false));
      menuManager.restoreIfOpen(id, trig, panel, false);
    });

    topbarEl.querySelectorAll('[data-select-agent]').forEach(btn => {
      btn.addEventListener('click', () => {
        menuManager.closeAll();
        controller.switchAgent(btn.dataset.selectAgent);
      });
    });

    topbarEl.querySelectorAll('[data-stop-agent]').forEach(btn => {
      btn.addEventListener('click', event => {
        event.stopPropagation();
        controller.stopSubagent(btn.dataset.stopAgent);
      });
    });

    topbarEl.querySelectorAll('[data-open-ws]').forEach(btn => {
      btn.addEventListener('click', () => {
        menuManager.closeAll();
        helpers.toast(`已请求在 ${btn.dataset.openWs} 中打开：${workspacePathForOpen}`);
      });
    });

    topbarEl.querySelectorAll('[data-copy-ws]').forEach(btn => {
      btn.addEventListener('click', () => {
        menuManager.closeAll();
        helpers.copy(btn.dataset.copyWs);
      });
    });

    icons(topbarEl);
  }

  function renderAcpBrandMark(account, sizeClass = '') {
    if (!account) return '';
    const bg = account.color || '#55798C';
    const label = account.badge || account.badgeText || 'AC';
    return `<span class="cv-acp-mark ${sizeClass}" style="background:${escape(bg)}" aria-hidden="true">${escape(label)}</span>`;
  }

  function renderAcpOptionRows(options, currentValue) {
    return options.map(opt => {
      const selected = opt.value === currentValue;
      return `
        <button type="button" class="cv-menu-item ${selected ? 'is-selected' : ''}" data-pick-acp-model="${escape(opt.value)}">
          <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
          <span class="cv-item-main cv-mono-tight">${escape(opt.name || opt.value)}</span>
        </button>
      `;
    }).join('');
  }

  function renderAcpModelSectionHTML(schema, query) {
    const slot = schema.modelSlot;
    const acc = schema.account;
    if (!slot || !acc) return '';
    const q = String(query || '').trim().toLowerCase();
    const matchOpt = opt => !q
      || String(opt.name || '').toLowerCase().includes(q)
      || String(opt.value || '').toLowerCase().includes(q);

    let listHtml = '';
    let matchedCount = 0;

    if (slot.groups && slot.groups.length) {
      const filteredGroups = slot.groups
        .map(g => ({ group: g.group, options: g.options.filter(matchOpt) }))
        .filter(g => g.options.length > 0);
      matchedCount = filteredGroups.reduce((accSum, g) => accSum + g.options.length, 0);
      listHtml = filteredGroups.map(g => `
        <div class="cv-menu-subhead"><span>${escape(g.group)}</span></div>
        ${renderAcpOptionRows(g.options, slot.currentValue)}
      `).join('');
    } else {
      const filtered = (slot.flatOptions || []).filter(matchOpt);
      matchedCount = filtered.length;
      listHtml = renderAcpOptionRows(filtered, slot.currentValue);
    }

    const total = slot.totalCount || (slot.flatOptions || []).length;
    const countBadge = q ? `${matchedCount}/${total}` : '';

    if (!matchedCount) {
      return `
        <div class="cv-menu-head">
          <span>${escape(acc.name)}</span>
          ${countBadge ? `<small>${escape(countBadge)}</small>` : ''}
        </div>
        <div class="cv-menu-empty-hint">未找到匹配「${escape(query)}」的模型</div>
      `;
    }

    return `
      <div class="cv-menu-head">
        <span>${escape(acc.name)}</span>
        ${countBadge ? `<small>${escape(countBadge)}</small>` : ''}
      </div>
      ${listHtml}
    `;
  }

  function renderNativeGroupsHTML(currentModelId, isNativeActive, query) {
    const q = String(query || '').trim().toLowerCase();
    const htmlParts = [];
    app.fixtures.accountGroups.forEach(grp => {
      const models = grp.models.filter(m =>
        !q
        || m.name.toLowerCase().includes(q)
        || grp.accountName.toLowerCase().includes(q)
        || (m.caps || []).some(c => c.toLowerCase().includes(q))
      );
      if (!models.length) return;
      htmlParts.push(`
        <div class="cv-menu-head"><span>${escape(grp.accountName)}</span></div>
        ${models.map(m => {
          const selected = isNativeActive && m.id === currentModelId;
          return `
            <button type="button" class="cv-menu-item ${selected ? 'is-selected' : ''}" data-pick-native-model="${escape(m.id)}">
              <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
              <span class="cv-item-main">${escape(m.name)}</span>
              <span class="cv-cap-badges">
                ${m.caps.map(c => `<span class="cv-cap-badge">${escape(c)}</span>`).join('')}
              </span>
            </button>
          `;
        }).join('')}
      `);
    });
    return htmlParts.join('<div class="cv-menu-divider"></div>');
  }

  function renderAcpAccountsListHTML(controller, query) {
    const s = controller.state;
    const q = String(query || '').trim().toLowerCase();
    const proj = s.targetType === 'project' ? controller.currentProject() : null;
    const isRemote = Boolean(proj?.sshAlias);
    const items = (app.fixtures.acpAccounts || []).filter(acc =>
      !q
      || acc.name.toLowerCase().includes(q)
      || acc.id.toLowerCase().includes(q)
    );
    if (!items.length) return '';
    return `
      <div class="cv-menu-head">
        <span>外部智能体</span>
      </div>
      ${items.map(acc => {
        const selected = s.backendKind === 'acp' && s.acpAccountId === acc.id;
        const sshBlocked = isRemote && !acc.supportsRemote;
        return `
          <button type="button" class="cv-menu-item ${selected ? 'is-selected' : ''}" data-pick-acp-account="${escape(acc.id)}">
            <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
            ${renderAcpBrandMark(acc)}
            <span class="cv-item-main">${escape(acc.name)}</span>
            <span class="cv-cap-badges">
              <span class="cv-cap-badge">ACP</span>
              ${sshBlocked ? '<span class="cv-cap-badge is-warn">仅本地</span>' : ''}
            </span>
          </button>
        `;
      }).join('')}
    `;
  }

  function buildModelMenuResultsHTML(controller, schema, query) {
    const s = controller.state;
    const isStart = s.stage === 'start';

    if (!isStart) {
      if (schema.kind === 'acp') {
        return renderAcpModelSectionHTML(schema, query);
      }
      const nativeBody = renderNativeGroupsHTML(s.modelId, true, query);
      return nativeBody || `<div class="cv-menu-empty-hint">未找到匹配「${escape(query)}」的模型</div>`;
    }

    const parts = [];
    if (schema.kind === 'acp' && !schema.deferred && schema.modelSlot?.kind === 'acp') {
      parts.push(renderAcpModelSectionHTML(schema, query));
    }

    const nativeHtml = renderNativeGroupsHTML(s.modelId, schema.kind === 'native', query);
    const acpAccountsHtml = renderAcpAccountsListHTML(controller, query);
    if (nativeHtml) parts.push(nativeHtml);
    if (acpAccountsHtml) parts.push(acpAccountsHtml);

    if (!parts.filter(Boolean).length) {
      return `<div class="cv-menu-empty-hint">未找到匹配「${escape(query)}」的选项</div>`;
    }
    return parts.filter(Boolean).join('<div class="cv-menu-divider"></div>');
  }

  function buildExtraMenuHTML(schema) {
    return `
      <div class="cv-menu-head">
        <span>扩展参数</span>
      </div>
      ${schema.extraOptions.map(opt => {
        if (opt.type === 'boolean') {
          const checked = Boolean(opt.currentValue);
          return `
            <div class="cv-extra-bool-row">
              <div class="cv-item-main">
                <div class="cv-item-title">${escape(opt.name)}</div>
              </div>
              <button
                type="button"
                class="cv-m3-switch ${checked ? 'is-on' : ''}"
                role="switch"
                aria-checked="${checked}"
                aria-label="${escape(opt.name)}"
                data-toggle-acp-bool="${escape(opt.id)}"
                data-next-val="${checked ? 'false' : 'true'}">
                <span class="cv-m3-switch-thumb"></span>
              </button>
            </div>
          `;
        }
        const items = opt.groups?.length
          ? opt.groups.flatMap(g => g.options)
          : (opt.options || []);
        return `
          <div class="cv-extra-group">
            <div class="cv-extra-group-head">
              <strong>${escape(opt.name)}</strong>
            </div>
            ${items.map(item => {
              const selected = item.value === opt.currentValue;
              return `
                <button
                  type="button"
                  class="cv-menu-item ${selected ? 'is-selected' : ''}"
                  data-pick-acp-extra="${escape(opt.id)}"
                  data-acp-val="${escape(item.value)}">
                  <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
                  <span class="cv-item-main">${escape(item.name || item.value)}</span>
                </button>
              `;
            }).join('')}
          </div>
        `;
      }).join('<div class="cv-menu-divider"></div>')}
    `;
  }

  /* ========================================================================
     3. Unified PromptComposerCard Component (100% Shared Between Start & Session)
     ======================================================================== */
  class PromptComposerCard {
    constructor(controller, menuManager, helpers) {
      this.controller = controller;
      this.menuManager = menuManager;
      this.helpers = helpers;
      this.node = node(`
        <div class="cv-prompt-card" aria-label="会话消息输入卡">
          <div class="cv-attachments" hidden></div>
          <textarea class="cv-textarea" rows="2" aria-label="输入消息"></textarea>
          <div class="cv-reason-region" hidden></div>
          <div class="cv-toolbar">
            <div class="cv-toolbar-left">
              <div class="cv-menu-anchor">
                <button
                  type="button"
                  class="cv-icon-btn cv-attach-trigger"
                  data-menu-trigger="attach"
                  aria-haspopup="menu"
                  aria-expanded="false"
                  title="添加附件（支持拖放文件或粘贴剪贴板图片）"
                  aria-label="添加附件">
                  ${icon('paperclip')}
                </button>
                <div class="cv-menu align-left" data-menu-panel="attach" role="menu" hidden>
                  <button type="button" class="cv-menu-item" data-attach-cmd="local">
                    ${icon('folder-open')}
                    <span class="cv-item-main">选择本地文件…</span>
                  </button>
                  <button type="button" class="cv-menu-item" data-attach-cmd="url">
                    ${icon('link-2')}
                    <span class="cv-item-main">添加远程链接…</span>
                  </button>
                  <button type="button" class="cv-menu-item" data-attach-cmd="paste">
                    ${icon('image')}
                    <span class="cv-item-main">粘贴剪贴板截图</span>
                  </button>
                </div>
              </div>
              <span class="cv-composer-status"></span>
            </div>
            <div class="cv-toolbar-right">
              <div class="cv-route-bar" role="group" aria-label="工作模式与主模型路由"></div>
              <div class="cv-action-slot"></div>
            </div>
          </div>
        </div>
      `);

      this.attachmentsEl = this.node.querySelector('.cv-attachments');
      this.textarea = this.node.querySelector('.cv-textarea');
      this.reasonEl = this.node.querySelector('.cv-reason-region');
      this.statusEl = this.node.querySelector('.cv-composer-status');
      this.routeBarEl = this.node.querySelector('.cv-route-bar');
      this.actionSlotEl = this.node.querySelector('.cv-action-slot');
      this.attachSignature = '';
      this.routeSignature = '';
      this.actionSignature = '';

      this.bindCardEvents();
      icons(this.node);
    }

    bindCardEvents() {
      const attachTrigger = this.node.querySelector('[data-menu-trigger="attach"]');
      const attachPanel = this.node.querySelector('[data-menu-panel="attach"]');
      attachTrigger.addEventListener('click', () => {
        this.menuManager.toggle('attach', attachTrigger, attachPanel, true);
      });

      this.node.querySelectorAll('[data-attach-cmd]').forEach(btn => {
        btn.addEventListener('click', () => {
          const cmd = btn.dataset.attachCmd;
          this.menuManager.closeAll();
          if (cmd === 'local') this.helpers.openFilePicker();
          else if (cmd === 'url') this.helpers.openUrlDialog();
          else if (cmd === 'paste') {
            if (this.controller.addPastedImage()) {
              this.helpers.toast('已粘贴图片缩略图（点击缩略图可弹层查看大图）');
            } else {
              this.helpers.toast(this.controller.state.lockNotice || '当前外部智能体不支持图片输入');
            }
          }
        });
      });

      this.textarea.addEventListener('input', () => {
        this.controller.setDraft(this.textarea.value);
        this.syncTextareaHeight();
      });

      this.textarea.addEventListener('keydown', event => {
        if (event.isComposing || event.keyCode === 229) return;
        if (event.key === 'Enter' && !event.shiftKey && !event.ctrlKey && !event.altKey && !event.metaKey) {
          event.preventDefault();
          const action = this.controller.getPrimaryAction();
          // §19.11: Pressing Enter on empty input does NOT trigger Continue!
          if ((action.kind === 'send' || action.kind === 'sendAndContinue') && action.enabled) {
            this.helpers.onSubmitFromComposer();
          }
        }
      });

      this.textarea.addEventListener('paste', event => {
        const items = Array.from(event.clipboardData?.items || []);
        const imageItems = items.filter(i => i.type.startsWith('image/'));
        if (imageItems.length) {
          event.preventDefault();
          const files = imageItems.map(i => i.getAsFile()).filter(Boolean);
          const ok = files.length
            ? this.controller.attach(files, { source: 'clipboard' })
            : this.controller.addPastedImage();
          if (ok) {
            this.helpers.toast('已粘贴图片缩略图（点击缩略图可弹层查看大图）');
          } else {
            this.helpers.toast(this.controller.state.lockNotice || '当前外部智能体不支持图片输入');
          }
        }
      });

      this.node.addEventListener('dragover', event => {
        event.preventDefault();
        this.node.classList.add('is-dragging');
      });
      this.node.addEventListener('dragleave', () => {
        this.node.classList.remove('is-dragging');
      });
      this.node.addEventListener('drop', event => {
        event.preventDefault();
        this.node.classList.remove('is-dragging');
        const files = Array.from(event.dataTransfer?.files || []);
        if (files.length) this.controller.attach(files);
      });
    }

    syncTextareaHeight() {
      const isStart = this.controller.state.stage === 'start';
      const minH = isStart ? 82 : 54;
      const maxH = isStart ? 190 : 150;
      if (!this.textarea.value) {
        this.textarea.style.height = '';
        return;
      }
      this.textarea.style.height = 'auto';
      this.textarea.style.height = Math.min(Math.max(this.textarea.scrollHeight, minH), maxH) + 'px';
    }

    update() {
      const s = this.controller.state;
      const locks = this.controller.getLockState();
      const schema = locks.schema;
      const action = this.controller.getPrimaryAction();
      const mode = this.controller.currentMode();
      const model = this.controller.currentModel();

      // 1. Sync textarea value & context-aware placeholder without clobbering active typing
      if (this.textarea.value !== s.draft) {
        this.textarea.value = s.draft;
        this.syncTextareaHeight();
      }
      let placeholder = s.stage === 'start' ? '描述你的需求…' : '输入消息…';
      this.textarea.placeholder = placeholder;

      // 2. Keep inline status strip free of explanatory copy inside display area
      this.statusEl.textContent = '';
      this.statusEl.hidden = true;

      // 3. Sync attachments rail (image thumbnails with click-to-lightbox + file/link chips)
      const nextAttachSig = s.attachments.map(a => `${a.id}:${a.name}:${a.dimensions || ''}:${a.url || ''}`).join('|');
      if (nextAttachSig !== this.attachSignature) {
        this.attachSignature = nextAttachSig;
        this.attachmentsEl.hidden = s.attachments.length === 0;
        this.attachmentsEl.innerHTML = s.attachments.map(att => {
          if (att.kind === 'image' && att.url) {
            const metaHint = [att.name, att.dimensions, att.sizeLabel].filter(Boolean).join(' · ');
            return `
              <div class="cv-att-thumb" role="group" aria-label="图片附件 ${escape(att.name)}">
                <button
                  type="button"
                  class="cv-att-thumb-btn"
                  data-preview-att="${escape(att.id)}"
                  title="${escape(metaHint)} · 点击弹层查看大图"
                  aria-label="查看图片大图 ${escape(att.name)}">
                  <img src="${escape(att.url)}" alt="${escape(att.name)}">
                  <span class="cv-att-thumb-zoom" aria-hidden="true">${icon('zoom-in')}</span>
                </button>
                <button
                  type="button"
                  class="cv-att-thumb-remove"
                  data-remove-att="${escape(att.id)}"
                  title="移除图片 ${escape(att.name)}"
                  aria-label="移除图片 ${escape(att.name)}">
                  ${icon('x')}
                </button>
              </div>
            `;
          }
          return `
            <span class="cv-attachment-chip">
              ${icon(att.kind === 'image' ? 'image' : att.kind === 'link' ? 'link-2' : 'file-text')}
              <span class="cv-attachment-name">${escape(att.name)}</span>
              <button type="button" class="cv-attachment-remove" data-remove-att="${escape(att.id)}" aria-label="移除附件 ${escape(att.name)}">
                ${icon('x')}
              </button>
            </span>
          `;
        }).join('');

        this.attachmentsEl.querySelectorAll('[data-preview-att]').forEach(btn => {
          btn.addEventListener('click', () => {
            const imageList = this.controller.state.attachments.filter(a => a.kind === 'image' && a.url);
            this.helpers.openImagePreview?.(imageList, btn.dataset.previewAtt, btn);
          });
        });
        this.attachmentsEl.querySelectorAll('[data-remove-att]').forEach(btn => {
          btn.addEventListener('click', event => {
            event.stopPropagation();
            this.controller.removeAttachment(btn.dataset.removeAtt);
          });
        });
        icons(this.attachmentsEl);
      }

      // 4. Sync inline reason region (only actionable blockers inside product UI)
      const reasonLines = [];
      if (s.stage === 'start' && locks.acpIssue) {
        reasonLines.push({
          blocker: true,
          acpIssue: true,
          iconName: 'triangle-alert',
          text: locks.acpIssue.message
        });
      }
      if (s.stage === 'session' && !s.frozenThread.routeAvailable) {
        reasonLines.push({
          blocker: true,
          iconName: 'triangle-alert',
          text: '当前模型不可用，请改选其他模型'
        });
      }
      this.reasonEl.hidden = reasonLines.length === 0;
      this.reasonEl.innerHTML = reasonLines.map(line => `
        <div class="cv-reason-line ${line.blocker ? 'is-blocker' : ''} ${line.acpIssue ? 'cv-acp-issue-banner' : ''}">
          ${icon(line.iconName)}
          <span class="cv-reason-text">${escape(line.text)}</span>
          ${line.acpIssue ? `
            <span class="cv-acp-issue-actions">
              <button type="button" class="cv-inline-fix-btn" data-recover-acp="native">改用内置模型</button>
              <button type="button" class="cv-inline-fix-btn" data-recover-acp="local">切回本地项目</button>
            </span>
          ` : ''}
        </div>
      `).join('');
      if (reasonLines.length) {
        this.reasonEl.querySelectorAll('[data-recover-acp]').forEach(btn => {
          btn.addEventListener('click', () => {
            if (btn.dataset.recoverAcp === 'native') {
              this.controller.selectNativeModel(this.controller.state.modelId);
              this.helpers.toast('已改用糊来帮内置模型');
            } else {
              this.controller.switchToLocalProjectForAcp();
              this.helpers.toast('已切回本地项目，可正常启动 ACP 会话');
            }
          });
        });
        icons(this.reasonEl);
      }

      // 5. Sync Unified 3+1 Route Selector Bar (Mode · Model/ACP · Thought · + Extra Tuning)
      const botManaged = s.stage === 'session' && s.frozenThread.botManaged && !locks.isAcp;
      const routeUnavailable = s.stage === 'session' && !s.frozenThread.routeAvailable;
      const acpPending = s.backendKind === 'acp' ? s.acpConfigPending : null;
      const extraSig = schema.extraOptions.map(o => `${o.id}=${String(o.currentValue)}`).join(',');
      const nextRouteSig = JSON.stringify({
        stage: s.stage,
        backendKind: s.backendKind,
        acpAccountId: s.acpAccountId,
        deferred: schema.deferred,
        pendingId: acpPending?.configId || null,
        targetType: s.targetType,
        projectId: s.projectId,
        modeId: schema.modeSlot?.currentValue || null,
        modeLabel: schema.modeSlot?.currentLabel || null,
        modeOpts: (schema.modeSlot?.flatOptions || []).length,
        modeEditable: locks.modeEditable,
        modeReason: locks.modeReason,
        modelVal: schema.modelSlot?.kind === 'acp' ? schema.modelSlot.currentValue : model.id,
        modelLabel: schema.modelSlot?.currentLabel || schema.account?.name || model.name,
        modelKind: schema.modelSlot?.kind || 'none',
        modelEditable: locks.modelEditable,
        modelReason: locks.modelReason,
        thoughtVal: schema.thoughtSlot?.currentValue || null,
        thoughtLabel: schema.thoughtSlot?.currentLabel || null,
        effortSupported: locks.effortSupported,
        effortEditable: locks.effortEditable,
        effortReason: locks.effortReason,
        extraSig,
        extraEditable: locks.extraEditable,
        extraReason: locks.extraReason,
        botManaged,
        routeUnavailable
      });

      if (nextRouteSig !== this.routeSignature) {
        this.routeSignature = nextRouteSig;
        const isAcp = schema.kind === 'acp';
        const showModeSlot = Boolean(schema.modeSlot);
        const modeOpts = schema.modeSlot?.flatOptions || schema.modeSlot?.options || [];
        const modeTitle = schema.modeSlot?.name || '工作模式';
        const modeCurrentLabel = schema.modeSlot?.currentLabel || mode.label;
        const modePending = Boolean(acpPending && schema.modeSlot && acpPending.configId === schema.modeSlot.id);

        const hasAcpModelSlot = isAcp && schema.modelSlot?.kind === 'acp';
        const modelTriggerLabel = isAcp
          ? (hasAcpModelSlot ? schema.modelSlot.currentLabel : (schema.account?.name || 'ACP'))
          : model.name;
        const modelTriggerTitle = isAcp
          ? `${schema.account?.name || 'ACP'}${hasAcpModelSlot ? ' / ' + schema.modelSlot.currentLabel : ''}${schema.deferred ? '（待首条启动后加载）' : ''}`
          : `主智能体模型：${model.accountName} / ${model.name}`;
        const modelPending = Boolean(acpPending && schema.modelSlot && acpPending.configId === schema.modelSlot.id);

        const showThoughtSlot = !isAcp || (!schema.deferred && (Boolean(schema.thoughtSlot) || hasAcpModelSlot));
        const thoughtOptions = isAcp
          ? (schema.thoughtSlot?.flatOptions || schema.thoughtSlot?.options || [])
          : (model.efforts || []).map(ef => ({ value: ef, name: ef }));
        const thoughtCurrentVal = schema.thoughtSlot?.currentValue || null;
        const thoughtCurrentLabel = schema.thoughtSlot?.currentLabel || thoughtCurrentVal || '—';
        const thoughtPending = Boolean(acpPending && schema.thoughtSlot && acpPending.configId === schema.thoughtSlot.id);

        const showExtraSlot = schema.extraOptions.length > 0;
        const extraPending = Boolean(acpPending && schema.extraOptions.some(o => o.id === acpPending.configId));
        const hasExtraActive = schema.extraOptions.some(o =>
          o.type === 'boolean' ? Boolean(o.currentValue) : (o.currentValue && o.currentValue !== 'workspace_safe')
        );

        const initialQuery = this.menuManager.openId === 'model' ? (this.menuManager.modelSearchQuery || '') : '';
        const modelResultsHTML = buildModelMenuResultsHTML(this.controller, schema, initialQuery);

        this.routeBarEl.innerHTML = `
          ${showModeSlot ? `
            <!-- Slot 1: Mode Selector -->
            <div class="cv-menu-anchor">
              ${locks.modeEditable ? `
                <button
                  type="button"
                  class="cv-quiet-trigger ${modePending ? 'is-pending-acp' : ''}"
                  data-route-trigger="mode"
                  data-menu-trigger="mode"
                  aria-haspopup="menu"
                  aria-expanded="false"
                  title="${escape(modeTitle + '：' + modeCurrentLabel)}">
                  ${modePending ? spinner() : ''}
                  <span>${escape(modeCurrentLabel)}</span>
                  <span class="cv-caret">${icon('chevron-down')}</span>
                </button>
                <div class="cv-menu align-right" data-menu-panel="mode" role="menu" hidden>
                  <div class="cv-menu-head">
                    <span>${escape(modeTitle)}</span>
                  </div>
                  ${modeOpts.map(m => {
                    const mVal = m.value ?? m.id;
                    const mLabel = m.name ?? m.label;
                    const selected = mVal === schema.modeSlot.currentValue;
                    return `
                      <button type="button" class="cv-menu-item ${selected ? 'is-selected' : ''}" data-pick-mode="${escape(mVal)}">
                        <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
                        <span class="cv-item-main">${escape(mLabel)}</span>
                      </button>
                    `;
                  }).join('')}
                </div>
              ` : `
                <span
                  class="cv-quiet-trigger is-disabled"
                  aria-disabled="true"
                  title="${escape(locks.modeReason)}">
                  ${modePending ? spinner() : ''}
                  <span>${escape(modeCurrentLabel)}</span>
                  <span class="cv-caret">${icon('chevron-down')}</span>
                </span>
              `}
            </div>
          ` : ''}

          ${botManaged ? `
            <span
              class="cv-quiet-trigger is-disabled is-static-label"
              aria-disabled="true"
              title="由机器人设置统一管理">
              ${icon('bot')}
              <span>${escape(model.name)}</span>
            </span>
          ` : `
            ${routeUnavailable ? `
              <button
                type="button"
                class="cv-route-warn-btn"
                data-warn-explain
                title="查看原因"
                aria-label="当前模型不可用">
                ${icon('triangle-alert')}
              </button>
            ` : ''}

            <!-- Slot 2: Main Agent Model / ACP Selector -->
            <div class="cv-menu-anchor">
              ${locks.modelEditable ? `
                <button
                  type="button"
                  class="cv-quiet-trigger ${isAcp ? 'is-acp-model' : ''} ${modelPending ? 'is-pending-acp' : ''}"
                  data-route-trigger="model"
                  data-menu-trigger="model"
                  aria-haspopup="menu"
                  aria-expanded="false"
                  title="${escape(modelTriggerTitle)}">
                  ${modelPending ? spinner() : (isAcp ? renderAcpBrandMark(schema.account, 'is-sm') : '')}
                  <span class="cv-model-label-text">${escape(modelTriggerLabel)}</span>
                  <span class="cv-caret">${icon('chevron-down')}</span>
                </button>
                <div class="cv-menu cv-menu-models align-right" data-menu-panel="model" role="menu" hidden>
                  <div class="cv-model-search-wrap">
                    <span class="cv-model-search-icon">${icon('search')}</span>
                    <input
                      type="text"
                      class="cv-model-search-input"
                      value="${escape(initialQuery)}"
                      placeholder="搜索模型…"
                      aria-label="搜索模型"
                      autocomplete="off"
                      spellcheck="false">
                    <button
                      type="button"
                      class="cv-model-search-clear"
                      title="清除搜索"
                      aria-label="清除搜索"
                      ${initialQuery ? '' : 'hidden'}>
                      ${icon('x')}
                    </button>
                  </div>
                  <div class="cv-model-menu-results" role="group" aria-label="模型列表">
                    ${modelResultsHTML}
                  </div>
                </div>
              ` : `
                <span
                  class="cv-quiet-trigger is-disabled ${isAcp && !hasAcpModelSlot ? 'is-static-label is-acp-model' : (isAcp ? 'is-acp-model' : '')}"
                  aria-disabled="true"
                  title="${escape(locks.modelReason)}">
                  ${modelPending ? spinner() : (isAcp ? renderAcpBrandMark(schema.account, 'is-sm') : '')}
                  <span class="cv-model-label-text">${escape(modelTriggerLabel)}</span>
                  ${isAcp && !hasAcpModelSlot ? '' : `<span class="cv-caret">${icon('chevron-down')}</span>`}
                </span>
              `}
            </div>

            ${showThoughtSlot ? `
              <!-- Slot 3: Reasoning Effort -->
              <div class="cv-menu-anchor">
                ${locks.effortEditable ? `
                  <button
                    type="button"
                    class="cv-quiet-trigger cv-mono is-effort ${thoughtPending ? 'is-pending-acp' : ''}"
                    data-route-trigger="effort"
                    data-menu-trigger="effort"
                    aria-haspopup="menu"
                    aria-expanded="false"
                    title="${escape((schema.thoughtSlot?.name || '思考强度') + '：' + thoughtCurrentLabel)}">
                    ${thoughtPending ? spinner() : ''}
                    <span>${escape(thoughtCurrentLabel)}</span>
                    <span class="cv-caret">${icon('chevron-down')}</span>
                  </button>
                  <div class="cv-menu align-right" data-menu-panel="effort" role="menu" hidden>
                    <div class="cv-menu-head">
                      <span>${escape(schema.thoughtSlot?.name || '思考强度')}</span>
                    </div>
                    ${thoughtOptions.map(ef => {
                      const efVal = ef.value ?? ef;
                      const efLabel = ef.name ?? efVal;
                      const selected = efVal === thoughtCurrentVal;
                      return `
                        <button type="button" class="cv-menu-item ${selected ? 'is-selected' : ''}" data-pick-effort="${escape(efVal)}">
                          <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
                          <span class="cv-item-main cv-mono">${escape(efLabel)}</span>
                        </button>
                      `;
                    }).join('')}
                  </div>
                ` : `
                  <span
                    class="cv-quiet-trigger cv-mono is-effort is-disabled"
                    aria-disabled="true"
                    title="${escape(locks.effortReason)}">
                    ${thoughtPending ? spinner() : ''}
                    <span>${escape(locks.effortSupported ? thoughtCurrentLabel : '—')}</span>
                    <span class="cv-caret">${icon('chevron-down')}</span>
                  </span>
                `}
              </div>
            ` : ''}

            ${showExtraSlot ? `
              <!-- Slot 4: Dynamic ACP Extra Parameters (boolean / select) -->
              <div class="cv-menu-anchor">
                ${locks.extraEditable ? `
                  <button
                    type="button"
                    class="cv-quiet-trigger cv-extra-trigger ${hasExtraActive ? 'has-active-extra' : ''} ${extraPending ? 'is-pending-acp' : ''}"
                    data-route-trigger="extra"
                    data-menu-trigger="extra"
                    aria-haspopup="menu"
                    aria-expanded="false"
                    title="扩展参数">
                    ${extraPending ? spinner() : icon('sliders-horizontal')}
                    <span>调优</span>
                    <span class="cv-extra-count">${schema.extraOptions.length}</span>
                  </button>
                  <div class="cv-menu cv-menu-acp-extra align-right" data-menu-panel="extra" role="menu" hidden>
                    ${buildExtraMenuHTML(schema)}
                  </div>
                ` : `
                  <span
                    class="cv-quiet-trigger cv-extra-trigger is-disabled"
                    aria-disabled="true"
                    title="${escape(locks.extraReason)}">
                    ${extraPending ? spinner() : icon('sliders-horizontal')}
                    <span>调优</span>
                    <span class="cv-extra-count">${schema.extraOptions.length}</span>
                  </span>
                `}
              </div>
            ` : ''}
          `}
        `;

        const modelPanel = this.routeBarEl.querySelector('[data-menu-panel="model"]');
        const modelResultsEl = modelPanel?.querySelector('.cv-model-menu-results');
        const modelSearchInput = modelPanel?.querySelector('.cv-model-search-input');
        const modelSearchClearBtn = modelPanel?.querySelector('.cv-model-search-clear');

        const bindModelResultsEvents = container => {
          if (!container) return;
          container.querySelectorAll('[data-pick-native-model]').forEach(btn => {
            btn.addEventListener('click', () => {
              this.menuManager.closeAll();
              this.controller.selectNativeModel(btn.dataset.pickNativeModel);
            });
          });
          container.querySelectorAll('[data-pick-acp-account]').forEach(btn => {
            btn.addEventListener('click', () => {
              this.menuManager.closeAll();
              this.controller.selectAcpAccount(btn.dataset.pickAcpAccount);
            });
          });
          container.querySelectorAll('[data-pick-acp-model]').forEach(btn => {
            btn.addEventListener('click', () => {
              this.menuManager.closeAll();
              this.controller.setModel(btn.dataset.pickAcpModel);
            });
          });
        };

        const syncModelSearchList = query => {
          this.menuManager.modelSearchQuery = query;
          if (modelSearchClearBtn) modelSearchClearBtn.hidden = !query;
          if (modelResultsEl) {
            modelResultsEl.innerHTML = buildModelMenuResultsHTML(this.controller, schema, query);
            bindModelResultsEvents(modelResultsEl);
            icons(modelResultsEl);
          }
        };

        // Bind editable route triggers
        ['mode', 'model', 'effort', 'extra'].forEach(kind => {
          const btn = this.routeBarEl.querySelector(`[data-route-trigger="${kind}"]`);
          const panel = this.routeBarEl.querySelector(`[data-menu-panel="${kind}"]`);
          if (btn && panel) {
            btn.addEventListener('click', () => {
              this.menuManager.toggle(kind, btn, panel, true);
              if (kind === 'model' && !panel.hidden && modelSearchInput) {
                syncModelSearchList(this.menuManager.modelSearchQuery || '');
                modelSearchInput.value = this.menuManager.modelSearchQuery || '';
                requestAnimationFrame(() => modelSearchInput.focus({ preventScroll: true }));
              }
            });
          }
          this.menuManager.restoreIfOpen(kind, btn, panel, true);
        });

        modelSearchInput?.addEventListener('input', () => {
          syncModelSearchList(modelSearchInput.value);
        });
        modelSearchInput?.addEventListener('click', event => event.stopPropagation());
        modelSearchClearBtn?.addEventListener('click', event => {
          event.stopPropagation();
          if (!modelSearchInput) return;
          modelSearchInput.value = '';
          syncModelSearchList('');
          modelSearchInput.focus({ preventScroll: true });
        });

        bindModelResultsEvents(modelResultsEl);

        this.routeBarEl.querySelector('[data-warn-explain]')?.addEventListener('click', () => {
          this.controller.explainLock(this.controller.state.frozenThread.routeUnavailableReason, 'warning');
        });


        this.routeBarEl.querySelectorAll('[data-pick-mode]').forEach(btn => {
          btn.addEventListener('click', () => {
            this.menuManager.closeAll();
            this.controller.setWorkMode(btn.dataset.pickMode);
          });
        });
        this.routeBarEl.querySelectorAll('[data-pick-effort]').forEach(btn => {
          btn.addEventListener('click', () => {
            this.menuManager.closeAll();
            this.controller.setEffort(btn.dataset.pickEffort);
          });
        });
        this.routeBarEl.querySelectorAll('[data-toggle-acp-bool]').forEach(btn => {
          btn.addEventListener('click', event => {
            event.stopPropagation();
            const cfgId = btn.dataset.toggleAcpBool;
            const nextVal = btn.dataset.nextVal === 'true';
            this.controller.setAcpConfigValue(cfgId, nextVal);
          });
        });
        this.routeBarEl.querySelectorAll('[data-pick-acp-extra]').forEach(btn => {
          btn.addEventListener('click', () => {
            this.menuManager.closeAll();
            this.controller.setAcpConfigValue(btn.dataset.pickAcpExtra, btn.dataset.acpVal);
          });
        });

        icons(this.routeBarEl);
      }

      // 6. Sync 6-State Primary Action Slot (Fixed 34x34px Circle — 0px Layout Shift Across All States!)
      const nextActionSig = JSON.stringify(action);
      if (nextActionSig !== this.actionSignature) {
        this.actionSignature = nextActionSig;
        const isStop = action.kind === 'stop';
        const isContinue = action.kind === 'continue';
        const isBusyTransition = action.kind === 'stopping' || action.kind === 'continuing';
        const iconName = isStop
          ? 'square'
          : isContinue
            ? 'play'
            : 'arrow-up';
        this.actionSlotEl.innerHTML = `
          <button
            type="button"
            class="cv-action-circle ${isStop ? 'is-stop' : ''} ${isContinue ? 'is-continue' : ''}"
            ${action.enabled ? '' : 'disabled'}
            title="${escape(isContinue ? '继续被中断的工作（不添加新内容）' : action.label)}"
            aria-label="${escape(action.label)}">
            ${isBusyTransition ? spinner('is-on-disabled') : icon(iconName)}
          </button>
        `;
        this.actionSlotEl.querySelector('button').addEventListener('click', () => {
          if (isStop) this.controller.stop();
          else if (isContinue) this.controller.resume();
          else this.helpers.onSubmitFromComposer();
        });
        icons(this.actionSlotEl);
      }
    }
  }

  /* ========================================================================
     4. Start Page Creation Stage (Mounts the Shared PromptComposerCard Inside!)
     ======================================================================== */
  function buildPreparationHTML(controller) {
    const prep = controller.state.preparation;
    if (!prep) return '';
    const project = controller.currentProject();
    const isAcp = controller.state.backendKind === 'acp';
    const acpAcc = isAcp ? controller.currentAcpAccount() : null;
    const steps = ['检查项目', '准备工作区', isAcp ? `连接 ${acpAcc?.name || 'ACP'}` : '初始化会话', '提交请求'];
    const isRunning = prep.status === 'running';
    const isFailed = prep.status === 'failed';

    return `
      <section class="cv-prep-card" aria-label="会话环境准备状态">
        ${isRunning ? '<mdui-linear-progress class="cv-prep-m3-progress" aria-label="会话环境准备中"></mdui-linear-progress>' : ''}
        <div class="cv-prep-body">
          <div class="cv-prep-head">
            <div class="cv-prep-icon ${isFailed ? 'is-error' : ''}">
              ${icon(isFailed ? 'circle-alert' : 'folder-git-2')}
            </div>
            <div>
              <h3>${isFailed ? '环境准备未完成' : '正在准备会话'}</h3>
            </div>
          </div>
          <ol class="cv-prep-steps">
            ${steps.map((title, idx) => {
              const done = idx < prep.stepIndex;
              const current = idx === prep.stepIndex;
              const cls = done ? 'is-done' : current ? (isFailed ? 'is-failed' : 'is-current') : '';
              const mark = done
                ? icon('circle-check')
                : current
                  ? (isFailed ? icon('circle-x') : spinner())
                  : icon('circle');
              return `
                <li class="cv-prep-step ${cls}">
                  <span class="cv-step-mark">${mark}</span>
                  <div>
                    <span>${escape(title)}</span>
                    ${current && prep.subStage ? `<span class="cv-step-sub">${escape(prep.subStage)}</span>` : ''}
                  </div>
                </li>
              `;
            }).join('')}
          </ol>
          ${isFailed && prep.error ? `
            <div class="cv-prep-alert">
              <span>${escape(prep.error)}</span>
              <button type="button" class="cv-mini-btn" data-start-action="switch-local">切换为本地目录</button>
            </div>
          ` : ''}
        </div>
        <details class="cv-prep-details" ${prep.expanded ? 'open' : ''}>
          <summary>
            <span>更多详情</span>
            <span class="cv-chevron">${icon('chevron-right')}</span>
          </summary>
          <div class="cv-prep-grid">
            <div class="cv-prep-kv">
              <small>项目</small>
              <span>${escape(project ? project.name : '无项目')}</span>
            </div>
            <div class="cv-prep-kv">
              <small>冻结的会话工作区</small>
              <span>${prep.frozenWorkspaceMode === 'worktree' ? '新建工作树' : '本地目录'}</span>
            </div>
            ${project?.sshAlias ? `
              <div class="cv-prep-kv">
                <small>远程主机</small>
                <span class="cv-mono">${escape(project.sshAlias)}</span>
              </div>
            ` : ''}
            ${prep.workspacePath ? `
              <div class="cv-prep-kv">
                <small>工作区路径</small>
                <span class="cv-mono">${escape(prep.workspacePath)}</span>
              </div>
            ` : ''}
            ${prep.branch ? `
              <div class="cv-prep-kv">
                <small>工作树分支</small>
                <span class="cv-mono">${escape(prep.branch)}</span>
              </div>
            ` : ''}
          </div>
        </details>
      </section>
    `;
  }

  /* ========================================================================
     4b. Fuzzy Project Search & Start-Page Project Selector Helpers
     ======================================================================== */
  function scoreFuzzyText(text, pattern) {
    if (!pattern) return { matched: true, score: 0, ranges: [] };
    const hay = String(text || '');
    const hayLower = hay.toLowerCase();
    const patLower = pattern.toLowerCase();

    // 1. Direct substring match (highest priority)
    const subIdx = hayLower.indexOf(patLower);
    if (subIdx !== -1) {
      const boundaryBonus = subIdx === 0 || /[-_./\\:\s]/.test(hay[subIdx - 1]) ? 40 : 0;
      const exactBonus = hayLower === patLower ? 60 : 0;
      return {
        matched: true,
        score: 200 + exactBonus + boundaryBonus - subIdx,
        ranges: [[subIdx, subIdx + patLower.length]]
      };
    }

    // 2. Subsequence fuzzy match (e.g. "plp" -> "pure-lang-pure", "dn" -> "design-notes")
    let pIdx = 0;
    let score = 80;
    let prevMatchIdx = -2;
    const indices = [];
    for (let i = 0; i < hayLower.length && pIdx < patLower.length; i++) {
      if (hayLower[i] === patLower[pIdx]) {
        indices.push(i);
        if (i === 0 || /[-_./\\:\s]/.test(hay[i - 1])) {
          score += 18;
        }
        if (i === prevMatchIdx + 1) {
          score += 12;
        } else if (prevMatchIdx >= 0) {
          score -= Math.min(8, i - prevMatchIdx - 1);
        }
        prevMatchIdx = i;
        pIdx++;
      }
    }

    if (pIdx !== patLower.length) {
      return { matched: false, score: -Infinity, ranges: [] };
    }

    const ranges = [];
    for (const idx of indices) {
      const last = ranges[ranges.length - 1];
      if (last && last[1] === idx) last[1] = idx + 1;
      else ranges.push([idx, idx + 1]);
    }
    return { matched: true, score, ranges };
  }

  function highlightRanges(text, ranges) {
    const str = String(text ?? '');
    if (!ranges || !ranges.length) return escape(str);
    let out = '';
    let cursor = 0;
    for (const [start, end] of ranges) {
      if (start > cursor) out += escape(str.slice(cursor, start));
      out += `<mark class="cv-fuzzy-mark">${escape(str.slice(start, end))}</mark>`;
      cursor = end;
    }
    if (cursor < str.length) out += escape(str.slice(cursor));
    return out;
  }

  function matchProjectForSearch(proj, rawQuery) {
    const q = String(rawQuery || '').trim();
    const sshLabel = proj.sshAlias ? `SSH · ${proj.sshAlias}` : '';
    if (!q) {
      return {
        matched: true,
        score: 0,
        nameHTML: escape(proj.name),
        sshHTML: escape(sshLabel),
        pathHTML: escape(proj.path)
      };
    }

    const tokens = q.split(/\s+/).filter(Boolean);
    let totalScore = 0;
    let nameRanges = [];
    let sshRanges = [];
    let pathRanges = [];

    for (const token of tokens) {
      const nameRes = scoreFuzzyText(proj.name, token);
      const sshRes = sshLabel ? scoreFuzzyText(sshLabel, token) : { matched: false, score: -Infinity, ranges: [] };
      const pathRes = scoreFuzzyText(proj.path, token);

      if (!nameRes.matched && !sshRes.matched && !pathRes.matched) {
        return { matched: false, score: -Infinity };
      }

      const bestFieldScore = Math.max(
        nameRes.matched ? nameRes.score + 50 : -Infinity,
        sshRes.matched ? sshRes.score + 25 : -Infinity,
        pathRes.matched ? pathRes.score : -Infinity
      );
      totalScore += bestFieldScore;

      if (nameRes.matched && !nameRanges.length) nameRanges = nameRes.ranges;
      if (sshRes.matched && !sshRanges.length) sshRanges = sshRes.ranges;
      if (pathRes.matched && !pathRanges.length) pathRanges = pathRes.ranges;
    }

    return {
      matched: true,
      score: totalScore,
      nameHTML: highlightRanges(proj.name, nameRanges),
      sshHTML: highlightRanges(sshLabel, sshRanges),
      pathHTML: highlightRanges(proj.path, pathRanges)
    };
  }

  function renderProjectMenuListHTML(controller, rawQuery) {
    const projects = app.fixtures.projects || [];
    const q = String(rawQuery || '').trim();
    const s = controller.state;

    const scored = [];
    projects.forEach((proj, index) => {
      const res = matchProjectForSearch(proj, q);
      if (res.matched) {
        scored.push({ proj, index, ...res });
      }
    });

    if (q) {
      scored.sort((a, b) => (b.score - a.score) || (a.index - b.index));
    }

    const countText = q
      ? `匹配 ${scored.length} / ${projects.length}`
      : `${projects.length} 个项目`;

    if (scored.length === 0) {
      return {
        countText,
        listHTML: `
          <div class="cv-project-empty" role="status">
            ${icon('search-x')}
            <span>未找到匹配「${escape(q)}」的已有项目</span>
          </div>
        `
      };
    }

    const listHTML = scored.map(({ proj, nameHTML, sshHTML, pathHTML }) => {
      const selected = s.targetType === 'project' && s.projectId === proj.id;
      return `
        <button
          type="button"
          class="cv-menu-item cv-project-option ${selected ? 'is-selected' : ''}"
          role="menuitemradio"
          aria-checked="${selected}"
          data-pick-project="${escape(proj.id)}">
          <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
          <span class="cv-ws-item-icon">${icon(proj.sshAlias ? 'server' : 'folder')}</span>
          <span class="cv-item-main">
            <div class="cv-item-title-row">
              <span class="cv-item-title">${nameHTML}</span>
              ${proj.sshAlias ? `<span class="cv-ssh-pill">${sshHTML}</span>` : ''}
              ${!proj.isGit ? `<span class="cv-cap-badge" title="普通文件夹（非 Git 仓库）">普通目录</span>` : ''}
            </div>
            <div class="cv-item-sub cv-mono">${pathHTML}</div>
          </span>
        </button>
      `;
    }).join('');

    return {
      countText,
      listHTML
    };
  }

  function renderStartStage(host, controller, composerCard, menuManager, helpers) {
    const s = controller.state;
    const locks = controller.getLockState();
    const project = controller.currentProject();
    const standalone = s.targetType === 'standalone';
    const effDelMode = controller.effectiveDelegationMode();
    const hasDelOverride = Boolean(s.delegationModeOverride || s.delegationPrefOverride);

    const heroHTML = s.preparation
      ? buildPreparationHTML(controller)
      : `
        <div class="cv-welcome">
          <h2>想从哪里开始？</h2>
        </div>
      `;

    const defaultModeName = controller.defaults.delegationMode === 'automatic' ? '自动选模' : '固定配置模板';
    const defaultPrefName = { economy: '经济', balanced: '平衡', fast: '快速' }[controller.defaults.delegationPreference];
    const currentSearchQuery = menuManager.openId === 'project' ? (menuManager.projectSearchQuery || '') : '';
    const initialProjMenu = renderProjectMenuListHTML(controller, currentSearchQuery);

    host.innerHTML = `
      <div class="cv-start-col">
        <div class="cv-hero-slot">${heroHTML}</div>

        <div class="cv-start-envelope" aria-label="新会话创建环境栏与输入卡">
          <div class="cv-env-bar">
            <div class="cv-env-left">
              <div class="cv-menu-anchor">
                ${locks.prepRunning ? `
                  <span
                    class="cv-quiet-trigger cv-project-trigger is-disabled"
                    aria-disabled="true"
                    title="${escape(standalone ? '无项目' : project.name)}">
                    ${icon(standalone ? 'file-box' : (project?.sshAlias ? 'server' : 'folder'))}
                    <span class="cv-anchor-name">${escape(standalone ? '无项目' : project.name)}</span>
                    ${project?.sshAlias ? `<span class="cv-ssh-pill">SSH · ${escape(project.sshAlias)}</span>` : ''}
                    <span class="cv-caret">${icon('chevron-down')}</span>
                  </span>
                ` : `
                  <button
                    type="button"
                    class="cv-quiet-trigger cv-project-trigger ${standalone ? 'is-standalone' : 'is-project'}"
                    data-menu-trigger="project"
                    aria-haspopup="menu"
                    aria-expanded="false"
                    title="${escape(standalone ? '无项目' : `${project.name}（${project.path}）`)}">
                    ${icon(standalone ? 'file-box' : (project?.sshAlias ? 'server' : 'folder'))}
                    <span class="cv-anchor-name">${escape(standalone ? '无项目' : project.name)}</span>
                    ${project?.sshAlias ? `<span class="cv-ssh-pill">SSH · ${escape(project.sshAlias)}</span>` : ''}
                    <span class="cv-caret">${icon('chevron-down')}</span>
                  </button>

                  <div class="cv-menu cv-menu-project align-left" data-menu-panel="project" role="menu" aria-label="选择新会话开启位置" hidden>
                    <div class="cv-menu-head">
                      <span>开启位置</span>
                    </div>
                    <button
                      type="button"
                      class="cv-menu-item ${standalone ? 'is-selected' : ''}"
                      role="menuitemradio"
                      aria-checked="${standalone}"
                      data-pick-target="standalone">
                      <span class="cv-check-slot">${standalone ? icon('check') : ''}</span>
                      <span class="cv-ws-item-icon">${icon('file-box')}</span>
                      <span class="cv-item-main">
                        <div class="cv-item-title">无项目</div>
                      </span>
                    </button>

                    <button
                      type="button"
                      class="cv-menu-item cv-new-project-item"
                      role="menuitem"
                      data-pick-target="new-project">
                      <span class="cv-check-slot">${icon('plus')}</span>
                      <span class="cv-ws-item-icon is-accent">${icon('folder-plus')}</span>
                      <span class="cv-item-main">
                        <div class="cv-item-title">新建项目…</div>
                      </span>
                    </button>

                    <div class="cv-menu-divider"></div>

                    <div class="cv-menu-head">
                      <span>已有项目</span>
                      <small data-project-count>${escape(initialProjMenu.countText)}</small>
                    </div>
                    <div class="cv-project-search-wrap">
                      <span class="cv-project-search-icon">${icon('search')}</span>
                      <input
                        type="text"
                        class="cv-project-search-input"
                        value="${escape(currentSearchQuery)}"
                        placeholder="搜索项目…"
                        aria-label="搜索已有项目"
                        autocomplete="off"
                        spellcheck="false">
                      <button
                        type="button"
                        class="cv-project-search-clear"
                        title="清除搜索"
                        aria-label="清除搜索"
                        ${currentSearchQuery ? '' : 'hidden'}>
                        ${icon('x')}
                      </button>
                    </div>
                    <div class="cv-project-list" role="group" aria-label="已有项目列表">
                      ${initialProjMenu.listHTML}
                    </div>
                  </div>
                `}
              </div>

              ${standalone ? '' : `
                <span class="cv-v-sep" aria-hidden="true"></span>
                <div class="cv-menu-anchor">
                  ${locks.prepRunning ? `
                    <span
                      class="cv-quiet-trigger cv-ws-trigger ${s.workspaceMode === 'worktree' ? 'is-worktree' : ''} is-disabled"
                      aria-disabled="true"
                      title="${s.workspaceMode === 'worktree' ? '新建工作树' : '本地目录'}">
                      ${icon(s.workspaceMode === 'worktree' ? 'git-branch' : 'folder')}
                      <span>${s.workspaceMode === 'worktree' ? '新建工作树' : '本地目录'}</span>
                      <span class="cv-caret">${icon('chevron-down')}</span>
                    </span>
                  ` : `
                    <button
                      type="button"
                      class="cv-quiet-trigger cv-ws-trigger ${s.workspaceMode === 'worktree' ? 'is-worktree' : ''}"
                      data-menu-trigger="workspace"
                      aria-haspopup="menu"
                      aria-expanded="false"
                      title="${s.workspaceMode === 'worktree' ? '新建工作树' : '本地目录'}">
                      ${icon(s.workspaceMode === 'worktree' ? 'git-branch' : 'folder')}
                      <span>${s.workspaceMode === 'worktree' ? '新建工作树' : '本地目录'}</span>
                      <span class="cv-caret">${icon('chevron-down')}</span>
                    </button>

                    <div class="cv-menu cv-menu-ws align-left" data-menu-panel="workspace" role="menu" hidden>
                      <div class="cv-menu-head">
                        <span>会话工作区</span>
                      </div>
                      ${[
                        {
                          val: 'local',
                          iconName: 'folder',
                          label: '本地目录'
                        },
                        {
                          val: 'worktree',
                          iconName: 'git-branch',
                          label: '新建工作树'
                        }
                      ].map(opt => {
                        const selected = s.workspaceMode === opt.val;
                        return `
                          <button type="button" class="cv-menu-item ${selected ? 'is-selected' : ''}" data-pick-ws="${opt.val}">
                            <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
                            <span class="cv-ws-item-icon ${opt.val === 'worktree' ? 'is-worktree' : ''}">${icon(opt.iconName)}</span>
                            <span class="cv-item-main">
                              <div class="cv-item-title">${escape(opt.label)}</div>
                            </span>
                          </button>
                        `;
                      }).join('')}
                    </div>
                  `}
                </div>
              `}
            </div>

            ${s.backendKind === 'acp' ? '' : `
              <div class="cv-env-right">
                <div class="cv-menu-anchor">
                  ${locks.prepRunning ? `
                    <span
                      class="cv-quiet-trigger is-disabled"
                      aria-disabled="true"
                      title="${escape(controller.delegationSummaryText())}">
                      ${icon('sliders-horizontal')}
                      <span>${escape(controller.delegationSummaryText())}</span>
                      <span class="cv-caret">${icon('chevron-down')}</span>
                    </span>
                  ` : `
                    <button
                      type="button"
                      class="cv-quiet-trigger ${hasDelOverride ? 'has-override' : ''}"
                      data-menu-trigger="delegation"
                      aria-haspopup="menu"
                      aria-expanded="false"
                      title="${escape(controller.delegationSummaryText())}">
                      ${icon('sliders-horizontal')}
                      <span>${escape(controller.delegationSummaryText())}</span>
                      <span class="cv-caret">${icon('chevron-down')}</span>
                    </button>

                    <div class="cv-menu cv-menu-wide align-right" data-menu-panel="delegation" role="menu" hidden>
                      <div class="cv-menu-head">
                        <span>分发模式</span>
                      </div>
                      ${[
                        { val: null, label: `跟随默认 · ${defaultModeName}` },
                        { val: 'profile', label: '固定配置模板' },
                        { val: 'automatic', label: '自动选模' }
                      ].map(opt => {
                        const selected = s.delegationModeOverride === opt.val;
                        return `
                          <button type="button" class="cv-menu-item ${selected ? 'is-selected' : ''}" data-del-mode="${opt.val ?? 'default'}">
                            <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
                            <span class="cv-item-main">${escape(opt.label)}</span>
                          </button>
                        `;
                      }).join('')}

                      <div class="cv-menu-divider"></div>

                      <div class="cv-menu-head">
                        <span>自动选模偏好</span>
                      </div>
                      ${[
                        { val: null, label: `跟随默认 · ${defaultPrefName}` },
                        { val: 'economy', label: '经济' },
                        { val: 'balanced', label: '平衡' },
                        { val: 'fast', label: '快速' }
                      ].map(opt => {
                        const selected = s.delegationPrefOverride === opt.val;
                        const disabled = effDelMode !== 'automatic';
                        return `
                          <button type="button" class="cv-menu-item ${selected ? 'is-selected' : ''}" data-del-pref="${opt.val ?? 'default'}" ${disabled ? 'disabled' : ''}>
                            <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
                            <span class="cv-item-main">${escape(opt.label)}</span>
                          </button>
                        `;
                      }).join('')}
                    </div>
                  `}
                </div>
              </div>
            `}
          </div>

          <div class="cv-start-card-mount"></div>
        </div>
      </div>
    `;

    // Mount the exact shared PromptComposerCard inside the concentric start envelope!
    host.querySelector('.cv-start-card-mount').append(composerCard.node);
    composerCard.update();

    host.querySelector('[data-start-action="switch-local"]')?.addEventListener('click', () => {
      controller.setWorkspaceMode('local');
      helpers.toast('已切换为「本地目录」，可直接点击发送');
    });

    // Project selector menu & fuzzy search bindings
    const projTrig = host.querySelector('[data-menu-trigger="project"]');
    const projPanel = host.querySelector('[data-menu-panel="project"]');
    const projSearchInput = projPanel?.querySelector('.cv-project-search-input');
    const projSearchClearBtn = projPanel?.querySelector('.cv-project-search-clear');
    const projCountEl = projPanel?.querySelector('[data-project-count]');
    const projListEl = projPanel?.querySelector('.cv-project-list');

    const syncProjectSearchList = query => {
      menuManager.projectSearchQuery = query;
      if (projSearchClearBtn) projSearchClearBtn.hidden = !query;
      const rendered = renderProjectMenuListHTML(controller, query);
      if (projCountEl) projCountEl.textContent = rendered.countText;
      if (projListEl) {
        projListEl.innerHTML = rendered.listHTML;
        icons(projListEl);
      }
    };

    projTrig?.addEventListener('click', () => {
      menuManager.toggle('project', projTrig, projPanel, false);
      if (projPanel && !projPanel.hidden) {
        syncProjectSearchList(menuManager.projectSearchQuery || '');
        if (projSearchInput) {
          projSearchInput.value = menuManager.projectSearchQuery || '';
          requestAnimationFrame(() => projSearchInput.focus({ preventScroll: true }));
        }
      }
    });
    menuManager.restoreIfOpen('project', projTrig, projPanel, false);

    projSearchInput?.addEventListener('input', () => {
      syncProjectSearchList(projSearchInput.value);
    });

    projSearchClearBtn?.addEventListener('click', event => {
      event.stopPropagation();
      if (!projSearchInput) return;
      projSearchInput.value = '';
      syncProjectSearchList('');
      projSearchInput.focus({ preventScroll: true });
    });

    projPanel?.addEventListener('click', event => {
      const targetBtn = event.target.closest('[data-pick-target]');
      if (targetBtn) {
        const targetKind = targetBtn.dataset.pickTarget;
        const pendingQuery = projSearchInput?.value.trim() || '';
        menuManager.closeAll();
        if (targetKind === 'standalone') {
          if (helpers.selectStandaloneOnStart) helpers.selectStandaloneOnStart();
          else controller.selectStandaloneStart();
        } else if (targetKind === 'new-project') {
          helpers.openAddProjectDialog?.(pendingQuery);
        }
        return;
      }
      const projBtn = event.target.closest('[data-pick-project]');
      if (projBtn) {
        const pid = projBtn.dataset.pickProject;
        menuManager.closeAll();
        if (helpers.selectProjectOnStart) helpers.selectProjectOnStart(pid);
        else controller.selectProjectStart(pid);
      }
    });

    const wsTrig = host.querySelector('[data-menu-trigger="workspace"]');
    const wsPanel = host.querySelector('[data-menu-panel="workspace"]');
    wsTrig?.addEventListener('click', () => {
      menuManager.toggle('workspace', wsTrig, wsPanel, false);
    });
    menuManager.restoreIfOpen('workspace', wsTrig, wsPanel, false);

    host.querySelectorAll('[data-pick-ws]').forEach(btn => {
      btn.addEventListener('click', () => {
        menuManager.closeAll();
        controller.setWorkspaceMode(btn.dataset.pickWs);
      });
    });

    const delTrig = host.querySelector('[data-menu-trigger="delegation"]');
    const delPanel = host.querySelector('[data-menu-panel="delegation"]');
    delTrig?.addEventListener('click', () => {
      menuManager.toggle('delegation', delTrig, delPanel, false);
    });
    menuManager.restoreIfOpen('delegation', delTrig, delPanel, false);

    host.querySelectorAll('[data-del-mode]').forEach(btn => {
      btn.addEventListener('click', () => {
        controller.setDelegationMode(btn.dataset.delMode);
      });
    });

    host.querySelectorAll('[data-del-pref]').forEach(btn => {
      btn.addEventListener('click', () => {
        menuManager.closeAll();
        controller.setDelegationPref(btn.dataset.delPref);
      });
    });

    icons(host);
  }

  /* ========================================================================
     5. Subagent Read-Only Dock (Matches AgentReadOnlyDockView in Flutter)
     ======================================================================== */
  function buildAgentReadOnlyDock(controller) {
    const agent = controller.currentAgent();
    const wrapper = node(`
      <section class="cv-readonly-dock" aria-label="子智能体会话只读栏">
        <div class="cv-readonly-head">
          <span class="cv-readonly-title">
            <span>只读 · ${escape(agent.role)}</span>
          </span>
          <button type="button" class="cv-button cv-primary" data-readonly-back>
            ${icon('arrow-left')}
            <span>返回主会话</span>
          </button>
        </div>
        <div class="cv-readonly-chips">
          <span class="cv-info-chip">
            ${icon('sparkles')}
            <span>${escape(statusLabel(agent.status))}</span>
          </span>
          <span class="cv-info-chip">
            ${icon('cpu')}
            <span>${escape(agent.routeLabel)}</span>
          </span>
          <span class="cv-info-chip" title="${escape(agent.workspacePath)}">
            ${icon('folder')}
            <span class="cv-mono">${escape(agent.workspacePath)}</span>
          </span>
        </div>
      </section>
    `);
    wrapper.querySelector('[data-readonly-back]').addEventListener('click', () => controller.switchAgent('root'));
    icons(wrapper);
    return wrapper;
  }

  function describeContextNotes(controller) {
    const s = controller.state;
    const locks = controller.getLockState();
    const schema = locks.schema;
    const notes = [];

    if (s.lockNotice) {
      notes.push(['交互提示', s.lockNotice]);
    }
    if (locks.acpIssue) {
      notes.push(['远程兼容性说明', locks.acpIssue.detail || locks.acpIssue.message]);
    }
    if (s.backendKind === 'acp' && schema.account?.specSummary) {
      notes.push([`ACP 协议探测 · ${schema.account.name}`, schema.account.specSummary]);
      if (schema.deferred) {
        notes.push([
          '首条激活机制',
          '当前外部智能体未在创建期预热进程，发送首条消息完成 session/new 握手后自动展开动态配置槽；也可点击下方「模拟预加载配置」预览握手后形态。'
        ]);
      }
    }

    if (s.stage === 'start') {
      const project = controller.currentProject();
      const standalone = s.targetType === 'standalone';
      let targetText = '';
      if (standalone) {
        targetText = '当前新会话将在「无项目」（Documents/anywork）开启，不绑定 Git 工作树，所属位置在会话创建时固定。';
      } else if (project?.sshAlias) {
        targetText = s.workspaceMode === 'worktree'
          ? `当前新会话将在远程项目「${project.name}」（SSH · ${project.sshAlias}）从 HEAD 检出独立工作树隔离改动，创建后工作区不可变更。`
          : `当前新会话将在远程项目「${project.name}」（SSH · ${project.sshAlias}）目录中直接协作，创建后工作区不可变更。`;
      } else {
        targetText = s.workspaceMode === 'worktree'
          ? `当前新会话将在项目「${project.name}」从 HEAD 新建独立 Git 工作树隔离改动，创建后固定工作区。`
          : `当前新会话将在项目「${project.name}」本地目录中开启（可在外层环境栏切换为无项目、已有项目或新建工作树）。`;
      }
      if (s.backendKind === 'acp') {
        notes.push(['开启位置与调度边界', `${targetText}外部智能体（ACP）内部自主处理工具调用与子任务编排；切回内置模型可重新配置子智能体分发。`]);
      } else {
        const effDelMode = controller.effectiveDelegationMode();
        const effDelPref = controller.effectiveDelegationPreference();
        const delHint = effDelMode === 'automatic'
          ? app.fixtures.preferenceHints[effDelPref]
          : '子智能体分发使用固定配置模板（自动选模偏好仅保留不生效），随首条消息发送一次性冻结。';
        notes.push(['开启位置与分发规则', `${targetText}${delHint}`]);
      }
    } else {
      const agent = controller.currentAgent();
      if (!agent.isRoot) {
        notes.push([
          '子智能体只读说明',
          '历史、进展、冻结模型与独立工作树仅供查看；需要它继续或调整方向时，请在主会话向主智能体表达要求。运行中的子智能体仅在顶栏「智能体」菜单行内提供单独停止入口。'
        ]);
      } else {
        if (s.continuationReason) {
          notes.push(['待继续状态说明', s.continuationReason]);
        }
        const canCompact = !s.live && !s.pending && s.transitionPhase === 'none' && s.history.length > 0;
        if (!canCompact) {
          notes.push(['上下文压缩条件', (s.live || s.pending || s.transitionPhase !== 'none')
            ? '当前会话正在执行或等待处理，轮次空闲后可从页脚上下文环手动触发强制压缩。'
            : '有已结束历史记录后可从页脚上下文环手动触发强制压缩。']);
        }
      }
    }
    return notes;
  }

  app.composer = {
    MenuManager,
    PromptComposerCard,
    renderTopbar,
    renderAcpBrandMark,
    buildPreparationHTML,
    renderStartStage,
    buildAgentReadOnlyDock,
    describeContextNotes
  };
})();
