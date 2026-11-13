(() => {
  'use strict';
  const app = window.AnyworkConversation;
  const clone = value => structuredClone(value);
  const runningCount = group => group.members.filter(member => member.status === 'running').length;
  const isWaitingForModel = live => live?.kind === 'waiting'
    || (live?.kind === 'workGroup' && runningCount(live) === 0);

  function freeze(value) {
    if (value && typeof value === 'object') {
      Object.values(value).forEach(freeze);
      Object.freeze(value);
    }
    return value;
  }

  const flattenSelectOptions = option => {
    if (!option) return [];
    if (Array.isArray(option.groups) && option.groups.length) {
      return option.groups.flatMap(g =>
        (g.options || []).map(item => ({ ...item, groupLabel: g.group }))
      );
    }
    return Array.isArray(option.options) ? option.options : [];
  };

  class ConversationController extends EventTarget {
    constructor(scenario = 'workgroup') {
      super();
      this.sequence = 0;
      this.timer = null;
      this.prepTimer = null;
      this.transitionTimer = null;
      this.acpPendingTimer = null;
      this.urls = new Set();
      this.disposed = false;
      this.defaults = {
        delegationMode: 'automatic',
        delegationPreference: 'balanced'
      };
      this.load(scenario);
    }

    id(prefix) { return prefix + '-' + (++this.sequence); }

    emit(reason) {
      if (!this.disposed) this.dispatchEvent(new CustomEvent('change', { detail: { reason } }));
    }

    note(text) { this.state.change = text; }

    findModel(modelId) {
      return app.fixtures.allModels.find(m => m.id === modelId) || app.fixtures.allModels[0];
    }

    findAcpAccount(accountId) {
      const list = app.fixtures.acpAccounts || [];
      return list.find(a => a.id === accountId) || list[0] || null;
    }

    currentAcpAccount() {
      if (this.state.backendKind !== 'acp' || !this.state.acpAccountId) return null;
      return this.findAcpAccount(this.state.acpAccountId);
    }

    currentProject() {
      if (this.state.targetType === 'standalone') return null;
      return app.fixtures.projects.find(p => p.id === this.state.projectId) || app.fixtures.projects[0];
    }

    currentMode() {
      return app.fixtures.modes.find(m => m.id === this.state.modeId) || app.fixtures.modes[0];
    }

    currentModel() {
      return this.findModel(this.state.modelId);
    }

    currentAgent() {
      return this.state.agents.find(a => a.id === this.state.activeAgentId) || this.state.agents[0];
    }

    effectiveDelegationMode() {
      return this.state.delegationModeOverride || this.defaults.delegationMode;
    }

    effectiveDelegationPreference() {
      return this.state.delegationPrefOverride || this.defaults.delegationPreference;
    }

    delegationSummaryText() {
      const mode = this.effectiveDelegationMode();
      const pref = this.effectiveDelegationPreference();
      const prefLabel = { economy: '经济', balanced: '平衡', fast: '快速' }[pref] || '平衡';
      return mode === 'automatic' ? `自动选模 · ${prefLabel}` : '固定模板';
    }

    haltTimers() {
      clearInterval(this.timer);
      clearInterval(this.prepTimer);
      clearTimeout(this.transitionTimer);
      clearTimeout(this.acpPendingTimer);
      this.timer = null;
      this.prepTimer = null;
      this.transitionTimer = null;
      this.acpPendingTimer = null;
      if (this.state) this.state.playing = false;
    }

    snapshot(item) {
      if (this.state.history.some(existing => existing.id === item.id)) return;
      this.state.history = [...this.state.history, freeze(clone(item))];
    }

    recordOutcome(live, status, error = '') {
      const interrupted = live?.kind === 'workGroup'
        ? live.members.filter(member => member.status === 'stopped' || member.status === 'failed').length : 0;
      this.snapshot({
        id: (live?.id || this.id('interaction')) + '-outcome',
        kind: 'outcome',
        status,
        sourceId: live?.id,
        subject: !live ? '待回答的问题'
          : live.kind === 'waiting' ? '模型响应'
          : live.kind === 'workGroup' ? `工作组 · ${live.members.length} 步${interrupted ? ` · ${interrupted} 步未完成` : ''}`
          : live.kind === 'textOutput' ? '文本输出' : '上下文压缩',
        error
      });
    }

    load(scenario) {
      this.haltTimers();
      this.urls.forEach(url => URL.revokeObjectURL(url));
      this.urls.clear();

      const spec = app.fixtures.scenarios.find(item => item.id === scenario)
        || app.fixtures.scenarios[0];

      this.modeRoutes = {
        'mode.simple': { modelId: 'gpt-6.1-sol', effort: 'max' },
        'mode.task': { modelId: 'claude-opus-4.6', effort: 'high' }
      };

      this.state = {
        scenario: spec.id,
        stage: spec.stage || 'session', // 'start' | 'session'
        targetType: 'project', // 'project' | 'standalone'
        projectId: 'pure-lang-pure',
        activeSidebarThreadId: 'thr-main',
        workspaceMode: 'local',
        delegationModeOverride: null,
        delegationPrefOverride: null,
        preparation: null,

        backendKind: 'native', // 'native' | 'acp'
        acpAccountId: null,
        acpDeferredProbe: false,
        acpValues: {},
        acpConfigState: null,
        acpConfigPending: null,

        modeId: 'mode.simple',
        modelId: 'gpt-6.1-sol',
        effort: 'max',
        lockNotice: null,
        lockNoticeTone: 'info',

        agents: app.fixtures.defaultAgents(),
        activeAgentId: spec.activeAgentId || 'root',
        frozenThread: {
          id: 'thr-main',
          title: '重构 SQLite 连接池超时重试与取消收敛',
          projectName: 'pure-lang-pure',
          sshAlias: null,
          workspaceMode: 'worktree',
          workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure\\.anywork\\worktrees\\thr_01jc9k\\session',
          branch: 'anywork/thr-01jc9k',
          delegationSummary: '自动选模 · 平衡',
          workflow: { active: false, stageLabel: '' },
          botManaged: false,
          routeAvailable: true,
          routeUnavailableReason: '',
          backendKind: 'native',
          acpAccountId: null,
          acpAccountName: '',
          acpBadgeText: '',
          acpColor: ''
        },

        history: [],
        live: null,
        pendingText: null,
        pending: null,
        draft: spec.initialDraft || '',
        attachments: spec.initialAttachments ? clone(spec.initialAttachments) : [],
        context: 42,
        throughput: 68.4,
        costLabel: '$0.18',
        playing: false,
        running: false,
        resumable: false,
        continuationReason: null,
        retryCompression: false,
        transitionPhase: 'none', // 'none' | 'stopping' | 'continuing'
        queue: [],
        cursor: 0,
        change: ''
      };

      // Configure Start Stage scenarios
      if (this.state.stage === 'start') {
        this.state.activeSidebarThreadId = null;
        if (spec.acpAccountId) {
          this.applyAcpPreset(spec.acpAccountId, { deferred: Boolean(spec.acpDeferred) });
          if (spec.id === 'start-acp-ssh-blocked') {
            this.state.projectId = 'pure-lang-remote';
            this.state.workspaceMode = 'local';
            this.note('SSH 远端项目选中本地 ACP · 输入卡上方提示兼容性阻塞并提供一键恢复');
          } else if (spec.acpDeferred) {
            this.state.workspaceMode = 'worktree';
            this.note('起始页 · ACP 待首次连接（未预探测模型列表时仅显示智能体入口，发送即一键握手）');
          } else {
            const acc = this.currentAcpAccount();
            this.note(`起始页 · 模型菜单已选中外部智能体 ${acc?.name || ''}（ACP），右下角槽位同步适配`);
          }
        } else if (spec.id === 'worktree') {
          this.state.workspaceMode = 'worktree';
          this.state.draft = '新增独立工作树，排查异步调度队列偶发卡顿并补充回归测试。';
          this.note('起始页 · 已选中新建工作树，点击发送可预览四阶段准备过程');
        } else if (spec.id === 'ssh-worktree') {
          this.state.projectId = 'pure-lang-remote';
          this.state.workspaceMode = 'worktree';
          this.state.delegationModeOverride = 'automatic';
          this.state.delegationPrefOverride = 'fast';
          this.note('SSH 远程项目 · 远端工作树与分发覆盖均在外层环境栏一眼可见');
        } else if (spec.id === 'standalone') {
          this.state.targetType = 'standalone';
          this.state.workspaceMode = 'local';
          this.note('无项目新会话 · 与项目新建会话共用同一新会话页面，当前开启在「无项目」（Documents/anywork）');
        } else if (spec.id === 'project-picker') {
          this.note('项目选择器 · 支持在「无项目」、模糊搜索「已有项目」与「新建项目」之间一键切换');
        } else if (spec.id === 'preparing') {
          this.state.workspaceMode = 'worktree';
          this.state.preparation = {
            status: 'running',
            stepIndex: 1,
            subStage: '正在创建工作树并检出文件…',
            frozenWorkspaceMode: 'worktree',
            workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure\\.anywork\\worktrees\\thr_01jc9k\\session',
            branch: 'anywork/thr-01jc9k',
            expanded: true
          };
          this.note('环境准备中 · 外层空间与分发已按提交快照锁定，内层仍可继续拟稿');
        } else if (spec.id === 'worktree-error') {
          this.state.projectId = 'notes-plain-dir';
          this.state.workspaceMode = 'worktree';
          this.state.draft = '整理本季度构建日志并分析增量索引未命中的原因。';
          this.state.attachments = [
            { id: 'att-err-img', ...app.fixtures.sampleScreenshots[2] },
            { id: 'att-err-1', name: 'ui-walkthrough-notes.md', kind: 'file' }
          ];
          this.state.preparation = {
            status: 'failed',
            stepIndex: 1,
            subStage: '仓库解析未通过',
            error: '目标目录不是有效的 Git 仓库（缺少 .git 或基线 HEAD 提交），无法创建独立工作树。提示词与附件草稿已原位保留。',
            frozenWorkspaceMode: 'worktree',
            workspacePath: 'C:\\Users\\dev\\Documents\\design-notes',
            branch: null,
            expanded: false
          };
          this.note('准备失败 · 原位保留草稿与附件，支持一键切回本地目录');
        } else if (spec.id === 'sidebar-add-project') {
          this.note('添加项目向导 · 支持选择本地文件夹或从 ~/.ssh/config 挂载远程 SSH 项目');
        } else {
          this.note('起始页 · 创建期配置（工作区、分发）与模型菜单（内置模型 / 外部 ACP 智能体）清晰统一');
        }
        this.emit('reset');
        return;
      }

      // Configure Session Stage scenarios
      if (spec.id === 'read-images') {
        this.state.projectId = 'pure-lang-remote';
        this.state.activeSidebarThreadId = 'thr-read-images';
        this.state.frozenThread.id = 'thr-read-images';
        this.state.frozenThread.title = '界面走查截图与远端预览核对';
        this.state.frozenThread.projectName = 'pure-lang-remote';
        this.state.frozenThread.sshAlias = 'gpu-dev';
        this.state.frozenThread.workspaceMode = 'local';
        this.state.frozenThread.branch = null;
        this.state.frozenThread.workspacePath = '/srv/repos/pure-lang';
        this.state.frozenThread.delegationSummary = '自动选模 · 平衡';
        app.fixtures.readImagesHistory().forEach(item => this.snapshot(item));
        this.state.agents.forEach(a => { a.status = 'completed'; });
        this.note('时间线查看图片 · 轻量单行折叠，展开即横向排布圆角缩略图，不展示文件地址');
      } else if (!spec.empty) {
        app.fixtures.history().forEach(item => this.snapshot(item));
      }

      if (spec.acpAccountId) {
        this.applyAcpPreset(spec.acpAccountId, { deferred: false });
        const acc = this.currentAcpAccount();
        this.state.frozenThread.id = `thr-${spec.id}`;
        const acpTaskTitles = {
          'acp.codex': '重构桥接线程异步取消与超时恢复',
          'acp.agy': '优化工作区增量文件索引与缓存命中',
          'acp.grok': '排查多端构建脚本过期缓存清理问题',
          'acp.opencode': '统一运行期日志格式化与分级过滤',
          'acp.claude': '审计跨平台凭据库迁移错误边界'
        };
        this.state.frozenThread.title = acpTaskTitles[acc?.id] || `${acc?.name || 'ACP'} 会话任务`;
        this.state.frozenThread.workspaceMode = 'local';
        this.state.frozenThread.branch = null;
        this.state.frozenThread.workspacePath = 'C:\\Users\\dev\\work\\pure-lang-pure';
        this.state.frozenThread.delegationSummary = '自动选模 · 平衡';
        this.state.agents.forEach(a => { a.status = 'completed'; });
        if (spec.acpPendingDemo) {
          this.state.acpConfigPending = {
            configId: 'use_ai_credits',
            targetValue: true,
            label: '超额自动启用 AI Credits',
            demoStatic: true
          };
          this.note('ACP 配置同步中 · 等待服务端 session/set_config_option 返回期间全部槽位只读防叠发');
        } else if (!spec.at) {
          this.note(`ACP 运行期空闲 · 已绑定「${acc?.name || ''}」，右下角同构映射服务端动态配置`);
        }
      }

      if (spec.workflowActive) {
        this.state.activeSidebarThreadId = 'thr-workflow';
        this.state.modeId = 'mode.task';
        this.state.modelId = 'claude-opus-4.6';
        this.state.effort = 'high';
        this.state.frozenThread.id = 'thr-workflow';
        this.state.frozenThread.title = '按任务模式重构桌面状态栏投影';
        this.state.frozenThread.workspaceMode = 'local';
        this.state.frozenThread.branch = null;
        this.state.frozenThread.workspacePath = 'C:\\Users\\dev\\work\\pure-lang-pure';
        this.state.frozenThread.delegationSummary = '固定模板';
        this.state.frozenThread.workflow = { active: true, stageLabel: '任务 · 实施' };
        this.state.agents.forEach(a => { a.status = 'completed'; });
        this.note('活动工作流空闲间隙 · 工作模式不可交互，主模型与思考强度保持可切换');
      }

      if (spec.routeUnavailable) {
        this.state.modelId = 'claude-opus-4.6';
        this.state.effort = 'high';
        this.state.frozenThread.routeAvailable = false;
        this.state.frozenThread.routeUnavailableReason = '账号「Anthropic API」上的 Claude Opus 4.6 当前配额已耗尽（HTTP 429），暂时无法发起新轮次；请点击模型选择器切换至其他可用模型。';
        this.state.agents.forEach(a => { a.status = 'completed'; });
        this.note('模型路由不可用 · 保留原选择不静默篡改，主按钮阻塞，可切换模型自救');
      }

      if (spec.botManaged) {
        this.state.frozenThread.title = '飞书研发群 · 每日构建巡检会话';
        this.state.frozenThread.botManaged = true;
        this.state.frozenThread.workspaceMode = 'local';
        this.state.frozenThread.branch = null;
        this.state.agents.forEach(a => { a.status = 'completed'; });
        this.note('机器人托管会话 · 模型与思考强度由机器人设置统一接管');
      }

      if (spec.at) {
        this.state.queue = app.fixtures.story(this.id('group'));
        const target = this.state.queue.findIndex(event => event.label === spec.at);
        if (target < 0) throw new Error('Unknown story frame: ' + spec.at);
        while (this.state.cursor <= target) this.advance();
        if (spec.id === 'long-tool-output') {
          this.state.live.members = [{
            id: 'long-tool-output', kind: 'command', title: '执行命令', target: 'cargo flutter analyze',
            status: 'running', elapsed: 12, cwd: '~/work/anywork', exitCode: null,
            output: Array.from({length: 60}, (_, i) => `检查第 ${i + 1} 项：通过。`).join('\n')
          }];
        }
        if (spec.id === 'reasoning-variants') {
          this.state.live.members = [
            { id: 'reasoning-summary-body', kind: 'thinking', title: '思考', summary: '排查 **connection_pool.rs** 写锁超时退避与取消路径', status: 'completed', elapsed: 125,
              content: '先确认 `acquire_with_cancel` 与后台 WAL checkpoint 的锁顺序，确保取消释放时不持有连接池主互斥锁。' },
            { id: 'reasoning-summary-only', kind: 'thinking', title: '思考', summary: '核对 **TransactionGuard::drop** 事务回滚时序', status: 'completed', elapsed: 125 },
            { id: 'reasoning-body-only', kind: 'thinking', title: '思考', status: 'completed', elapsed: 125,
              content: '连接租约释放前同步检查未提交状态，在异步工作池中排入安全回滚并归还可用计数。' }
          ];
        }
      } else if (spec.live === 'compacting') {
        this.startCompression();
      } else if (spec.pending) {
        const sealed = app.fixtures.group(this.id('group'), true);
        sealed.members = sealed.members.slice(0, 2);
        sealed.elapsed = 4;
        this.snapshot(sealed);
        this.state.pending = clone(spec.pending);
        this.state.pending.id = this.id('interaction');
        this.note('提问到达 · 工作组已整组入时间线，输入框暂存草稿并切换为问答停靠');
      } else if (spec.outcome) {
        this.state.live = app.fixtures.group(this.id('group'));
        if (spec.outcome === 'failed') this.fail({ silentEmit: true });
        else this.stop({ immediate: true, silentEmit: true });
      } else if (spec.id === 'receipts') {
        this.snapshot({
          id: this.id('receipt'),
          kind: 'receipt',
          type: 'questions',
          title: '用户已回答',
          subtitle: '2 个问题',
          content: '### 连接池写锁争用超时后的默认重试策略？\n指数退避 + 随机抖动（12ms–80ms）\n\n### 本轮回归测试需要补充覆盖哪些场景？\nCancellationToken 取消信号触发回滚、多线程高并发写锁争用\n\n敏感回答已隐藏'
        });
        this.state.agents.forEach(a => { a.status = 'completed'; });
        this.note('问答已完成 · 时间线保留只读回执，敏感回答已隐藏');
      } else if (spec.id === 'idle' || spec.id === 'empty' || spec.id === 'sidebar-archived') {
        this.state.agents.forEach(a => { a.status = 'completed'; });
        if (!this.state.change) {
          this.note(spec.id === 'sidebar-archived'
            ? '侧边栏已归档目录 · 支持搜索历史归档会话并一键恢复至原列表'
            : spec.empty
              ? '空会话 · 输入首条消息启动完整运行流'
              : '轮次空闲 · 除顶栏创建期冻结项外，工作模式、模型与强度均可配置');
        }
      }

      if (spec.id === 'sidebar-overview') {
        this.note('侧边栏总览 · 保留蓝色竖条选中态，清理本地标签与已完成对勾噪音');
      } else if (spec.id === 'sidebar-open-menu') {
        this.note('跨边界二级菜单 · 「打开方式 ▶」向右展开原色应用徽标，不被滚动容器裁切');
      } else if (spec.id === 'sidebar-filter-active') {
        this.note('状态筛选「进行中」· 自动展开折叠的 SSH 项目 dcsdk2，定位全部后台任务');
      }

      if (spec.stoppingCleanup) {
        this.state.transitionPhase = 'stopping';
        this.note('已受理停止命令 · 正在等待工具子进程树与句柄收束清理');
      }

      if (spec.id === 'submission-failed') {
        this.snapshot({
          id: this.id('submission'),
          kind: 'user',
          author: '你',
          text: '请整理今天的界面走查结论。',
          time: '刚刚',
          submissionPhase: 'failed',
          submissionError: '本次请求明确未发送，原提交内容仍可重试。'
        });
      }

      this.syncRootAgentStatus();
      this.state.running = Boolean(this.state.live || this.state.pending || this.state.transitionPhase !== 'none');
      this.emit('reset');
    }

    applyAcpPreset(accountId, options = {}) {
      const account = this.findAcpAccount(accountId);
      if (!account) return;
      this.state.backendKind = 'acp';
      this.state.acpAccountId = account.id;
      this.state.acpDeferredProbe = Boolean(options.deferred);
      this.state.acpValues = clone(account.defaults || {});
      this.state.acpConfigState = account.resolveConfig(this.state.acpValues);
      this.state.acpConfigPending = null;
      this.state.frozenThread.backendKind = 'acp';
      this.state.frozenThread.acpAccountId = account.id;
      this.state.frozenThread.acpAccountName = account.name;
      this.state.frozenThread.acpBadgeText = account.badge;
      this.state.frozenThread.acpColor = account.color;
    }

    flattenSelectOptions(option) {
      return flattenSelectOptions(option);
    }

    getComposerSchema() {
      const s = this.state;
      if (s.backendKind !== 'acp') {
        const mode = this.currentMode();
        const model = this.currentModel();
        return {
          kind: 'native',
          deferred: false,
          account: null,
          modeSlot: {
            kind: 'native',
            id: 'mode',
            name: '工作模式',
            currentValue: mode.id,
            currentLabel: mode.label,
            options: app.fixtures.modes.map(m => ({ value: m.id, name: m.label, description: m.desc }))
          },
          modelSlot: {
            kind: 'native',
            id: 'model',
            name: '主智能体模型',
            currentValue: model.id,
            currentLabel: model.name,
            accountName: model.accountName
          },
          thoughtSlot: model.efforts.length
            ? {
                kind: 'native',
                id: 'effort',
                name: '思考强度',
                currentValue: s.effort,
                currentLabel: s.effort || '—',
                options: model.efforts.map(e => ({ value: e, name: e }))
              }
            : null,
          extraOptions: [],
          imageSupported: true
        };
      }

      const account = this.currentAcpAccount();
      const cfg = s.acpConfigState;
      const imageSupported = cfg?.promptCapabilities?.image !== false;

      if (s.stage === 'start' && s.acpDeferredProbe) {
        return {
          kind: 'acp',
          deferred: true,
          account,
          modeSlot: null,
          modelSlot: {
            kind: 'acp-deferred',
            id: 'model',
            name: '外部智能体',
            currentValue: account?.id || '',
            currentLabel: account?.name || 'ACP'
          },
          thoughtSlot: null,
          extraOptions: [],
          imageSupported
        };
      }

      if (Array.isArray(cfg?.configOptions)) {
        const opts = cfg.configOptions;
        const rawMode = opts.find(o => o.category === 'mode' && o.type === 'select') || null;
        const rawModel = opts.find(o => o.category === 'model' && o.type === 'select') || null;
        const rawThought = opts.find(o => o.category === 'thought_level' && o.type === 'select') || null;
        const consumed = new Set([rawMode?.id, rawModel?.id, rawThought?.id].filter(Boolean));
        const extraOptions = opts.filter(o => !consumed.has(o.id));

        const enrichSelect = opt => {
          if (!opt) return null;
          const flat = flattenSelectOptions(opt);
          const matched = flat.find(item => item.value === opt.currentValue) || flat[0];
          return {
            ...opt,
            kind: 'acp',
            flatOptions: flat,
            currentLabel: matched ? matched.name : String(opt.currentValue ?? '')
          };
        };

        return {
          kind: 'acp',
          deferred: false,
          account,
          modeSlot: enrichSelect(rawMode),
          modelSlot: enrichSelect(rawModel),
          thoughtSlot: enrichSelect(rawThought),
          extraOptions,
          imageSupported
        };
      }

      // Legacy modes fallback when configOptions is absent
      const legacyModes = cfg?.modes;
      let modeSlot = null;
      if (legacyModes && Array.isArray(legacyModes.availableModes) && legacyModes.availableModes.length) {
        const flat = legacyModes.availableModes.map(m => ({
          value: m.id,
          name: m.name,
          description: m.description || ''
        }));
        const matched = flat.find(item => item.value === legacyModes.currentModeId) || flat[0];
        modeSlot = {
          kind: 'acp-legacy',
          id: '__legacy_mode__',
          name: '会话模式',
          currentValue: legacyModes.currentModeId,
          currentLabel: matched ? matched.name : legacyModes.currentModeId,
          flatOptions: flat,
          options: flat
        };
      }

      return {
        kind: 'acp',
        deferred: false,
        account,
        modeSlot,
        modelSlot: null,
        thoughtSlot: null,
        extraOptions: [],
        imageSupported
      };
    }

    getAcpCompatibilityIssue() {
      const s = this.state;
      if (s.stage !== 'start' || s.backendKind !== 'acp' || s.targetType !== 'project') return null;
      const proj = this.currentProject();
      const acc = this.currentAcpAccount();
      if (proj?.sshAlias && acc && !acc.supportsRemote) {
        return {
          blocker: true,
          code: 'ssh-acp-unsupported',
          projectName: proj.name,
          sshAlias: proj.sshAlias,
          accountName: acc.name,
          message: `${acc.name} 暂不支持远程 SSH 项目`,
          detail: `外部智能体「${acc.name}」(ACP) 仅支持在本地目录运行，暂无法在 SSH 远端项目「${proj.name}」(${proj.sshAlias}) 启动会话。`
        };
      }
      return null;
    }

    syncRootAgentStatus() {
      const rootAgent = this.state.agents.find(a => a.isRoot);
      if (!rootAgent) return;
      const schema = this.getComposerSchema();
      if (this.state.backendKind === 'acp') {
        const accName = schema.account?.name || 'ACP';
        const subModel = schema.modelSlot?.currentLabel;
        const thought = schema.thoughtSlot?.currentLabel;
        rootAgent.routeLabel = schema.deferred
          ? `ACP · ${accName}（待握手）`
          : [accName, subModel, thought].filter(Boolean).join(' · ');
      } else {
        const model = this.currentModel();
        rootAgent.routeLabel = `${model.name}${this.state.effort ? ' · ' + this.state.effort : ''}`;
      }
      rootAgent.status = (this.state.live || this.state.pending || this.state.transitionPhase !== 'none')
        ? 'running'
        : (this.state.resumable ? 'stopped' : 'idle');
    }

    /* ======================================================================
       Authoritative Configuration Lock Matrix & Primary Action Resolution
       ====================================================================== */
    getLockState() {
      const s = this.state;
      const isStart = s.stage === 'start';
      const isSubagent = !isStart && s.activeAgentId !== 'root';
      const prepRunning = isStart && s.preparation?.status === 'running';
      const turnBusy = !isStart && (Boolean(s.live) || Boolean(s.pending) || s.transitionPhase !== 'none');
      const configPending = !isStart && s.backendKind === 'acp' && Boolean(s.acpConfigPending);
      const schema = this.getComposerSchema();
      const acpIssue = this.getAcpCompatibilityIssue();
      const isAcp = s.backendKind === 'acp';
      const botManaged = !isStart && s.frozenThread.botManaged && !isAcp;

      const projectEditable = isStart && !prepRunning;
      const workspaceEditable = isStart && s.targetType === 'project' && !prepRunning;
      const delegationEditable = isStart && !prepRunning && !isAcp;

      const modeSupported = Boolean(schema.modeSlot);
      const modelSupported = isAcp ? Boolean(schema.modelSlot) : true;
      const effortSupported = Boolean(schema.thoughtSlot);

      let modeEditable = true;
      let modeReason = '';
      if (isSubagent) {
        modeEditable = false;
        modeReason = '子智能体会话为只读视图，不支持配置工作模式。';
      } else if (prepRunning) {
        modeEditable = false;
        modeReason = '正在准备新会话环境，首轮工作模式已按提交快照锁定。';
      } else if (schema.deferred) {
        modeEditable = false;
        modeReason = '当前处于待首次连接状态，发送首条消息完成 ACP 握手后即可显示并配置服务端模式。';
      } else if (!modeSupported) {
        modeEditable = false;
        modeReason = `智能体「${schema.account?.name || '当前'}」未提供可配置模式。`;
      } else if (turnBusy) {
        modeEditable = false;
        modeReason = '会话运行或等待处理期间无法切换工作模式。请等待本轮结束，或先点击右侧停止后再切换。';
      } else if (configPending) {
        modeEditable = false;
        modeReason = `正在向「${schema.account?.name || 'ACP'}」同步上一项配置变更，确认返回前暂不叠加修改。`;
      } else if (!isStart && s.frozenThread.workflow.active && !isAcp) {
        modeEditable = false;
        modeReason = `当前「${s.frozenThread.workflow.stageLabel}」工作流仍在进行中，中途不可切换工作模式；但主智能体模型与思考强度仍可正常修改，将在下一轮生效。`;
      }

      let modelEditable = true;
      let modelReason = '';
      if (isSubagent) {
        modelEditable = false;
        modelReason = '子智能体使用创建时冻结的模型路由（只读），不支持单独改选。';
      } else if (prepRunning) {
        modelEditable = false;
        modelReason = '正在准备新会话环境，首轮模型路由已按提交快照冻结。';
      } else if (botManaged) {
        modelEditable = false;
        modelReason = '当前会话由外部机器人渠道托管，模型与思考强度由机器人配置统一决定，不支持在单会话内单独覆盖。';
      } else if (isAcp && !isStart && !modelSupported) {
        modelEditable = false;
        modelReason = `旧版智能体「${schema.account?.name || 'ACP'}」未暴露可切换的模型列表。`;
      } else if (turnBusy) {
        modelEditable = false;
        modelReason = '会话正在执行或收束清理中，暂时无法切换主模型。请停止当前执行或等待本轮完成后重试。';
      } else if (configPending) {
        modelEditable = false;
        modelReason = `正在等待外部智能体确认配置响应（set_config_option），完成后即可继续操作。`;
      }

      let effortEditable = modelEditable && effortSupported && !schema.deferred;
      let effortReason = '';
      if (schema.deferred) {
        effortEditable = false;
        effortReason = '待首次连接并握手成功后自动获取该智能体支持的思考强度。';
      } else if (!modelEditable && effortSupported) {
        effortReason = configPending
          ? '正在等待外部智能体确认配置响应（set_config_option），完成后即可继续调整。'
          : turnBusy
            ? '会话正在执行或收束清理中，暂时无法调整思考强度。待当前轮次空闲后即可修改。'
            : modelReason;
      } else if (!effortSupported) {
        const targetLabel = isAcp
          ? (schema.modelSlot?.currentLabel || schema.account?.name || '当前智能体')
          : this.currentModel().name;
        effortReason = `当前所选「${targetLabel}」未暴露思考强度配置项，该选择器自动保持置空锁定。`;
      }

      let extraEditable = Boolean(schema.extraOptions.length);
      let extraReason = '';
      if (extraEditable) {
        if (isSubagent) {
          extraEditable = false;
          extraReason = '子智能体会话为只读视图。';
        } else if (prepRunning) {
          extraEditable = false;
          extraReason = '正在准备新会话环境，扩展配置已锁定。';
        } else if (turnBusy) {
          extraEditable = false;
          extraReason = '会话执行期间暂不可调整外部智能体扩展配置。';
        } else if (configPending) {
          extraEditable = false;
          extraReason = '正在等待外部智能体确认配置变更。';
        }
      }

      return {
        isStart,
        isSubagent,
        isAcp,
        prepRunning,
        turnBusy,
        configPending,
        schema,
        acpIssue,
        projectEditable,
        workspaceEditable,
        delegationEditable,
        modeSupported,
        modeEditable,
        modeReason,
        modelSupported,
        modelEditable,
        modelReason,
        effortSupported,
        effortEditable,
        effortReason,
        extraEditable,
        extraReason
      };
    }

    getPrimaryAction() {
      const s = this.state;
      const hasContent = Boolean(s.draft.trim() || s.attachments.length);

      if (s.stage === 'start') {
        const prepRunning = s.preparation?.status === 'running';
        const acpIssue = this.getAcpCompatibilityIssue();
        return {
          kind: 'send',
          enabled: hasContent && !prepRunning && !acpIssue,
          label: prepRunning ? '正在准备会话' : (acpIssue ? '当前远端环境不支持此智能体' : '发送'),
          statusText: prepRunning ? '正在准备' : ''
        };
      }

      if (s.activeAgentId !== 'root') {
        return { kind: 'readOnly', enabled: false, label: '只读', statusText: '' };
      }

      if (s.transitionPhase === 'stopping') {
        return { kind: 'stopping', enabled: false, label: '正在停止', statusText: '正在停止' };
      }

      if (s.transitionPhase === 'continuing') {
        return { kind: 'continuing', enabled: false, label: '正在继续', statusText: '正在继续' };
      }

      if (s.backendKind === 'acp' && s.acpConfigPending) {
        return { kind: 'send', enabled: false, label: '正在同步配置', statusText: '同步配置中' };
      }

      const routeBlocked = !s.frozenThread.routeAvailable;
      if (routeBlocked) {
        if (s.live) return { kind: 'stop', enabled: true, label: '停止', statusText: '' };
        if (!hasContent && s.resumable) return { kind: 'continue', enabled: false, label: '继续', statusText: '' };
        return { kind: 'send', enabled: false, label: '发送', statusText: '' };
      }

      if (s.live) {
        return hasContent
          ? { kind: 'sendAndContinue', enabled: true, label: '发送并继续', statusText: '' }
          : { kind: 'stop', enabled: true, label: '停止', statusText: '' };
      }

      if (s.resumable) {
        return hasContent
          ? { kind: 'sendAndContinue', enabled: true, label: '发送并继续', statusText: '' }
          : { kind: 'continue', enabled: true, label: '继续', statusText: '' };
      }

      return { kind: 'send', enabled: hasContent, label: '发送', statusText: '' };
    }

    explainLock(message, tone = 'info') {
      this.state.lockNotice = message;
      this.state.lockNoticeTone = tone;
      this.emit('notice');
    }

    dismissLockNotice() {
      if (!this.state.lockNotice) return;
      this.state.lockNotice = null;
      this.emit('notice');
    }

    /* ======================================================================
       Sidebar Navigation & Start Stage Actions
       ====================================================================== */
    selectStandaloneStart() {
      this.haltTimers();
      const fromSession = this.state.stage === 'session';
      this.state.stage = 'start';
      this.state.targetType = 'standalone';
      this.state.activeSidebarThreadId = null;
      this.state.workspaceMode = 'local';
      this.state.preparation = null;
      this.state.lockNotice = null;
      this.state.acpConfigPending = null;
      if (fromSession) {
        this.state.live = null;
        this.state.pending = null;
        this.state.resumable = false;
        this.state.continuationReason = null;
        this.state.transitionPhase = 'none';
        this.state.running = false;
      }
      this.note('新会话目标切换为「无项目」· 工作区固定为 Documents/anywork，也可在列表切换项目');
      this.emit('reset');
    }

    selectProjectStart(projectId) {
      this.haltTimers();
      const fromSession = this.state.stage === 'session';
      this.state.stage = 'start';
      this.state.targetType = 'project';
      this.state.projectId = projectId;
      this.state.activeSidebarThreadId = null;
      this.state.preparation = null;
      this.state.lockNotice = null;
      this.state.acpConfigPending = null;
      if (fromSession) {
        this.state.live = null;
        this.state.pending = null;
        this.state.resumable = false;
        this.state.continuationReason = null;
        this.state.transitionPhase = 'none';
        this.state.running = false;
      }
      const proj = this.currentProject();
      const acpIssue = this.getAcpCompatibilityIssue();
      if (acpIssue) {
        this.note(`项目已切换为「${proj.name}」· 当前选中的外部智能体不支持 SSH 远端工作区`);
      } else {
        this.note(`新会话目标切换为项目「${proj.name}」· 可在外层选择本地目录或新建工作树`);
      }
      this.emit('reset');
    }

    openSidebarThread(threadId) {
      for (const proj of app.fixtures.projects) {
        const hit = proj.threads.find(t => t.id === threadId);
        if (hit) {
          this.load(hit.scenario);
          this.state.projectId = proj.id;
          this.state.activeSidebarThreadId = hit.id;
          this.state.frozenThread.id = hit.id;
          this.state.frozenThread.title = hit.title;
          this.state.frozenThread.projectName = proj.name;
          this.state.frozenThread.sshAlias = proj.sshAlias;
          this.state.frozenThread.workspaceMode = hit.worktree ? 'worktree' : 'local';
          this.state.frozenThread.branch = hit.branch;
          this.state.frozenThread.workspacePath = hit.workspacePath;
          this.state.frozenThread.delegationSummary = hit.delegationSummary;
          this.emit('reset');
          return;
        }
      }
      const standaloneHit = app.fixtures.standaloneThreads.find(t => t.id === threadId);
      if (standaloneHit) {
        this.load(standaloneHit.scenario);
        this.state.targetType = 'standalone';
        this.state.activeSidebarThreadId = standaloneHit.id;
        this.state.frozenThread.id = standaloneHit.id;
        this.state.frozenThread.title = standaloneHit.title;
        this.state.frozenThread.projectName = '非项目会话';
        this.state.frozenThread.sshAlias = null;
        this.state.frozenThread.workspaceMode = 'local';
        this.state.frozenThread.branch = null;
        this.state.frozenThread.workspacePath = standaloneHit.workspacePath;
        this.state.frozenThread.delegationSummary = standaloneHit.delegationSummary;
        this.emit('reset');
      }
    }

    switchAgent(agentId) {
      if (!this.state.agents.some(a => a.id === agentId)) return;
      this.state.activeAgentId = agentId;
      this.state.lockNotice = null;
      this.note(agentId === 'root'
        ? '已切回主智能体会话 · 恢复主会话输入框'
        : `已切入子智能体 ${agentId} · 输入区切换为只读停靠面板`);
      this.emit('agent');
    }

    stopSubagent(agentId) {
      const target = this.state.agents.find(a => a.id === agentId && !a.isRoot);
      if (!target || target.status !== 'running') return;
      target.status = 'stopping';
      this.note(`已向子智能体 ${target.role} 发送停止请求…`);
      this.emit('agent');
      setTimeout(() => {
        if (this.disposed) return;
        target.status = 'waiting';
        this.note(`子智能体 ${target.role} 已停止 · 等待主智能体后续调度`);
        this.emit('agent');
      }, 500);
    }

    setWorkspaceMode(mode) {
      const locks = this.getLockState();
      if (!locks.workspaceEditable) return;
      this.state.workspaceMode = mode;
      if (mode === 'local' && this.state.preparation?.status === 'failed') {
        this.state.preparation = null;
      }
      this.note(mode === 'worktree'
        ? '已切换为「新建工作树」· 首条消息提交时将从 HEAD 检出并冻结'
        : '已切换为「本地目录」· 直接在项目目录协作');
      this.emit('config');
    }

    setDelegationMode(val) {
      if (!this.getLockState().delegationEditable) return;
      this.state.delegationModeOverride = val === 'default' ? null : val;
      this.note(`子智能体分发更新为「${this.delegationSummaryText()}」`);
      this.emit('config');
    }

    setDelegationPref(val) {
      if (!this.getLockState().delegationEditable) return;
      this.state.delegationPrefOverride = val === 'default' ? null : val;
      this.note(`自动选模偏好更新为「${this.delegationSummaryText()}」`);
      this.emit('config');
    }

    selectNativeModel(modelId) {
      const locks = this.getLockState();
      if (!locks.modelEditable) {
        this.explainLock(locks.modelReason);
        return;
      }
      if (this.state.stage !== 'start' && this.state.backendKind === 'acp') {
        this.explainLock('会话创建后不能在内置模型与外部 ACP 智能体之间跨后端切换');
        return;
      }
      this.state.backendKind = 'native';
      this.state.acpAccountId = null;
      this.state.acpDeferredProbe = false;
      this.state.acpConfigState = null;
      this.state.acpConfigPending = null;
      const spec = this.findModel(modelId);
      this.state.modelId = spec.id;
      if (!spec.efforts.length) {
        this.state.effort = null;
      } else if (!spec.efforts.includes(this.state.effort)) {
        this.state.effort = spec.defaultEffort || spec.efforts[0];
      }
      this.modeRoutes[this.state.modeId] = {
        modelId: this.state.modelId,
        effort: this.state.effort
      };
      if (this.state.stage === 'session' && !this.state.frozenThread.routeAvailable) {
        this.state.frozenThread.routeAvailable = true;
        this.state.frozenThread.routeUnavailableReason = '';
        this.note(`已改选可用模型「${spec.name}」· 路由不可用阻塞已解除`);
      } else {
        this.note(`主智能体切换为内置模型「${spec.name}」${this.state.effort ? ' · ' + this.state.effort : '（无思考强度参数）'}`);
      }
      this.state.lockNotice = null;
      this.syncRootAgentStatus();
      this.emit('config');
    }

    selectAcpAccount(accountId, options = {}) {
      if (this.state.stage !== 'start') {
        this.explainLock('外部 ACP 智能体只能在新建会话时选定；会话创建后仅支持切换当前智能体自身声明的子模型与动态配置');
        return;
      }
      const locks = this.getLockState();
      if (locks.prepRunning) {
        this.explainLock('会话正在准备与提交首条请求，暂时锁定配置切换');
        return;
      }
      const acc = this.findAcpAccount(accountId);
      if (!acc) return;
      this.applyAcpPreset(acc.id, {
        deferred: Boolean(options.deferred)
      });
      this.state.lockNotice = null;
      this.syncRootAgentStatus();
      const acpIssue = this.getAcpCompatibilityIssue();
      if (acpIssue) {
        this.note(`已选择外部智能体「${acc.name}」· 但当前选中的远端 SSH 项目暂不支持 ACP`);
      } else if (this.state.acpDeferredProbe) {
        this.note(`已选定外部智能体「${acc.name}」· 该智能体将在发出首条消息时加载子模型与配置项`);
      } else {
        const schema = this.getComposerSchema();
        this.note(`主智能体切换为外部 ACP「${acc.name}」${schema.modelSlot ? ' · 默认模型 ' + schema.modelSlot.currentLabel : ''}`);
      }
      this.emit('config');
    }

    enableAcpStartProbe() {
      if (this.state.stage !== 'start' || this.state.backendKind !== 'acp') return;
      const acc = this.currentAcpAccount();
      if (!acc) return;
      this.applyAcpPreset(acc.id, { deferred: false });
      this.state.lockNotice = null;
      this.syncRootAgentStatus();
      this.note(`已模拟启动前加载「${acc.name}」的 session/new 配置快照 · 现在可直接预选子模型与参数`);
      this.emit('config');
    }

    switchToLocalProjectForAcp() {
      if (this.state.stage !== 'start') return;
      const localProj = app.fixtures.projects.find(p => !p.sshAlias);
      if (localProj) {
        this.selectProjectStart(localProj.id);
      } else {
        this.selectStandaloneStart();
      }
    }

    resolveLegacyModeLabel(modeId, cfgState) {
      const hit = cfgState?.modes?.availableModes?.find(m => m.id === modeId);
      return hit ? hit.name : modeId;
    }

    findOptionLabel(option, value) {
      if (!option) return String(value ?? '');
      if (option.type === 'boolean') return value ? '已开启' : '已关闭';
      const flat = flattenSelectOptions(option);
      const hit = flat.find(item => item.value === value);
      return hit ? hit.name : String(value ?? '');
    }

    setAcpConfigValue(configId, value) {
      if (this.state.backendKind !== 'acp') return;
      const acc = this.currentAcpAccount();
      const schema = this.getComposerSchema();
      const locks = this.getLockState();
      if (locks.prepRunning) {
        this.explainLock('会话正在准备与提交首条请求，暂时锁定配置变更');
        return;
      }
      if (locks.turnBusy) {
        this.explainLock('外部智能体执行本轮期间只读，请等待本轮结束或手动停止后再调整配置');
        return;
      }
      if (locks.configPending) {
        this.explainLock('正在等待外部智能体返回上一项 session/set_config_option 确认…');
        return;
      }
      const isMode = schema.modeSlot?.id === configId;
      const isModel = schema.modelSlot?.id === configId;
      const isThought = schema.thoughtSlot?.id === configId;
      if (isMode && !locks.modeEditable) {
        this.explainLock(locks.modeReason);
        return;
      }
      if (isModel && !locks.modelEditable) {
        this.explainLock(locks.modelReason);
        return;
      }
      if (isThought && !locks.effortEditable) {
        this.explainLock(locks.effortReason);
        return;
      }
      if (!isMode && !isModel && !isThought && !locks.extraEditable) {
        this.explainLock(locks.extraReason);
        return;
      }

      const rawList = this.state.acpConfigState?.configOptions || [];
      const targetOption = rawList.find(opt => opt.id === configId) || null;
      const valueLabel = isMode && this.state.acpConfigState?.modes && !targetOption
        ? this.resolveLegacyModeLabel(value, this.state.acpConfigState)
        : this.findOptionLabel(targetOption, value);
      const optName = targetOption ? targetOption.name : (isMode ? '模式' : configId);

      const commitChange = () => {
        if (!acc) return;
        const hadThoughtBefore = Boolean(this.getComposerSchema().thoughtSlot);
        if (configId === '__legacy_mode__' && this.state.acpConfigState?.modes) {
          this.state.acpValues.legacyMode = value;
          this.state.acpConfigState.modes.currentModeId = value;
          this.note(`已通过 session/set_mode 将「${acc.name}」模式切换为「${valueLabel}」`);
        } else {
          this.state.acpValues[configId] = value;
          this.state.acpConfigState = acc.resolveConfig(this.state.acpValues);
          const nextSchema = this.getComposerSchema();
          const hasThoughtAfter = Boolean(nextSchema.thoughtSlot);
          if (isModel && hadThoughtBefore && !hasThoughtAfter) {
            this.note(`外部模型已切换为「${valueLabel}」· 该模型不返回 thought_level，思考强度槽位已自动隐去`);
          } else if (isModel && !hadThoughtBefore && hasThoughtAfter) {
            this.note(`外部模型已切换为「${valueLabel}」· 智能体同步下发思考强度 ${nextSchema.thoughtSlot.currentLabel}`);
          } else {
            this.note(`外部智能体「${acc.name}」${optName}已更新为「${valueLabel}」`);
          }
        }
        this.state.lockNotice = null;
        this.syncRootAgentStatus();
      };

      if (this.state.stage === 'start') {
        commitChange();
        this.emit('config');
        return;
      }

      this.state.acpConfigPending = {
        configId,
        targetValue: value,
        label: `${optName} → ${valueLabel}`
      };
      this.state.lockNotice = null;
      this.note(`正在等待「${acc?.name || 'ACP'}」确认变更：${optName} → ${valueLabel}…`);
      this.emit('config');
      clearTimeout(this.acpPendingTimer);
      this.acpPendingTimer = setTimeout(() => {
        if (this.disposed) return;
        this.state.acpConfigPending = null;
        commitChange();
        this.emit('config');
      }, 280);
    }

    setWorkMode(modeId) {
      const locks = this.getLockState();
      if (!locks.modeEditable) {
        this.explainLock(locks.modeReason);
        return;
      }
      if (this.state.backendKind === 'acp') {
        if (locks.schema.modeSlot?.id) {
          this.setAcpConfigValue(locks.schema.modeSlot.id, modeId);
        }
        return;
      }
      this.state.modeId = modeId;
      const saved = this.modeRoutes[modeId];
      if (saved) {
        this.state.modelId = saved.modelId;
        this.state.effort = saved.effort;
      }
      this.state.lockNotice = null;
      this.syncRootAgentStatus();
      const label = this.currentMode().label;
      this.note(`工作模式切换为「${label}」· 同步加载该模式默认路由`);
      this.emit('config');
    }

    setModel(modelId) {
      if (this.state.backendKind === 'acp') {
        const schema = this.getComposerSchema();
        if (schema.modelSlot?.kind === 'acp' && schema.modelSlot.id) {
          this.setAcpConfigValue(schema.modelSlot.id, modelId);
        }
        return;
      }
      this.selectNativeModel(modelId);
    }

    setEffort(effort) {
      if (this.state.backendKind === 'acp') {
        const schema = this.getComposerSchema();
        if (schema.thoughtSlot?.id) {
          this.setAcpConfigValue(schema.thoughtSlot.id, effort);
        }
        return;
      }
      const locks = this.getLockState();
      if (!locks.effortEditable) {
        this.explainLock(locks.effortReason);
        return;
      }
      this.state.effort = effort;
      this.modeRoutes[this.state.modeId] = {
        modelId: this.state.modelId,
        effort: this.state.effort
      };
      this.state.lockNotice = null;
      this.syncRootAgentStatus();
      this.note(`思考强度调整为 ${effort}`);
      this.emit('config');
    }

    /* ======================================================================
       First-Turn Start Submission -> Preparation -> Runtime Session Handoff
       ====================================================================== */
    submitStartPrompt() {
      const hasContent = Boolean(this.state.draft.trim() || this.state.attachments.length);
      if (!hasContent || this.state.preparation?.status === 'running') return;

      const acpIssue = this.getAcpCompatibilityIssue();
      if (acpIssue) {
        this.explainLock(acpIssue.message, 'warning');
        return;
      }

      const project = this.currentProject();
      const promptText = this.state.draft.trim() || '（仅附件草稿）';
      const frozenWs = this.state.targetType === 'standalone' ? 'local' : this.state.workspaceMode;
      const isAcp = this.state.backendKind === 'acp';
      const acpAccount = isAcp ? this.currentAcpAccount() : null;

      if (project && !project.isGit && frozenWs === 'worktree') {
        this.state.preparation = {
          status: 'failed',
          stepIndex: 1,
          subStage: '仓库解析未通过',
          error: `项目「${project.name}」不是有效的 Git 仓库（缺少 .git 或 HEAD 提交），无法创建独立工作树。你的输入与附件草稿已原位保留。`,
          frozenWorkspaceMode: 'worktree',
          workspacePath: project.path,
          branch: null,
          expanded: false
        };
        this.note('工作树准备失败 · 原位保留输入与附件草稿');
        this.emit('config');
        return;
      }

      const frozenAttachments = clone(this.state.attachments);
      const frozenDelegation = isAcp
        ? `外部 ACP · ${acpAccount?.name || 'Agent'}`
        : this.delegationSummaryText();
      const wsPath = project
        ? (frozenWs === 'worktree'
          ? (project.sshAlias
            ? `${project.path}/.anywork/worktrees/thr_01jd2m/session`
            : `${project.path}\\.anywork\\worktrees\\thr_01jd2m\\session`)
          : project.path)
        : 'C:\\Users\\dev\\Documents\\anywork';
      const branch = frozenWs === 'worktree' ? 'anywork/thr-01jd2m' : null;

      this.state.draft = '';
      this.state.attachments = [];
      this.state.lockNotice = null;
      this.state.preparation = {
        status: 'running',
        stepIndex: 0,
        subStage: isAcp ? `正在校验工作区并准备连接 ${acpAccount?.name || 'ACP'}…` : '正在检查项目与会话配置…',
        frozenWorkspaceMode: frozenWs,
        workspacePath: wsPath,
        branch,
        expanded: frozenWs === 'worktree'
      };
      this.note(isAcp ? `已冻结首条草稿，准备启动外部智能体 ${acpAccount?.name || 'ACP'}` : '已冻结首条草稿并开始准备会话环境');
      this.emit('config');

      const acpLabel = acpAccount?.name || '外部 ACP';
      const frames = frozenWs === 'worktree'
        ? [
            { step: 1, sub: '正在检查 Git 仓库与基线提交…' },
            { step: 1, sub: '正在创建工作树并检出文件…' },
            { step: 2, sub: isAcp ? `正在建立 ${acpLabel} session/new 并拉取配置项…` : '正在初始化会话环境…' },
            { step: 3, sub: '正在提交你的第一条请求…' },
            { done: true }
          ]
        : [
            { step: 1, sub: '正在准备会话工作区…' },
            { step: 2, sub: isAcp ? `正在建立 ${acpLabel} session/new 并拉取配置项…` : '正在初始化会话环境…' },
            { step: 3, sub: '正在提交你的第一条请求…' },
            { done: true }
          ];

      let cursor = 0;
      clearInterval(this.prepTimer);
      this.prepTimer = setInterval(() => {
        const frame = frames[cursor++];
        if (!frame || !this.state.preparation) {
          clearInterval(this.prepTimer);
          this.prepTimer = null;
          return;
        }
        if (frame.done) {
          clearInterval(this.prepTimer);
          this.prepTimer = null;
          // Transition seamlessly into the Runtime Session Stage!
          this.state.stage = 'session';
          this.state.preparation = null;
          this.state.activeAgentId = 'root';
          if (isAcp && acpAccount && (this.state.acpDeferredProbe || !this.state.acpConfigState)) {
            this.state.acpDeferredProbe = false;
            this.state.acpConfigState = acpAccount.resolveConfig(this.state.acpValues || {});
          }
          const resolvedSchema = this.getComposerSchema();
          this.state.frozenThread = {
            id: 'thr-created',
            title: promptText.slice(0, 28) + (promptText.length > 28 ? '…' : ''),
            projectName: project ? project.name : '非项目会话',
            sshAlias: project?.sshAlias || null,
            workspaceMode: frozenWs,
            workspacePath: wsPath,
            branch,
            delegationSummary: frozenDelegation,
            workflow: {
              active: !isAcp && this.state.modeId === 'mode.task',
              stageLabel: !isAcp && this.state.modeId === 'mode.task' ? '任务 · 规划' : ''
            },
            botManaged: false,
            backendKind: isAcp ? 'acp' : 'native',
            acpAccountId: acpAccount?.id || null,
            acpAccountName: acpAccount?.name || '',
            acpBadgeText: acpAccount?.badge || '',
            acpColor: acpAccount?.color || '#55798C',
            routeAvailable: true,
            routeUnavailableReason: ''
          };
          this.state.history = [];
          this.snapshot({
            id: this.id('user'),
            kind: 'user',
            author: '你',
            text: promptText,
            attachments: frozenAttachments,
            time: '刚刚'
          });
          this.note(isAcp
            ? `${acpLabel} 会话已建立 · 已接收实时配置槽位（${resolvedSchema.modelSlot ? resolvedSchema.modelSlot.currentLabel : '无独立模型项'}），开始首轮执行`
            : '会话环境就绪 · 外层创建栏已退役并锁定在顶栏，开始首轮执行');
          this.emit('reset');
          this.beginTask();
          return;
        }
        this.state.preparation.stepIndex = frame.step;
        this.state.preparation.subStage = frame.sub;
        this.emit('prep');
      }, 560);
    }

    /* ======================================================================
       Runtime Session Timeline, Live Status Bar & Interruption Lifecycle
       ====================================================================== */
    startCompression() {
      this.state.live = { id: this.id('compression'), kind: 'compacting', elapsed: 0 };
      this.state.queue = [{ type: 'tick' }, { type: 'tick' }, { type: 'finishCompression' }, { type: 'finishTurn' }];
      this.state.cursor = 0;
      this.state.running = true;
      this.syncRootAgentStatus();
      this.note('开始压缩 · 状态栏单行显示，运行期选择器临时锁定');
    }

    compact() {
      if (this.state.stage !== 'session' || this.state.activeAgentId !== 'root') return;
      if (this.state.live || this.state.pending || this.state.transitionPhase !== 'none' || !this.state.history.length) return;
      this.state.resumable = false;
      this.state.continuationReason = null;
      this.state.retryCompression = false;
      this.startCompression();
      this.emit('live');
      this.play();
    }

    seal(status = 'completed', error = '') {
      const live = this.state.live;
      if (!live) return null;
      if (live.kind === 'workGroup') {
        if (live.members.length) {
          this.snapshot({ id: live.id, kind: 'workGroup', status, elapsed: live.elapsed, members: live.members });
        }
      } else if (live.kind === 'textOutput') {
        if (live.visible) this.snapshot({
          id: live.id, kind: 'text', status, error, text: live.text,
          visibility: live.text.length ? 'content' : 'finalEmptyAfterContent'
        });
      } else if (live.kind === 'compacting' && status === 'completed') {
        this.snapshot({ id: live.id, kind: 'compression', status: 'completed' });
        this.state.context = 18;
      }
      this.state.live = null;
      return live;
    }

    closeGroupFor(reason) {
      const live = this.state.live;
      if (live?.kind === 'workGroup') {
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
          if (live?.kind === 'workGroup') {
            live.resting = false;
            this.state.running = true;
            break;
          }
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
          const grp = this.state.live;
          grp.resting = false;
          grp.members.push(clone(event.member));
          this.state.running = true;
          this.note(grp.members.length === 1 ? '新工作组 · 首个成员插入状态栏' : `插入成员 · 当前工作组共 ${grp.members.length} 步`);
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
              } else if (member.kind === 'readImage') {
                member.title = `查看了 ${(member.images || []).length} 张图片`;
              }
              member.targets?.forEach(target => {
                target.status = 'completed';
                target.report = target.report.replace('正在核对', '已核对');
              });
              this.note(runningCount(live) ? '成员完成 · 切换为语义图标留在当前工作组' : '组内成员全部完成 · 等待下一条信息决定去向');
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
          this.state.pendingText = { id: event.id, kind: 'textOutput', text: '', elapsed: 0, visible: false };
          this.state.running = true;
          this.note('真实正文开始 · 尚无公开内容，不建立边界');
          break;
        }
        case 'appendText':
          if (this.state.pendingText && event.text.length) {
            this.closeGroupFor('first visible content');
            this.state.live = this.state.pendingText;
            this.state.pendingText = null;
            this.state.live.visible = true;
            this.note('首次内容可读 · 冻结前工作组');
          }
          if (this.state.live?.kind === 'textOutput') this.state.live.text += event.text;
          break;
        case 'finishText':
          if (this.state.pendingText) {
            this.state.pendingText = null;
            this.note('始终空正文结束 · 原工作尾组继续保留');
          } else if (live?.kind === 'textOutput') {
            if (typeof event.finalText === 'string') live.text = event.finalText;
            this.seal();
            this.note('正文结束 · 仅结束自己的块，不产生第二次工作边界');
          }
          break;
        case 'finishCompression':
          if (live?.kind === 'compacting' && (!event.id || event.id === live.id)) {
            this.seal();
            this.note('压缩成功 · 时间线追加完成记录，选择器恢复可配');
          }
          break;
        case 'finishTurn': {
          if (live?.kind === 'workGroup') {
            live.resting = true;
            this.note('轮次结束 · 同一工作尾组静态保留，可继续追加');
          } else if (live?.kind === 'waiting') {
            this.state.live = null;
            this.note('轮次结束 · 状态栏收起，模型选择器已解锁');
          } else if (!live) {
            this.note('轮次结束 · 状态栏收起，模型选择器已解锁');
          }
          if (!this.state.live || this.state.live.resting) {
            this.state.running = false;
            this.state.resumable = false;
            this.state.continuationReason = null;
            this.state.retryCompression = false;
            this.state.lockNotice = null;
            this.state.agents.forEach(a => { if (!a.isRoot && a.status === 'running') a.status = 'completed'; });
            this.haltTimers();
          }
          break;
        }
        default: throw new Error('Unknown demo event: ' + event.type);
      }
      this.syncRootAgentStatus();
    }

    advance() {
      const event = this.state.queue[this.state.cursor];
      if (!event) return false;
      const live = this.state.live;
      if (live && this.state.running) {
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
      if (this.disposed || this.state.stage !== 'session' || this.state.pending || this.state.transitionPhase !== 'none') return;
      if (!this.advance()) { this.haltTimers(); this.emit('playback'); return; }
      if (this.state.cursor >= this.state.queue.length) this.haltTimers();
      this.emit('step');
    }

    play() {
      if (this.disposed || this.state.stage !== 'session' || this.state.pending || this.state.transitionPhase !== 'none' || this.state.cursor >= this.state.queue.length) return;
      this.haltTimers();
      this.state.playing = true;
      this.timer = setInterval(() => this.step(), 860);
      this.emit('playback');
    }

    pause() { this.haltTimers(); this.emit('playback'); }

    finishInterrupted(status, message) {
      const pending = this.state.pending;
      const ended = this.seal(status, message);
      if (pending) {
        this.snapshot({
          id: pending.id,
          kind: 'receipt',
          title: status === 'failed' ? '交互未完成' : '交互已取消',
          subtitle: pending.title,
          content: status === 'failed' ? message : '本轮已停止，没有提交决定。'
        });
      }
      this.recordOutcome(ended, status, message);
      this.state.pending = null;
      this.state.queue = [];
      this.state.cursor = 0;
      this.state.transitionPhase = 'none';
      this.state.running = false;
      this.state.lockNotice = null;
      this.syncRootAgentStatus();
    }

    completeStoppingCleanup() {
      if (this.state.transitionPhase !== 'stopping') return;
      clearTimeout(this.transitionTimer);
      this.transitionTimer = null;
      this.finishInterrupted('stopped', '');
      this.state.resumable = true;
      this.state.continuationReason = '已被用户停止';
      this.state.retryCompression = false;
      this.syncRootAgentStatus();
      this.note('停止收束完成 · 工作组移入时间线，模型选择器已解锁，可点击「▶ 继续」');
      this.emit('stop');
    }

    stop(options = {}) {
      if (!this.state.live && !this.state.pending && this.state.transitionPhase !== 'stopping') return;
      this.haltTimers();
      if (options.immediate) {
        this.finishInterrupted('stopped', '');
        this.state.resumable = true;
        this.state.continuationReason = '已被用户停止';
        this.state.retryCompression = false;
        this.syncRootAgentStatus();
        this.note('已停止 · 当前内容结束并移入时间线，模型已解锁，主按钮切换为「▶ 继续」');
        if (!options.silentEmit) this.emit('stop');
        return;
      }
      // Show brief, authentic `正在停止` cleanup phase before settling into `stopped`
      this.state.transitionPhase = 'stopping';
      this.syncRootAgentStatus();
      this.note('停止命令已受理 · 正在收束工具进程与在途流…');
      this.emit('stop');
      this.transitionTimer = setTimeout(() => {
        if (!this.disposed) this.completeStoppingCleanup();
      }, 420);
    }

    fail(options = {}) {
      const live = this.state.live;
      if (!live && !this.state.pending) return;
      this.haltTimers();
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
      this.state.continuationReason = compacting ? null : '上次执行因错误中断，可切换模型或点击「▶ 继续」恢复';
      this.state.retryCompression = compacting;
      this.syncRootAgentStatus();
      this.note('执行失败 · 当前内容结束并移入时间线，附独立失败记录');
      if (!options.silentEmit) this.emit('failure');
    }

    beginTask() {
      this.state.resumable = false;
      this.state.continuationReason = null;
      this.state.retryCompression = false;
      this.state.transitionPhase = 'none';
      this.state.lockNotice = null;
      this.state.queue = app.fixtures.story(this.id('group'));
      this.state.cursor = 0;
      this.step();
      this.play();
    }

    resume() {
      if (this.state.live || !this.state.resumable || !this.state.frozenThread.routeAvailable) return;
      this.state.transitionPhase = 'continuing';
      this.syncRootAgentStatus();
      this.note('继续请求已受理 · 正在恢复中断的工作…');
      this.emit('continue');
      this.transitionTimer = setTimeout(() => {
        if (!this.disposed) this.beginTask();
      }, 320);
    }

    setDraft(value) {
      this.state.draft = value;
      this.emit('draft');
    }

    attach(files, options = {}) {
      const fromClipboard = options.source === 'clipboard';
      const schema = this.getComposerSchema();
      let addedCount = 0;
      let rejectedImage = false;
      for (const file of files) {
        const isImage = Boolean(file.type?.startsWith('image/') || /\.(png|jpe?g|webp|gif|svg)$/i.test(file.name || ''));
        if (isImage && !schema.imageSupported) {
          rejectedImage = true;
          continue;
        }
        const url = URL.createObjectURL(file);
        this.urls.add(url);
        const kb = file.size ? (file.size >= 1048576 ? (file.size / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(file.size / 1024)) + ' KB') : '';
        const fallbackName = fromClipboard
          ? `clipboard-image-${(this.pasteSeq = (this.pasteSeq || 0) + 1)}.png`
          : 'attachment';
        const displayName = (!file.name || (fromClipboard && file.name === 'image.png')) ? fallbackName : file.name;
        const entry = {
          id: this.id('attachment'),
          name: displayName,
          kind: isImage ? 'image' : 'file',
          sourceLabel: fromClipboard ? '剪贴板粘贴 · PNG' : (isImage ? '本地图片' : '本地文件'),
          sizeLabel: kb,
          dimensions: '',
          url,
          size: file.size
        };
        this.state.attachments.push(entry);
        addedCount += 1;
        if (isImage) {
          const probe = new Image();
          probe.onload = () => {
            if (this.disposed) return;
            entry.dimensions = `${probe.naturalWidth} × ${probe.naturalHeight}`;
            this.emit('draft');
          };
          probe.src = url;
        }
      }
      if (rejectedImage && addedCount === 0) {
        this.explainLock(`${schema.account?.name || '当前智能体'} 不支持图片输入`, 'warning');
        this.note(`图片附件已拦截 · 「${schema.account?.name || 'ACP'}」的 promptCapabilities.image = false`);
        return false;
      }
      if (rejectedImage && addedCount > 0) {
        this.explainLock(`已添加文件；${schema.account?.name || '当前智能体'} 不支持图片输入`, 'warning');
        this.note(`图片附件已过滤 · 「${schema.account?.name || 'ACP'}」的 promptCapabilities.image = false`);
      } else if (addedCount > 0) {
        this.note(fromClipboard ? '已从剪贴板粘贴图片缩略图（点击缩略图可弹层查看大图）' : '已添加本地附件草稿');
      }
      this.emit('draft');
      return addedCount > 0;
    }

    addLinkAttachment(rawUrl) {
      const trimmed = String(rawUrl || '').trim();
      if (!trimmed) return;
      const shortName = trimmed.split('/').filter(Boolean).pop() || trimmed;
      this.state.attachments.push({
        id: this.id('link'),
        name: shortName,
        kind: 'link',
        url: trimmed
      });
      this.emit('draft');
    }

    addPastedImage() {
      const schema = this.getComposerSchema();
      if (!schema.imageSupported) {
        this.explainLock(`${schema.account?.name || '当前智能体'} 不支持图片输入`, 'warning');
        this.note(`已忽略剪贴板图片 · 「${schema.account?.name || 'ACP'}」声明 promptCapabilities.image = false`);
        return false;
      }
      const samples = app.fixtures.sampleScreenshots || [];
      const index = (this.pasteSampleCursor = ((this.pasteSampleCursor || 0) + 1)) - 1;
      const sample = samples[index % Math.max(1, samples.length)] || {
        name: 'clipboard-screenshot.png',
        kind: 'image',
        sourceLabel: '剪贴板粘贴 · PNG',
        dimensions: '1280 × 800',
        sizeLabel: '184 KB',
        url: ''
      };
      const suffix = index >= samples.length ? `-${index + 1}` : '';
      const baseName = sample.name.replace(/\.png$/i, '');
      this.state.attachments.push({
        ...sample,
        id: this.id('paste'),
        name: `${baseName}${suffix}.png`
      });
      this.note('已粘贴图片草稿 · 以缩略图排布，点击可弹层查看高清大图');
      this.emit('draft');
      return true;
    }

    removeAttachment(id) {
      const item = this.state.attachments.find(attachment => attachment.id === id);
      if (item?.url && this.urls.has(item.url)) {
        URL.revokeObjectURL(item.url);
        this.urls.delete(item.url);
      }
      this.state.attachments = this.state.attachments.filter(attachment => attachment.id !== id);
      this.emit('draft');
    }

    submit() {
      if (this.state.stage === 'start') {
        this.submitStartPrompt();
        return;
      }
      if (this.state.activeAgentId !== 'root') return;
      if (this.state.pending || this.state.transitionPhase !== 'none') return;
      if (!this.state.frozenThread.routeAvailable) return;
      if (!this.state.draft.trim() && !this.state.attachments.length) return;

      const text = this.state.draft;
      const attachments = clone(this.state.attachments);
      const wasRunning = this.state.running;
      if (this.state.live?.kind === 'workGroup') {
        this.closeGroupFor('accepted input');
      } else if (wasRunning) {
        this.stop({ immediate: true, silentEmit: true });
      }
      this.snapshot({
        id: this.id('user'),
        kind: 'user',
        author: '你',
        text: text || '（附加文件）',
        attachments,
        time: '刚刚'
      });
      this.state.draft = '';
      this.state.attachments = [];
      this.note(wasRunning ? '已发送新指示并接续执行 · 原运行组已先封存进时间线' : '已提交新消息 · 开启新一轮执行');
      this.beginTask();
    }

    retrySubmission(inputId) {
      const index = this.state.history.findIndex(item => item.id === inputId);
      const failed = this.state.history[index];
      if (failed?.submissionPhase !== 'failed') return;
      // This concept simulates a confirmed retry; it never reads the new draft.
      this.state.history[index] = {
        ...failed,
        id: this.id('user'),
        submissionPhase: 'accepted',
        submissionError: null
      };
      this.note('模拟重试已接纳 · 下一条草稿保持不变');
      this.emit('reset');
    }

    removeSubmission(inputId) {
      this.state.history = this.state.history.filter(item =>
        item.id !== inputId || item.submissionPhase !== 'failed');
      this.emit('reset');
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
      this.haltTimers();
      this.snapshot(receipt);
      this.state.pending = null;
      this.state.running = false;
      this.state.queue = [];
      this.state.cursor = 0;
      this.emit('decision');
      this.beginTask();
    }

    dispose() {
      this.haltTimers();
      this.disposed = true;
      this.urls.forEach(url => URL.revokeObjectURL(url));
      this.urls.clear();
    }
  }

  app.isWaitingForModel = isWaitingForModel;
  app.flattenSelectOptions = flattenSelectOptions;
  app.ConversationController = ConversationController;
})();
