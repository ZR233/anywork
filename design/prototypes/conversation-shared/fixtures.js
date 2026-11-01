(() => {
  'use strict';
  const app = window.AnyworkConversation = window.AnyworkConversation || {};

  /* ========================================================================
     1. Shared Sidebar Projects, Threads, Modes & Model Catalog
     ======================================================================== */
  const projects = [
    {
      id: 'pure-lang-pure',
      name: 'pure-lang-pure',
      path: 'C:\\Users\\dev\\work\\pure-lang-pure',
      sshAlias: null,
      isGit: true,
      threads: [
        {
          id: 'thr-main',
          title: '会话组件化与运行期输入框锁定',
          worktree: true,
          branch: 'anywork/thr-01jc9k',
          workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure\\.anywork\\worktrees\\thr_01jc9k\\session',
          delegationSummary: '自动选模 · 平衡',
          scenario: 'running-locked'
        },
        {
          id: 'thr-workflow',
          title: '按任务模式重构桌面状态栏投影',
          worktree: false,
          branch: null,
          workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure',
          delegationSummary: '固定模板',
          scenario: 'workflow-locked'
        }
      ]
    },
    {
      id: 'pure-lang-remote',
      name: 'pure-lang-remote',
      path: '/srv/repos/pure-lang',
      sshAlias: 'gpu-dev',
      isGit: true,
      threads: [
        {
          id: 'thr-linux-gtk',
          title: 'Linux 原生 GTK 预检与打包',
          worktree: true,
          branch: 'anywork/thr-01jb7x',
          workspacePath: '/srv/repos/pure-lang/.anywork/worktrees/thr_01jb7x/session',
          delegationSummary: '自动选模 · 快速',
          scenario: 'workgroup'
        }
      ]
    },
    {
      id: 'notes-plain-dir',
      name: 'design-notes',
      path: 'C:\\Users\\dev\\Documents\\design-notes',
      sshAlias: null,
      isGit: false,
      threads: []
    }
  ];

  const standaloneThreads = [
    {
      id: 'thr-standalone-doc',
      title: '整理 Markdown 表格排版对比',
      worktree: false,
      workspacePath: 'C:\\Users\\dev\\Documents\\anywork',
      delegationSummary: '自动选模 · 平衡',
      scenario: 'idle'
    }
  ];

  const modes = [
    { id: 'mode.simple', label: '简洁', desc: '直接对话与工具执行，无固定阶段图约束' },
    { id: 'mode.task', label: '任务', desc: '按规划 → 实施 → 验证阶段推进复杂工程任务' }
  ];

  const accountGroups = [
    {
      accountId: 'openai-sub',
      accountName: 'OpenAI 订阅',
      models: [
        { id: 'gpt-6.1-sol', name: 'GPT-6.1 Sol', caps: ['文', '图', '件'], efforts: ['low', 'medium', 'high', 'max'], defaultEffort: 'max' },
        { id: 'gpt-5.4-mini', name: 'GPT-5.4 Mini', caps: ['文', '图'], efforts: ['low', 'medium', 'high'], defaultEffort: 'medium' }
      ]
    },
    {
      accountId: 'anthropic-main',
      accountName: 'Anthropic API',
      models: [
        { id: 'claude-opus-4.6', name: 'Claude Opus 4.6', caps: ['文', '图'], efforts: ['low', 'medium', 'high', 'max'], defaultEffort: 'high' }
      ]
    },
    {
      accountId: 'deepseek-official',
      accountName: 'DeepSeek 官方',
      models: [
        { id: 'deepseek-r1', name: 'DeepSeek-R1', caps: ['文'], efforts: ['medium', 'high'], defaultEffort: 'high' },
        { id: 'deepseek-v3.2', name: 'DeepSeek-V3.2', caps: ['文'], efforts: [], defaultEffort: null }
      ]
    }
  ];

  const allModels = accountGroups.flatMap(group =>
    group.models.map(model => ({ ...model, accountId: group.accountId, accountName: group.accountName }))
  );

  const preferenceHints = {
    economy: '满足任务能力与质量要求后，优先降低预计整体成本；未知价格不当免费。',
    balanced: '综合任务适配、近期评价、成本与完成时间，不降低质量要求。',
    fast: '满足能力、质量与审查要求后，优先缩短整体完成时间。'
  };

  function svgDataUri(svg) {
    return 'data:image/svg+xml;charset=UTF-8,' + encodeURIComponent(svg.trim());
  }

  const sampleScreenshots = [
    {
      name: 'narrow-viewport-check.png',
      kind: 'image',
      sourceLabel: '剪贴板粘贴 · PNG',
      dimensions: '1280 × 800',
      sizeLabel: '184 KB',
      caption: '窄窗口（580px）下外层会话环境栏与底部锁定选择器自然折行走查截图',
      url: svgDataUri(`
        <svg xmlns="http://www.w3.org/2000/svg" width="1280" height="800" viewBox="0 0 1280 800">
          <rect width="1280" height="800" fill="#F3EDE3"/>
          <rect x="44" y="38" width="1192" height="724" rx="18" fill="#EFE6DA" stroke="#D8CDBF" stroke-width="2"/>
          <rect x="44" y="38" width="1192" height="58" rx="18" fill="#E7DED2"/>
          <circle cx="80" cy="67" r="7" fill="#C6B7A6"/>
          <circle cx="102" cy="67" r="7" fill="#C6B7A6"/>
          <circle cx="124" cy="67" r="7" fill="#55798C"/>
          <text x="156" y="73" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="18" font-weight="600" fill="#40362F">糊来帮 · 窄视口响应式布局与工作树切换走查 (580px)</text>
          <rect x="1036" y="51" width="172" height="32" rx="8" fill="#FAF6EF" stroke="#D8CDBF"/>
          <text x="1058" y="72" font-family="Consolas, monospace" font-size="14" fill="#55798C">独立工作树 · thr-01jc9k</text>

          <rect x="170" y="138" width="940" height="236" rx="16" fill="#FAF6EF" stroke="#D8CDBF" stroke-width="2"/>
          <rect x="170" y="138" width="940" height="62" rx="16" fill="#EFE6DA"/>
          <rect x="198" y="153" width="176" height="32" rx="8" fill="#FAF6EF" stroke="#D8CDBF"/>
          <text x="218" y="174" font-family="Consolas, monospace" font-size="15" font-weight="600" fill="#40362F">pure-lang-pure</text>
          <rect x="394" y="151" width="276" height="36" rx="9" fill="#E3D8C9" stroke="#D3C5B4"/>
          <text x="420" y="174" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="14" fill="#66584E">本地目录</text>
          <rect x="518" y="154" width="148" height="30" rx="7" fill="#FAF6EF"/>
          <text x="544" y="174" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="14" font-weight="600" fill="#40362F">⑂ 新建工作树</text>
          <rect x="910" y="153" width="172" height="32" rx="8" fill="#FAF6EF" stroke="#D8CDBF"/>
          <text x="932" y="174" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="14" fill="#40362F">自动选模 · 平衡 ⌄</text>

          <text x="204" y="238" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="18" fill="#40362F">验证窄窗口下外层「本地目录 / 新建工作树」与底部三联选择器的换行对齐边界…</text>
          <rect x="204" y="316" width="140" height="34" rx="8" fill="#EFE6DA" stroke="#D8CDBF"/>
          <text x="226" y="338" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="14" fill="#66584E">📎 2 张截图草稿</text>
          <rect x="688" y="316" width="336" height="34" rx="8" fill="#F3EDE3" stroke="#D8CDBF"/>
          <text x="710" y="338" font-family="Consolas, monospace" font-size="14" fill="#514039">简洁 ⌄  ·  GPT-6.1 Sol ⌄  ·  max ⌄</text>
          <circle cx="1062" cy="333" r="19" fill="#514039"/>
          <text x="1055" y="339" font-family="Segoe UI, sans-serif" font-size="18" font-weight="700" fill="#FAF6EF">↑</text>

          <rect x="170" y="408" width="940" height="302" rx="16" fill="#FAF6EF" stroke="#D8CDBF" stroke-width="2"/>
          <rect x="202" y="436" width="876" height="48" rx="10" fill="#EFE6DA" stroke="#D8CDBF"/>
          <text x="226" y="466" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="15" fill="#514039">ⓘ 会话正在执行或收束清理中，暂时无法切换主模型。请停止当前执行或等待本轮完成后重试。</text>
          <rect x="202" y="510" width="420" height="168" rx="12" fill="#F3EDE3" stroke="#D8CDBF"/>
          <text x="228" y="546" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="16" font-weight="600" fill="#40362F">✓ 外层环境栏紧凑无挤压、无横向滚动</text>
          <text x="228" y="582" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="15" fill="#66584E">• 工作区采用紧凑下拉列表（本地目录 / 新建工作树）</text>
          <text x="228" y="614" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="15" fill="#66584E">• 粘贴图片以缩略图排布，点击弹层查看原图</text>
          <text x="228" y="646" font-family="Consolas, monospace" font-size="14" fill="#42604C">PASS · contrast 7.4:1 · 0 overflow</text>

          <rect x="652" y="510" width="426" height="168" rx="12" fill="#DDE9F0" stroke="#BFD0D8"/>
          <text x="678" y="546" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="16" font-weight="600" fill="#2B424F">运行期不可交互选择器 · 等宽零位移态</text>
          <rect x="678" y="566" width="372" height="40" rx="8" fill="#FAF6EF" stroke="#D8CDBF"/>
          <text x="700" y="591" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="14" fill="#A69789">简洁 ⌄</text>
          <text x="768" y="591" font-family="Consolas, monospace" font-size="14" fill="#A69789">GPT-6.1 Sol ⌄</text>
          <text x="906" y="591" font-family="Consolas, monospace" font-size="14" fill="#A69789">max ⌄</text>
          <circle cx="1018" cy="586" r="13" fill="#514039"/>
          <text x="1013" y="591" font-family="Segoe UI, sans-serif" font-size="13" fill="#FAF6EF">↑</text>
          <text x="678" y="642" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="14" fill="#3F6072">省略锁标并保持一致控件几何，状态切换零位移</text>
        </svg>
      `)
    },
    {
      name: 'clipboard-lock-matrix.png',
      kind: 'image',
      sourceLabel: '剪贴板粘贴 · PNG',
      dimensions: '1440 × 900',
      sizeLabel: '232 KB',
      caption: '运行期配置可配性状态矩阵与定宽主圆钮「▶ 继续 / ↑ 发送」零位移对照截图',
      url: svgDataUri(`
        <svg xmlns="http://www.w3.org/2000/svg" width="1440" height="900" viewBox="0 0 1440 900">
          <rect width="1440" height="900" fill="#F3EDE3"/>
          <rect x="56" y="48" width="1328" height="804" rx="18" fill="#FAF6EF" stroke="#D8CDBF" stroke-width="2"/>
          <rect x="56" y="48" width="1328" height="68" rx="18" fill="#EFE6DA"/>
          <text x="96" y="90" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="22" font-weight="600" fill="#40362F">会话运行期不可配项矩阵 · 截图对照 (1440 × 900)</text>
          <rect x="1156" y="65" width="190" height="34" rx="9" fill="#E5EBE2" stroke="#B9CCB4"/>
          <text x="1182" y="87" font-family="Consolas, monospace" font-size="14" font-weight="600" fill="#42604C">Siamese Light #F3EDE3</text>

          <rect x="96" y="154" width="600" height="300" rx="14" fill="#F3EDE3" stroke="#D8CDBF"/>
          <text x="128" y="196" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="18" font-weight="600" fill="#40362F">1. 活动工作流空闲间隙（任务 · 实施）</text>
          <text x="128" y="232" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="15" fill="#66584E">工作模式单独置灰不可交互，主模型与思考强度开放换模：</text>
          <text x="142" y="288" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="15" fill="#A69789">任务</text>
          <rect x="210" y="264" width="196" height="38" rx="8" fill="#FAF6EF" stroke="#514039" stroke-width="1.5"/>
          <text x="232" y="288" font-family="Consolas, monospace" font-size="15" font-weight="600" fill="#40362F">Claude Opus 4.6 ⌄</text>
          <rect x="422" y="264" width="108" height="38" rx="8" fill="#FAF6EF" stroke="#D8CDBF"/>
          <text x="448" y="288" font-family="Consolas, monospace" font-size="15" fill="#40362F">high ⌄</text>
          <text x="128" y="348" font-family="Consolas, monospace" font-size="14" fill="#42604C">✓ 切换模型在下一轮生效，不重置当前 Plan 与阶段进度</text>

          <rect x="744" y="154" width="600" height="300" rx="14" fill="#F3EDE3" stroke="#D8CDBF"/>
          <text x="776" y="196" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="18" font-weight="600" fill="#40362F">2. 绑定模型路由不可用（HTTP 429 / 已停用）</text>
          <text x="776" y="232" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="15" fill="#914447">⚠ 保留原模型名称不静默改选，阻断提交但开放换模自救：</text>
          <rect x="776" y="264" width="42" height="38" rx="8" fill="#F3E0DD" stroke="#E1B8B9"/>
          <text x="789" y="289" font-family="Segoe UI, sans-serif" font-size="17" font-weight="700" fill="#914447">⚠</text>
          <rect x="828" y="264" width="196" height="38" rx="8" fill="#FAF6EF" stroke="#914447" stroke-width="1.5"/>
          <text x="850" y="288" font-family="Consolas, monospace" font-size="15" font-weight="600" fill="#40362F">Claude Opus 4.6 ⌄</text>
          <circle cx="1284" cy="283" r="20" fill="#D9CAB9"/>
          <text x="1277" y="290" font-family="Segoe UI, sans-serif" font-size="18" fill="#8A7A6C">↑</text>
          <text x="776" y="348" font-family="Consolas, monospace" font-size="14" fill="#514039">→ 点击模型菜单改选可用模型后立即恢复可发送状态</text>

          <rect x="96" y="492" width="1248" height="312" rx="14" fill="#EFE6DA" stroke="#D8CDBF"/>
          <text x="132" y="538" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="19" font-weight="600" fill="#40362F">3. 唯一主操作槽位六态确定性转换</text>
          <rect x="132" y="572" width="180" height="84" rx="12" fill="#FAF6EF" stroke="#D8CDBF"/>
          <text x="154" y="606" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="14" fill="#8A7A6C">空闲空草稿</text>
          <text x="154" y="636" font-family="Consolas, monospace" font-size="16" font-weight="600" fill="#8A7A6C">禁用圆钮 ↑</text>

          <rect x="332" y="572" width="180" height="84" rx="12" fill="#FAF6EF" stroke="#D8CDBF"/>
          <text x="354" y="606" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="14" fill="#66584E">运行中空草稿</text>
          <text x="354" y="636" font-family="Consolas, monospace" font-size="16" font-weight="600" fill="#40362F">中性停止 ■</text>

          <rect x="532" y="572" width="210" height="84" rx="12" fill="#FAF6EF" stroke="#D8CDBF"/>
          <text x="554" y="606" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="14" fill="#66584E">运行中已拟文字/贴图</text>
          <text x="554" y="636" font-family="Consolas, monospace" font-size="16" font-weight="600" fill="#514039">发送并继续 ↑</text>

          <rect x="762" y="572" width="210" height="84" rx="12" fill="#FAF6EF" stroke="#D8CDBF"/>
          <text x="784" y="606" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="14" fill="#66584E">停止命令已受理</text>
          <text x="784" y="636" font-family="Consolas, monospace" font-size="16" font-weight="600" fill="#8A7A6C">正在停止 ◌</text>

          <rect x="992" y="572" width="316" height="84" rx="12" fill="#514039"/>
          <text x="1020" y="606" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="14" fill="#E1D4C5">已停止含未消费继续点 + 空草稿</text>
          <text x="1020" y="638" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="18" font-weight="600" fill="#FAF6EF">▶ 继续（空回车不误触恢复）</text>

          <text x="132" y="732" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="15" fill="#66584E">提示：使用 Esc 关闭当前大图弹层，或使用键盘 ← / → 在当前草稿的多张粘贴图片间切换查看。</text>
        </svg>
      `)
    },
    {
      name: 'worktree-branch-status.png',
      kind: 'image',
      sourceLabel: '剪贴板粘贴 · PNG',
      dimensions: '1200 × 760',
      sizeLabel: '168 KB',
      caption: '独立 Git 工作树检出路径与分支隔离状态检查截图',
      url: svgDataUri(`
        <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="760" viewBox="0 0 1200 760">
          <rect width="1200" height="760" fill="#F3EDE3"/>
          <rect x="52" y="46" width="1096" height="668" rx="16" fill="#FAF6EF" stroke="#D8CDBF" stroke-width="2"/>
          <rect x="52" y="46" width="1096" height="60" rx="16" fill="#DDE9F0"/>
          <text x="88" y="83" font-family="Consolas, monospace" font-size="19" font-weight="600" fill="#2B424F">git worktree list · anywork/thr-01jc9k</text>
          <rect x="88" y="142" width="1024" height="220" rx="12" fill="#F3EDE3" stroke="#D8CDBF"/>
          <text x="118" y="186" font-family="Consolas, monospace" font-size="16" fill="#40362F">C:/Users/dev/work/pure-lang-pure                                    a7fd91c [main]</text>
          <text x="118" y="226" font-family="Consolas, monospace" font-size="16" font-weight="600" fill="#55798C">C:/Users/dev/work/pure-lang-pure/.anywork/worktrees/thr_01jc9k/session  a7fd91c [anywork/thr-01jc9k]</text>
          <text x="118" y="266" font-family="Consolas, monospace" font-size="15" fill="#42604C">✓ 主工作区干净无污染 · 会话改动与子智能体审查工作树完全隔离</text>
          <text x="118" y="316" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="15" fill="#66584E">会话创建后工作区模式已冻结于顶栏只读徽标，不可在运行中途切回原本地目录。</text>
          <rect x="88" y="396" width="1024" height="272" rx="12" fill="#EFE6DA" stroke="#D8CDBF"/>
          <text x="118" y="442" font-family="Segoe UI, Microsoft YaHei UI, sans-serif" font-size="17" font-weight="600" fill="#40362F">四阶段环境准备时间线快照</text>
          <text x="118" y="486" font-family="Consolas, monospace" font-size="15" fill="#42604C">[1/4] ✓ 检查项目           12ms</text>
          <text x="118" y="524" font-family="Consolas, monospace" font-size="15" fill="#42604C">[2/4] ✓ 准备工作区 (HEAD)  148ms</text>
          <text x="118" y="562" font-family="Consolas, monospace" font-size="15" fill="#42604C">[3/4] ✓ 初始化会话         34ms</text>
          <text x="118" y="600" font-family="Consolas, monospace" font-size="15" fill="#42604C">[4/4] ✓ 提交首条请求       19ms</text>
        </svg>
      `)
    }
  ];

  function defaultAgents() {
    return [
      {
        id: 'root',
        isRoot: true,
        role: '主智能体',
        title: '会话组件化与运行期输入框锁定',
        routeLabel: 'GPT-6.1 Sol · max',
        status: 'running',
        workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure\\.anywork\\worktrees\\thr_01jc9k\\session'
      },
      {
        id: 'reviewer',
        isRoot: false,
        role: 'reviewer',
        title: '核对运行期选择器锁定原因与只读停靠',
        routeLabel: 'Claude Opus 4.6 · high',
        status: 'running',
        workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure\\.anywork\\worktrees\\thr_01jc9k\\agents\\reviewer'
      },
      {
        id: 'explorer',
        isRoot: false,
        role: 'explorer',
        title: '梳理起始页与会话页共享组件边界',
        routeLabel: 'GPT-5.4 Mini · medium',
        status: 'completed',
        workspacePath: 'C:\\Users\\dev\\work\\pure-lang-pure\\.anywork\\worktrees\\thr_01jc9k\\agents\\explorer'
      }
    ];
  }

  /* ========================================================================
     2. Shared Timeline, WorkGroup, Q&A & Playback Story Fixtures
     ======================================================================== */
  const text = [
    '已经把会话界面收敛为同一套共享模块：**起始页与运行期会话共用外壳、顶栏与 `PromptComposerCard`，上方时间线只放已结束内容，下方状态栏承载正在进行的工作组**。',
    '',
    '### 运行期配置可配性分层',
    '- **创建期一次性冻结**：工作区模式（`本地目录` / `新建工作树`）与子智能体分发在会话创建后上移至顶栏只读徽标，外层创建托盘自动退役。',
    '- **运行期条件锁定**：轮次运行或等待期间锁定模式、主模型与思考强度（点击展示明确原因）；轮次空闲后即使处于活动工作流阶段，仍允许切换下一轮主模型与思考强度。',
    '- **子智能体只读停靠**：切到子智能体视图时输入区整体替换为只读停靠面板，新要求统一回到主会话表达。',
    '',
    '```dart',
    'final modeEditable = thread.isIdle && !workflow.isActive && activeInteraction == null;',
    'final routeEditable = thread.isIdle && !thread.isBotManaged;',
    '```',
    '',
    '| 配置项 | 起始页（新建草稿） | 根会话运行中 | 根会话空闲（活动工作流） | 子智能体会话 |',
    '| --- | --- | --- | --- | --- |',
    '| 工作区 / 分发 | 外层环境栏可配 | 顶栏只读冻结 | 顶栏只读冻结 | 只读芯片 |',
    '| 工作模式 | 可切换 | 锁定（附原因） | 锁定（工作流中） | 只读停靠 |',
    '| 主模型 / 强度 | 可切换 | 锁定（附原因） | 可切换（下轮生效） | 冻结路由只读 |',
    '',
    '> 运行中文本输入与附件草稿始终保持可编辑，输入内容后主按钮自动由「停止」切换为「发送并继续」。'
  ].join('\n');

  const closingText = '静态检查与视觉核对已全部通过。\n\n所有会话入口页面现在共享同一套 `conversation-shared` 组件与状态控制器。';

  function members(id, terminal) {
    const status = terminal ? 'completed' : 'running';
    return [
      { id: id + '-thinking', kind: 'thinking', title: '梳理会话共享组件与锁定边界', status: 'completed', elapsed: 3,
        content: '已完成的成员**留在状态栏的当前工作组**；同时核对运行期 `SessionModeSelector` 与 `ModelRoleSelector` 的就地锁定提示。' },
      { id: id + '-read', kind: 'read', title: '读取文件', target: 'composer_dock_connector.dart', status: 'completed', elapsed: 1,
        path: 'code/anywork/lib/src/features/conversation/composer/connectors/composer_dock_connector.dart',
        content: '已核对运行期选择器锁定规则：\n- 工作模式要求 idle 且无活动工作流\n- 模型与强度仅要求当前轮次 idle，点击锁定项通过 _modelNotice 就地解释原因。' },
      { id: id + '-command', kind: 'command', title: '执行命令', target: 'cargo test -p pl-core --features sqlite',
        status, elapsed: terminal ? 8 : 5, cwd: '~/work/anywork', exitCode: terminal ? 0 : null,
        output: 'Compiling pl-core\nrunning 24 tests\ntest finished_group_enters_timeline ... ok\ntest locked_route_preserves_draft ... ok' + (terminal ? '\ntest result: ok. 24 passed; 0 failed\nProcess exited with code 0' : '') },
      { id: id + '-search', kind: 'search', title: '搜索交互约定', target: '选择器锁定 · 运行中发送', status: 'completed', elapsed: 2,
        queries: ['被锁定的选择器必须给出可见原因', '运行中发送并继续与草稿冻结'],
        results: [
          { title: 'design/19-studio-ui.md §19.2 动态工作模式与工作流状态', description: '被锁定的选择器必须给出可见原因，不得出现看似可点却静默吞掉点击的控件。', url: 'https://developer.mozilla.org/zh-CN/docs/Web/Accessibility/ARIA' },
          { title: 'design/19-studio-ui.md §19.11 运行中发送消息与剪贴板粘贴', description: '运行中无草稿显示停止，输入草稿后切换为发送并继续，Esc 停止并保留草稿。', url: 'https://developer.mozilla.org/zh-CN/docs/Web/HTML/Element/dialog' }
        ] },
      { id: id + '-edit', kind: 'edit', title: '修改文件', target: 'conversation-shared/composer.js', status: 'completed', elapsed: 2,
        path: 'design/prototypes/conversation-shared/composer.js',
        files: [
          { name: 'composer.js', added: 28, removed: 0,
            diff: '@@ 共享会话输入卡与锁定提示 @@\n+ renderPromptComposerCard({ stage, locks, primaryAction });\n+ if (locks.notice) renderDismissibleLockNotice(locks.notice);\n+ onLockedSelectorClick(reason => controller.explainLock(reason));' },
          { name: 'session-start/index.html', added: 6, removed: 18,
            diff: '@@ 复用 conversation-shared 消除重复实现 @@\n- <script defer src="preview.js"></script>\n+ <script defer src="../conversation-shared/preview.js"></script>' }
        ] },
      { id: id + '-wait', kind: 'wait', title: '等待子智能体', target: 'explorer · reviewer',
        status, elapsed: terminal ? 7 : 4, rule: '等待两个成员都返回结果',
        targets: [
          { name: 'explorer', task: '梳理起始页与会话页共享组件边界', status: 'completed', report: '已确认外层创建环境栏仅在起始页挂载，会话页复用同一内层输入卡。' },
          { name: 'reviewer', task: '核对运行期选择器锁定原因与只读停靠', status, report: terminal ? '完成全部锁定态、模型不可用告警与子会话只读面板核对。' : '正在核对运行期锁定点击反馈与子智能体只读面板。' }
        ] }
    ];
  }

  function group(id = 'group-active', terminal = false) {
    return { id, kind: 'workGroup', status: terminal ? 'completed' : 'running', elapsed: terminal ? 18 : 12, members: members(id, terminal) };
  }

  function followUpMembers(id) {
    return [
      { id: id + '-thinking', kind: 'thinking', title: '确认收尾检查', status: 'running', elapsed: 0,
        content: '正文已经结束，这是新的工作组：先在状态栏插入成员，等下一段正文出现时再整组进入时间线。' },
      { id: id + '-command', kind: 'command', title: '执行命令', target: 'cargo flutter analyze', status: 'running', elapsed: 0,
        cwd: '~/work/anywork', exitCode: null, output: 'Analyzing anywork...' }
    ];
  }

  function history() {
    const old = group('group-history', true);
    old.members = old.members.slice(0, 3);
    return [
      { id: 'message-user-1', kind: 'user', author: '你', text: '把会话设计稿组件化避免每个页面复制一份，再把会话运行时的输入框交互和不可配项体现清楚。', time: '14:32' },
      old,
      { id: 'message-assistant-1', kind: 'text', status: 'completed', time: '14:34',
        text: '我会先把侧栏、顶栏、时间线和主输入卡统一收敛到 `conversation-shared`，再细化已建会话中「创建期永久冻结」与「运行期动态锁定」的分层交互。' },
      { id: 'compression-history', kind: 'compression', status: 'completed', time: '14:35' },
      { id: 'message-user-2', kind: 'user', author: '你', text: '重点检查运行中锁模型、活动工作流锁模式、中断后继续以及子智能体只读视图。', time: '14:36' }
    ];
  }

  function childHistory(agent) {
    const subGroup = {
      id: 'sub-group-' + agent.id,
      kind: 'workGroup',
      status: 'completed',
      elapsed: 6,
      members: [
        {
          id: 'sub-' + agent.id + '-read',
          kind: 'read',
          title: '读取文件',
          target: 'session_selectors.dart',
          status: 'completed',
          elapsed: 2,
          path: 'code/anywork/lib/src/features/status/session_selectors.dart',
          content: '已核对 _QuietSelectorMenu.onBlockedTap：禁用状态下点击触发 _explainSelection，不静默吞掉操作。'
        },
        {
          id: 'sub-' + agent.id + '-search',
          kind: 'search',
          title: '搜索只读契约',
          target: 'AgentReadOnlyDockView',
          status: 'completed',
          elapsed: 4,
          queries: ['子智能体会话（只读）', '顶栏智能体切换菜单唯一停止入口'],
          results: [
            { title: 'composer_support_views.dart · AgentReadOnlyDockView', description: '子会话详情只展示历史、进展、冻结模型与工作区，不提供输入或继续按钮。', url: 'https://developer.mozilla.org/zh-CN/' }
          ]
        }
      ]
    };
    return [
      {
        id: 'sub-user-' + agent.id,
        kind: 'user',
        author: '主智能体委派',
        time: '14:36',
        text: `请核对「${agent.title}」，确认所有不可配置项都有清晰的视觉区分与原因反馈，并提交核查报告。`
      },
      subGroup,
      {
        id: 'sub-assistant-' + agent.id,
        kind: 'text',
        status: 'completed',
        time: '14:37',
        text: agent.status === 'completed'
          ? '已完成核查并向主智能体提交报告：\n- 创建期工作区模式与子智能体分发已移至顶栏只读芯片；\n- 运行期被锁定的选择器均带有锁形指示与点击原因横条。'
          : '已初步核对选择器锁定逻辑，正在继续检查模型不可用（`unavailable`）与子智能体只读面板的边界表现。'
      }
    ];
  }

  const questions = {
    id: 'questions', kind: 'questions', title: '确认两个运行期交互细节', index: 0,
    questions: [
      { title: '点击运行期已锁定的选择器时如何反馈？', description: '遵循 §19.2 不静默吞掉点击的交互准则。', multiple: false,
        options: ['在输入卡上方展开可关闭的就地原因提示条（推荐）', '仅依赖鼠标悬停 Tooltip'] },
      { title: '需要重点覆盖哪些不可配状态？', description: '可以多选，也可以补充自己的要求。', multiple: true,
        options: ['创建期冻结（本地目录 / 工作树 / 分发）', '运行中三联全锁与并发拟稿', '活动工作流仅锁模式、开放换模', '子智能体只读停靠面板'], secret: true }
    ],
    answers: [['在输入卡上方展开可关闭的就地原因提示条（推荐）'], ['创建期冻结（本地目录 / 工作树 / 分发）', '运行中三联全锁与并发拟稿']],
    others: ['', ''],
    secret: ''
  };

  /* ========================================================================
     3. Unified Scenario Catalog (Grouped by Lifecycle Stage)
     ======================================================================== */
  const scenarioGroups = [
    { id: 'start', label: '一、新会话创建期（起始页双层输入台）' },
    { id: 'composer', label: '二、会话运行时输入框与配置锁定' },
    { id: 'timeline', label: '三、时间线与实时状态栏整组交接' }
  ];

  const scenarios = [
    // Group 1: Start Page Creation Stage
    {
      id: 'local',
      group: 'start',
      stage: 'start',
      label: '起始页 · 本地目录（默认）',
      hint: '创建前外层环境栏完全可配：项目名旁通过紧凑下拉列表切换「本地目录 / 新建工作树」，右侧单层面板配置子智能体分发。'
    },
    {
      id: 'worktree',
      group: 'start',
      stage: 'start',
      label: '起始页 · 新建工作树',
      hint: '外层工作区下拉已选中「新建工作树」（眼眸蓝分支图标提示）；点击发送可完整预览四阶段环境准备并自动转入运行期会话。'
    },
    {
      id: 'ssh-worktree',
      group: 'start',
      stage: 'start',
      label: '起始页 · SSH 远程项目工作树',
      hint: 'SSH 项目在外层展示远程主机徽标，工作区下拉列表支持在远端项目目录与远端新建工作树之间紧凑切换。'
    },
    {
      id: 'standalone',
      group: 'start',
      stage: 'start',
      label: '起始页 · 非项目独立会话',
      hint: '全局「新会话」无需先添加项目，外层工作区位置收敛为不可交互的「固定本地目录」标签，不显示工作树下拉列表。'
    },
    {
      id: 'preparing',
      group: 'start',
      stage: 'start',
      label: '起始页 · 首条请求环境准备中',
      hint: '首条消息提交后欢迎区切换为四阶段准备卡片：此时外层工作区与分发已冻结锁定，但内层输入框仍允许提前编辑下一条草稿。'
    },
    {
      id: 'worktree-error',
      group: 'start',
      stage: 'start',
      label: '起始页 · 工作树准备失败保留草稿',
      hint: '非 Git 目录尝试创建工作树失败时，原位保留提示词与附件草稿，提供一键「切换为本地目录」恢复入口。'
    },

    // Group 2: Runtime Session Composer & Locked Configuration Matrix
    {
      id: 'running-locked',
      group: 'composer',
      stage: 'session',
      at: 'workgroup',
      label: '运行中 · 选择器零位移不可交互 + 可并发拟稿',
      hint: '会话已创建并正在运行：外层工作区栏已退役为顶栏等高只读徽标；模式、模型、强度省略锁标并保持一致控件几何呈置灰不可交互态（状态切换零位移），输入框仍可随时打字或贴图，主按钮为「停止 (■)」。'
    },
    {
      id: 'running-draft',
      group: 'composer',
      stage: 'session',
      at: 'workgroup',
      initialDraft: '顺便对照这两张粘贴的走查截图，检查窄窗口下底部选择器的折行表现并补充到设计文档表格里。',
      initialAttachments: [
        { id: 'att-running-1', ...sampleScreenshots[0] },
        { id: 'att-running-2', ...sampleScreenshots[1] }
      ],
      label: '运行中已拟草稿与贴图 · 缩略图预览 + 发送并继续 (↑)',
      hint: '运行期间粘贴的图片在输入框上方以缩略图排布（点击任意缩略图可弹层查看高清大图并左右切换，右上角 × 单独移除）；选择器保持简洁不可交互态，主按钮自动切换为「发送并继续 (↑)」。'
    },
    {
      id: 'stopping-cleanup',
      group: 'composer',
      stage: 'session',
      at: 'workgroup',
      stoppingCleanup: true,
      label: '停止收束中 · 「正在停止」过渡锁',
      hint: '点击停止并获命令板受理、后台进程树清理尚未结束时：外显「正在停止」与旋转进度，暂时锁闭提交与继续入口，防止清理期并发重入。'
    },
    {
      id: 'workflow-locked',
      group: 'composer',
      stage: 'session',
      workflowActive: true,
      label: '活动工作流（轮次空闲）· 仅模式不可交互、开放换模',
      hint: '处于「任务 · 实施」活动工作流且当前轮次刚结束空闲：工作模式保持原宽置灰不可交互，主智能体模型与思考强度完全开放可点，切换后在下一轮生效且不重置计划。'
    },
    {
      id: 'stopped',
      group: 'composer',
      stage: 'session',
      outcome: 'stopped',
      label: '已停止待继续 · 解锁换模 + 定宽「▶」继续圆钮',
      hint: '执行停止后轮次回到空闲：模型与思考强度原位解锁（可先换模再恢复），右下角 34×34px 主圆钮原位切为「▶」继续（空输入回车不误触；输入补充内容后零位移切为「↑」发送并继续）。'
    },
    {
      id: 'model-unavailable',
      group: 'composer',
      stage: 'session',
      routeUnavailable: true,
      initialDraft: '继续验证模型恢复后的下一轮输出。',
      label: '模型不可用 · 阻塞发送但保留换模自救',
      hint: '当前绑定的模型配额耗尽或离线时：保留原模型名不静默篡改，显示告警按钮并锁闭发送，但模型选择器保持可点——改选任一可用模型即可立即恢复发送！'
    },
    {
      id: 'bot-managed',
      group: 'composer',
      stage: 'session',
      botManaged: true,
      label: '机器人托管会话 · 模型由机器人统一设置',
      hint: '由飞书 / Telegram 等机器人渠道发起的会话：模型与思考强度合并为只读的「由机器人统一设置」胶囊，避免单会话临时覆盖与机器人规则冲突。'
    },
    {
      id: 'subagent-readonly',
      group: 'composer',
      stage: 'session',
      at: 'workgroup',
      activeAgentId: 'reviewer',
      label: '子智能体视图 · 全输入区只读停靠面板',
      hint: '从顶栏「3 个智能体」切入子智能体 reviewer：整个输入框与选择器替换为只读停靠面板，展示冻结模型与独立工作树；唯一停止入口位于顶栏智能体菜单行内。'
    },

    // Group 3: Timeline & Live Status Bar Handoff Scenarios
    {
      id: 'workgroup',
      group: 'timeline',
      stage: 'session',
      at: 'workgroup',
      label: '状态栏 · 工作组进行中',
      hint: '当前工作组位于状态栏：成员逐个插入，已完成的切换为对应语义图标留在组内，运行中的继续计时。时间线不出现半成品。'
    },
    {
      id: 'thinking',
      group: 'timeline',
      stage: 'session',
      at: 'thinking',
      label: '状态栏 · 思考中（尚无成员）',
      hint: '新轮次尚无任何信息，状态栏只显示不可展开的「思考中」与耗时；不生成空工作组。'
    },
    {
      id: 'group-idle',
      group: 'timeline',
      stage: 'session',
      at: 'group-idle',
      label: '状态栏 · 工作组待交接',
      hint: '成员已全部完成，工作组仍留在状态栏并显示「思考中」。下一条是工具则继续并入本组；是正文、提问或轮次结束则整组移入时间线。'
    },
    {
      id: 'text',
      group: 'timeline',
      stage: 'session',
      at: 'text',
      label: '状态栏 · 实时流式文本',
      hint: '正文开始的一刻，上一工作组已整组移入时间线。流式 Markdown 在状态栏输出，结束后整段进入时间线。'
    },
    {
      id: 'after-text',
      group: 'timeline',
      stage: 'session',
      at: 'after-text',
      label: '状态栏 · 文本结束后等待',
      hint: '完整正文已进入时间线，轮次尚未结束，状态栏显示「思考中」。之后的工具会在状态栏开启新工作组。'
    },
    {
      id: 'next-group',
      group: 'timeline',
      stage: 'session',
      at: 'next-group',
      label: '状态栏 · 开启新工作组',
      hint: '上一组已在时间线中结束；新工作组先在状态栏插入，不会接到时间线里的旧组后面。'
    },
    {
      id: 'compacting',
      group: 'timeline',
      stage: 'session',
      live: 'compacting',
      label: '状态栏 · 正在压缩上下文',
      hint: '上下文压缩期间单行展示并锁定输入区路由选择器；压缩成功后时间线追加单行「已完成压缩」回执。'
    },
    {
      id: 'questions',
      group: 'timeline',
      stage: 'session',
      pending: questions,
      initialDraft: '（回答完问题后继续沿用这段暂存草稿）',
      label: '停靠区 · 待回答提问（暂存草稿）',
      hint: '提问到达时此前的工作组整组移入时间线，输入框暂时让位于分步问答停靠面板并自动保留未发草稿；回答或跳过后草稿原样恢复。'
    },
    {
      id: 'receipts',
      group: 'timeline',
      stage: 'session',
      label: '时间线 · 只读问答回执',
      hint: '问题回答或跳过后，在时间线中形成默认折叠的只读回执；敏感回答保持隐藏。'
    },
    {
      id: 'failed',
      group: 'timeline',
      stage: 'session',
      outcome: 'failed',
      label: '时间线 · 执行失败终态与继续',
      hint: '失败成员在组内标记，原因在独立的折叠失败记录中按需展开；轮次空闲后可先切换模型或直接点击「▶ 继续」恢复。'
    },
    {
      id: 'idle',
      group: 'timeline',
      stage: 'session',
      label: '空闲阅读 · 全部轮次配置可改',
      hint: '无运行任务且无活动工作流：状态栏收起，模式、主模型、思考强度与上下文立即压缩均处于自由可用状态，仅创建期工作区与分发保持顶栏只读。'
    },
    {
      id: 'empty',
      group: 'timeline',
      stage: 'session',
      empty: true,
      label: '已建空会话 · 准备首轮对话',
      hint: '在空白会话中输入第一条消息，完整体验从状态栏工作组到时间线交接与运行期配置锁定的全过程。'
    }
  ];

  function textEvents(source, label) {
    return Array.from({ length: Math.ceil(source.length / 32) }, (_, index) => ({
      type: 'appendText',
      text: source.slice(index * 32, (index + 1) * 32),
      ...(index === 4 && label ? { label } : {})
    }));
  }

  function story(id) {
    const first = members(id, false).map(member => ({ ...member, status: 'running', elapsed: 0 }));
    first.find(member => member.kind === 'wait').targets[0].status = 'running';
    const add = member => ({ type: 'addMember', groupId: id, member });
    const done = name => ({ type: 'memberDone', id: id + '-' + name });
    const next = id + '-next';
    const [nextThinking, nextCommand] = followUpMembers(next);
    return [
      { type: 'waitForModel', id, label: 'thinking' },
      { type: 'tick' },
      add(first[0]), done('thinking'),
      add(first[1]), done('read'),
      add(first[2]), add(first[3]),
      { type: 'appendCommand', line: 'test history_is_immutable ... ok' },
      done('search'),
      add(first[4]), done('edit'),
      add(first[5]),
      { type: 'appendCommand', line: 'test group_moves_as_a_whole ... ok', label: 'workgroup' },
      done('command'), done('wait'),
      { type: 'tick', label: 'group-idle' }, { type: 'tick' },
      { type: 'startText', id: id + '-text' },
      ...textEvents(text, 'text'),
      { type: 'finishText' },
      { type: 'waitForModel', id: next, label: 'after-text' },
      { type: 'tick' },
      { type: 'addMember', groupId: next, member: nextThinking },
      { type: 'memberDone', id: nextThinking.id },
      { type: 'addMember', groupId: next, member: nextCommand, label: 'next-group' },
      { type: 'appendCommand', line: 'No issues found! (ran in 3.2s)' },
      { type: 'memberDone', id: nextCommand.id },
      { type: 'tick' },
      { type: 'startText', id: next + '-text' },
      ...textEvents(closingText),
      { type: 'finishText' },
      { type: 'finishTurn' }
    ];
  }

  app.fixtures = {
    projects,
    standaloneThreads,
    modes,
    accountGroups,
    allModels,
    preferenceHints,
    sampleScreenshots,
    defaultAgents,
    text,
    group,
    history,
    childHistory,
    questions,
    scenarioGroups,
    scenarios,
    story
  };
})();
