(() => {
  'use strict';
  const app = window.AnyworkConversation;
  const {
    node, icon, activityIndicator, icons, button, escape,
    MarkdownView, WorkGroupView, PendingView, historyItem, selectedInside
  } = app.ui;
  const {
    MenuManager, PromptComposerCard, renderTopbar,
    buildPreparationHTML, renderStartStage, buildAgentReadOnlyDock,
    describeContextNotes
  } = app.composer;

  let instanceSequence = 0;

  function orderedGroupsForPage(page) {
    const order = page === 'sidebar'
      ? ['sidebar', 'start', 'composer', 'timeline']
      : page === 'start'
        ? ['start', 'sidebar', 'composer', 'timeline']
        : page === 'composer'
          ? ['composer', 'sidebar', 'start', 'timeline']
          : ['timeline', 'sidebar', 'composer', 'start'];
    return order.map(id => app.fixtures.scenarioGroups.find(g => g.id === id)).filter(Boolean);
  }

  function guideForPage(page) {
    if (page === 'sidebar') {
      return {
        title: '统一侧边栏组件化与降噪交互准则',
        items: [
          ['顺畅顶层动线', '将全局「新建会话」上移为顶部柔和浅色主卡，紧随实时搜索与三态筛选，不再割裂「项目」标题与项目树。'],
          ['双列纵向严格对齐', '会话前导 16px 状态槽位与项目文件夹图标同轴对齐，会话标题与项目名称左边界严格对齐；右侧按「置顶 · 工作树 · 更多菜单」定轴排布，工作树与项目「+」同列、更多菜单与项目「⋯」同列。'],
          ['保留蓝条与跨栏浮层', '选中会话保留拿铁底色与左侧眼眸蓝竖条；省略本地冗余标签与空闲对勾，二级「打开方式 ▶」原色徽标子菜单挂载于顶层浮层不裁切。']
        ]
      };
    }
    if (page === 'start') {
      return {
        title: '创建期组件融合与双层创建台',
        items: [
          ['统一新会话与模型融合', '去掉外层「糊来帮 / ACP」独立切换，内置模型与外部 ACP 智能体统一收纳在同一模型下拉菜单；动态配置按 3+1 槽位呈现。'],
          ['双层同心创建台', '起始页外层暖米环境栏收纳创建期一次性冻结项（所属项目 / 本地目录 / 新建工作树 / 分发），内层复用统一输入卡。'],
          ['外部化说明边界', '主展示区仅保留纯净真实产品控件，协议探测详情、SSH 兼容提示与预设规则均汇总在右侧检查器。']
        ]
      };
    }
    if (page === 'composer') {
      return {
        title: '运行期动态槽位与零位移交互准则',
        items: [
          ['创建期永久冻结', '所属项目、本地目录 / 独立工作树、子智能体分发（及 ACP 身份）在会话创建后收敛至顶栏等高只读标签。'],
          ['3+1 动态槽位与单飞确认', '内置与 ACP 模型共享「模式 · 模型 · 思考强度 + ⚙ 调优」底栏，运行中或 ACP 往返确认期间等宽置灰，切换零位移。'],
          ['并发拟稿与定宽主钮', '运行中文本框与附件（支持图片工具）保持可用，34×34px 定宽主圆钮在「停止 ■」「发送并继续 ↑」「收束中 ◌」「继续 ▶」间原位切换。']
        ]
      };
    }
    return {
      title: '状态栏是当前工作组，时间线只有已结束',
      items: [
        ['状态栏 · 当前工作组', '新成员逐个插入，已完成的以对应语义图标留在组内；下一条仍是工具时继续并入本组。'],
        ['分组边界整组交接', '出现正文开始、提问、轮次结束、停止或失败时，整组一次移入时间线，之后不再变化。'],
        ['极简查看图片行', '时间线以轻量折叠行展示「查看了 N 张图片」，展开即横向排布圆角缩略图，不展示文件地址。']
      ]
    };
  }

  function pageChromeMeta(page) {
    if (page === 'sidebar') {
      return {
        title: '项目与会话侧边栏共享组件',
        subtitle: '重构为独立可复用的 StudioSidebar 组件并在全部会话概念稿页面统一挂载：梳理顶层操作动线、对齐项目与会话的前导图标及文字层级、清理重复标签与状态噪音、保留左侧眼眸蓝选中竖条，并完整支持跨栏二级「打开方式 ▶」菜单、状态筛选、归档恢复与可拖拽宽度。',
        footerHTML: '侧边栏由 <code>sidebar-shared/</code> 单一事实源提供，所有会话概念稿复用同一组件实例。保留选中会话的拿铁底色与左侧 <code>3px</code> 眼眸蓝竖条；会话前导 <code>16px</code> 状态槽位与项目文件夹图标纵向对齐，会话标题与项目名称左边界严格对齐；本地项目省略冗余「本地」字样，空闲/已完成会话在前导槽位保持留白而不渲染对勾；会话行尾按「置顶 (<code>18px</code>) · 工作树 (<code>22px</code>，对齐项目新建会话按钮) · 更多菜单 (<code>22px</code> 常驻占位)」定轴对齐，切换任意运行态、悬停态或置顶态均保持零位移。'
      };
    }
    if (page === 'start') {
      return {
        title: '新会话起始页与工作区输入布局',
        subtitle: '内置模型与外部 ACP 智能体统一收纳在同一模型选择器，动态映射 3+1 配置槽位；外层环境栏管理项目（无项目 / 已有项目搜索 / 新建项目）、工作区与内置分发，协议与规则说明统一外置到右侧检查器。',
        footerHTML: '展示区仅呈现真实产品界面与开发任务；外部检查器汇总 ACP 协议字段、SSH 兼容性说明与预加载触发按钮。'
      };
    }
    if (page === 'composer') {
      return {
        title: '会话运行时输入框与配置锁定交互',
        subtitle: '展示内置模型与外部 ACP 会话运行期的 3+1 动态槽位、⚙ 调优二级弹层、往返单飞确认态、运行期等宽不可交互态、并发草稿及子智能体只读底栏。',
        footerHTML: '会话运行中文本框与可用附件始终允许并发编辑；当前不可更改的槽位省略锁图标保持等宽置灰（状态切换 0px 位移），所有协议及规则说明置于右侧检查器。'
      };
    }
    return {
      title: '会话时间线与实时状态栏',
      subtitle: '状态栏承载正在进行的工作组、流式正文或上下文压缩，时间线只收录已结束内容；下方输入区与起始页及运行期锁定稿共用同一套会话组件。',
      footerHTML: '新工作组先在状态栏插入成员，完成的成员留在组内；出现正文、提问、轮次结束、停止或失败时整组移入时间线。右侧检查器同步展示实时配置可配性矩阵与状态交接记录，所有任务均为本地模拟。'
    };
  }

  function mountPageChrome(host) {
    const page = host.dataset.page || 'session';
    const meta = pageChromeMeta(page);
    const tabs = [
      { id: 'sidebar', href: '../project-sidebar/index.html', label: '项目与会话侧边栏', ico: 'panel-left' },
      { id: 'start', href: '../session-start/index.html', label: '新会话起始页', ico: 'sparkles' },
      { id: 'composer', href: '../session-composer/index.html', label: '运行时输入框与锁定', ico: 'sliders-horizontal' },
      { id: 'session', href: '../live-status/index.html', label: '时间线与实时状态栏', ico: 'activity' }
    ];
    host.innerHTML = `
      <header class="cv-page-header">
        <div>
          <div class="cv-page-header-nav">
            <mdui-button variant="text" href="../index.html" class="cv-m3-back-btn">
              <span slot="icon">${icon('arrow-left')}</span>设计稿索引
            </mdui-button>
            <mdui-segmented-button-group selects="single" value="${escape(page)}" class="cv-m3-page-tabs" aria-label="会话概念稿视图切换">
              ${tabs.map(tab => `
                <mdui-segmented-button value="${escape(tab.id)}" data-nav-href="${tab.href}">
                  <span slot="icon">${icon(tab.ico)}</span>${escape(tab.label)}
                </mdui-segmented-button>
              `).join('')}
            </mdui-segmented-button-group>
          </div>
          <h1>${escape(meta.title)}</h1>
          <p>${escape(meta.subtitle)}</p>
        </div>
        <mdui-chip class="cv-m3-meta-chip" tabindex="-1">
          <span slot="icon">${icon('palette')}</span>Material 3 · 暹罗浅色 · 共享组件
        </mdui-chip>
      </header>
      <main class="cv-page-main">
        <div class="cv-preview-mount"></div>
        <footer class="cv-page-foot">
          ${meta.footerHTML}<br>
          <a href="../conversation-shared/README.md">共享会话组件说明</a> · <a href="../../concepts/session-start-layout.md">起始与运行期输入设计</a> · <a href="../../19-studio-ui.md">桌面界面规范</a> · <a href="../../26-timeline-content.md">时间线内容契约</a>
        </footer>
      </main>
    `;
    const headerEl = host.querySelector('.cv-page-header');
    icons(headerEl);
    headerEl.querySelectorAll('mdui-segmented-button[data-nav-href]').forEach(seg => {
      seg.addEventListener('click', () => {
        if (seg.getAttribute('value') !== page) {
          window.location.href = seg.dataset.navHref;
        }
      });
    });
    const mount = host.querySelector('.cv-preview-mount');
    mount.dataset.page = page;
    if (host.dataset.scenario) mount.dataset.scenario = host.dataset.scenario;
    if (host.dataset.controls) mount.dataset.controls = host.dataset.controls;
    return mount;
  }

  class ConversationPreview {
    constructor(root) {
      this.root = root;
      this.id = 'conversation-preview-' + (++instanceSequence);
      this.page = root.dataset.page || 'session';
      const urlScenario = new URLSearchParams(window.location.search).get('scenario');
      const defaultScenario = this.page === 'sidebar'
        ? 'sidebar-overview'
        : this.page === 'start'
          ? 'local'
          : this.page === 'composer'
            ? 'running-locked'
            : 'workgroup';
      const initialScenario = (urlScenario && app.fixtures.scenarios.some(item => item.id === urlScenario))
        ? urlScenario
        : (root.dataset.scenario || defaultScenario);

      this.controller = new app.ConversationController(initialScenario);
      this.signal = new AbortController();
      this.sidebarCollapsed = false;
      this.historyNodes = new Map();
      this.renderedHistoryOwner = '';
      this.followHistory = true;
      this.followText = true;
      this.lastRead = 0;
      this.toastTimer = null;
      this.liveView = null;

      this.menuManager = new MenuManager(root, () => this.windowEl);
      this.lightboxState = { images: [], index: 0, zoomActual: false, triggerEl: null };
      this.actions = {
        copy: text => this.copy(text),
        retrySubmission: inputId => this.controller.retrySubmission(inputId),
        removeSubmission: inputId => this.controller.removeSubmission(inputId),
        detail: (title, content, path) => this.detail(title, content, path),
        previewImage: (images, activeId, triggerEl) => this.openImagePreview(images, activeId, triggerEl)
      };
      this.composerHelpers = {
        toast: msg => this.toast(msg),
        copy: text => this.copy(text),
        openFilePicker: () => this.fileInput.click(),
        openUrlDialog: () => this.urlDialog.showModal(),
        openImagePreview: (images, activeId, triggerEl) => this.openImagePreview(images, activeId, triggerEl),
        selectStandaloneOnStart: () => {
          if (this.sidebar) this.sidebar.archivedMode = false;
          this.controller.selectStandaloneStart();
        },
        selectProjectOnStart: projectId => {
          if (this.sidebar) {
            this.sidebar.archivedMode = false;
            this.sidebar.expandedIds.add(projectId);
          }
          this.controller.selectProjectStart(projectId);
        },
        openAddProjectDialog: initialName => {
          this.sidebar?.openAddProjectDialog(initialName);
        },
        onSubmitFromComposer: () => {
          this.followHistory = true;
          this.controller.submit();
        }
      };

      this.composerCard = new PromptComposerCard(this.controller, this.menuManager, this.composerHelpers);

      this.build();
      this.bindGlobalEvents();
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
      const groups = orderedGroupsForPage(this.page);
      const guide = guideForPage(this.page);

      root.classList.add('cv-preview');
      if (root.dataset.controls === 'false') root.classList.add('cv-no-controls');

      const scenarioMenuHTML = groups.map((grp, gIdx) => {
        const items = app.fixtures.scenarios.filter(s => s.group === grp.id);
        return `
          ${gIdx > 0 ? '<div class="cv-menu-divider"></div>' : ''}
          <div class="cv-menu-head"><span>${escape(grp.label)}</span></div>
          ${items.map(s => `
            <button type="button" class="cv-menu-item cv-scenario-option" data-pick-scenario="${escape(s.id)}">
              <span class="cv-check-slot"></span>
              <span class="cv-item-main">
                <div class="cv-item-title">${escape(s.label)}</div>
              </span>
            </button>
          `).join('')}
        `;
      }).join('');

      root.innerHTML = `
        <div class="cv-demo-layout">
          <section class="cv-window" aria-label="糊来帮统一会话概念预览">
            <div class="cv-shell">
              <aside data-sidebar-host aria-label="项目与会话侧边栏"></aside>

              <div class="cv-workspace">
                <header class="cv-topbar">
                  <div class="cv-topbar-left"></div>
                  <div class="cv-topbar-right"></div>
                </header>

                <!-- Stage 1: New Session Start Stage -->
                <div class="cv-start-stage" hidden></div>

                <!-- Stage 2: Runtime Session Stage -->
                <div class="cv-session-stage" hidden>
                  <div class="cv-history" role="region" aria-label="已结束的时间线" tabindex="0">
                    <div class="cv-reading-column">
                      <div class="cv-history-start"></div>
                      <div class="cv-history-list"></div>
                      <div class="cv-resting-tail" aria-label="可继续追加的静态工作尾组"></div>
                    </div>
                  </div>
                  <div class="cv-unread-wrap"></div>
                  <div class="cv-bottom">
                    <div class="cv-reading-column">
                      <div class="cv-live-host"></div>
                      <div class="cv-composer-dock">
                        <div class="cv-lock-notice-host"></div>
                        <div class="cv-pending-host"></div>
                        <div class="cv-readonly-host"></div>
                        <div class="cv-composer-card-mount"></div>
                      </div>
                      <footer class="cv-conversation-footer">
                        <div class="cv-footer-left"></div>
                        <div class="cv-footer-right">
                          <span class="cv-cap-summary" title="当前会话已启用的技能、MCP 与 LSP 服务数量">技能 9 · MCP 2 · LSP 1</span>
                          <details class="cv-context">
                            <summary aria-label="上下文详情">
                              <span class="cv-context-ring"></span>
                              <span>上下文</span>
                            </summary>
                            <div class="cv-context-popover">
                              <h3>上下文用量</h3>
                              <div class="cv-context-value"></div>
                              <div class="cv-context-meta">89.2k / 212.32k 自动压缩阈值 · 最大窗口 400k</div>
                              <p class="cv-context-explanation"></p>
                            </div>
                          </details>
                        </div>
                      </footer>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <input class="cv-file-input" type="file" multiple hidden>
            <div class="cv-toast" role="status" hidden></div>
          </section>

          <aside class="cv-side" aria-label="概念稿演示控制" ${root.dataset.controls === 'false' ? 'hidden' : ''}>
            <mdui-card variant="outlined" class="cv-inspector-card">
              <h2>统一会话组件与交互演示</h2>
              <p class="cv-inspector-lead">全部会话页面共用同一套外壳、顶栏、时间线与输入卡，无跨页复制代码。所有交互均为本地模拟。</p>
              <div class="cv-menu-anchor cv-m3-select-anchor">
                <button
                  type="button"
                  class="cv-m3-select"
                  data-menu-trigger="scenario"
                  aria-haspopup="menu"
                  aria-expanded="false">
                  <span class="cv-m3-select-label">切换生命周期场景</span>
                  <span class="cv-m3-select-value"></span>
                  <span class="cv-caret">${icon('chevron-down')}</span>
                </button>
                <div class="cv-menu cv-scenario-menu align-right" data-menu-panel="scenario" role="menu" hidden>
                  ${scenarioMenuHTML}
                </div>
              </div>
              <div class="cv-scenario-hint"></div>
              <div class="cv-external-notes" aria-label="外部设计说明" hidden></div>
              <div class="cv-quick-presets" aria-label="一键对比内置与 ACP 配置形态"></div>
              <div class="cv-demo-controls"></div>
              <div class="cv-playback-box" hidden>
                <div class="cv-demo-progress">
                  <span>时间线交接进度</span>
                  <span class="cv-step-count cv-tabular"></span>
                </div>
                <mdui-linear-progress class="cv-playback-progress" value="0" aria-label="演示进度"></mdui-linear-progress>
                <div class="cv-demo-state"></div>
              </div>
            </mdui-card>

            <mdui-card variant="outlined" class="cv-inspector-card">
              <div class="cv-matrix-box">
                <h3>实时配置可配性矩阵</h3>
                <div class="cv-matrix-list"></div>
              </div>

              <div class="cv-guide">
                <h3>${escape(guide.title)}</h3>
                <ul class="cv-guide-list">
                  ${guide.items.map(([head, body]) => `<li><strong>${escape(head)}</strong>：${escape(body)}</li>`).join('')}
                </ul>
                <div class="cv-stats">
                  <div class="cv-stats-line"><span>当前视图</span><strong class="cv-stage-label"></strong></div>
                  <div class="cv-stats-line"><span>时间线 / 状态栏</span><strong class="cv-live-label"></strong></div>
                  <div class="cv-stats-change"><span>最近变化</span><strong class="cv-last-change"></strong></div>
                </div>
              </div>
            </mdui-card>
          </aside>
        </div>

        <dialog class="cv-dialog cv-detail-dialog">
          <div class="cv-dialog-header"><h2></h2></div>
          <div class="cv-dialog-body"></div>
        </dialog>

        <dialog class="cv-dialog is-compact cv-url-dialog">
          <h3 style="margin:0 0 6px;font-size:15px;font-weight:600;">添加远程附件链接</h3>
          <p style="margin:0 0 12px;font-size:12px;color:var(--cv-secondary);">输入 HTTPS 图片或文档链接，作为草稿附件加入当前会话输入框。</p>
          <input type="url" class="cv-url-input" value="https://example.com/specs/runtime-composer-locks.pdf" placeholder="https://...">
          <div class="cv-dialog-actions">
            <button type="button" class="cv-button" data-url-dialog="cancel">取消</button>
            <button type="button" class="cv-button cv-primary" data-url-dialog="confirm">添加链接</button>
          </div>
        </dialog>

        <dialog class="cv-dialog cv-image-dialog" aria-label="图片大图预览">
          <div class="cv-lightbox-header">
            <div class="cv-lightbox-title-group">
              <h2 class="cv-lightbox-title"></h2>
              <span class="cv-lightbox-meta"></span>
            </div>
            <div class="cv-lightbox-controls">
              <div class="cv-lightbox-pager" hidden>
                <button type="button" class="cv-button cv-quiet cv-icon-only" data-lightbox-cmd="prev" title="上一张图片 (←)" aria-label="上一张图片">
                  ${icon('chevron-left')}
                </button>
                <span class="cv-lightbox-count cv-tabular"></span>
                <button type="button" class="cv-button cv-quiet cv-icon-only" data-lightbox-cmd="next" title="下一张图片 (→)" aria-label="下一张图片">
                  ${icon('chevron-right')}
                </button>
              </div>
              <button type="button" class="cv-button cv-quiet" data-lightbox-cmd="zoom">
                ${icon('maximize-2')}
                <span class="cv-lightbox-zoom-label">1:1 原图</span>
              </button>
              <button type="button" class="cv-button cv-quiet cv-icon-only" data-lightbox-cmd="close" title="关闭大图预览" aria-label="关闭大图预览">
                ${icon('x')}
              </button>
            </div>
          </div>
          <div class="cv-lightbox-stage">
            <img class="cv-lightbox-img" alt="">
          </div>
          <div class="cv-lightbox-footer" hidden></div>
        </dialog>
      `;

      this.windowEl = root.querySelector('.cv-window');
      this.shellEl = root.querySelector('.cv-shell');
      this.sidebarEl = root.querySelector('[data-sidebar-host]');
      this.topbarEl = root.querySelector('.cv-topbar');
      this.topbarLeftEl = root.querySelector('.cv-topbar-left');
      this.topbarRightEl = root.querySelector('.cv-topbar-right');
      this.startStageEl = root.querySelector('.cv-start-stage');
      this.sessionStageEl = root.querySelector('.cv-session-stage');

      this.sidebar = new window.AnyworkSidebar.StudioSidebar({
        host: this.sidebarEl,
        windowEl: this.windowEl,
        shellEl: this.shellEl,
        controller: this.controller,
        onToast: msg => this.toast(msg),
        onCopy: text => this.copy(text)
      });

      this.history = root.querySelector('.cv-history');
      this.historyStart = root.querySelector('.cv-history-start');
      this.historyList = root.querySelector('.cv-history-list');
      this.liveHost = root.querySelector('.cv-live-host');
      this.lockNoticeHost = root.querySelector('.cv-lock-notice-host');
      this.pendingHost = root.querySelector('.cv-pending-host');
      this.readonlyHost = root.querySelector('.cv-readonly-host');
      this.sessionCardMount = root.querySelector('.cv-composer-card-mount');
      this.footerLeftEl = root.querySelector('.cv-footer-left');

      this.unread = button('回到最新', 'arrow-down', () => {
        this.followHistory = true;
        this.lastRead = controller.state.history.length;
        this.scrollHistory();
        this.updateUnread();
      }, 'cv-unread');
      this.unread.hidden = true;
      root.querySelector('.cv-unread-wrap').append(this.unread);

      this.pendingView = new PendingView(this.pendingHost, controller, this.id);

      this.compressButton = button('立即压缩', 'minimize-2', () => {
        root.querySelector('.cv-context').open = false;
        controller.compact();
      });
      root.querySelector('.cv-context-popover').append(this.compressButton);
      this.contextValue = root.querySelector('.cv-context-value');
      this.contextExplanation = root.querySelector('.cv-context-explanation');

      this.fileInput = root.querySelector('.cv-file-input');
      this.toastNode = root.querySelector('.cv-toast');
      this.scenarioTrigger = root.querySelector('[data-menu-trigger="scenario"]');
      this.scenarioMenu = root.querySelector('[data-menu-panel="scenario"]');
      this.scenarioValueEl = root.querySelector('.cv-m3-select-value');
      this.externalNotesEl = root.querySelector('.cv-external-notes');
      this.quickPresetsEl = root.querySelector('.cv-quick-presets');
      this.playbackBox = root.querySelector('.cv-playback-box');
      this.matrixListEl = root.querySelector('.cv-matrix-list');

      const presetItems = this.page === 'start'
        ? [
            { id: 'start-project', label: '内置默认' },
            { id: 'start-acp-codex', label: 'Codex (动态强度)' },
            { id: 'start-acp-agy', label: 'Antigravity (⚙调优)' },
            { id: 'start-acp-grok', label: 'Grok (146/纯文本)' },
            { id: 'start-acp-deferred', label: '首条激活态' },
            { id: 'start-acp-ssh-blocked', label: 'SSH 阻断' }
          ]
        : [
            { id: 'idle-editable', label: '内置空闲' },
            { id: 'acp-codex-idle', label: 'Codex ACP' },
            { id: 'acp-agy-extra', label: 'Antigravity ⚙调优' },
            { id: 'acp-claude-legacy', label: 'Claude 旧版' },
            { id: 'acp-config-pending', label: 'ACP 确认中' },
            { id: 'acp-running-locked', label: 'ACP 运行锁' }
          ];
      if (this.quickPresetsEl) {
        this.quickPresetsEl.innerHTML = presetItems.map(p => `
          <button type="button" class="cv-preset-chip" data-quick-preset="${escape(p.id)}">${escape(p.label)}</button>
        `).join('');
        this.quickPresetsEl.querySelectorAll('[data-quick-preset]').forEach(btn => {
          btn.addEventListener('click', () => {
            const id = btn.dataset.quickPreset;
            controller.load(id);
            this.sidebar?.applyScenarioPreset(id);
          });
        });
      }

      // Inspector controls
      const controlsHost = root.querySelector('.cv-demo-controls');
      this.playButton = button('播放过程', 'play', () => controller.state.playing ? controller.pause() : controller.play(), 'cv-primary');
      this.stepButton = button('单步', 'step-forward', () => controller.step(), 'cv-tonal');
      this.finishStopButton = button('完成停止收束', 'check', () => controller.completeStoppingCleanup(), 'cv-primary');
      this.failureButton = button('模拟失败', 'circle-alert', () => controller.fail());
      this.probeAcpButton = button('模拟预加载配置', 'sparkles', () => {
        controller.enableAcpStartProbe();
        this.toast('已模拟预加载配置');
      }, 'cv-tonal');
      this.probeAcpButton.hidden = true;
      this.sidebarBtn = button('侧栏开关', 'panel-left', () => this.toggleSidebar());
      this.resetButton = button('重置', 'rotate-ccw', () => {
        const sc = controller.state.scenario;
        controller.load(sc);
        this.sidebar?.applyScenarioPreset(sc);
      });
      controlsHost.append(this.playButton, this.stepButton, this.finishStopButton, this.failureButton, this.probeAcpButton, this.sidebarBtn, this.resetButton);

      this.dialog = root.querySelector('.cv-detail-dialog');
      const close = button('关闭', 'x', () => this.dialog.close(), 'cv-quiet cv-icon-only');
      close.setAttribute('aria-label', '关闭详情');
      this.dialog.querySelector('.cv-dialog-header').append(close);

      this.urlDialog = root.querySelector('.cv-url-dialog');
      this.urlInput = this.urlDialog.querySelector('.cv-url-input');
      this.imageDialog = root.querySelector('.cv-image-dialog');

      icons(root);
    }

    bindGlobalEvents() {
      const controller = this.controller;
      this.scrollTimers = new WeakMap();
      this.activeScrollingEls = new Set();

      const markScrolling = rawTarget => {
        if (this.suppressScrollReveal) return;
        const el = rawTarget === document ? document.documentElement : rawTarget;
        if (!(el instanceof Element)) return;
        el.classList.add('is-scrolling');
        this.activeScrollingEls.add(el);
        clearTimeout(this.scrollTimers.get(el));
        this.scrollTimers.set(el, setTimeout(() => {
          el.classList.remove('is-scrolling');
          this.activeScrollingEls.delete(el);
        }, 850));
      };

      this.root.addEventListener('scroll', event => markScrolling(event.target), {
        capture: true,
        passive: true,
        signal: this.signal.signal
      });
      window.addEventListener('scroll', event => markScrolling(event.target), {
        passive: true,
        signal: this.signal.signal
      });

      this.scenarioTrigger?.addEventListener('click', () => {
        this.menuManager.toggle('scenario', this.scenarioTrigger, this.scenarioMenu, false);
        const activeOpt = this.scenarioMenu?.querySelector('.cv-scenario-option.is-selected');
        activeOpt?.scrollIntoView({ block: 'nearest' });
      });

      this.scenarioMenu?.querySelectorAll('[data-pick-scenario]').forEach(opt => {
        opt.addEventListener('click', () => {
          this.menuManager.closeAll();
          const sc = opt.dataset.pickScenario;
          controller.load(sc);
          this.sidebar?.applyScenarioPreset(sc);
        });
      });

      document.addEventListener('pointerdown', event => {
        if (this.menuManager.openId && !event.target.closest('.cv-menu-anchor')) {
          this.menuManager.closeAll();
        }
      }, { signal: this.signal.signal });

      this.root.addEventListener('click', event => {
        const shellBtn = event.target.closest('[data-shell-action]');
        if (shellBtn) {
          const act = shellBtn.dataset.shellAction;
          this.menuManager.closeAll();
          if (act === 'toggle-sidebar') this.toggleSidebar();
          else if (act === 'back-to-root') controller.switchAgent('root');
        }
      }, { signal: this.signal.signal });

      document.addEventListener('keydown', event => {
        if (event.key === 'Escape' && this.menuManager.openId) {
          event.preventDefault();
          this.menuManager.closeAll();
        }
      }, { signal: this.signal.signal });

      this.fileInput.addEventListener('change', () => {
        if (this.fileInput.files?.length) {
          controller.attach(this.fileInput.files);
          this.fileInput.value = '';
        }
      });

      this.dialog.addEventListener('click', event => {
        if (event.target === this.dialog) {
          const bounds = this.dialog.getBoundingClientRect();
          if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) {
            this.dialog.close();
          }
        }
      });

      this.urlDialog.addEventListener('click', event => {
        const btn = event.target.closest('[data-url-dialog]');
        if (!btn) return;
        if (btn.dataset.urlDialog === 'cancel') {
          this.urlDialog.close();
        } else if (btn.dataset.urlDialog === 'confirm') {
          controller.addLinkAttachment(this.urlInput.value);
          this.urlDialog.close();
        }
      });

      this.imageDialog.addEventListener('click', event => {
        if (event.target === this.imageDialog) {
          const bounds = this.imageDialog.getBoundingClientRect();
          if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) {
            this.imageDialog.close();
            return;
          }
        }
        const cmdBtn = event.target.closest('[data-lightbox-cmd]');
        if (cmdBtn) {
          const cmd = cmdBtn.dataset.lightboxCmd;
          if (cmd === 'close') this.imageDialog.close();
          else if (cmd === 'prev') this.stepLightbox(-1);
          else if (cmd === 'next') this.stepLightbox(1);
          else if (cmd === 'zoom') this.toggleLightboxZoom();
          return;
        }
        if (event.target.classList.contains('cv-lightbox-img')) {
          this.toggleLightboxZoom();
        }
      });

      this.imageDialog.addEventListener('close', () => {
        const trigger = this.lightboxState.triggerEl;
        this.lightboxState.triggerEl = null;
        if (trigger && trigger.isConnected) trigger.focus();
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
    }

    toggleSidebar() {
      this.sidebar?.closeMenus();
      this.sidebar?.hideHoverCard();
      if (window.innerWidth <= 920) {
        this.shellEl.classList.toggle('is-mobile-drawer-open');
        this.sidebar?.syncDrawerBackdrop();
      } else {
        this.sidebarCollapsed = !this.sidebarCollapsed;
        this.shellEl.classList.toggle('is-sidebar-collapsed', this.sidebarCollapsed);
      }
    }

    scrollHistory() {
      this.history.scrollTop = this.history.scrollHeight;
    }

    updateUnread() {
      if (this.controller.state.stage !== 'session' || this.controller.state.activeAgentId !== 'root') {
        this.unread.hidden = true;
        return;
      }
      const count = Math.max(0, this.controller.state.history.length - this.lastRead);
      this.unread.hidden = this.followHistory || count === 0;
      this.unread.querySelector('span').textContent = count ? `${count} 项新内容 · 回到最新` : '回到最新';
    }

    renderLockNotice() {
      this.lockNoticeHost.replaceChildren();
    }

    renderLive() {
      const state = this.controller.state;
      const isSubagent = state.activeAgentId !== 'root';
      if (isSubagent) {
        const subAgent = this.controller.currentAgent();
        if (subAgent.status === 'running') {
          this.liveHost.innerHTML = `<section class="cv-live" aria-label="子智能体当前状态"><div class="cv-thinking-header">${activityIndicator('restingCat')}<span class="cv-live-title">${escape(subAgent.role)} 正在执行…</span><span class="cv-tabular">执行了 4 秒</span></div></section>`;
          icons(this.liveHost);
        } else {
          this.liveHost.replaceChildren();
        }
        this.liveView = null;
        return;
      }

      const live = state.live;
      const tailHost = this.root.querySelector('.cv-resting-tail');
      if (!live || live.kind !== 'workGroup' || !live.resting) {
        tailHost?.replaceChildren();
      }
      if (!live) {
        this.liveHost.replaceChildren();
        this.liveView = null;
        return;
      }
      const kind = live.kind;
      if (this.liveView?.id !== live.id || this.liveView.kind !== kind) {
        this.liveHost.replaceChildren();
        const surface = node(`<section class="cv-live" data-live-kind="${escape(kind)}" aria-label="当前状态栏"></section>`);
        this.liveHost.append(surface);
        this.liveView = { id: live.id, kind, surface };
        if (kind === 'waiting') {
          surface.append(node(`<div class="cv-thinking-header">${activityIndicator('restingCat')}<span class="cv-live-title" role="status">思考中</span><span class="cv-tabular" aria-hidden="true"></span></div>`));
        } else if (kind === 'workGroup') {
          this.liveView.group = new WorkGroupView(live, 'live', this.actions);
          surface.append(this.liveView.group.node);
        } else if (kind === 'textOutput') {
          surface.append(node(`<div class="cv-response-header">${activityIndicator('writing')}<span class="cv-live-title">正在输出</span><span class="cv-tabular"></span></div>`));
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
          surface.append(node(`<div class="cv-compressing-header">${activityIndicator('compactingZip')}<span class="cv-live-title">正在压缩上下文</span><span class="cv-tabular"></span></div>`));
        }
        icons(surface);
      }
      if (kind === 'workGroup') {
        const resting = Boolean(live.resting);
        this.liveView.group.mode = resting ? 'resting' : 'live';
        this.liveView.group.node.classList.toggle('cv-group-live', !resting);
        this.liveView.group.node.classList.toggle('cv-group-history', resting);
        (resting ? tailHost : this.liveView.surface).append(this.liveView.group.node);
        this.liveView.surface.hidden = resting;
        this.liveView.group.update(live);
      } else {
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

    renderSessionStage(reason) {
      const state = this.controller.state;
      const agent = this.controller.currentAgent();
      const isSubagent = !agent.isRoot;
      const ownerKey = isSubagent ? `sub:${agent.id}:${agent.status}` : 'root';

      if (reason === 'reset' || this.renderedHistoryOwner !== ownerKey) {
        this.historyList.replaceChildren();
        this.historyNodes.clear();
        this.renderedHistoryOwner = ownerKey;
        this.followHistory = true;
      }

      const items = isSubagent ? app.fixtures.childHistory(agent) : state.history;
      const oldTop = this.history.scrollTop;

      if (items.length === 0 && this.historyNodes.size === 0 && !this.historyList.firstChild) {
        const empty = node(`<div class="cv-empty">${icon('sparkles')}<h2>新会话已就绪</h2></div>`);
        empty.append(button('填入示例任务', 'arrow-up-right', () => {
          this.controller.setDraft('梳理 SQLite 连接池取消路径并补充回归测试。');
          this.composerCard.textarea.focus();
        }));
        this.historyList.append(empty);
        icons(empty);
      }
      if (items.length && this.historyList.querySelector('.cv-empty')) {
        this.historyList.replaceChildren();
      }

      items.forEach(item => {
        if (this.historyNodes.has(item.id)) return;
        const rendered = historyItem(item, this.actions);
        rendered.dataset.historyId = item.id;
        this.historyNodes.set(item.id, rendered);
        this.historyList.append(rendered);
        icons(rendered);
      });

      this.historyStart.hidden = items.length === 0;
      this.historyStart.textContent = isSubagent ? agent.role : '今天';

      this.renderLive();
      this.renderLockNotice();

      if (isSubagent) {
        this.pendingView.update(null);
        this.sessionCardMount.hidden = true;
        this.readonlyHost.replaceChildren(buildAgentReadOnlyDock(this.controller));
      } else {
        this.readonlyHost.replaceChildren();
        this.pendingView.update(state.pending);
        if (this.composerCard.node.parentElement !== this.sessionCardMount) {
          this.sessionCardMount.append(this.composerCard.node);
        }
        this.sessionCardMount.hidden = Boolean(state.pending);
        this.composerCard.update();
      }

      // Status footer
      const schema = this.controller.getComposerSchema();
      const modeLabel = state.backendKind === 'acp'
        ? (schema.modeSlot ? schema.modeSlot.currentLabel : `ACP · ${schema.account?.name || 'Agent'}`)
        : this.controller.currentMode().label;
      const wf = state.frozenThread.workflow;
      const leftParts = [];
      if (isSubagent) {
        leftParts.push(`<span class="cv-workflow-pill is-active">${icon('git-fork')}<span>子智能体 · ${escape(agent.role)}</span></span>`);
      } else if (wf.active && state.backendKind !== 'acp') {
        leftParts.push(`<span class="cv-workflow-pill is-active" title="${escape(wf.stageLabel)}">${icon('workflow')}<span>${escape(wf.stageLabel)}</span></span>`);
      } else {
        leftParts.push(`<span class="cv-workflow-pill">${escape(modeLabel)}</span>`);
      }
      if (!isSubagent && state.live) {
        leftParts.push(`<span>·</span><span class="cv-tabular">${state.throughput} 词元/秒</span>`);
      }
      leftParts.push(`<span>·</span><span class="cv-tabular">累计 ${escape(state.costLabel)}</span>`);
      this.footerLeftEl.innerHTML = leftParts.join('');
      icons(this.footerLeftEl);

      // Context ring & popover
      this.contextValue.textContent = state.context + '%';
      this.root.querySelector('.cv-context-ring').style.setProperty('--cv-context-fill', state.context + '%');
      const canCompact = !isSubagent && !state.live && !state.pending && state.transitionPhase === 'none' && state.history.length > 0;
      this.compressButton.disabled = !canCompact;
      this.compressButton.querySelector('span').textContent = state.retryCompression ? '重试压缩' : '立即压缩';
      this.contextExplanation.hidden = true;
      this.contextExplanation.textContent = '';

      if (reason === 'reset' && state.scenario === 'read-images' && !isSubagent) {
        this.history.scrollTop = 0;
        this.lastRead = state.history.length;
        this.followHistory = this.history.scrollHeight - this.history.clientHeight < 22;
      } else if (this.followHistory) {
        this.scrollHistory();
        if (!isSubagent) this.lastRead = state.history.length;
      } else {
        this.history.scrollTop = oldTop;
      }
      this.updateUnread();
    }

    renderInspector() {
      const state = this.controller.state;
      const locks = this.controller.getLockState();
      const action = this.controller.getPrimaryAction();
      const currentScenario = app.fixtures.scenarios.find(item => item.id === state.scenario);

      if (currentScenario) {
        if (this.scenarioValueEl) {
          this.scenarioValueEl.textContent = currentScenario.label;
          this.scenarioTrigger?.setAttribute('title', currentScenario.label);
        }
        if (this.scenarioMenu && this.renderedScenarioId !== currentScenario.id) {
          this.renderedScenarioId = currentScenario.id;
          this.scenarioMenu.querySelectorAll('[data-pick-scenario]').forEach(btn => {
            const selected = btn.dataset.pickScenario === currentScenario.id;
            btn.classList.toggle('is-selected', selected);
            const checkSlot = btn.querySelector('.cv-check-slot');
            if (checkSlot) checkSlot.innerHTML = selected ? icon('check') : '';
          });
          icons(this.scenarioMenu);
        }
        this.root.querySelector('.cv-scenario-hint').textContent = currentScenario.hint;
      }

      if (this.externalNotesEl) {
        const extNotes = describeContextNotes(this.controller);
        if (extNotes.length > 0) {
          this.externalNotesEl.hidden = false;
          this.externalNotesEl.innerHTML = extNotes.map(([title, body]) => `
            <div class="cv-ext-note-item">
              <strong>${escape(title)}</strong>
              <span>${escape(body)}</span>
            </div>
          `).join('');
        } else {
          this.externalNotesEl.hidden = true;
          this.externalNotesEl.replaceChildren();
        }
      }

      if (this.quickPresetsEl) {
        this.quickPresetsEl.querySelectorAll('[data-quick-preset]').forEach(btn => {
          btn.classList.toggle('is-active', btn.dataset.quickPreset === state.scenario);
        });
      }

      const inRootSession = state.stage === 'session' && state.activeAgentId === 'root';
      const hasQueue = inRootSession && !state.pending && state.transitionPhase === 'none' && state.cursor < state.queue.length;

      if (this.probeAcpButton) {
        this.probeAcpButton.hidden = !(state.stage === 'start' && state.backendKind === 'acp' && state.acpDeferredProbe);
      }
      this.playButton.hidden = !inRootSession;
      this.stepButton.hidden = !inRootSession;
      this.failureButton.hidden = !inRootSession;
      this.finishStopButton.hidden = state.transitionPhase !== 'stopping';
      this.playbackBox.hidden = !inRootSession;

      if (inRootSession) {
        this.playButton.disabled = !hasQueue;
        this.stepButton.disabled = !hasQueue || state.playing;
        const playLabel = state.playing ? '暂停' : '播放过程';
        if (this.playButton.dataset.label !== playLabel) {
          this.playButton.dataset.label = playLabel;
          this.playButton.innerHTML = icon(state.playing ? 'pause' : 'play') + `<span>${playLabel}</span>`;
          icons(this.playButton);
        }
        this.failureButton.disabled = (!state.live && !state.pending) || state.transitionPhase !== 'none';
        this.root.querySelector('.cv-step-count').textContent = `${state.cursor} / ${state.queue.length}`;
        const progress = this.root.querySelector('.cv-playback-progress');
        if (progress) {
          progress.value = state.cursor / Math.max(1, state.queue.length);
        }
        this.root.querySelector('.cv-demo-state').textContent = state.transitionPhase === 'stopping'
          ? '停止收束中 · 可点击上方「完成停止收束」进入已停止态'
          : state.pending
            ? '停靠区等待回答 · 原草稿已自动暂存'
            : state.playing
              ? '正在连续播放 · 输入框可并发打字，选择器已锁定'
              : hasQueue
                ? '演示已暂停 · 可单步推进或在下方并发编辑草稿与粘贴图片'
                : '当前无队列事件 · 可自由切换配置或发送新消息';
      }

      // Live Configuration Mutability Matrix
      const schema = locks.schema;
      let wsStatus;
      if (state.stage === 'start') {
        if (locks.acpIssue) wsStatus = ['SSH 阻断 ACP 启动', 'warn'];
        else if (locks.prepRunning) wsStatus = ['准备期已锁', 'locked'];
        else if (state.backendKind === 'acp') wsStatus = ['ACP · 无内部子分发', 'open'];
        else if (state.targetType === 'standalone') wsStatus = ['无项目 · 可切换项目', 'open'];
        else wsStatus = ['外层环境栏可配', 'open'];
      } else {
        wsStatus = [state.backendKind === 'acp' ? '创建冻结 · ACP 顶栏标签' : '创建冻结 · 顶栏只读', 'frozen'];
      }

      let modeStatus;
      if (locks.isSubagent) modeStatus = ['子会话只读', 'frozen'];
      else if (schema.deferred) modeStatus = ['待首次启动后获取', 'locked'];
      else if (!locks.modeSupported) modeStatus = ['协议未返回 · 槽位省略', 'locked'];
      else if (locks.configPending && state.acpConfigPending?.configId === schema.modeSlot?.id) modeStatus = ['等待 ACP 确认中…', 'warn'];
      else if (locks.modeEditable) modeStatus = [schema.modeSlot?.kind === 'acp-legacy' ? '可切（legacy modes）' : '可切换', 'open'];
      else if (!locks.isStart && state.frozenThread.workflow.active && !locks.isAcp) modeStatus = ['已锁 · 工作流进行中', 'locked'];
      else modeStatus = ['已锁 · 会话运行中', 'locked'];

      let modelStatus;
      if (locks.isSubagent) modelStatus = ['冻结路由 · 只读', 'frozen'];
      else if (!locks.isStart && state.frozenThread.botManaged && !locks.isAcp) modelStatus = ['已锁 · 机器人统一设置', 'locked'];
      else if (locks.configPending && state.acpConfigPending?.configId === schema.modelSlot?.id) modelStatus = ['等待 ACP 确认中…', 'warn'];
      else if (locks.isAcp && !locks.isStart && !locks.modelSupported) modelStatus = ['协议未暴露模型 · 只读胶囊', 'frozen'];
      else if (!locks.isStart && !state.frozenThread.routeAvailable) modelStatus = ['可换模（当前不可用）', 'warn'];
      else if (locks.modelEditable) modelStatus = [locks.isAcp ? (locks.isStart ? '内置+ACP 统一可换' : '可切该 ACP 子模型') : '可切换（下轮生效）', 'open'];
      else modelStatus = ['已锁 · 会话运行中', 'locked'];

      let effortStatus;
      if (locks.isSubagent) effortStatus = ['冻结路由 · 只读', 'frozen'];
      else if (!locks.isStart && state.frozenThread.botManaged && !locks.isAcp) effortStatus = ['已锁 · 机器人统一设置', 'locked'];
      else if (schema.deferred) effortStatus = ['待首次握手获取', 'locked'];
      else if (locks.configPending && state.acpConfigPending?.configId === schema.thoughtSlot?.id) modeStatus && (effortStatus = ['等待 ACP 确认中…', 'warn']);
      else if (!locks.effortSupported) effortStatus = ['已锁 · 模型无此参数', 'locked'];
      else if (locks.effortEditable) effortStatus = ['可切换', 'open'];
      else effortStatus = ['已锁 · 会话运行中', 'locked'];

      const extraCount = schema.extraOptions.length;
      let extraStatus = null;
      if (extraCount > 0) {
        if (locks.configPending && schema.extraOptions.some(o => o.id === state.acpConfigPending?.configId)) {
          extraStatus = [`同步中 · ${extraCount} 项`, 'warn'];
        } else {
          extraStatus = [locks.extraEditable ? `可调 · ${extraCount} 项动态参数` : `已锁 · ${extraCount} 项`, locks.extraEditable ? 'open' : 'locked'];
        }
      }

      let composerStatus;
      if (locks.isSubagent) composerStatus = ['只读停靠面板', 'frozen'];
      else if (locks.acpIssue) composerStatus = ['SSH+ACP 启动已阻断', 'warn'];
      else if (state.pending) composerStatus = ['问答停靠（草稿已暂存）', 'locked'];
      else if (action.kind === 'stopping') composerStatus = ['正在停止（过渡锁）', 'locked'];
      else if (action.kind === 'continuing') composerStatus = ['正在继续…', 'locked'];
      else if (!locks.isStart && !state.frozenThread.routeAvailable) composerStatus = ['草稿可写 · 发送已阻塞', 'warn'];
      else if (!schema.imageSupported) composerStatus = [`纯文本模式（禁传图片）`, 'open'];
      else if (action.kind === 'stop') composerStatus = ['可并发拟稿 · 主钮「停止」', 'open'];
      else if (action.kind === 'sendAndContinue') composerStatus = ['主钮「发送并继续 ↑」', 'open'];
      else if (action.kind === 'continue') composerStatus = ['主钮「▶ 继续」', 'open'];
      else composerStatus = [action.enabled ? '主钮「发送 ↑」就绪' : '可编辑（空草稿禁用发送）', 'open'];

      const matrixRows = [
        ['后端引擎', locks.isAcp ? `ACP · ${schema.account?.name || 'Agent'}` : '糊来帮内置', locks.isAcp ? 'open' : 'frozen'],
        ['项目 / 工作区 / 分发', ...wsStatus],
        ['工作模式', ...modeStatus],
        ['主智能体模型', ...modelStatus],
        ['思考强度', ...effortStatus],
        ...(extraStatus ? [['⚙ 调优参数', ...extraStatus]] : []),
        ['输入与主操作', ...composerStatus]
      ];

      this.matrixListEl.innerHTML = matrixRows.map(([key, text, tone]) => `
        <div class="cv-matrix-row">
          <span class="cv-matrix-key">${escape(key)}</span>
          <span class="cv-matrix-badge" data-tone="${escape(tone)}">${escape(text)}</span>
        </div>
      `).join('');

      this.root.querySelector('.cv-stage-label').textContent = state.stage === 'start'
        ? '起始页（双层创建台）'
        : locks.isSubagent
          ? `子智能体 · ${this.controller.currentAgent().role}`
          : '主会话（单层输入卡）';

      const grp = state.live?.kind === 'workGroup' ? state.live : null;
      const liveText = state.stage === 'start'
        ? (state.preparation ? `环境准备 · 步骤 ${state.preparation.stepIndex + 1}/4` : '待提交首条消息')
        : state.pending
          ? `${state.history.length} 项 · 问答停靠`
          : grp
            ? `${state.history.length} 项 · 工作组 ${grp.members.length} 步`
            : `${state.history.length} 项 · ${({ waiting: '思考中', textOutput: '正在输出', compacting: '正在压缩' })[state.live?.kind] || '空闲收起'}`;
      this.root.querySelector('.cv-live-label').textContent = liveText;
      this.root.querySelector('.cv-last-change').textContent = state.change || '—';
    }

    render(reason) {
      const state = this.controller.state;

      if (reason === 'draft') {
        this.composerCard.update();
        if (state.pending) this.pendingView.update(state.pending);
        this.renderInspector();
        return;
      }

      if (reason === 'notice') {
        if (state.lockNotice) this.toast(state.lockNotice);
        if (state.stage !== 'start') this.renderLockNotice();
        this.renderInspector();
        return;
      }

      if (reason === 'prep' && state.stage === 'start') {
        const heroSlot = this.startStageEl.querySelector('.cv-hero-slot');
        if (heroSlot && state.preparation) {
          heroSlot.innerHTML = buildPreparationHTML(this.controller);
          icons(heroSlot);
        }
        this.renderInspector();
        return;
      }

      if (reason === 'pendingInput') {
        this.pendingView.update(state.pending);
        return;
      }

      this.root.dataset.playing = String(state.playing);

      if (reason === 'reset') {
        this.suppressScrollReveal = true;
        this.activeScrollingEls?.forEach(el => {
          clearTimeout(this.scrollTimers?.get(el));
          el.classList.remove('is-scrolling');
        });
        this.activeScrollingEls?.clear();
        this.liveView = null;
        this.liveHost.replaceChildren();
        this.dialog.close();
        this.imageDialog.close();
        this.menuManager.closeAll();
        clearTimeout(this.toastTimer);
        this.toastNode.hidden = true;
      }

      if (reason === 'reset' && !this._initialPresetApplied) {
        this._initialPresetApplied = true;
        this.sidebar?.applyScenarioPreset(state.scenario);
      } else {
        this.sidebar?.render();
      }
      renderTopbar(this.topbarLeftEl, this.topbarRightEl, this.topbarEl, this.controller, this.menuManager, this.composerHelpers);

      if (state.stage === 'start') {
        this.sessionStageEl.hidden = true;
        this.startStageEl.hidden = false;
        renderStartStage(this.startStageEl, this.controller, this.composerCard, this.menuManager, this.composerHelpers);
        if (reason === 'reset' && state.scenario === 'project-picker') {
          requestAnimationFrame(() => {
            const projTrig = this.startStageEl.querySelector('[data-menu-trigger="project"]');
            const projPanel = this.startStageEl.querySelector('[data-menu-panel="project"]');
            if (projTrig && projPanel && projPanel.hidden) {
              this.menuManager.open('project', projTrig, projPanel, false);
              projPanel.querySelector('.cv-project-search-input')?.focus({ preventScroll: true });
            }
          });
        }
      } else {
        this.startStageEl.hidden = true;
        this.sessionStageEl.hidden = false;
        this.renderSessionStage(reason);
      }

      this.renderInspector();

      if (reason === 'reset') {
        requestAnimationFrame(() => {
          this.suppressScrollReveal = false;
        });
      }
    }

    async copy(text) {
      try {
        await navigator.clipboard.writeText(text);
        this.toast('已复制到剪贴板');
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

    openImagePreview(images, activeId, triggerEl = null) {
      if (!images?.length) return;
      const idx = Math.max(0, images.findIndex(item => item.id === activeId));
      this.lightboxState = {
        images,
        index: idx,
        zoomActual: false,
        triggerEl
      };
      this.syncLightboxView();
      if (!this.imageDialog.open) this.imageDialog.showModal();
    }

    stepLightbox(delta) {
      const list = this.lightboxState.images;
      if (list.length <= 1) return;
      this.lightboxState.index = (this.lightboxState.index + delta + list.length) % list.length;
      this.lightboxState.zoomActual = false;
      this.syncLightboxView();
    }

    toggleLightboxZoom() {
      this.lightboxState.zoomActual = !this.lightboxState.zoomActual;
      this.syncLightboxView();
    }

    syncLightboxView() {
      const { images, index, zoomActual } = this.lightboxState;
      const current = images[index];
      if (!current) return;
      this.imageDialog.querySelector('.cv-lightbox-title').textContent = current.name;
      const metaParts = [
        current.sourceLabel || '图片预览',
        current.dimensions,
        current.sizeLabel
      ].filter(Boolean);
      this.imageDialog.querySelector('.cv-lightbox-meta').textContent = metaParts.join(' · ');

      const pager = this.imageDialog.querySelector('.cv-lightbox-pager');
      pager.hidden = images.length <= 1;
      if (images.length > 1) {
        this.imageDialog.querySelector('.cv-lightbox-count').textContent = `${index + 1} / ${images.length}`;
      }

      const stage = this.imageDialog.querySelector('.cv-lightbox-stage');
      stage.classList.toggle('is-actual-size', zoomActual);
      const imgEl = this.imageDialog.querySelector('.cv-lightbox-img');
      imgEl.src = current.url;
      imgEl.alt = current.name;
      imgEl.title = zoomActual ? '点击恢复适应窗口大小' : '点击放大至 1:1 原始尺寸';

      const zoomLabel = this.imageDialog.querySelector('.cv-lightbox-zoom-label');
      zoomLabel.textContent = zoomActual ? '适应窗口' : '1:1 原图';

      const footer = this.imageDialog.querySelector('.cv-lightbox-footer');
      footer.hidden = !current.caption;
      footer.textContent = current.caption || '';
    }

    toast(message) {
      clearTimeout(this.toastTimer);
      this.toastNode.textContent = message;
      this.toastNode.hidden = false;
      this.toastTimer = setTimeout(() => { this.toastNode.hidden = true; }, 2200);
    }

    dispose() {
      this.sidebar?.destroy();
      this.controller.dispose();
      this.signal.abort();
      clearTimeout(this.toastTimer);
      this.dialog.close();
      this.urlDialog.close();
      this.imageDialog.close();
      app.instances.delete(this);
      delete this.root.conversationPreview;
    }
  }

  app.instances = new Set();
  app.mount = host => {
    if (host.conversationPreview) return host.conversationPreview;
    const mountTarget = host.dataset.pageChrome === 'true' ? mountPageChrome(host) : host;
    const preview = new ConversationPreview(mountTarget);
    host.conversationPreview = preview;
    app.instances.add(preview);
    return preview;
  };

  function boot() {
    const roots = document.querySelectorAll('[data-conversation-preview]');
    if (!roots.length) return;
    if (!window.marked || !window.DOMPurify || !window.lucide || !window.AnyworkSidebar) {
      roots.forEach(root => {
        root.textContent = '概念稿依赖未加载。请联网后重新打开页面（Marked / DOMPurify / Lucide / StudioSidebar）。';
      });
      return;
    }
    roots.forEach(root => app.mount(root));
  }

  if (document.readyState === 'loading') {
    window.addEventListener('DOMContentLoaded', boot, { once: true });
  } else {
    boot();
  }

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
