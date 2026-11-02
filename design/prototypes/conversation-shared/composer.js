(() => {
  'use strict';
  const app = window.AnyworkConversation;
  const { escape, node, icon, spinner, icons, statusLabel } = app.ui;

  /* ========================================================================
     1. Popover Menu Manager (Single Active Menu + Viewport Auto-Flip)
     ======================================================================== */
  class MenuManager {
    constructor(root, getWindowEl) {
      this.root = root;
      this.getWindowEl = getWindowEl;
      this.openId = null;
      this.projectSearchQuery = '';
    }

    closeAll() {
      if (!this.openId) return;
      this.openId = null;
      this.projectSearchQuery = '';
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
        ${!isSubagent ? `
          <span
            class="cv-frozen-chip cv-frozen-delegation"
            title="会话创建时已固定子智能体分发策略（只读）：${escape(ft.delegationSummary)}">
            ${icon('sliders-horizontal')}
            <span>${escape(ft.delegationSummary)}</span>
          </span>
        ` : ''}
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
          title="查看主会话与子智能体列表，或停止运行中的子智能体">
          ${icon('users')}
          <span class="cv-tabular">${activeAgentsCount} 个智能体</span>
          <span class="cv-caret">${icon('chevron-down')}</span>
        </button>
        <div class="cv-menu cv-menu-agents align-right" data-menu-panel="agents" role="menu" hidden>
          <div class="cv-menu-head">
            <span>会话智能体目录</span>
            <small>子会话只读 · 可单独停止</small>
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
                  <span class="cv-agent-state-pill" data-status="${escape(ag.status)}">${escape(statusLabel(ag.status))}</span>
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
                  title="添加附件（支持拖放文件或 Ctrl+V 粘贴剪贴板图片）"
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
                    <span class="cv-item-main">粘贴剪贴板截图（模拟 Ctrl+V）</span>
                  </button>
                </div>
              </div>
              <span class="cv-kbd-hint"></span>
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
      this.kbdHintEl = this.node.querySelector('.cv-kbd-hint');
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
            this.controller.addPastedImage();
            this.helpers.toast('已粘贴图片缩略图（点击缩略图可弹层查看大图）');
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
        } else if (event.key === 'Escape' && this.controller.state.stage === 'session' && this.controller.state.live) {
          event.preventDefault();
          this.controller.stop();
        }
      });

      this.textarea.addEventListener('paste', event => {
        const items = Array.from(event.clipboardData?.items || []);
        const imageItems = items.filter(i => i.type.startsWith('image/'));
        if (imageItems.length) {
          event.preventDefault();
          const files = imageItems.map(i => i.getAsFile()).filter(Boolean);
          if (files.length) this.controller.attach(files, { source: 'clipboard' });
          else this.controller.addPastedImage();
          this.helpers.toast('已粘贴图片缩略图（点击缩略图可弹层查看大图）');
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
      const action = this.controller.getPrimaryAction();
      const mode = this.controller.currentMode();
      const model = this.controller.currentModel();

      // 1. Sync textarea value & context-aware placeholder without clobbering active typing
      if (this.textarea.value !== s.draft) {
        this.textarea.value = s.draft;
        this.syncTextareaHeight();
      }
      let placeholder = '描述下一步，或补充你的想法…';
      if (s.stage === 'start') {
        placeholder = locks.prepRunning ? '环境准备期间仍可提前输入下一条草稿…' : '描述你的需求…';
      } else if (s.transitionPhase === 'stopping') {
        placeholder = '正在收束清理当前执行，草稿内容可继续编辑并保留…';
      } else if (!s.frozenThread.routeAvailable) {
        placeholder = '当前模型不可用（草稿可正常编辑，请先在右下角改选可用模型）…';
      } else if (s.live) {
        placeholder = '会话运行中，可提前拟定下一条消息、拖放文件或 Ctrl+V 粘贴图片…';
      } else if (s.resumable) {
        placeholder = '可直接点击右侧「继续」，或输入补充指示后「发送并继续」…';
      }
      this.textarea.placeholder = placeholder;

      // 2. Sync keyboard / transition hint (keeps right-hand primary action slot 100% fixed width)
      this.kbdHintEl.textContent = s.stage === 'start'
        ? (locks.prepRunning ? '正在准备会话空间…' : 'Enter 发送 · Shift + Enter 换行')
        : action.kind === 'stopping'
          ? '正在停止收束当前执行…'
          : action.kind === 'continuing'
            ? '正在恢复执行…'
            : s.live
              ? '运行中可并发拟稿 · Esc 停止'
              : s.resumable
                ? '已停止 · 点击右侧 ▶ 继续，或输入补充内容发送'
                : 'Enter 发送 · Shift + Enter 换行';

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

      // 4. Sync inline reason region (route blocker & continuation note)
      const reasonLines = [];
      if (s.stage === 'session' && !s.frozenThread.routeAvailable) {
        reasonLines.push({
          blocker: true,
          iconName: 'triangle-alert',
          text: '当前模型不可用，暂时不能继续。请在右下角模型选择器改选其他可用模型。'
        });
      }
      if (s.stage === 'session' && s.resumable && s.continuationReason) {
        reasonLines.push({
          blocker: false,
          iconName: 'info',
          text: s.continuationReason
        });
      }
      this.reasonEl.hidden = reasonLines.length === 0;
      this.reasonEl.innerHTML = reasonLines.map(line => `
        <div class="cv-reason-line ${line.blocker ? 'is-blocker' : ''}">
          ${icon(line.iconName)}
          <span>${escape(line.text)}</span>
        </div>
      `).join('');
      if (reasonLines.length) icons(this.reasonEl);

      // 5. Sync 3-Part Lock-Aware Route Selector Bar (Mode · Model · Effort)
      const botManaged = s.stage === 'session' && s.frozenThread.botManaged;
      const routeUnavailable = s.stage === 'session' && !s.frozenThread.routeAvailable;
      const nextRouteSig = JSON.stringify({
        modeId: mode.id,
        modeEditable: locks.modeEditable,
        modeReason: locks.modeReason,
        modelId: model.id,
        modelEditable: locks.modelEditable,
        modelReason: locks.modelReason,
        effort: s.effort,
        effortSupported: locks.effortSupported,
        effortEditable: locks.effortEditable,
        effortReason: locks.effortReason,
        botManaged,
        routeUnavailable
      });

      if (nextRouteSig !== this.routeSignature) {
        this.routeSignature = nextRouteSig;
        this.routeBarEl.innerHTML = `
          <!-- Work Mode Selector -->
          <div class="cv-menu-anchor">
            ${locks.modeEditable ? `
              <button
                type="button"
                class="cv-quiet-trigger"
                data-route-trigger="mode"
                data-menu-trigger="mode"
                aria-haspopup="menu"
                aria-expanded="false"
                title="${escape('工作模式：' + mode.label)}">
                <span>${escape(mode.label)}</span>
                <span class="cv-caret">${icon('chevron-down')}</span>
              </button>
              <div class="cv-menu align-right" data-menu-panel="mode" role="menu" hidden>
                <div class="cv-menu-head"><span>工作模式</span></div>
                ${app.fixtures.modes.map(m => {
                  const selected = m.id === mode.id;
                  return `
                    <button type="button" class="cv-menu-item ${selected ? 'is-selected' : ''}" data-pick-mode="${escape(m.id)}">
                      <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
                      <span class="cv-item-main">
                        <div class="cv-item-title">${escape(m.label)}</div>
                        <div class="cv-item-sub">${escape(m.desc)}</div>
                      </span>
                    </button>
                  `;
                }).join('')}
              </div>
            ` : `
              <span
                class="cv-quiet-trigger is-disabled"
                aria-disabled="true"
                title="${escape(locks.modeReason)}">
                <span>${escape(mode.label)}</span>
                <span class="cv-caret">${icon('chevron-down')}</span>
              </span>
            `}
          </div>

          ${botManaged ? `
            <span
              class="cv-quiet-trigger is-disabled is-static-label"
              aria-disabled="true"
              title="模型与思考强度由机器人设置统一管理">
              ${icon('bot')}
              <span>${escape(model.name)} · 由机器人统一设置</span>
            </span>
          ` : `
            ${routeUnavailable ? `
              <button
                type="button"
                class="cv-route-warn-btn"
                data-warn-explain
                title="点击查看当前模型不可用原因"
                aria-label="当前模型路由不可用详情">
                ${icon('triangle-alert')}
              </button>
            ` : ''}

            <!-- Main Agent Model Selector -->
            <div class="cv-menu-anchor">
              ${locks.modelEditable ? `
                <button
                  type="button"
                  class="cv-quiet-trigger"
                  data-route-trigger="model"
                  data-menu-trigger="model"
                  aria-haspopup="menu"
                  aria-expanded="false"
                  title="${escape(`主智能体模型：${model.accountName} / ${model.name}`)}">
                  <span>${escape(model.name)}</span>
                  <span class="cv-caret">${icon('chevron-down')}</span>
                </button>
                <div class="cv-menu cv-menu-models align-right" data-menu-panel="model" role="menu" hidden>
                  ${app.fixtures.accountGroups.map((grp, gIdx) => `
                    ${gIdx > 0 ? '<div class="cv-menu-divider"></div>' : ''}
                    <div class="cv-menu-head"><span>${escape(grp.accountName)}</span></div>
                    ${grp.models.map(m => {
                      const selected = m.id === model.id;
                      return `
                        <button type="button" class="cv-menu-item ${selected ? 'is-selected' : ''}" data-pick-model="${escape(m.id)}">
                          <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
                          <span class="cv-item-main">${escape(m.name)}</span>
                          <span class="cv-cap-badges">
                            ${m.caps.map(c => `<span class="cv-cap-badge">${escape(c)}</span>`).join('')}
                          </span>
                        </button>
                      `;
                    }).join('')}
                  `).join('')}
                </div>
              ` : `
                <span
                  class="cv-quiet-trigger is-disabled"
                  aria-disabled="true"
                  title="${escape(locks.modelReason)}">
                  <span>${escape(model.name)}</span>
                  <span class="cv-caret">${icon('chevron-down')}</span>
                </span>
              `}
            </div>

            <!-- Reasoning Effort Selector -->
            <div class="cv-menu-anchor">
              ${locks.effortEditable ? `
                <button
                  type="button"
                  class="cv-quiet-trigger cv-mono is-effort"
                  data-route-trigger="effort"
                  data-menu-trigger="effort"
                  aria-haspopup="menu"
                  aria-expanded="false"
                  title="${escape('思考强度：' + s.effort)}">
                  <span>${escape(s.effort || '—')}</span>
                  <span class="cv-caret">${icon('chevron-down')}</span>
                </button>
                <div class="cv-menu align-right" data-menu-panel="effort" role="menu" hidden>
                  <div class="cv-menu-head"><span>思考强度</span></div>
                  ${model.efforts.map(ef => {
                    const selected = ef === s.effort;
                    return `
                      <button type="button" class="cv-menu-item cv-mono ${selected ? 'is-selected' : ''}" data-pick-effort="${escape(ef)}">
                        <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
                        <span class="cv-item-main">${escape(ef)}</span>
                      </button>
                    `;
                  }).join('')}
                </div>
              ` : `
                <span
                  class="cv-quiet-trigger cv-mono is-effort is-disabled"
                  aria-disabled="true"
                  title="${escape(locks.effortReason)}">
                  <span>${escape(locks.effortSupported ? (s.effort || '—') : '—')}</span>
                  <span class="cv-caret">${icon('chevron-down')}</span>
                </span>
              `}
            </div>
          `}
        `;

        // Bind editable route triggers
        ['mode', 'model', 'effort'].forEach(kind => {
          const btn = this.routeBarEl.querySelector(`[data-route-trigger="${kind}"]`);
          const panel = this.routeBarEl.querySelector(`[data-menu-panel="${kind}"]`);
          if (btn && panel) {
            btn.addEventListener('click', () => this.menuManager.toggle(kind, btn, panel, true));
          }
          this.menuManager.restoreIfOpen(kind, btn, panel, true);
        });

        this.routeBarEl.querySelector('[data-warn-explain]')?.addEventListener('click', () => {
          this.controller.explainLock(this.controller.state.frozenThread.routeUnavailableReason, 'warning');
        });

        this.routeBarEl.querySelectorAll('[data-pick-mode]').forEach(btn => {
          btn.addEventListener('click', () => {
            this.menuManager.closeAll();
            this.controller.setWorkMode(btn.dataset.pickMode);
          });
        });
        this.routeBarEl.querySelectorAll('[data-pick-model]').forEach(btn => {
          btn.addEventListener('click', () => {
            this.menuManager.closeAll();
            this.controller.setModel(btn.dataset.pickModel);
          });
        });
        this.routeBarEl.querySelectorAll('[data-pick-effort]').forEach(btn => {
          btn.addEventListener('click', () => {
            this.menuManager.closeAll();
            this.controller.setEffort(btn.dataset.pickEffort);
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
    const steps = ['检查项目', '准备工作区', '初始化会话', '提交请求'];
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
              <p>${isFailed ? '输入与附件草稿已原位保留，可切换工作区模式或调整后重新发送。' : '准备好会话空间后将自动进入运行期会话并处理你的首条请求。'}</p>
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
              <span>${prep.frozenWorkspaceMode === 'worktree' ? '新建工作树 (worktree)' : '本地目录 (local)'}</span>
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
        firstMatchId: null,
        listHTML: `
          <div class="cv-project-empty" role="status">
            ${icon('search-x')}
            <span>未找到匹配「${escape(q)}」的已有项目</span>
            <small>可尝试输入名称、路径或 SSH 别名缩写，或点击下方「新建项目…」</small>
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
      firstMatchId: scored[0]?.proj.id || null,
      listHTML
    };
  }

  function renderStartStage(host, controller, composerCard, menuManager, helpers) {
    const s = controller.state;
    const locks = controller.getLockState();
    const project = controller.currentProject();
    const standalone = s.targetType === 'standalone';
    const effDelMode = controller.effectiveDelegationMode();
    const effDelPref = controller.effectiveDelegationPreference();
    const hasDelOverride = Boolean(s.delegationModeOverride || s.delegationPrefOverride);

    let subtitle = '';
    if (standalone) {
      subtitle = '当前新会话将开启在「无项目」（保存在 Documents/anywork），也可点击下方切换至已有项目或新建项目。';
    } else if (project?.sshAlias) {
      subtitle = s.workspaceMode === 'worktree'
        ? `当前新会话将在远程项目「${project.name}」（SSH · ${project.sshAlias}）从 HEAD 检出独立工作树隔离改动。`
        : `当前新会话将在远程项目「${project.name}」（SSH · ${project.sshAlias}）目录中直接协作。`;
    } else {
      subtitle = s.workspaceMode === 'worktree'
        ? `当前新会话将在项目「${project.name}」从 HEAD 新建独立 Git 工作树，代码修改与原工作区互不干扰。`
        : `当前新会话将在项目「${project.name}」中开启，可在下方切换为无项目、其他项目或新建工作树。`;
    }

    const heroHTML = s.preparation
      ? buildPreparationHTML(controller)
      : `
        <div class="cv-welcome">
          <h2>想从哪里开始？</h2>
          <p>${escape(subtitle)}</p>
        </div>
      `;

    const defaultModeName = controller.defaults.delegationMode === 'automatic' ? '自动选模' : '固定配置模板';
    const defaultPrefName = { economy: '经济', balanced: '平衡', fast: '快速' }[controller.defaults.delegationPreference];
    const currentSearchQuery = menuManager.openId === 'project' ? (menuManager.projectSearchQuery || '') : '';
    const initialProjMenu = renderProjectMenuListHTML(controller, currentSearchQuery);

    host.innerHTML = `
      <div class="cv-start-col">
        <div class="cv-hero-slot">${heroHTML}</div>

        ${s.lockNotice ? `
          <div class="cv-lock-notice ${s.lockNoticeTone === 'warning' ? 'is-warning' : ''}" role="status">
            ${icon('info')}
            <span class="cv-lock-notice-text">${escape(s.lockNotice)}</span>
            <button type="button" class="cv-lock-notice-close" data-dismiss-notice aria-label="关闭提示">${icon('x')}</button>
          </div>
        ` : ''}

        <div class="cv-start-envelope" aria-label="新会话创建环境栏与输入卡">
          <div class="cv-env-bar">
            <div class="cv-env-left">
              <div class="cv-menu-anchor">
                ${locks.prepRunning ? `
                  <span
                    class="cv-quiet-trigger cv-project-trigger is-disabled"
                    aria-disabled="true"
                    title="正在准备新会话环境，所属项目已按提交快照固定">
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
                    title="${escape(standalone
                      ? '新会话将开启在：无项目（保存在 C:\\Users\\dev\\Documents\\anywork）· 点击可切换已有项目或新建项目'
                      : `新会话将开启在项目：${project.name}（${project.path}）· 点击可切换为无项目、已有项目或新建项目`)}">
                    ${icon(standalone ? 'file-box' : (project?.sshAlias ? 'server' : 'folder'))}
                    <span class="cv-anchor-name">${escape(standalone ? '无项目' : project.name)}</span>
                    ${project?.sshAlias ? `<span class="cv-ssh-pill">SSH · ${escape(project.sshAlias)}</span>` : ''}
                    <span class="cv-caret">${icon('chevron-down')}</span>
                  </button>

                  <div class="cv-menu cv-menu-project align-left" data-menu-panel="project" role="menu" aria-label="选择新会话开启位置" hidden>
                    <div class="cv-project-search-wrap">
                      <span class="cv-project-search-icon">${icon('search')}</span>
                      <input
                        type="text"
                        class="cv-project-search-input"
                        value="${escape(currentSearchQuery)}"
                        placeholder="模糊搜索已有项目（名称、路径、SSH）…"
                        aria-label="模糊搜索已有项目"
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

                    <div class="cv-menu-head">
                      <span>新会话开启位置</span>
                      <small>会话创建时固定</small>
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
                        <div class="cv-item-sub">不绑定代码仓库 · 默认保存在 Documents/anywork</div>
                      </span>
                    </button>

                    <div class="cv-menu-divider"></div>

                    <div class="cv-menu-head">
                      <span>已有项目</span>
                      <small data-project-count>${escape(initialProjMenu.countText)}</small>
                    </div>
                    <div class="cv-project-list" role="group" aria-label="已有项目列表">
                      ${initialProjMenu.listHTML}
                    </div>

                    <div class="cv-menu-divider"></div>

                    <button
                      type="button"
                      class="cv-menu-item cv-new-project-item"
                      role="menuitem"
                      data-pick-target="new-project">
                      <span class="cv-check-slot">${icon('plus')}</span>
                      <span class="cv-ws-item-icon is-accent">${icon('folder-plus')}</span>
                      <span class="cv-item-main">
                        <div class="cv-item-title">新建项目…</div>
                        <div class="cv-item-sub">添加本地代码目录或连接 ~/.ssh/config 远程主机目录</div>
                      </span>
                    </button>
                  </div>
                `}
              </div>

              <span class="cv-v-sep" aria-hidden="true"></span>

              ${standalone ? `
                <span
                  class="cv-quiet-trigger is-disabled is-static-label"
                  aria-disabled="true"
                  title="无项目新会话固定保存在 Documents/anywork，不提供 Git 工作树选项">
                  ${icon('folder')}
                  <span>固定本地目录</span>
                </span>
              ` : `
                <div class="cv-menu-anchor">
                  ${locks.prepRunning ? `
                    <span
                      class="cv-quiet-trigger cv-ws-trigger ${s.workspaceMode === 'worktree' ? 'is-worktree' : ''} is-disabled"
                      aria-disabled="true"
                      title="正在准备新会话环境，工作区模式已按提交快照固定">
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
                      title="${s.workspaceMode === 'worktree' ? '会话工作区：新建工作树（从仓库当前 HEAD 检出）' : '会话工作区：本地目录（直接使用当前项目目录）'}">
                      ${icon(s.workspaceMode === 'worktree' ? 'git-branch' : 'folder')}
                      <span>${s.workspaceMode === 'worktree' ? '新建工作树' : '本地目录'}</span>
                      <span class="cv-caret">${icon('chevron-down')}</span>
                    </button>

                    <div class="cv-menu cv-menu-ws align-left" data-menu-panel="workspace" role="menu" hidden>
                      <div class="cv-menu-head">
                        <span>会话工作区</span>
                        <small>会话创建时固定</small>
                      </div>
                      ${[
                        {
                          val: 'local',
                          iconName: 'folder',
                          label: '本地目录',
                          desc: '直接在当前项目目录中读写与执行'
                        },
                        {
                          val: 'worktree',
                          iconName: 'git-branch',
                          label: '新建工作树',
                          desc: '从仓库当前 HEAD 检出独立工作树隔离改动'
                        }
                      ].map(opt => {
                        const selected = s.workspaceMode === opt.val;
                        return `
                          <button type="button" class="cv-menu-item ${selected ? 'is-selected' : ''}" data-pick-ws="${opt.val}">
                            <span class="cv-check-slot">${selected ? icon('check') : ''}</span>
                            <span class="cv-ws-item-icon ${opt.val === 'worktree' ? 'is-worktree' : ''}">${icon(opt.iconName)}</span>
                            <span class="cv-item-main">
                              <div class="cv-item-title">${escape(opt.label)}</div>
                              <div class="cv-item-sub">${escape(opt.desc)}</div>
                            </span>
                          </button>
                        `;
                      }).join('')}
                    </div>
                  `}
                </div>
              `}
            </div>

            <div class="cv-env-right">
              <div class="cv-menu-anchor">
                ${locks.prepRunning ? `
                  <span
                    class="cv-quiet-trigger is-disabled"
                    aria-disabled="true"
                    title="正在准备新会话环境，子智能体分发策略已按提交快照固定">
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
                    title="子智能体分发策略 · ${escape(controller.delegationSummaryText())}（创建会话时冻结）">
                    ${icon('sliders-horizontal')}
                    <span>${escape(controller.delegationSummaryText())}</span>
                    <span class="cv-caret">${icon('chevron-down')}</span>
                  </button>

                  <div class="cv-menu cv-menu-wide align-right" data-menu-panel="delegation" role="menu" hidden>
                    <div class="cv-menu-head">
                      <span>分发模式</span>
                      <small>会话创建时固定</small>
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
                      <small>${effDelMode === 'automatic' ? '当前生效' : '固定模式下保留'}</small>
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

                    <div class="cv-menu-footnote">
                      ${effDelMode === 'automatic'
                        ? escape(app.fixtures.preferenceHints[effDelPref])
                        : '仅自动选模时生效；固定配置模板模式下保留该偏好值。'}
                    </div>
                  </div>
                `}
              </div>
            </div>
          </div>

          <div class="cv-start-card-mount"></div>
        </div>
      </div>
    `;

    // Mount the exact shared PromptComposerCard inside the concentric start envelope!
    host.querySelector('.cv-start-card-mount').append(composerCard.node);
    composerCard.update();

    host.querySelector('[data-dismiss-notice]')?.addEventListener('click', () => controller.dismissLockNotice());
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
    let latestFirstMatchId = initialProjMenu.firstMatchId;

    const syncProjectSearchList = query => {
      menuManager.projectSearchQuery = query;
      if (projSearchClearBtn) projSearchClearBtn.hidden = !query;
      const rendered = renderProjectMenuListHTML(controller, query);
      latestFirstMatchId = rendered.firstMatchId;
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

    projSearchInput?.addEventListener('keydown', event => {
      if (event.isComposing || event.keyCode === 229) return;
      if (event.key === 'Escape' && projSearchInput.value) {
        event.preventDefault();
        event.stopPropagation();
        projSearchInput.value = '';
        syncProjectSearchList('');
      } else if (event.key === 'Enter' && projSearchInput.value.trim() && latestFirstMatchId) {
        event.preventDefault();
        event.stopPropagation();
        const targetId = latestFirstMatchId;
        menuManager.closeAll();
        if (helpers.selectProjectOnStart) helpers.selectProjectOnStart(targetId);
        else controller.selectProjectStart(targetId);
      }
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
    const waiting = agent.status === 'waiting' || agent.status === 'stopped';
    const wrapper = node(`
      <section class="cv-readonly-dock" aria-label="子智能体会话只读说明">
        <div class="cv-readonly-head">
          <span class="cv-readonly-title">
            <span>子智能体会话（只读）</span>
          </span>
          <button type="button" class="cv-button cv-primary" data-readonly-back>
            ${icon('arrow-left')}
            <span>返回主会话继续沟通</span>
          </button>
        </div>
        ${waiting ? `<p class="cv-readonly-copy">等待主智能体调度该成员。</p>` : ''}
        <p class="cv-readonly-copy">历史、进展、冻结模型与独立工作树仅供查看；需要它继续或调整方向时，请在主会话向主智能体表达要求。运行中的子智能体仅在顶栏「智能体」菜单行内提供单独停止入口。</p>
        <div class="cv-readonly-chips">
          <span class="cv-info-chip">
            ${icon('sparkles')}
            <span>状态：${escape(statusLabel(agent.status))}</span>
          </span>
          <span class="cv-info-chip">
            ${icon('cpu')}
            <span>冻结路由：${escape(agent.routeLabel)}</span>
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

  app.composer = {
    MenuManager,
    PromptComposerCard,
    renderTopbar,
    buildPreparationHTML,
    renderStartStage,
    buildAgentReadOnlyDock
  };
})();
