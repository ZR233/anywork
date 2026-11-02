(() => {
  'use strict';

  const escape = value => String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

  const lucideIcon = name => `<i data-lucide="${escape(name)}" aria-hidden="true"></i>`;

  function hydrateIcons(scope) {
    if (globalThis.lucide && scope) {
      globalThis.lucide.createIcons({
        nameAttr: 'data-lucide',
        attrs: { width: 15, height: 15, 'stroke-width': 1.85 },
        root: scope
      });
    }
  }

  /* ========================================================================
     1. Authentic Host App Color Vector Logos (Shared by Sidebar & Topbar)
     ======================================================================== */
  const HOST_APP_SVGS = {
    vscode: `
      <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
        <path d="M17.58 2.26a1.32 1.32 0 0 0-1.52.27L7.34 10.5 3.63 7.68a.88.88 0 0 0-1.13.06l-1.18 1.08a.89.89 0 0 0 0 1.31L4.7 13.2l-3.38 3.07a.89.89 0 0 0 0 1.31l1.18 1.08a.88.88 0 0 0 1.13.06l3.71-2.82 8.72 7.97a1.32 1.32 0 0 0 1.52.27l4.18-2.01a1.33 1.33 0 0 0 .76-1.2V5.47c0-.51-.3-.98-.76-1.2l-4.18-2.01Z" fill="#007ACC"/>
        <path d="M17.5 2.3v19.4l4.26-2.05c.46-.22.76-.69.76-1.2V5.55c0-.51-.3-.98-.76-1.2L17.5 2.3Z" fill="#1F9CF0"/>
        <path d="M17.5 7.22 10.62 13.2l6.88 5.98V7.22Z" fill="#FAF6EF"/>
      </svg>
    `,
    zed: `
      <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
        <rect x="2" y="2" width="20" height="20" rx="5" fill="#1F2024"/>
        <rect x="4.75" y="4.75" width="14.5" height="14.5" rx="3" stroke="#E8E8EC" stroke-width="1.45" stroke-opacity="0.72"/>
        <path d="M8.3 8.4h7.4L8.3 15.6h7.4" stroke="#FFFFFF" stroke-width="1.85" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
    `,
    terminal: `
      <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
        <rect x="2" y="3" width="20" height="18" rx="4.5" fill="#2A2B2F"/>
        <path d="M6.8 9.2 10.4 12l-3.6 2.8" stroke="#F0F3F6" stroke-width="1.85" stroke-linecap="round" stroke-linejoin="round"/>
        <path d="M12.2 15h4.8" stroke="#80B5D3" stroke-width="1.85" stroke-linecap="round"/>
      </svg>
    `
  };

  function hostAppLogo(appKey) {
    return `<span class="sb-host-logo">${HOST_APP_SVGS[appKey] || HOST_APP_SVGS.terminal}</span>`;
  }

  const SSH_HOSTS = [
    { alias: 'gpu-dev', spec: 'dev@10.24.8.16:22', auth: '密钥认证', defaultDir: '/srv/repos/pure-lang' },
    { alias: 'dcsdk2', spec: 'zhou@192.168.50.42:22', auth: 'ssh-agent', defaultDir: '/data/work/dcsdk2' },
    { alias: 'build-linux', spec: 'ci@10.24.12.90:2222', auth: '密钥认证', defaultDir: '/home/ci/workspace' }
  ];

  function createDefaultCatalog(fixtures) {
    // Merge & enrich canonical fixture projects so every existing scenario ID works seamlessly
    // while showcasing realistic sidebar hierarchy, paging, pin states, and status badges.
    const projects = [
      {
        id: 'pure-lang-pure',
        name: 'pure-lang-pure',
        path: 'C:\\Users\\dev\\work\\pure-lang-pure',
        sshAlias: null,
        isGit: true,
        pinned: true,
        defaultExpanded: true,
        pageSize: 5
      },
      {
        id: 'pure-lang-remote',
        name: 'pure-lang-remote',
        path: '/srv/repos/pure-lang',
        sshAlias: 'gpu-dev',
        isGit: true,
        pinned: false,
        defaultExpanded: true,
        pageSize: 5
      },
      {
        id: 'dcsdk2',
        name: 'dcsdk2',
        path: '/data/work/dcsdk2',
        sshAlias: 'dcsdk2',
        isGit: true,
        pinned: false,
        defaultExpanded: false,
        pageSize: 5
      },
      {
        id: 'xiaohu-home',
        name: '小糊-家',
        path: 'C:\\Users\\dev\\work\\xiaohu-home',
        sshAlias: null,
        isGit: true,
        pinned: false,
        defaultExpanded: false,
        pageSize: 5
      },
      {
        id: 'notes-plain-dir',
        name: 'design-notes',
        path: 'C:\\Users\\dev\\Documents\\design-notes',
        sshAlias: null,
        isGit: false,
        pinned: false,
        defaultExpanded: false,
        pageSize: 5
      }
    ];

    const threads = [
      // Project 1: pure-lang-pure
      {
        id: 'thr-main',
        workspaceId: 'pure-lang-pure',
        title: '完成 Issue #243 开发并创建关联 PR',
        worktree: true,
        branch: 'anywork/thr-01jc9k',
        workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure\\.anywork\\worktrees\\thr_01jc9k\\session',
        delegationSummary: '自动选模 · 平衡',
        scenario: 'running-locked',
        pinned: true,
        archived: false,
        status: 'running',
        updatedLabel: '刚刚'
      },
      {
        id: 'thr-questions',
        workspaceId: 'pure-lang-pure',
        title: '确认侧边栏组件化与二级菜单交互边界',
        worktree: true,
        branch: 'anywork/thr-01jd4p',
        workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure\\.anywork\\worktrees\\thr_01jd4p\\session',
        delegationSummary: '自动选模 · 平衡',
        scenario: 'questions',
        pinned: false,
        archived: false,
        status: 'attention',
        updatedLabel: '3 分钟前'
      },
      {
        id: 'thr-workflow',
        workspaceId: 'pure-lang-pure',
        title: '按设计稿完善账号管理页面并验证流程',
        worktree: true,
        branch: 'anywork/thr-01jb9m',
        workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure\\.anywork\\worktrees\\thr_01jb9m\\session',
        delegationSummary: '固定模板',
        scenario: 'workflow-locked',
        pinned: false,
        archived: false,
        status: 'idle',
        updatedLabel: '26 分钟前'
      },
      {
        id: 'thr-ci-deb',
        workspaceId: 'pure-lang-pure',
        title: '增加 CI x86 deb 发布并提 PR',
        worktree: true,
        branch: 'anywork/thr-01jb2c',
        workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure\\.anywork\\worktrees\\thr_01jb2c\\session',
        delegationSummary: '自动选模 · 平衡',
        scenario: 'idle',
        pinned: false,
        archived: false,
        status: 'idle',
        updatedLabel: '1 小时前'
      },
      {
        id: 'thr-close-issue',
        workspaceId: 'pure-lang-pure',
        title: '关闭已解决的 Issue',
        worktree: false,
        branch: null,
        workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure',
        delegationSummary: '自动选模 · 经济',
        scenario: 'receipts',
        pinned: false,
        archived: false,
        status: 'idle',
        updatedLabel: '3 小时前'
      },
      // Earlier paged items in pure-lang-pure (revealed via "查看更早会话")
      {
        id: 'thr-mode-prompt',
        workspaceId: 'pure-lang-pure',
        title: '分析 mode 提示词是否进入 system 提示词',
        worktree: false,
        branch: null,
        workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure',
        delegationSummary: '自动选模 · 平衡',
        scenario: 'idle',
        pinned: false,
        archived: false,
        status: 'idle',
        updatedLabel: '昨天'
      },
      {
        id: 'thr-feishu-file',
        workspaceId: 'pure-lang-pure',
        title: '重构飞书会话并支持双向文件传输',
        worktree: true,
        branch: 'anywork/thr-01ja4w',
        workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure\\.anywork\\worktrees\\thr_01ja4w\\session',
        delegationSummary: '自动选模 · 平衡',
        scenario: 'idle',
        pinned: false,
        archived: false,
        status: 'idle',
        updatedLabel: '2 天前'
      },
      {
        id: 'thr-helper-toolchain',
        workspaceId: 'pure-lang-pure',
        title: '在 rust-toolchain.toml 添加 helper 所需组件',
        worktree: false,
        branch: null,
        workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure',
        delegationSummary: '自动选模 · 快速',
        scenario: 'idle',
        pinned: false,
        archived: false,
        status: 'idle',
        updatedLabel: '3 天前'
      },

      // Project 2: pure-lang-remote (SSH)
      {
        id: 'thr-linux-gtk',
        workspaceId: 'pure-lang-remote',
        title: 'Linux 原生 GTK 预检与打包',
        worktree: true,
        branch: 'anywork/thr-01jb7x',
        workspacePath: '/srv/repos/pure-lang/.anywork/worktrees/thr_01jb7x/session',
        delegationSummary: '自动选模 · 快速',
        scenario: 'workgroup',
        pinned: false,
        archived: false,
        status: 'idle',
        updatedLabel: '42 分钟前'
      },
      {
        id: 'thr-read-images',
        workspaceId: 'pure-lang-remote',
        title: '界面走查截图与远端预览核对',
        worktree: false,
        branch: null,
        workspacePath: '/srv/repos/pure-lang',
        delegationSummary: '自动选模 · 平衡',
        scenario: 'read-images',
        pinned: false,
        archived: false,
        status: 'idle',
        updatedLabel: '2 小时前'
      },

      // Project 3: dcsdk2 (SSH, collapsed by default with 1 background running session!)
      {
        id: 'thr-dcsdk-link',
        workspaceId: 'dcsdk2',
        title: '排查交叉编译链接器符号冲突',
        worktree: true,
        branch: 'anywork/thr-01jc1r',
        workspacePath: '/data/work/dcsdk2/.anywork/worktrees/thr_01jc1r/session',
        delegationSummary: '自动选模 · 平衡',
        scenario: 'workgroup',
        pinned: false,
        archived: false,
        status: 'running',
        updatedLabel: '1 分钟前'
      },
      {
        id: 'thr-dcsdk-sync',
        workspaceId: 'dcsdk2',
        title: '切换到最新主线代码并校验头文件',
        worktree: false,
        branch: null,
        workspacePath: '/data/work/dcsdk2',
        delegationSummary: '自动选模 · 快速',
        scenario: 'idle',
        pinned: false,
        archived: false,
        status: 'idle',
        updatedLabel: '昨天'
      },

      // Project 4: 小糊-家 (Cleaned up redundant project prefix "小糊-家 / oc_5373..."!)
      {
        id: 'thr-bot-home',
        workspaceId: 'xiaohu-home',
        title: '飞书家庭群 · 每日提醒与文件归档助手',
        worktree: false,
        branch: null,
        workspacePath: 'C:\\Users\\dev\\work\\xiaohu-home',
        delegationSummary: '由机器人统一设置',
        scenario: 'bot-managed',
        pinned: false,
        archived: false,
        status: 'idle',
        updatedLabel: '4 小时前'
      },

      // Standalone (Non-Project) Sessions
      {
        id: 'thr-standalone-weather',
        workspaceId: '__standalone__',
        title: '查询济南今日天气',
        worktree: false,
        branch: null,
        workspacePath: 'C:\\Users\\dev\\Documents\\anywork',
        delegationSummary: '自动选模 · 快速',
        scenario: 'idle',
        pinned: false,
        archived: false,
        status: 'idle',
        updatedLabel: '今天 09:15'
      },
      {
        id: 'thr-standalone-doc',
        workspaceId: '__standalone__',
        title: '整理 Markdown 表格排版对比',
        worktree: false,
        branch: null,
        workspacePath: 'C:\\Users\\dev\\Documents\\anywork',
        delegationSummary: '自动选模 · 平衡',
        scenario: 'idle',
        pinned: false,
        archived: false,
        status: 'idle',
        updatedLabel: '昨天'
      },

      // Pre-populated Archived Sessions (for instant Archived view preview & restore!)
      {
        id: 'thr-arch-1',
        workspaceId: 'pure-lang-pure',
        title: '早期侧栏固定 232px 宽度布局调研记录',
        worktree: false,
        branch: null,
        workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure',
        delegationSummary: '自动选模 · 平衡',
        scenario: 'idle',
        pinned: false,
        archived: true,
        status: 'idle',
        updatedLabel: '10/21'
      },
      {
        id: 'thr-arch-2',
        workspaceId: '__standalone__',
        title: '临时正则表达式分组匹配测试',
        worktree: false,
        branch: null,
        workspacePath: 'C:\\Users\\dev\\Documents\\anywork',
        delegationSummary: '自动选模 · 经济',
        scenario: 'idle',
        pinned: false,
        archived: true,
        status: 'idle',
        updatedLabel: '10/18'
      }
    ];

    if (fixtures) {
      // Keep app.fixtures.projects & standaloneThreads synchronized for start-stage lookups
      fixtures.projects = projects.map(p => ({
        ...p,
        threads: threads.filter(t => t.workspaceId === p.id && !t.archived)
      }));
      fixtures.standaloneThreads = threads.filter(t => t.workspaceId === '__standalone__' && !t.archived);
    }

    return { projects, threads };
  }

  /* ========================================================================
     2. Shared Reusable StudioSidebar Component
     ======================================================================== */
  class StudioSidebar {
    constructor(options) {
      this.host = options.host;
      this.windowEl = options.windowEl;
      this.shellEl = options.shellEl;
      this.controller = options.controller;
      this.onToast = options.onToast || (() => {});
      this.onCopy = options.onCopy || (() => {});
      this.settingsHref = options.settingsHref || '../accounts-list/index.html';

      this.catalog = createDefaultCatalog(window.AnyworkConversation?.fixtures);
      this.expandedIds = new Set(
        this.catalog.projects.filter(p => p.defaultExpanded).map(p => p.id)
      );
      this.showMoreIds = new Set();

      this.searchQuery = '';
      this.filter = 'all'; // 'all' | 'running' | 'attention'
      this.archivedMode = false;
      this.sidebarWidth = 304;
      this.defaultWidth = 304;
      this.hasUpdate = true;

      this.openMenu = null; // { kind: 'thread'|'project', id: string, submenuOpen: boolean, triggerEl: HTMLElement }
      this.hoverTimer = null;
      this.activeHoverKey = '';
      this.addWizardState = { remote: false, sshAlias: 'gpu-dev', path: 'C:\\Users\\dev\\work\\my-rust-app', name: 'my-rust-app' };
      this.seq = 0;
      this.abort = new AbortController();

      this.mountSkeleton();
      this.bindEvents();
      this.syncWidthToShell();
      this.render();
    }

    get isFiltered() {
      return Boolean(this.searchQuery.trim()) || this.filter !== 'all' || this.archivedMode;
    }

    mountSkeleton() {
      this.host.classList.add('sb-host');
      this.host.innerHTML = `
        <div class="sb-top">
          <button
            type="button"
            class="sb-new-session-btn"
            data-sb-action="standalone-start"
            title="新建会话（进入新会话页，默认无项目，可在页内切换已有项目或新建项目 · Ctrl+N）">
            ${lucideIcon('square-pen')}
            <span>新建会话</span>
            <span class="sb-kbd">Ctrl+N</span>
          </button>

          <div class="sb-search-wrap">
            <span class="sb-search-icon">${lucideIcon('search')}</span>
            <input
              type="text"
              class="sb-search-input"
              placeholder="搜索项目与会话"
              aria-label="搜索项目与会话"
              autocomplete="off"
              spellcheck="false">
            <span class="sb-search-hint">Ctrl+K</span>
            <button type="button" class="sb-search-clear" title="清除搜索" aria-label="清除搜索" hidden>
              ${lucideIcon('x')}
            </button>
          </div>

          <div class="sb-filter-host"></div>
        </div>

        <div class="sb-scroll" role="tree" aria-label="项目与会话列表"></div>

        <div class="sb-foot"></div>

        <div
          class="sb-resizer"
          tabindex="0"
          role="separator"
          aria-orientation="vertical"
          aria-label="拖动调整侧边栏宽度（双击恢复默认宽度）"
          title="拖动调整宽度 · 双击恢复默认"></div>
      `;

      this.newSessionBtn = this.host.querySelector('.sb-new-session-btn');
      this.searchInput = this.host.querySelector('.sb-search-input');
      this.searchHint = this.host.querySelector('.sb-search-hint');
      this.searchClearBtn = this.host.querySelector('.sb-search-clear');
      this.filterHost = this.host.querySelector('.sb-filter-host');
      this.scrollEl = this.host.querySelector('.sb-scroll');
      this.footEl = this.host.querySelector('.sb-foot');
      this.resizerEl = this.host.querySelector('.sb-resizer');

      // Mobile drawer backdrop inside shell
      this.backdropEl = document.createElement('div');
      this.backdropEl.className = 'sb-drawer-backdrop';
      this.shellEl.append(this.backdropEl);

      // Window-level Portal for context menus, submenus & hover detail card (prevents overflow clipping!)
      this.portalEl = document.createElement('div');
      this.portalEl.className = 'sb-portal';
      this.portalEl.innerHTML = `
        <div class="sb-menu-layer" hidden></div>
        <div class="sb-hover-card" hidden></div>
      `;
      this.windowEl.append(this.portalEl);
      this.menuLayerEl = this.portalEl.querySelector('.sb-menu-layer');
      this.hoverCardEl = this.portalEl.querySelector('.sb-hover-card');

      // Component-owned modal dialogs
      this.dialogEl = document.createElement('dialog');
      this.dialogEl.className = 'sb-dialog';
      this.windowEl.append(this.dialogEl);

      hydrateIcons(this.host);
    }

    syncFixturesReference() {
      const fixtures = window.AnyworkConversation?.fixtures;
      if (!fixtures) return;
      fixtures.projects = this.catalog.projects.map(p => ({
        ...p,
        threads: this.catalog.threads.filter(t => t.workspaceId === p.id && !t.archived)
      }));
      fixtures.standaloneThreads = this.catalog.threads.filter(
        t => t.workspaceId === '__standalone__' && !t.archived
      );
    }

    registerCreatedThreadFromController() {
      const s = this.controller?.state;
      if (!s || s.stage !== 'session' || !s.frozenThread?.id) return;
      const ft = s.frozenThread;
      const exists = this.catalog.threads.some(t => t.id === ft.id);
      if (!exists) {
        const wsId = s.targetType === 'standalone' ? '__standalone__' : (s.projectId || this.catalog.projects[0]?.id);
        const created = {
          id: ft.id,
          workspaceId: wsId,
          title: ft.title,
          worktree: ft.workspaceMode === 'worktree',
          branch: ft.branch || null,
          workspacePath: ft.workspacePath,
          delegationSummary: ft.delegationSummary || '自动选模 · 平衡',
          scenario: 'workgroup',
          pinned: false,
          archived: false,
          status: 'running',
          updatedLabel: '刚刚'
        };
        this.catalog.threads.unshift(created);
        s.activeSidebarThreadId = created.id;
        if (wsId !== '__standalone__') this.expandedIds.add(wsId);
        this.syncFixturesReference();
      }
    }

    effectiveThreadStatus(thread) {
      const s = this.controller?.state;
      if (s && s.stage === 'session' && s.activeSidebarThreadId === thread.id) {
        let next = 'idle';
        if (s.pending) next = 'attention';
        else if (s.live || s.transitionPhase !== 'none') next = 'running';
        else {
          const last = s.history?.at(-1);
          if (last?.kind === 'outcome' && last.status === 'failed') next = 'failed';
        }
        thread.status = next;
        return next;
      }
      return thread.status || 'idle';
    }

    effectiveThreadTitle(thread) {
      const s = this.controller?.state;
      if (s && s.stage === 'session' && s.activeSidebarThreadId === thread.id && s.frozenThread?.id === thread.id) {
        return s.frozenThread.title || thread.title;
      }
      return thread.title;
    }

    sortedProjects() {
      return [...this.catalog.projects].sort((a, b) => {
        const pinDiff = (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0);
        if (pinDiff !== 0) return pinDiff;
        return this.catalog.projects.indexOf(a) - this.catalog.projects.indexOf(b);
      });
    }

    threadsForWorkspace(workspaceId) {
      const q = this.searchQuery.trim().toLowerCase();
      return this.catalog.threads
        .filter(t => {
          if (t.workspaceId !== workspaceId) return false;
          if (Boolean(t.archived) !== this.archivedMode) return false;
          const st = this.effectiveThreadStatus(t);
          if (!this.archivedMode) {
            if (this.filter === 'running' && st !== 'running') return false;
            if (this.filter === 'attention' && st !== 'attention') return false;
          }
          if (q) {
            const title = this.effectiveThreadTitle(t).toLowerCase();
            const proj = this.catalog.projects.find(p => p.id === workspaceId);
            const projMatch = proj && (`${proj.name} ${proj.path} ${proj.sshAlias || ''}`).toLowerCase().includes(q);
            if (!title.includes(q) && !t.workspacePath.toLowerCase().includes(q) && !projMatch) {
              return false;
            }
          }
          return true;
        })
        .sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0));
    }

    globalCounts() {
      let running = 0;
      let attention = 0;
      let archived = 0;
      for (const t of this.catalog.threads) {
        if (t.archived) {
          archived++;
          continue;
        }
        const st = this.effectiveThreadStatus(t);
        if (st === 'running') running++;
        else if (st === 'attention') attention++;
      }
      return { running, attention, archived };
    }

    /* ======================================================================
       Rendering (Preserves Search Input Focus & Scroll Offset)
       ====================================================================== */
    render() {
      this.registerCreatedThreadFromController();
      const s = this.controller?.state;
      if (s?.stage === 'session' && s.projectId && s.targetType !== 'standalone') {
        // Ensure initial selected project is expanded on scenario reset if no manual collapse happened
      }

      const standaloneDraftActive = s?.stage === 'start' && s.targetType === 'standalone';
      this.newSessionBtn.classList.toggle('is-active', Boolean(standaloneDraftActive));

      const hasQuery = Boolean(this.searchQuery);
      this.searchHint.hidden = hasQuery;
      this.searchClearBtn.hidden = !hasQuery;
      if (this.searchInput.value !== this.searchQuery) {
        this.searchInput.value = this.searchQuery;
      }

      const counts = this.globalCounts();
      this.renderFilterOrArchiveBar(counts);
      this.renderTree();
      this.renderFooter(counts);

      if (this.openMenu) {
        this.repositionOpenMenu();
      }
    }

    renderFilterOrArchiveBar(counts) {
      if (this.archivedMode) {
        this.filterHost.innerHTML = `
          <div class="sb-archived-banner" role="status">
            <span class="sb-archived-banner-title">
              ${lucideIcon('archive')}
              <span>已归档会话 (${counts.archived})</span>
            </span>
            <button type="button" class="sb-archived-back" data-sb-action="exit-archived">返回列表</button>
          </div>
        `;
        hydrateIcons(this.filterHost);
        return;
      }

      const tabs = [
        { id: 'all', label: '全部', count: 0 },
        { id: 'running', label: '进行中', count: counts.running },
        { id: 'attention', label: '待处理', count: counts.attention }
      ];

      this.filterHost.innerHTML = `
        <div class="sb-filter-bar" role="tablist" aria-label="按会话状态筛选">
          ${tabs.map(tab => {
            const selected = this.filter === tab.id;
            return `
              <button
                type="button"
                role="tab"
                aria-selected="${selected}"
                class="sb-filter-tab ${selected ? 'is-selected' : ''}"
                data-sb-action="set-filter"
                data-filter="${tab.id}">
                <span>${tab.label}</span>
                ${tab.count > 0 ? `<span class="sb-filter-count">${tab.count}</span>` : ''}
              </button>
            `;
          }).join('')}
        </div>
      `;
    }

    renderThreadRow(thread, project) {
      const s = this.controller?.state;
      const isSelected = !this.archivedMode && s?.stage === 'session' && s.activeSidebarThreadId === thread.id;
      const isMenuOpen = this.openMenu?.kind === 'thread' && this.openMenu.id === thread.id;
      const status = this.effectiveThreadStatus(thread);
      const title = this.effectiveThreadTitle(thread);

      if (this.archivedMode) {
        return `
          <div
            class="sb-thread-row is-archived"
            data-hover-kind="thread"
            data-thread-id="${escape(thread.id)}">
            <div class="sb-thread-select">
              <span class="sb-thread-title">${escape(title)}</span>
            </div>
            <div class="sb-thread-meta">
              <button
                type="button"
                class="sb-restore-btn"
                data-sb-action="restore-thread"
                data-thread-id="${escape(thread.id)}"
                title="恢复此会话到原列表">
                ${lucideIcon('archive-restore')}
                <span>恢复</span>
              </button>
            </div>
          </div>
        `;
      }

      // Fixed 4-axis trailing coordinate system: [pin (Col 1)] [worktree (Col 2)] [status (Col 3, always reserved)] [more (Col 4, always reserved)]
      // Ensures ZERO icon horizontal drift across idle / running / attention / failed / hover / active / pin transitions!
      const pinSlotHTML = thread.pinned
        ? `<button
            type="button"
            class="sb-slot sb-pin-badge"
            data-sb-action="toggle-pin-thread"
            data-thread-id="${escape(thread.id)}"
            title="已置顶 · 点击取消置顶"
            aria-label="取消置顶 ${escape(title)}">
            ${lucideIcon('pin')}
          </button>`
        : '';

      const worktreeSlotHTML = thread.worktree
        ? `<span class="sb-slot sb-worktree-slot is-worktree" title="独立 Git 工作树${thread.branch ? ' · ' + escape(thread.branch) : ''}">${lucideIcon('git-branch')}</span>`
        : (thread.pinned ? `<span class="sb-slot sb-worktree-slot is-empty" aria-hidden="true"></span>` : '');

      let statusSlotHTML = `<span class="sb-slot sb-status-slot is-empty" aria-hidden="true"></span>`;
      if (status === 'running') {
        statusSlotHTML = `<span class="sb-slot sb-status-slot is-running" title="进行中" aria-label="进行中"><span class="sb-ring"></span></span>`;
      } else if (status === 'attention') {
        statusSlotHTML = `<span class="sb-slot sb-status-slot is-attention" title="等待你的确认或回答" aria-label="待处理">${lucideIcon('circle-help')}</span>`;
      } else if (status === 'failed') {
        statusSlotHTML = `<span class="sb-slot sb-status-slot is-failed" title="上次执行异常中断" aria-label="执行失败">${lucideIcon('circle-alert')}</span>`;
      }

      return `
        <div
          class="sb-thread-row ${isSelected ? 'is-active' : ''} ${isMenuOpen ? 'is-menu-open' : ''}"
          role="treeitem"
          aria-selected="${isSelected}"
          data-hover-kind="thread"
          data-thread-id="${escape(thread.id)}">
          <button
            type="button"
            class="sb-thread-select"
            data-sb-action="select-thread"
            data-thread-id="${escape(thread.id)}">
            <span class="sb-thread-title">${escape(title)}</span>
          </button>
          <div class="sb-thread-meta">
            ${pinSlotHTML}
            ${worktreeSlotHTML}
            ${statusSlotHTML}
            <span class="sb-slot sb-more-slot">
              <button
                type="button"
                class="sb-more-btn"
                data-sb-action="thread-menu"
                data-thread-id="${escape(thread.id)}"
                aria-haspopup="menu"
                aria-expanded="${isMenuOpen}"
                title="会话操作"
                aria-label="${escape(title)} 更多操作">
                ${lucideIcon('ellipsis')}
              </button>
            </span>
          </div>
        </div>
      `;
    }

    renderTree() {
      const s = this.controller?.state;
      const q = this.searchQuery.trim().toLowerCase();
      const projects = this.sortedProjects();

      const visibleProjectBlocks = [];
      for (const proj of projects) {
        const rows = this.threadsForWorkspace(proj.id);
        const nameMatchesQuery = q && (`${proj.name} ${proj.path} ${proj.sshAlias || ''}`).toLowerCase().includes(q);

        if (this.isFiltered && rows.length === 0 && !(this.filter === 'all' && !this.archivedMode && nameMatchesQuery)) {
          continue;
        }

        const expanded = this.isFiltered || this.expandedIds.has(proj.id);
        const isOwner = !this.archivedMode && s?.stage === 'session' && s.targetType !== 'standalone' && s.projectId === proj.id;
        const isDraftTarget = !this.archivedMode && s?.stage === 'start' && s.targetType === 'project' && s.projectId === proj.id;
        const isMenuOpen = this.openMenu?.kind === 'project' && this.openMenu.id === proj.id;

        // Background activity summary when a project is collapsed
        let collapsedRunning = 0;
        let collapsedAttention = 0;
        if (!expanded && !this.archivedMode) {
          for (const t of this.catalog.threads) {
            if (t.workspaceId !== proj.id || t.archived) continue;
            const st = this.effectiveThreadStatus(t);
            if (st === 'running') collapsedRunning++;
            else if (st === 'attention') collapsedAttention++;
          }
        }

        // Pagination: show all pinned + first `pageSize` unpinned unless "show more" is active or filtered
        let displayRows = rows;
        let hiddenCount = 0;
        if (expanded && !this.isFiltered && !this.showMoreIds.has(proj.id)) {
          const pinnedRows = rows.filter(r => r.pinned);
          const normalRows = rows.filter(r => !r.pinned);
          const limit = proj.pageSize || 5;
          if (normalRows.length > limit) {
            displayRows = [...pinnedRows, ...normalRows.slice(0, limit)];
            hiddenCount = normalRows.length - limit;
          }
        }

        visibleProjectBlocks.push(`
          <div class="sb-project-group ${expanded ? 'is-expanded' : ''}" data-project-group="${escape(proj.id)}">
            <div
              class="sb-project-row ${isOwner ? 'is-owner' : ''} ${isDraftTarget ? 'is-draft-target' : ''} ${isMenuOpen ? 'is-menu-open' : ''}"
              data-hover-kind="project"
              data-project-id="${escape(proj.id)}">
              <button
                type="button"
                class="sb-proj-toggle"
                data-sb-action="toggle-project"
                data-project-id="${escape(proj.id)}"
                aria-expanded="${expanded}">
                <span class="sb-proj-chevron">${lucideIcon('chevron-right')}</span>
                <span class="sb-proj-folder">${lucideIcon(expanded ? 'folder-open' : 'folder')}</span>
                <span class="sb-proj-name">${escape(proj.name)}</span>
                ${proj.sshAlias ? `<span class="sb-ssh-badge">SSH</span>` : ''}
                ${proj.pinned ? `<span class="sb-proj-pin-mark" title="已置顶项目">${lucideIcon('pin')}</span>` : ''}
              </button>

              <div class="sb-proj-tail">
                ${(!expanded && (collapsedRunning > 0 || collapsedAttention > 0)) ? `
                  <span class="sb-proj-collapsed-status">
                    ${collapsedRunning > 0 ? `<span class="sb-ring" title="${collapsedRunning} 个会话进行中"></span>` : ''}
                    ${collapsedAttention > 0 ? `<span class="sb-attention-pill" title="${collapsedAttention} 个会话待处理">${collapsedAttention}</span>` : ''}
                  </span>
                ` : ''}
                ${!this.archivedMode ? `
                  <span class="sb-proj-actions">
                    <button
                      type="button"
                      class="sb-icon-btn"
                      data-sb-action="project-new-session"
                      data-project-id="${escape(proj.id)}"
                      title="在 ${escape(proj.name)} 中新建会话"
                      aria-label="在 ${escape(proj.name)} 中新建会话">
                      ${lucideIcon('plus')}
                    </button>
                    <button
                      type="button"
                      class="sb-icon-btn"
                      data-sb-action="project-menu"
                      data-project-id="${escape(proj.id)}"
                      aria-haspopup="menu"
                      aria-expanded="${isMenuOpen}"
                      title="项目操作"
                      aria-label="${escape(proj.name)} 项目操作">
                      ${lucideIcon('ellipsis')}
                    </button>
                  </span>
                ` : ''}
              </div>
            </div>

            ${expanded ? `
              <div class="sb-thread-list" role="group">
                ${displayRows.length
                  ? displayRows.map(t => this.renderThreadRow(t, proj)).join('')
                  : `<div class="sb-empty-note">${this.isFiltered ? '无匹配会话' : '暂无会话，点击项目右侧 + 开始'}</div>`
                }
                ${hiddenCount > 0 ? `
                  <button
                    type="button"
                    class="sb-earlier-btn"
                    data-sb-action="show-earlier"
                    data-project-id="${escape(proj.id)}">
                    ${lucideIcon('history')}
                    <span>查看更早会话 (${hiddenCount})</span>
                  </button>
                ` : ''}
              </div>
            ` : ''}
          </div>
        `);
      }

      const standaloneRows = this.threadsForWorkspace('__standalone__');
      const showStandaloneSection = !this.isFiltered || standaloneRows.length > 0;
      const nothingMatches = this.isFiltered && visibleProjectBlocks.length === 0 && standaloneRows.length === 0;

      const prevScroll = this.scrollEl.scrollTop;
      this.scrollEl.innerHTML = nothingMatches
        ? `
          <div class="sb-empty-state">
            <span>${this.archivedMode ? '没有匹配的已归档会话' : '没有找到匹配的项目或会话'}</span>
            <button type="button" class="sb-empty-reset" data-sb-action="reset-filters">清除筛选条件</button>
          </div>
        `
        : `
          ${(visibleProjectBlocks.length > 0 || !this.isFiltered) ? `
            <section class="sb-section" aria-label="项目目录">
              <div class="sb-section-head">
                <span class="sb-section-label">${this.archivedMode ? '项目归档' : '项目'}</span>
                ${!this.archivedMode ? `
                  <button type="button" class="sb-section-action" data-sb-action="add-project">
                    ${lucideIcon('plus')}
                    <span>添加项目</span>
                  </button>
                ` : ''}
              </div>
              ${visibleProjectBlocks.join('')}
            </section>
          ` : ''}

          ${showStandaloneSection ? `
            <section class="sb-section is-standalone" aria-label="非项目会话">
              <div class="sb-section-head">
                <span class="sb-section-label">非项目会话</span>
                ${!this.archivedMode ? `
                  <button
                    type="button"
                    class="sb-icon-btn"
                    data-sb-action="standalone-start"
                    title="新建非项目会话"
                    aria-label="新建非项目会话">
                    ${lucideIcon('plus')}
                  </button>
                ` : ''}
              </div>
              <div class="sb-standalone-list">
                ${standaloneRows.length
                  ? standaloneRows.map(t => this.renderThreadRow(t, null)).join('')
                  : `<div class="sb-empty-note">暂无独立会话</div>`
                }
              </div>
            </section>
          ` : ''}
        `;

      this.scrollEl.scrollTop = prevScroll;
      hydrateIcons(this.scrollEl);
    }

    renderFooter(counts) {
      this.footEl.innerHTML = `
        <button
          type="button"
          class="sb-foot-btn ${this.archivedMode ? 'is-selected' : ''}"
          data-sb-action="toggle-archived"
          aria-pressed="${this.archivedMode}"
          title="${this.archivedMode ? '返回活跃会话目录' : '查看已归档会话'}">
          ${lucideIcon(this.archivedMode ? 'folder-open' : 'archive')}
          <span>已归档</span>
          ${counts.archived > 0 ? `<span class="sb-foot-count">${counts.archived}</span>` : ''}
        </button>

        <a
          class="sb-foot-btn"
          href="${escape(this.settingsHref)}"
          data-sb-action="open-settings"
          title="打开设置（账号、模型路由、智能体与安全配置）">
          <span class="sb-foot-icon-wrap">
            ${lucideIcon('settings')}
            ${this.hasUpdate ? '<span class="sb-update-dot" title="发现新版本更新"></span>' : ''}
          </span>
          <span>设置</span>
        </a>
      `;
      hydrateIcons(this.footEl);
    }

    /* ======================================================================
       Portal Context Menu & Two-Level "Open With ▶" Submenu
       ====================================================================== */
    closeMenus() {
      if (!this.openMenu) return;
      this.openMenu = null;
      this.menuLayerEl.hidden = true;
      this.menuLayerEl.innerHTML = '';
      this.host.querySelectorAll('.is-menu-open').forEach(el => el.classList.remove('is-menu-open'));
      this.host.querySelectorAll('[aria-expanded="true"][aria-haspopup="menu"]').forEach(btn => {
        btn.setAttribute('aria-expanded', 'false');
      });
    }

    openProjectMenu(projectId, triggerEl) {
      if (this.openMenu?.kind === 'project' && this.openMenu.id === projectId) {
        this.closeMenus();
        return;
      }
      this.hideHoverCard();
      this.closeMenus();
      const proj = this.catalog.projects.find(p => p.id === projectId);
      if (!proj) return;

      this.openMenu = { kind: 'project', id: projectId, triggerEl, submenuOpen: false };
      triggerEl.setAttribute('aria-expanded', 'true');
      triggerEl.closest('.sb-project-row')?.classList.add('is-menu-open');

      this.menuLayerEl.innerHTML = `
        <div class="sb-pop-menu" role="menu" aria-label="${escape(proj.name)} 项目菜单">
          <button type="button" class="sb-menu-item" role="menuitem" data-menu-cmd="pin-project" data-id="${escape(proj.id)}">
            ${lucideIcon('pin')}
            <span>${proj.pinned ? '取消置顶项目' : '置顶项目'}</span>
          </button>
          <button type="button" class="sb-menu-item" role="menuitem" data-menu-cmd="copy-project-path" data-id="${escape(proj.id)}">
            ${lucideIcon('copy')}
            <span>复制路径</span>
          </button>
          <div class="sb-menu-divider"></div>
          <button type="button" class="sb-menu-item is-danger" role="menuitem" data-menu-cmd="close-project" data-id="${escape(proj.id)}">
            ${lucideIcon('folder-x')}
            <span>关闭项目</span>
          </button>
        </div>
      `;
      this.menuLayerEl.hidden = false;
      hydrateIcons(this.menuLayerEl);
      this.repositionOpenMenu();
    }

    openThreadMenu(threadId, triggerEl, forceSubmenu = false) {
      if (!forceSubmenu && this.openMenu?.kind === 'thread' && this.openMenu.id === threadId) {
        this.closeMenus();
        return;
      }
      this.hideHoverCard();
      this.closeMenus();
      const thread = this.catalog.threads.find(t => t.id === threadId);
      if (!thread) return;
      const proj = this.catalog.projects.find(p => p.id === thread.workspaceId);
      const targetPath = proj?.sshAlias ? `${proj.sshAlias}:${thread.workspacePath}` : thread.workspacePath;

      this.openMenu = { kind: 'thread', id: threadId, triggerEl, submenuOpen: forceSubmenu };
      triggerEl.setAttribute('aria-expanded', 'true');
      triggerEl.closest('.sb-thread-row')?.classList.add('is-menu-open');

      this.menuLayerEl.innerHTML = `
        <div class="sb-pop-menu" role="menu" aria-label="会话操作菜单">
          <button type="button" class="sb-menu-item" role="menuitem" data-menu-cmd="pin-thread" data-id="${escape(thread.id)}">
            ${lucideIcon('pin')}
            <span>${thread.pinned ? '取消置顶' : '置顶'}</span>
          </button>
          <button type="button" class="sb-menu-item" role="menuitem" data-menu-cmd="rename-thread" data-id="${escape(thread.id)}">
            ${lucideIcon('pencil')}
            <span>重命名会话</span>
          </button>
          <button type="button" class="sb-menu-item" role="menuitem" data-menu-cmd="copy-thread-path" data-id="${escape(thread.id)}">
            ${lucideIcon('copy')}
            <span>复制路径</span>
          </button>
          <div class="sb-menu-divider"></div>
          <div class="sb-submenu-wrap">
            <button
              type="button"
              class="sb-menu-item ${forceSubmenu ? 'is-open' : ''}"
              role="menuitem"
              aria-haspopup="menu"
              aria-expanded="${forceSubmenu}"
              data-menu-cmd="toggle-open-with"
              title="打开会话工作区：${escape(targetPath)}">
              ${lucideIcon('external-link')}
              <span>打开方式</span>
              <span class="sb-submenu-arrow">${lucideIcon('chevron-right')}</span>
            </button>
            <div class="sb-submenu" role="menu" aria-label="打开方式" ${forceSubmenu ? '' : 'hidden'}>
              <button
                type="button"
                class="sb-menu-item"
                role="menuitem"
                data-menu-cmd="open-host-app"
                data-app="VS Code"
                data-target="${escape(targetPath)}"
                title="${escape(targetPath)}">
                ${hostAppLogo('vscode')}
                <span>在 VS Code 中打开</span>
              </button>
              <button
                type="button"
                class="sb-menu-item"
                role="menuitem"
                data-menu-cmd="open-host-app"
                data-app="Zed"
                data-target="${escape(targetPath)}"
                title="${escape(targetPath)}">
                ${hostAppLogo('zed')}
                <span>在 Zed 中打开</span>
              </button>
              <button
                type="button"
                class="sb-menu-item"
                role="menuitem"
                data-menu-cmd="open-host-app"
                data-app="终端"
                data-target="${escape(targetPath)}"
                title="${escape(targetPath)}">
                ${hostAppLogo('terminal')}
                <span>在终端中打开</span>
              </button>
            </div>
          </div>
          <div class="sb-menu-divider"></div>
          <button type="button" class="sb-menu-item is-danger" role="menuitem" data-menu-cmd="archive-thread" data-id="${escape(thread.id)}">
            ${lucideIcon('archive')}
            <span>归档会话</span>
          </button>
        </div>
      `;

      const subWrap = this.menuLayerEl.querySelector('.sb-submenu-wrap');
      const subBtn = subWrap?.querySelector('[data-menu-cmd="toggle-open-with"]');
      const subPanel = subWrap?.querySelector('.sb-submenu');
      if (subWrap && subBtn && subPanel) {
        const showSub = () => {
          this.openMenu.submenuOpen = true;
          subBtn.classList.add('is-open');
          subBtn.setAttribute('aria-expanded', 'true');
          subPanel.hidden = false;
          this.adjustSubmenuFlip(subWrap, subPanel);
        };
        const hideSub = () => {
          this.openMenu.submenuOpen = false;
          subBtn.classList.remove('is-open');
          subBtn.setAttribute('aria-expanded', 'false');
          subPanel.hidden = true;
        };
        subWrap.addEventListener('mouseenter', showSub);
        subWrap.addEventListener('mouseleave', hideSub);
      }

      this.menuLayerEl.hidden = false;
      hydrateIcons(this.menuLayerEl);
      this.repositionOpenMenu();
    }

    repositionOpenMenu() {
      if (!this.openMenu) return;
      const menuEl = this.menuLayerEl.querySelector('.sb-pop-menu');
      const trig = this.openMenu.triggerEl;
      if (!menuEl || !trig || !trig.isConnected) {
        this.closeMenus();
        return;
      }

      const winRect = this.windowEl.getBoundingClientRect();
      const trigRect = trig.getBoundingClientRect();
      const menuRect = menuEl.getBoundingClientRect();

      // Anchor slightly right-aligned to the `...` trigger so submenu extends cleanly across sidebar border (like screenshot 3!)
      let left = trigRect.left - winRect.left - 8;
      let top = trigRect.bottom - winRect.top + 4;

      if (left + menuRect.width > winRect.width - 12) {
        left = Math.max(8, winRect.width - menuRect.width - 12);
      }
      if (top + menuRect.height > winRect.height - 12) {
        top = Math.max(8, trigRect.top - winRect.top - menuRect.height - 4);
      }

      menuEl.style.left = `${Math.round(left)}px`;
      menuEl.style.top = `${Math.round(top)}px`;

      const subWrap = menuEl.querySelector('.sb-submenu-wrap');
      const subPanel = menuEl.querySelector('.sb-submenu');
      if (subWrap && subPanel && !subPanel.hidden) {
        this.adjustSubmenuFlip(subWrap, subPanel);
      }
    }

    adjustSubmenuFlip(subWrap, subPanel) {
      subWrap.classList.remove('is-flip-left', 'is-flip-up');
      const winRect = this.windowEl.getBoundingClientRect();
      const subRect = subPanel.getBoundingClientRect();
      if (subRect.right > winRect.right - 10) {
        subWrap.classList.add('is-flip-left');
      }
      if (subRect.bottom > winRect.bottom - 10) {
        subWrap.classList.add('is-flip-up');
      }
    }

    /* ======================================================================
       Read-Only Hover Detail Overlay (Clean Incremental Facts Only)
       ====================================================================== */
    hideHoverCard() {
      clearTimeout(this.hoverTimer);
      this.hoverTimer = null;
      this.activeHoverKey = '';
      if (this.hoverCardEl) {
        this.hoverCardEl.hidden = true;
      }
    }

    scheduleHoverCard(rowEl) {
      if (this.openMenu || this.dialogEl.open) return;
      const kind = rowEl.dataset.hoverKind;
      const id = kind === 'project' ? rowEl.dataset.projectId : rowEl.dataset.threadId;
      const key = `${kind}:${id}`;
      if (key === this.activeHoverKey) return;

      this.hideHoverCard();
      this.activeHoverKey = key;
      this.hoverTimer = setTimeout(() => {
        if (this.openMenu || !rowEl.isConnected) return;
        this.showHoverCard(kind, id, rowEl);
      }, 360);
    }

    showHoverCard(kind, id, rowEl) {
      if (kind === 'project') {
        const proj = this.catalog.projects.find(p => p.id === id);
        if (!proj) return;
        const envText = proj.sshAlias ? `SSH 远程主机 · ${proj.sshAlias}` : '本地目录项目';
        this.hoverCardEl.innerHTML = `
          <div class="sb-hover-title">${escape(proj.name)}</div>
          <div class="sb-hover-row">
            ${lucideIcon(proj.sshAlias ? 'server' : 'laptop')}
            <span>${escape(envText)}</span>
          </div>
          <div class="sb-hover-row">
            ${lucideIcon('folder-open')}
            <span class="sb-hover-mono">${escape(proj.path)}</span>
          </div>
        `;
      } else {
        const thread = this.catalog.threads.find(t => t.id === id);
        if (!thread) return;
        const proj = this.catalog.projects.find(p => p.id === thread.workspaceId);
        const title = this.effectiveThreadTitle(thread);
        const status = this.effectiveThreadStatus(thread);
        const statusText = thread.archived
          ? '已归档'
          : status === 'running'
            ? '进行中'
            : status === 'attention'
              ? '等待确认'
              : status === 'failed'
                ? '执行失败'
                : '空闲';
        const pathDisplay = proj?.sshAlias
          ? `${proj.sshAlias}:${thread.workspacePath}`
          : thread.workspacePath;

        this.hoverCardEl.innerHTML = `
          <div class="sb-hover-title">${escape(title)}</div>
          ${thread.worktree ? `
            <div class="sb-hover-row">
              ${lucideIcon('git-branch')}
              <span>独立工作树${thread.branch ? ` · <span class="sb-hover-mono">${escape(thread.branch)}</span>` : ''}</span>
            </div>
          ` : ''}
          <div class="sb-hover-row">
            ${lucideIcon('folder-open')}
            <span class="sb-hover-mono">${escape(pathDisplay)}</span>
          </div>
          <div class="sb-hover-row">
            <span class="sb-hover-dot" data-tone="${escape(status)}"></span>
            <span>${escape(statusText)} · ${escape(thread.updatedLabel || '刚刚')}</span>
          </div>
        `;
      }

      hydrateIcons(this.hoverCardEl);
      this.hoverCardEl.hidden = false;

      const winRect = this.windowEl.getBoundingClientRect();
      const hostRect = this.host.getBoundingClientRect();
      const rowRect = rowEl.getBoundingClientRect();
      const cardRect = this.hoverCardEl.getBoundingClientRect();

      let left = hostRect.right - winRect.left + 8;
      let top = rowRect.top - winRect.top - 2;
      if (left + cardRect.width > winRect.width - 10) {
        left = Math.max(8, winRect.width - cardRect.width - 10);
      }
      if (top + cardRect.height > winRect.height - 10) {
        top = Math.max(8, winRect.height - cardRect.height - 10);
      }
      this.hoverCardEl.style.left = `${Math.round(left)}px`;
      this.hoverCardEl.style.top = `${Math.round(top)}px`;
    }

    /* ======================================================================
       Modal Dialogs: Rename Session / Archive Confirm / Add Project Wizard
       ====================================================================== */
    openRenameDialog(threadId) {
      const thread = this.catalog.threads.find(t => t.id === threadId);
      if (!thread) return;
      const currentTitle = this.effectiveThreadTitle(thread);

      this.dialogEl.innerHTML = `
        <form method="dialog" class="sb-dialog-form">
          <h3>重命名会话</h3>
          <p>更新侧边栏与会话顶栏共享的显示标题（最多 80 个字符）。</p>
          <div class="sb-field-label">
            <span>会话标题</span>
            <span class="sb-char-count">${currentTitle.length} / 80</span>
          </div>
          <input type="text" class="sb-text-input" maxlength="85" value="${escape(currentTitle)}" aria-label="会话标题">
          <div class="sb-field-error" hidden></div>
          <div class="sb-dialog-actions">
            <button type="button" class="sb-btn" data-dlg-cancel>取消</button>
            <button type="submit" class="sb-btn is-primary" data-dlg-submit>保存</button>
          </div>
        </form>
      `;

      const input = this.dialogEl.querySelector('.sb-text-input');
      const counter = this.dialogEl.querySelector('.sb-char-count');
      const errEl = this.dialogEl.querySelector('.sb-field-error');
      const submitBtn = this.dialogEl.querySelector('[data-dlg-submit]');

      const validate = () => {
        const val = input.value.trim();
        counter.textContent = `${val.length} / 80`;
        if (!val) {
          errEl.textContent = '会话标题不能为空。';
          errEl.hidden = false;
          submitBtn.disabled = true;
          return false;
        }
        if (val.length > 80) {
          errEl.textContent = '会话标题不能超过 80 个字符。';
          errEl.hidden = false;
          submitBtn.disabled = true;
          return false;
        }
        errEl.hidden = true;
        submitBtn.disabled = false;
        return true;
      };

      input.addEventListener('input', validate);
      this.dialogEl.querySelector('[data-dlg-cancel]').addEventListener('click', () => this.dialogEl.close());
      this.dialogEl.querySelector('form').addEventListener('submit', event => {
        event.preventDefault();
        if (!validate()) return;
        const nextTitle = input.value.trim();
        thread.title = nextTitle;
        const s = this.controller?.state;
        if (s?.frozenThread?.id === thread.id) {
          s.frozenThread.title = nextTitle;
          this.controller.note(`会话已重命名为「${nextTitle}」`);
          this.controller.emit('config');
        }
        this.syncFixturesReference();
        this.dialogEl.close();
        this.render();
        this.onToast('已更新会话标题');
      });

      this.dialogEl.showModal();
      input.focus();
      input.select();
    }

    openArchiveDialog(threadId) {
      const thread = this.catalog.threads.find(t => t.id === threadId);
      if (!thread) return;
      const title = this.effectiveThreadTitle(thread);

      this.dialogEl.innerHTML = `
        <div>
          <h3>归档这个会话？</h3>
          <p>将停止「${escape(title)}」的活动工作并移入「已归档」目录，会话历史记录、工作区文件与未提交内容均完整保留，随时可恢复查看。</p>
          <div class="sb-dialog-actions">
            <button type="button" class="sb-btn" data-dlg-cancel>取消</button>
            <button type="button" class="sb-btn is-primary" data-dlg-confirm>归档会话</button>
          </div>
        </div>
      `;
      this.dialogEl.querySelector('[data-dlg-cancel]').addEventListener('click', () => this.dialogEl.close());
      this.dialogEl.querySelector('[data-dlg-confirm]').addEventListener('click', () => {
        thread.archived = true;
        thread.status = 'idle';
        this.syncFixturesReference();
        this.dialogEl.close();

        const s = this.controller?.state;
        if (s?.stage === 'session' && s.activeSidebarThreadId === thread.id) {
          const fallback = this.catalog.threads.find(t => !t.archived && t.workspaceId === thread.workspaceId)
            || this.catalog.threads.find(t => !t.archived);
          if (fallback) this.selectThread(fallback.id);
          else this.controller.selectStandaloneStart();
        } else {
          this.render();
        }
        this.onToast('会话已移入「已归档」');
      });
      this.dialogEl.showModal();
    }

    openCloseProjectDialog(projectId) {
      const proj = this.catalog.projects.find(p => p.id === projectId);
      if (!proj) return;

      this.dialogEl.innerHTML = `
        <div>
          <h3>从侧边栏关闭项目？</h3>
          <p>将从侧边栏移除「${escape(proj.name)}」，磁盘上的源码目录与历史会话数据不会被删除，后续重新添加该目录即可恢复。</p>
          <div class="sb-dialog-actions">
            <button type="button" class="sb-btn" data-dlg-cancel>取消</button>
            <button type="button" class="sb-btn is-danger" data-dlg-confirm>关闭项目</button>
          </div>
        </div>
      `;
      this.dialogEl.querySelector('[data-dlg-cancel]').addEventListener('click', () => this.dialogEl.close());
      this.dialogEl.querySelector('[data-dlg-confirm]').addEventListener('click', () => {
        this.catalog.projects = this.catalog.projects.filter(p => p.id !== projectId);
        this.expandedIds.delete(projectId);
        this.syncFixturesReference();
        this.dialogEl.close();

        const s = this.controller?.state;
        if (s?.projectId === projectId && s.targetType !== 'standalone') {
          const nextProj = this.catalog.projects[0];
          if (nextProj) this.controller.selectProjectStart(nextProj.id);
          else this.controller.selectStandaloneStart();
        }
        this.render();
        this.onToast(`已关闭项目「${proj.name}」`);
      });
      this.dialogEl.showModal();
    }

    openAddProjectDialog(initialName = '') {
      const cleanSeed = String(initialName || '').trim().replace(/[\\/:*?"<>|]+/g, '-');
      if (cleanSeed) {
        this.addWizardState.name = cleanSeed;
        this.addWizardState.path = this.addWizardState.remote
          ? `/srv/repos/${cleanSeed}`
          : `C:\\Users\\dev\\work\\${cleanSeed}`;
      }
      const renderWizard = () => {
        const w = this.addWizardState;
        const selectedHost = SSH_HOSTS.find(h => h.alias === w.sshAlias) || SSH_HOSTS[0];

        this.dialogEl.innerHTML = `
          <form class="sb-add-proj-form">
            <h3>添加项目</h3>
            <p>打开本地代码目录，或通过 ~/.ssh/config 连接远程开发主机目录。</p>

            <div class="sb-choice-grid" role="radiogroup" aria-label="项目位置类型">
              <button type="button" class="sb-choice-card ${!w.remote ? 'is-selected' : ''}" data-loc-mode="local">
                <strong>${lucideIcon('laptop')}本地项目</strong>
                <small>直接选择本机文件夹</small>
              </button>
              <button type="button" class="sb-choice-card ${w.remote ? 'is-selected' : ''}" data-loc-mode="remote">
                <strong>${lucideIcon('server')}远程项目 (SSH)</strong>
                <small>复用 SSH 主机与远端目录</small>
              </button>
            </div>

            ${w.remote ? `
              <div class="sb-field-label"><span>选择 SSH 主机 (~/.ssh/config)</span></div>
              <div class="sb-ssh-list">
                ${SSH_HOSTS.map(h => `
                  <div class="sb-ssh-option ${h.alias === selectedHost.alias ? 'is-selected' : ''}" data-pick-ssh="${escape(h.alias)}">
                    <div><strong>${escape(h.alias)}</strong> · <code>${escape(h.spec)}</code></div>
                    <code>${escape(h.auth)}</code>
                  </div>
                `).join('')}
              </div>
            ` : ''}

            <div class="sb-field-label"><span>${w.remote ? `远端目录路径 (${selectedHost.alias})` : '本地目录路径'}</span></div>
            <input type="text" class="sb-text-input is-mono" data-proj-path value="${escape(w.path)}">

            <div class="sb-field-label" style="margin-top:10px;"><span>项目显示名称</span></div>
            <input type="text" class="sb-text-input" data-proj-name value="${escape(w.name)}">

            <div class="sb-dialog-actions">
              <button type="button" class="sb-btn" data-dlg-cancel>取消</button>
              <button type="submit" class="sb-btn is-primary">添加并打开</button>
            </div>
          </form>
        `;

        hydrateIcons(this.dialogEl);

        this.dialogEl.querySelectorAll('[data-loc-mode]').forEach(btn => {
          btn.addEventListener('click', () => {
            const isRemote = btn.dataset.locMode === 'remote';
            if (w.remote === isRemote) return;
            w.remote = isRemote;
            if (isRemote) {
              const host = SSH_HOSTS.find(h => h.alias === w.sshAlias) || SSH_HOSTS[0];
              w.path = host.defaultDir + '-next';
              w.name = w.path.split('/').filter(Boolean).pop() || 'remote-app';
            } else {
              w.path = 'C:\\Users\\dev\\work\\my-rust-app';
              w.name = 'my-rust-app';
            }
            renderWizard();
          });
        });

        this.dialogEl.querySelectorAll('[data-pick-ssh]').forEach(opt => {
          opt.addEventListener('click', () => {
            const host = SSH_HOSTS.find(h => h.alias === opt.dataset.pickSsh);
            if (!host) return;
            w.sshAlias = host.alias;
            w.path = host.defaultDir + '-service';
            w.name = w.path.split('/').filter(Boolean).pop() || host.alias;
            renderWizard();
          });
        });

        const pathInput = this.dialogEl.querySelector('[data-proj-path]');
        const nameInput = this.dialogEl.querySelector('[data-proj-name]');
        pathInput.addEventListener('input', () => {
          w.path = pathInput.value;
          const guessed = w.path.split(/[\\/]/).filter(Boolean).pop();
          if (guessed) {
            w.name = guessed;
            nameInput.value = guessed;
          }
        });
        nameInput.addEventListener('input', () => { w.name = nameInput.value; });

        this.dialogEl.querySelector('[data-dlg-cancel]').addEventListener('click', () => this.dialogEl.close());
        this.dialogEl.querySelector('form').addEventListener('submit', event => {
          event.preventDefault();
          const cleanPath = pathInput.value.trim();
          const cleanName = nameInput.value.trim() || cleanPath.split(/[\\/]/).filter(Boolean).pop() || 'new-project';
          if (!cleanPath) return;

          const sshAlias = w.remote ? w.sshAlias : null;
          const existing = this.catalog.projects.find(p => p.path === cleanPath && p.sshAlias === sshAlias);
          if (existing) {
            this.expandedIds.add(existing.id);
            this.dialogEl.close();
            this.controller?.selectProjectStart(existing.id);
            this.render();
            this.onToast(`已定位到既有项目「${existing.name}」`);
            return;
          }

          const newProj = {
            id: `proj-custom-${++this.seq}`,
            name: cleanName,
            path: cleanPath,
            sshAlias,
            isGit: true,
            pinned: false,
            defaultExpanded: true,
            pageSize: 5
          };
          this.catalog.projects.unshift(newProj);
          this.expandedIds.add(newProj.id);
          this.archivedMode = false;
          this.syncFixturesReference();
          this.dialogEl.close();
          this.controller?.selectProjectStart(newProj.id);
          this.render();
          this.onToast(`已添加${sshAlias ? '远程 SSH ' : ''}项目「${newProj.name}」`);
        });
      };

      renderWizard();
      this.dialogEl.showModal();
    }

    /* ======================================================================
       Navigation & State Mutations
       ====================================================================== */
    selectThread(threadId) {
      const hit = this.catalog.threads.find(t => t.id === threadId && !t.archived);
      if (!hit || !this.controller) return;
      const proj = this.catalog.projects.find(p => p.id === hit.workspaceId);

      this.controller.load(hit.scenario || 'idle');
      if (hit.workspaceId === '__standalone__') {
        this.controller.state.targetType = 'standalone';
        this.controller.state.projectId = this.catalog.projects[0]?.id || 'pure-lang-pure';
      } else {
        this.controller.state.targetType = 'project';
        this.controller.state.projectId = hit.workspaceId;
        this.expandedIds.add(hit.workspaceId);
      }

      this.controller.state.activeSidebarThreadId = hit.id;
      const ft = this.controller.state.frozenThread;
      ft.id = hit.id;
      ft.title = hit.title;
      ft.projectName = proj ? proj.name : '非项目会话';
      ft.sshAlias = proj?.sshAlias || null;
      ft.workspaceMode = hit.worktree ? 'worktree' : 'local';
      ft.branch = hit.branch || null;
      ft.workspacePath = hit.workspacePath;
      ft.delegationSummary = hit.delegationSummary || '自动选模 · 平衡';

      this.controller.emit('reset');
      this.closeDrawerIfNarrow();
      this.render();
    }

    closeDrawerIfNarrow() {
      if (this.shellEl.classList.contains('is-mobile-drawer-open')) {
        this.shellEl.classList.remove('is-mobile-drawer-open');
        this.backdropEl.classList.remove('is-open');
      }
    }

    syncDrawerBackdrop() {
      const open = this.shellEl.classList.contains('is-mobile-drawer-open');
      this.backdropEl.classList.toggle('is-open', open);
    }

    syncWidthToShell() {
      this.shellEl.style.setProperty('--sb-width', `${Math.round(this.sidebarWidth)}px`);
    }

    applyScenarioPreset(scenarioId) {
      this.closeMenus();
      this.hideHoverCard();
      if (this.dialogEl.open) this.dialogEl.close();

      // Reset transient filters when switching scenarios unless the scenario explicitly demonstrates filtering/archive
      this.searchQuery = '';
      this.filter = 'all';
      this.archivedMode = false;

      if (scenarioId === 'sidebar-filter-active') {
        this.filter = 'running';
      } else if (scenarioId === 'sidebar-archived') {
        this.archivedMode = true;
      }

      const s = this.controller?.state;
      if (s?.projectId && s.targetType !== 'standalone') {
        this.expandedIds.add(s.projectId);
      }

      this.render();

      if (scenarioId === 'sidebar-open-menu') {
        requestAnimationFrame(() => {
          const activeId = this.controller?.state.activeSidebarThreadId || 'thr-main';
          const btn = this.host.querySelector(`.sb-more-btn[data-thread-id="${CSS.escape(activeId)}"]`);
          if (btn) this.openThreadMenu(activeId, btn, true);
        });
      } else if (scenarioId === 'sidebar-add-project') {
        requestAnimationFrame(() => this.openAddProjectDialog());
      }
    }

    /* ======================================================================
       Event Wiring (Search, Actions, Portal Menus, Hover Detail, Resizer)
       ====================================================================== */
    bindEvents() {
      const sig = this.abort.signal;

      // 1. Live search without losing IME or cursor position
      this.searchInput.addEventListener('input', () => {
        this.closeMenus();
        this.hideHoverCard();
        this.searchQuery = this.searchInput.value;
        const hasQuery = Boolean(this.searchQuery);
        this.searchHint.hidden = hasQuery;
        this.searchClearBtn.hidden = !hasQuery;
        this.renderTree();
      }, { signal: sig });

      this.searchInput.addEventListener('keydown', event => {
        if (event.key === 'Escape' && this.searchQuery) {
          event.preventDefault();
          event.stopPropagation();
          this.searchQuery = '';
          this.render();
        }
      }, { signal: sig });

      this.searchClearBtn.addEventListener('click', () => {
        this.searchQuery = '';
        this.render();
        this.searchInput.focus();
      }, { signal: sig });

      // 2. Delegated clicks inside sidebar host
      this.host.addEventListener('click', event => {
        const actionBtn = event.target.closest('[data-sb-action]');
        if (!actionBtn) return;

        const act = actionBtn.dataset.sbAction;
        if (act === 'open-settings') {
          // Allow native <a> link navigation to accounts prototype
          return;
        }

        event.stopPropagation();
        this.hideHoverCard();

        if (act === 'standalone-start') {
          this.closeMenus();
          this.archivedMode = false;
          this.controller?.selectStandaloneStart();
          this.closeDrawerIfNarrow();
          this.render();
        } else if (act === 'set-filter') {
          this.closeMenus();
          this.filter = actionBtn.dataset.filter || 'all';
          this.render();
        } else if (act === 'toggle-archived' || act === 'exit-archived') {
          this.closeMenus();
          this.archivedMode = act === 'exit-archived' ? false : !this.archivedMode;
          this.render();
        } else if (act === 'reset-filters') {
          this.searchQuery = '';
          this.filter = 'all';
          this.archivedMode = false;
          this.render();
        } else if (act === 'toggle-project') {
          this.closeMenus();
          const pid = actionBtn.dataset.projectId;
          if (this.isFiltered) return;
          if (!this.expandedIds.delete(pid)) this.expandedIds.add(pid);
          this.renderTree();
        } else if (act === 'project-new-session') {
          this.closeMenus();
          const pid = actionBtn.dataset.projectId;
          this.expandedIds.add(pid);
          this.controller?.selectProjectStart(pid);
          this.closeDrawerIfNarrow();
          this.render();
        } else if (act === 'project-menu') {
          this.openProjectMenu(actionBtn.dataset.projectId, actionBtn);
        } else if (act === 'add-project') {
          this.closeMenus();
          this.openAddProjectDialog();
        } else if (act === 'select-thread') {
          this.closeMenus();
          this.selectThread(actionBtn.dataset.threadId);
        } else if (act === 'toggle-pin-thread') {
          this.closeMenus();
          const t = this.catalog.threads.find(item => item.id === actionBtn.dataset.threadId);
          if (t) {
            t.pinned = !t.pinned;
            this.renderTree();
            this.onToast(t.pinned ? '会话已置顶' : '已取消置顶');
          }
        } else if (act === 'thread-menu') {
          this.openThreadMenu(actionBtn.dataset.threadId, actionBtn, false);
        } else if (act === 'show-earlier') {
          this.showMoreIds.add(actionBtn.dataset.projectId);
          this.renderTree();
        } else if (act === 'restore-thread') {
          const t = this.catalog.threads.find(item => item.id === actionBtn.dataset.threadId);
          if (t) {
            t.archived = false;
            this.syncFixturesReference();
            this.render();
            this.onToast(`已恢复会话「${t.title}」`);
          }
        }
      }, { signal: sig });

      // 3. Portal menu actions
      this.menuLayerEl.addEventListener('click', event => {
        const cmdBtn = event.target.closest('[data-menu-cmd]');
        if (!cmdBtn) return;
        event.stopPropagation();

        const cmd = cmdBtn.dataset.menuCmd;
        const id = cmdBtn.dataset.id;

        if (cmd === 'toggle-open-with') {
          const subWrap = cmdBtn.closest('.sb-submenu-wrap');
          const subPanel = subWrap?.querySelector('.sb-submenu');
          if (subPanel && this.openMenu) {
            this.openMenu.submenuOpen = subPanel.hidden;
            subPanel.hidden = !this.openMenu.submenuOpen;
            cmdBtn.classList.toggle('is-open', this.openMenu.submenuOpen);
            cmdBtn.setAttribute('aria-expanded', String(this.openMenu.submenuOpen));
            if (this.openMenu.submenuOpen) this.adjustSubmenuFlip(subWrap, subPanel);
          }
          return;
        }

        this.closeMenus();

        if (cmd === 'pin-project') {
          const proj = this.catalog.projects.find(p => p.id === id);
          if (proj) {
            proj.pinned = !proj.pinned;
            this.renderTree();
            this.onToast(proj.pinned ? `已置顶项目「${proj.name}」` : `已取消置顶「${proj.name}」`);
          }
        } else if (cmd === 'copy-project-path') {
          const proj = this.catalog.projects.find(p => p.id === id);
          if (proj) this.onCopy(proj.path);
        } else if (cmd === 'close-project') {
          this.openCloseProjectDialog(id);
        } else if (cmd === 'pin-thread') {
          const t = this.catalog.threads.find(item => item.id === id);
          if (t) {
            t.pinned = !t.pinned;
            this.renderTree();
            this.onToast(t.pinned ? '会话已置顶' : '已取消置顶');
          }
        } else if (cmd === 'rename-thread') {
          this.openRenameDialog(id);
        } else if (cmd === 'copy-thread-path') {
          const t = this.catalog.threads.find(item => item.id === id);
          if (t) this.onCopy(t.workspacePath);
        } else if (cmd === 'open-host-app') {
          this.onToast(`已在 ${cmdBtn.dataset.app} 中打开：${cmdBtn.dataset.target}`);
        } else if (cmd === 'archive-thread') {
          this.openArchiveDialog(id);
        }
      }, { signal: sig });

      // 4. Read-only hover detail card tracking
      this.scrollEl.addEventListener('pointermove', event => {
        if (event.pointerType === 'touch') return;
        if (event.target.closest('.sb-more-btn, .sb-pin-badge, .sb-proj-actions, .sb-restore-btn')) {
          this.hideHoverCard();
          return;
        }
        const row = event.target.closest('[data-hover-kind]');
        if (row) this.scheduleHoverCard(row);
        else this.hideHoverCard();
      }, { signal: sig });

      this.scrollEl.addEventListener('pointerleave', () => this.hideHoverCard(), { signal: sig });
      this.scrollEl.addEventListener('scroll', () => {
        this.hideHoverCard();
        if (this.openMenu) this.repositionOpenMenu();
      }, { passive: true, signal: sig });

      // 5. Resizer drag, double-click reset & keyboard step
      this.resizerEl.addEventListener('pointerdown', event => {
        if (event.button !== 0) return;
        event.preventDefault();
        this.closeMenus();
        this.hideHoverCard();
        this.resizerEl.setPointerCapture(event.pointerId);
        this.host.classList.add('is-resizing');
        const startX = event.clientX;
        const startW = this.sidebarWidth;
        const maxW = Math.min(390, Math.max(250, this.windowEl.clientWidth - 480));

        const onMove = moveEv => {
          const next = Math.max(236, Math.min(maxW, startW + (moveEv.clientX - startX)));
          this.sidebarWidth = next;
          this.syncWidthToShell();
        };
        const onUp = () => {
          this.host.classList.remove('is-resizing');
          this.resizerEl.removeEventListener('pointermove', onMove);
          this.resizerEl.removeEventListener('pointerup', onUp);
          this.resizerEl.removeEventListener('pointercancel', onUp);
        };
        this.resizerEl.addEventListener('pointermove', onMove);
        this.resizerEl.addEventListener('pointerup', onUp);
        this.resizerEl.addEventListener('pointercancel', onUp);
      }, { signal: sig });

      this.resizerEl.addEventListener('dblclick', () => {
        this.sidebarWidth = this.defaultWidth;
        this.syncWidthToShell();
        this.onToast('已恢复侧边栏默认宽度');
      }, { signal: sig });

      this.resizerEl.addEventListener('keydown', event => {
        if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
          event.preventDefault();
          const delta = event.key === 'ArrowRight' ? 16 : -16;
          this.sidebarWidth = Math.max(236, Math.min(390, this.sidebarWidth + delta));
          this.syncWidthToShell();
        } else if (event.key === 'Home') {
          event.preventDefault();
          this.sidebarWidth = this.defaultWidth;
          this.syncWidthToShell();
        }
      }, { signal: sig });

      // 6. Backdrop click closes mobile drawer
      this.backdropEl.addEventListener('click', () => this.closeDrawerIfNarrow(), { signal: sig });

      // 7. Close menu on outside click, Escape, or dialog backdrop click
      document.addEventListener('pointerdown', event => {
        if (!this.openMenu) return;
        if (event.target.closest('.sb-pop-menu') || event.target === this.openMenu.triggerEl || this.openMenu.triggerEl?.contains(event.target)) {
          return;
        }
        this.closeMenus();
      }, { signal: sig });

      document.addEventListener('keydown', event => {
        if (event.key === 'Escape' && this.openMenu) {
          event.preventDefault();
          this.closeMenus();
          return;
        }
        const mod = event.ctrlKey || event.metaKey;
        if (mod && event.key.toLowerCase() === 'k') {
          event.preventDefault();
          if (this.shellEl.classList.contains('is-sidebar-collapsed')) {
            this.shellEl.classList.remove('is-sidebar-collapsed');
          }
          this.searchInput.focus();
          this.searchInput.select();
        } else if (mod && event.key.toLowerCase() === 'n' && !this.dialogEl.open) {
          event.preventDefault();
          const s = this.controller?.state;
          if (s?.projectId && s.targetType !== 'standalone') {
            this.expandedIds.add(s.projectId);
            this.controller.selectProjectStart(s.projectId);
          } else {
            this.controller?.selectStandaloneStart();
          }
          this.render();
        }
      }, { signal: sig });

      this.dialogEl.addEventListener('click', event => {
        if (event.target === this.dialogEl) {
          const rect = this.dialogEl.getBoundingClientRect();
          if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) {
            this.dialogEl.close();
          }
        }
      }, { signal: sig });
    }

    destroy() {
      this.closeMenus();
      this.hideHoverCard();
      this.abort.abort();
      this.portalEl?.remove();
      this.dialogEl?.remove();
      this.backdropEl?.remove();
    }
  }

  window.AnyworkSidebar = {
    StudioSidebar,
    hostAppLogo,
    HOST_APP_SVGS
  };
})();
