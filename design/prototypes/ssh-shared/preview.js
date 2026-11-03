// Shared SSH remote development & server-scoped configuration prototype (Material 3 / Siamese Light Theme).
document.getElementById("aw-preview-mount").innerHTML = `<div id="aw-ssh" class="mdui-theme-light" aria-label="SSH 远程开发与服务器专属配置 Material 3 设计预览">
  <mdui-card variant="outlined" class="aw-previewbar" aria-label="设计评审场景切换">
    <span class="aw-previewlabel"><i data-lucide="sliders-horizontal" aria-hidden="true"></i>场景预览</span>
    <mdui-select id="aw-type" label="设计维度" value="overview" variant="outlined"></mdui-select>
    <mdui-select id="aw-scenario" class="aw-state-select" label="展示状态" value="overview:normal" variant="outlined"></mdui-select>
    <div class="aw-stepper" aria-label="快速切换场景">
      <mdui-tooltip content="上一场景"><mdui-button-icon id="aw-prev-scenario" aria-label="上一场景"><i data-lucide="chevron-left" aria-hidden="true"></i></mdui-button-icon></mdui-tooltip>
      <span class="aw-scenario-index" id="aw-scenario-index">1 / 18</span>
      <mdui-tooltip content="下一场景"><mdui-button-icon id="aw-next-scenario" aria-label="下一场景"><i data-lucide="chevron-right" aria-hidden="true"></i></mdui-button-icon></mdui-tooltip>
    </div>
    <mdui-segmented-button-group selects="single" class="aw-view-group" id="aw-view-group" value="list" aria-label="视图切换">
      <mdui-segmented-button value="list" id="aw-view-list">服务器列表</mdui-segmented-button>
      <mdui-segmented-button value="add" id="aw-view-add">添加服务器</mdui-segmented-button>
      <mdui-segmented-button value="detail" id="aw-view-detail">服务器配置中心</mdui-segmented-button>
      <mdui-segmented-button value="mcp" id="aw-view-mcp">服务器 MCP 专页</mdui-segmented-button>
    </mdui-segmented-button-group>
  </mdui-card>
  <div class="aw-shell" id="aw-shell">
    <aside class="aw-sidebar">
      <div class="aw-brand"><mdui-avatar><i data-lucide="cat" aria-hidden="true"></i></mdui-avatar>糊来帮</div>
      <mdui-button variant="text" class="aw-back-chat" id="aw-back-chat" href="../project-sidebar/index.html"><span slot="icon"><i data-lucide="arrow-left" aria-hidden="true"></i></span>返回聊天</mdui-button>
      <nav id="aw-nav" aria-label="设置导航"></nav>
      <div class="aw-sidebar-bottom"><span class="aw-small-dot"></span>设置 · 远程开发与服务器配置</div>
    </aside>
    <main class="aw-main" id="aw-main"></main>
  </div>
  <div class="aw-preview-foot">
    <span><i data-lucide="palette" aria-hidden="true"></i>Material 3 · 暹罗浅色 · 依据 design/22-ssh-remote.md 与 design/20-config.md</span>
    <span id="aw-coverage">示例数据 · 不修改真实 ~/.ssh/config</span>
  </div>
  <mdui-dialog id="aw-dialog" headline="服务器设置" close-on-esc>
    <div id="aw-dialog-content"></div>
    <mdui-button slot="action" variant="text" id="aw-dialog-cancel">取消</mdui-button>
    <mdui-button slot="action" variant="filled" id="aw-dialog-save">保存</mdui-button>
  </mdui-dialog>
  <mdui-snackbar id="aw-snackbar" placement="bottom" auto-close-delay="2800" closeable></mdui-snackbar>
</div>`;

(() => {
const root = document.getElementById('aw-ssh');
const $ = s => root.querySelector(s);
const $$ = s => Array.from(root.querySelectorAll(s));
const escapeHTML = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const icon = (name, slot = '') => `<span${slot ? ` slot="${slot}"` : ''}><i data-lucide="${name}" aria-hidden="true"></i></span>`;
const btn = (label, action, variant = 'text', ico = '', attrs = '') => `<mdui-button variant="${variant}" data-action="${action}" ${attrs}>${ico ? icon(ico, 'icon') : ''}${label}</mdui-button>`;
const iconBtn = (label, action, ico, attrs = '') => `<mdui-tooltip content="${escapeHTML(label)}"><mdui-button-icon aria-label="${escapeHTML(label)}" data-action="${action}" ${attrs}>${icon(ico)}</mdui-button-icon></mdui-tooltip>`;
const chip = (label, ico = '') => `<mdui-chip class="aw-chip-sm" tabindex="-1">${ico ? icon(ico, 'icon') : ''}${label}</mdui-chip>`;
const status = (text, tone = 'neutral', ico = '') => `<span class="aw-status ${tone}">${ico ? icon(ico) : ''}${text}</span>`;
const notice = (message, tone = 'warning', action = '') => `<div class="aw-notice ${tone}">${icon(tone === 'error' ? 'circle-alert' : tone === 'success' ? 'circle-check' : 'info')}<div class="aw-notice-text">${message}</div>${action}</div>`;

const groups = {
  overview: {
    label: '服务器列表与概览',
    states: [
      ['normal', '多服务器与专属配置概览（默认）'],
      ['readonly', '含 ~/.ssh/config 手写只读主机'],
      ['empty', '尚未配置 SSH 服务器（空状态）']
    ]
  },
  connection: {
    label: '连接、辅助进程与认证状态',
    states: [
      ['ready', '已连接 · remote-helper v10 就绪'],
      ['connecting', '首次连接 · 正在上传辅助进程 (68%)'],
      ['reconnecting', '网络闪断 · 指数退避重连 (第 3 次 / 4s)'],
      ['passwordPrompt', '免密探测未过 · 弹出 SSH 密码认证'],
      ['pubkeyOnlyError', '认证失败 · 仅接受公钥 (不弹密码框)'],
      ['browseDir', '交互式浏览远端 POSIX 目录并打开项目']
    ]
  },
  serverMcp: {
    label: '服务器 MCP 创建与维护',
    states: [
      ['mcpNormal', '远端 stdio 与 HTTP 服务混合运行'],
      ['mcpCreate', '展开创建服务器专属 MCP（含模板）'],
      ['mcpToolsExpanded', '展开查看 MCP 已注册工具与租约代次'],
      ['mcpMissingCred', '远端 MCP 缺少环境变量凭据'],
      ['mcpStartFailed', '远端 MCP 进程启动失败与排障'],
      ['mcpGlobalOverride', '全局 MCP 在本机的路径重映射与禁用']
    ]
  },
  serverExtensions: {
    label: '服务器扩展配置中心',
    states: [
      ['extEnv', '远端 Shell 采集、自定义环境变量与工具链'],
      ['extLspSkills', '远端 LSP 语言服务监督与共享技能目录'],
      ['extWorkspacePolicy', '关联项目、Git 工作树、端口转发与资源预算']
    ]
  }
};

const allSteps = Object.entries(groups).flatMap(([type, g]) => g.states.map(([s, label]) => ({ type, scenario: s, label })));
const totalScenarios = allSteps.length;

const mcpPresets = [
  { key: 'postgres', name: '远端 PostgreSQL 数据库', icon: 'database', transport: 'stdio', id: 'postgres_prod', command: 'uvx', args: 'mcp-server-postgres postgresql://127.0.0.1:5432/ml_platform', cwd: '/srv/ml-platform', env: 'PGPASSWORD=••••••••, PGSSLMODE=prefer', desc: '通过远端辅助进程直连服务器本机或内网 PostgreSQL，无需暴露数据库公网端口' },
  { key: 'docker', name: '远端 Docker 容器与镜像', icon: 'container', transport: 'stdio', id: 'docker_engine', command: 'uvx', args: 'mcp-server-docker --socket unix:///var/run/docker.sock', cwd: '/home/ubuntu', env: 'DOCKER_API_VERSION=1.45', desc: '在远端服务器直接查询容器状态、构建日志与 GPU 容器资源占用' },
  { key: 'filesystem', name: '远端受限目录访问', icon: 'folder-tree', transport: 'stdio', id: 'remote_dataset_fs', command: 'npx', args: '-y @modelcontextprotocol/server-filesystem /data/shared-datasets', cwd: '/data/shared-datasets', env: '', desc: '挂载工作区以外的远端只读数据集或共享归档目录供模型按需检索' },
  { key: 'git', name: '远端 Git 仓库深度审计', icon: 'git-branch', transport: 'stdio', id: 'git_monorepo', command: 'uvx', args: 'mcp-server-git --repository /home/ubuntu/pure-lang', cwd: '/home/ubuntu/pure-lang', env: '', desc: '在远端大仓库上直接执行提交图谱、blame 与分支对比工具' },
  { key: 'prometheus', name: '远端 GPU / 集群监控网关', icon: 'activity', transport: 'streamableHttp', id: 'dcgm_metrics_http', endpoint: 'http://127.0.0.1:9400/mcp', bearerEnv: 'PROMETHEUS_MCP_TOKEN', headers: 'X-Cluster-Region: cn-north-gpu', desc: '连接服务器内网 Streamable HTTP 端点，实时读取 NVIDIA DCGM 与节点指标' },
  { key: 'custom', name: '自定义远端 MCP 服务', icon: 'terminal', transport: 'stdio', id: 'custom_remote_mcp', command: '/opt/mcp/bin/server', args: '--stdio --config /etc/mcp/config.toml', cwd: '/home/ubuntu', env: 'RUST_LOG=info', desc: '手动指定远端可执行文件或内网 Streamable HTTP 地址' }
];

const initialServers = [
  {
    alias: 'gpu-a100-prod',
    hostName: '10.24.8.102',
    port: 22,
    username: 'ubuntu',
    identityFile: '~/.ssh/id_ed25519_gpu',
    hasPassword: false,
    managed: true,
    roleTag: 'GPU 训练与推理节点',
    icon: 'cpu',
    state: 'ready',
    arch: 'x86_64-unknown-linux-musl',
    osInfo: 'Ubuntu 24.04.1 LTS (Linux 6.8.0-45)',
    hardware: '2 × NVIDIA A100 80GB · 128 GB RAM',
    helperVersion: 'v10 (sha256:8f3a…c91b)',
    shell: '/bin/bash (登录环境已采集)',
    leaseInfo: '心跳 5s · 租约 30s · HTTP/2 流控正常',
    budgetUsed: '42 MB',
    budgetLimit: '512 MB (自动 cgroup 预算)',
    projects: [
      { name: 'pure-lang', path: '/home/ubuntu/pure-lang', worktrees: 1, branch: 'main' },
      { name: 'llm-eval-harness', path: '/data/llm-eval-harness', worktrees: 0, branch: 'feat/v10-bench' }
    ],
    envVars: [
      { key: 'CUDA_VISIBLE_DEVICES', value: '0,1', scope: 'exec / MCP / LSP', secret: false },
      { key: 'HF_ENDPOINT', value: 'https://hf-mirror.com', scope: 'exec / MCP', secret: false },
      { key: 'RUSTUP_DIST_SERVER', value: 'https://rsproxy.cn', scope: 'exec / LSP', secret: false },
      { key: 'INTERNAL_REGISTRY_TOKEN', value: 'glpat-••••••••92a1', scope: '仅远端 MCP', secret: true }
    ],
    toolchains: [
      { tool: 'git', detected: '/usr/bin/git (2.43.0)', override: '' },
      { tool: 'node / npx', detected: '/home/ubuntu/.nvm/versions/node/v22.9.0/bin/npx', override: '/home/ubuntu/.nvm/versions/node/v22.9.0/bin' },
      { tool: 'python3 / uvx', detected: '/home/ubuntu/.local/bin/uvx (0.4.18)', override: '' },
      { tool: 'cargo / rustc', detected: '/home/ubuntu/.cargo/bin/cargo (1.84.0)', override: '' }
    ],
    lspServers: [
      { id: 'rust-analyzer', name: 'rust-analyzer', lang: 'rust', state: 'available', detail: '已就绪 · 0 诊断 · 索引完成 (pure-lang)', binary: '/home/ubuntu/.cargo/bin/rust-analyzer' },
      { id: 'pyright', name: 'pyright-langserver', lang: 'python', state: 'available', detail: '已就绪 · 2 诊断 · 监听 /data/llm-eval-harness', binary: '/home/ubuntu/.local/bin/pyright-langserver' },
      { id: 'clangd', name: 'clangd', lang: 'c / cpp / cuda', state: 'checking', detail: '正在扫描 compile_commands.json · 74%', binary: '/usr/bin/clangd-18' }
    ],
    skillDirs: [
      { path: '<workspace>/.agents/skills', kind: '远端项目源（默认高优）', count: 6, status: '已合并' },
      { path: '/opt/ai-infra/shared-skills', kind: '服务器级共享只读技能源', count: 4, status: '已启用' },
      { path: '本地 ~/.agents/skills + 内置系统技能', kind: '本地只读源（跨端自动注入）', count: 11, status: '已合并' }
    ],
    portForwards: [
      { id: 'pf1', label: 'TensorBoard 监控面板', type: 'LocalForward', local: '127.0.0.1:6006', remote: '127.0.0.1:6006', active: true },
      { id: 'pf2', label: 'vLLM 内网推理网关', type: 'LocalForward', local: '127.0.0.1:8000', remote: '127.0.0.1:8000', active: true }
    ]
  },
  {
    alias: 'dev-arm64-ubuntu',
    hostName: 'arm-builder.internal.dev',
    port: 2222,
    username: 'zhourui',
    identityFile: '~/.ssh/id_ed25519',
    hasPassword: true,
    managed: true,
    roleTag: 'ARM64 交叉编译测试机',
    icon: 'server',
    state: 'ready',
    arch: 'aarch64-unknown-linux-musl',
    osInfo: 'Ubuntu 22.04.5 LTS (Linux 5.15.0-122-generic)',
    hardware: 'Kunpeng 920 16 vCPU · 32 GB RAM',
    helperVersion: 'v10 (sha256:4d19…e02a)',
    shell: '/bin/zsh (登录环境已采集)',
    leaseInfo: '心跳 5s · 租约 30s · HTTP/2 流控正常',
    budgetUsed: '18 MB',
    budgetLimit: '256 MB',
    projects: [
      { name: 'pl-remote-helper-musl', path: '/home/zhourui/pure-lang', worktrees: 2, branch: 'fix/arm64-stat' }
    ],
    envVars: [
      { key: 'CARGO_BUILD_TARGET', value: 'aarch64-unknown-linux-musl', scope: 'exec', secret: false }
    ],
    toolchains: [
      { tool: 'git', detected: '/usr/bin/git (2.34.1)', override: '' },
      { tool: 'cargo / rustc', detected: '/home/zhourui/.cargo/bin/cargo (1.84.0)', override: '' }
    ],
    lspServers: [
      { id: 'rust-analyzer', name: 'rust-analyzer', lang: 'rust', state: 'available', detail: '已就绪 · 0 诊断', binary: '/home/zhourui/.cargo/bin/rust-analyzer' }
    ],
    skillDirs: [
      { path: '<workspace>/.agents/skills', kind: '远端项目源', count: 6, status: '已合并' }
    ],
    portForwards: []
  },
  {
    alias: 'staging-k8s-node',
    hostName: '172.18.40.19',
    port: 22,
    username: 'ops',
    identityFile: '',
    hasPassword: true,
    managed: true,
    roleTag: '预发容器集群节点',
    icon: 'boxes',
    state: 'reconnecting',
    attempt: 3,
    delaySeconds: 4,
    arch: 'x86_64-unknown-linux-musl',
    osInfo: 'Debian GNU/Linux 12 (bookworm)',
    hardware: '8 vCPU · 16 GB RAM',
    helperVersion: 'v10 (sha256:8f3a…c91b)',
    shell: '/bin/bash',
    leaseInfo: '传输通道重连中 · 远端实例租约剩余 19s',
    budgetUsed: '12 MB',
    budgetLimit: '256 MB',
    projects: [
      { name: 'deploy-manifests', path: '/srv/k8s/manifests', worktrees: 0, branch: 'staging' }
    ],
    envVars: [],
    toolchains: [],
    lspServers: [],
    skillDirs: [],
    portForwards: []
  },
  {
    alias: 'corp-sec-gateway',
    hostName: 'sec-gw.corp.example.com',
    port: 22,
    username: 'developer',
    identityFile: '~/.ssh/id_rsa_legacy',
    hasPassword: false,
    managed: true,
    roleTag: '安全审计受限主机',
    icon: 'shield-alert',
    state: 'failed',
    errorCode: 'authenticationFailed',
    sshPasswordOffered: false,
    errorMessage: '该服务器未提供密码认证（Permission denied (publickey)），请配置有效 SSH 密钥或启动 ssh-agent。',
    arch: 'x86_64-unknown-linux-musl',
    osInfo: 'Rocky Linux 9.4',
    hardware: '4 vCPU · 8 GB RAM',
    helperVersion: '尚未握手',
    shell: '未采集',
    leaseInfo: '未建立连接',
    budgetUsed: '0 MB',
    budgetLimit: '256 MB',
    projects: [],
    envVars: [],
    toolchains: [],
    lspServers: [],
    skillDirs: [],
    portForwards: []
  },
  {
    alias: 'legacy-bastion-manual',
    hostName: 'jump.infra.example.org',
    port: 22022,
    username: 'zhourui',
    identityFile: '~/.ssh/id_ed25519_infra',
    hasPassword: false,
    managed: false,
    roleTag: '手写 ProxyJump 跳板配置',
    icon: 'lock',
    state: 'disconnected',
    arch: 'x86_64-unknown-linux-musl',
    osInfo: '按需连接后探测',
    hardware: '用户手写 ~/.ssh/config 条目',
    helperVersion: '按需部署 v10',
    shell: '按需采集',
    leaseInfo: '未连接（手写条目仅支持连接与浏览目录，不由 anywork 覆写配置块）',
    budgetUsed: '0 MB',
    budgetLimit: '自动',
    projects: [],
    envVars: [],
    toolchains: [],
    lspServers: [],
    skillDirs: [],
    portForwards: []
  }
];

const initialServerMcps = {
  'gpu-a100-prod': [
    {
      id: 'postgres_ml_meta',
      scope: 'server',
      enabled: true,
      transport: 'stdio',
      command: 'uvx',
      args: 'mcp-server-postgres postgresql://127.0.0.1:5432/ml_platform',
      cwd: '/srv/ml-platform',
      env: 'PGPASSWORD=••••••••, PGSSLMODE=prefer',
      state: 'available',
      checkedAt: '14:32:08',
      generation: 6,
      pid: 48291,
      tools: [
        { name: 'query', fullName: 'mcp__postgres_ml_meta__query', desc: '在远端 PostgreSQL 执行只读 SQL 查询并返回结构化行集' },
        { name: 'list_tables', fullName: 'mcp__postgres_ml_meta__list_tables', desc: '列出当前 schema 下的全部数据表与视图定义' },
        { name: 'describe_table', fullName: 'mcp__postgres_ml_meta__describe_table', desc: '读取指定数据表的列类型、索引与外键约束' },
        { name: 'explain_plan', fullName: 'mcp__postgres_ml_meta__explain_plan', desc: '分析查询执行计划与索引命中情况' }
      ]
    },
    {
      id: 'docker_gpu_runtime',
      scope: 'server',
      enabled: true,
      transport: 'stdio',
      command: 'uvx',
      args: 'mcp-server-docker --socket unix:///var/run/docker.sock',
      cwd: '/home/ubuntu',
      env: 'DOCKER_API_VERSION=1.45',
      state: 'available',
      checkedAt: '14:32:08',
      generation: 6,
      pid: 48304,
      tools: [
        { name: 'list_containers', fullName: 'mcp__docker_gpu_runtime__list_containers', desc: '列出远端主机运行中与已退出的容器实例' },
        { name: 'container_logs', fullName: 'mcp__docker_gpu_runtime__container_logs', desc: '按行数或时间范围抓取远端容器 stdout/stderr 日志' },
        { name: 'inspect_gpu_mounts', fullName: 'mcp__docker_gpu_runtime__inspect_gpu_mounts', desc: '核验容器的 NVIDIA Runtime 设备挂载与显存限制' }
      ]
    },
    {
      id: 'dcgm_cluster_metrics',
      scope: 'server',
      enabled: true,
      transport: 'streamableHttp',
      endpoint: 'http://127.0.0.1:9400/mcp',
      bearerEnv: 'PROMETHEUS_MCP_TOKEN',
      headers: 'X-Cluster-Region: cn-north-gpu',
      state: 'available',
      checkedAt: '14:32:10',
      generation: 4,
      tools: [
        { name: 'gpu_utilization', fullName: 'mcp__dcgm_cluster_metrics__gpu_utilization', desc: '读取各张 A100 GPU 的实时 SM 利用率、温度与显存水位' },
        { name: 'nccl_bandwidth', fullName: 'mcp__dcgm_cluster_metrics__nccl_bandwidth', desc: '查询多卡 NVLink 通信吞吐与异常重传计数' }
      ]
    },
    {
      id: 'github_enterprise_audit',
      scope: 'server',
      enabled: true,
      transport: 'stdio',
      command: 'npx',
      args: '-y @modelcontextprotocol/server-github',
      cwd: '/home/ubuntu/pure-lang',
      env: 'GITHUB_PERSONAL_ACCESS_TOKEN=',
      state: 'missingCredential',
      errorMessage: '缺少必需凭据：远端环境变量 GITHUB_PERSONAL_ACCESS_TOKEN 为空，暂不发起进程连接。',
      checkedAt: '14:31:50',
      generation: 2,
      tools: []
    },
    {
      id: 'legacy_redis_inspector',
      scope: 'server',
      enabled: false,
      transport: 'stdio',
      command: 'uvx',
      args: 'mcp-server-redis redis://127.0.0.1:6379/0',
      cwd: '/home/ubuntu',
      env: '',
      state: 'disabled',
      checkedAt: '13:10:00',
      generation: 1,
      tools: []
    }
  ],
  'dev-arm64-ubuntu': [
    {
      id: 'arm64_cross_fs',
      scope: 'server',
      enabled: true,
      transport: 'stdio',
      command: 'npx',
      args: '-y @modelcontextprotocol/server-filesystem /opt/musl-toolchains',
      cwd: '/home/zhourui',
      env: '',
      state: 'available',
      checkedAt: '14:28:15',
      generation: 3,
      pid: 19042,
      tools: [
        { name: 'read_file', fullName: 'mcp__arm64_cross_fs__read_file', desc: '读取远端交叉编译工具链头文件与链接脚本' },
        { name: 'list_directory', fullName: 'mcp__arm64_cross_fs__list_directory', desc: '列出工具链 sysroot 目录结构' }
      ]
    }
  ]
};

const globalMcpOverrides = [
  { id: 'zhipu_search', transport: 'streamableHttp', source: '内置 (Zhipu Coding Plan)', globalState: '已启用', policy: 'inherit', effective: '跟随全局启用 · 复用本地已验证令牌' },
  { id: 'zhipu_reader', transport: 'streamableHttp', source: '内置 (Zhipu Coding Plan)', globalState: '已启用', policy: 'inherit', effective: '跟随全局启用 · 复用本地已验证令牌' },
  { id: 'filesystem', transport: 'stdio', source: '全局 config.toml (D:/workspace)', globalState: '已启用', policy: 'remap', remapNote: '远端路径重映射为 /data/shared-datasets', effective: '在此服务器按重映射路径运行' },
  { id: 'windows_local_automation', transport: 'stdio', source: '全局 config.toml (powershell.exe)', globalState: '已启用', policy: 'disable', effective: '在此 Linux 服务器显式禁用（避免平台命令报错）' }
];

const remoteDirTree = {
  '/home/ubuntu': {
    parent: '/home',
    entries: [
      { name: 'pure-lang', path: '/home/ubuntu/pure-lang', note: 'Git 仓库 · main' },
      { name: 'workspace-models', path: '/home/ubuntu/workspace-models', note: '目录' },
      { name: 'scripts', path: '/home/ubuntu/scripts', note: '目录' },
      { name: '.anywork', path: '/home/ubuntu/.anywork', note: '受管辅助进程与工作树缓冲' }
    ]
  },
  '/home/ubuntu/pure-lang': {
    parent: '/home/ubuntu',
    entries: [
      { name: 'code', path: '/home/ubuntu/pure-lang/code', note: 'Rust & Flutter 源码' },
      { name: 'design', path: '/home/ubuntu/pure-lang/design', note: '架构契约与原型' },
      { name: 'scripts', path: '/home/ubuntu/pure-lang/scripts', note: '工程脚本' }
    ]
  },
  '/data': {
    parent: '/',
    entries: [
      { name: 'llm-eval-harness', path: '/data/llm-eval-harness', note: 'Git 仓库 · feat/v10-bench' },
      { name: 'shared-datasets', path: '/data/shared-datasets', note: '只读数据集挂载点' }
    ]
  },
  '/home': {
    parent: '/',
    entries: [
      { name: 'ubuntu', path: '/home/ubuntu', note: '用户主目录' },
      { name: 'zhourui', path: '/home/zhourui', note: '用户主目录' }
    ]
  }
};

const urlParams = new URLSearchParams(location.search);
const mountPage = document.getElementById('aw-preview-mount').dataset.page || 'list';
const initPage = ['list', 'add', 'detail', 'mcp'].includes(urlParams.get('page')) ? urlParams.get('page') : mountPage;

let state = {
  type: 'overview',
  scenario: 'normal',
  page: initPage,
  selectedServer: urlParams.get('server') || 'gpu-a100-prod',
  detailTab: urlParams.get('tab') || 'overview',
  search: '',
  listFilter: 'all',
  mcpSearch: '',
  mcpFilter: 'all',
  mcpCreatorOpen: false,
  mcpEditingId: null,
  mcpPreset: 'postgres',
  mcpForm: {
    id: 'postgres_prod',
    transport: 'stdio',
    command: 'uvx',
    args: 'mcp-server-postgres postgresql://127.0.0.1:5432/ml_platform',
    cwd: '/srv/ml-platform',
    env: 'PGPASSWORD=••••••••, PGSSLMODE=prefer',
    endpoint: 'http://127.0.0.1:9400/mcp',
    bearerEnv: 'PROMETHEUS_MCP_TOKEN',
    headers: 'X-Cluster-Region: cn-north-gpu'
  },
  expandedMcps: ['postgres_ml_meta'],
  servers: JSON.parse(JSON.stringify(initialServers)),
  serverMcps: JSON.parse(JSON.stringify(initialServerMcps)),
  globalOverrides: JSON.parse(JSON.stringify(globalMcpOverrides)),
  addPreset: 'gpu',
  addForm: {
    alias: 'gpu-h100-cluster',
    hostName: '10.24.12.88',
    port: '22',
    username: 'ubuntu',
    identityFile: '~/.ssh/id_ed25519_gpu',
    password: '',
    initDefaultMcp: true,
    openDetailAfterSave: true
  },
  dirBrowsePath: '/home/ubuntu'
};

if (urlParams.get('scenario')) {
  const sc = urlParams.get('scenario');
  const found = allSteps.find(x => x.scenario === sc);
  if (found) {
    state.type = found.type;
    state.scenario = found.scenario;
  }
}

function currentServer() {
  return state.servers.find(s => s.alias === state.selectedServer) || state.servers[0];
}

function serverMcpsList(alias) {
  const list = state.serverMcps[alias] || [];
  if (state.type === 'serverMcp' && state.scenario === 'mcpStartFailed' && alias === 'gpu-a100-prod') {
    return list.map(m => m.id === 'docker_gpu_runtime' ? {
      ...m,
      state: 'unavailable',
      errorMessage: '进程启动失败 (exit code 127)：远端 PATH (/usr/local/bin:/usr/bin) 中未找到 uvx，请在「环境与工具链」中配置 uvx 路径或修正启动命令。'
    } : m);
  }
  return list;
}

function effectiveServerState(s) {
  if (s.alias === state.selectedServer && state.type === 'connection') {
    if (state.scenario === 'connecting') return 'connecting';
    if (state.scenario === 'reconnecting') return 'reconnecting';
    if (state.scenario === 'passwordPrompt') return 'waitingForInput';
    if (state.scenario === 'pubkeyOnlyError') return 'failed';
    if (state.scenario === 'ready') return 'ready';
  }
  return s.state;
}

function connStatusBadge(s) {
  const st = effectiveServerState(s);
  if (st === 'ready') return status('已连接', 'success', 'check-circle-2');
  if (st === 'connecting') return status('正在部署助手 68%', 'info', 'loader');
  if (st === 'reconnecting') return status(`重新连接中 · 第 ${s.attempt || 3} 次`, 'warning', 'refresh-cw');
  if (st === 'waitingForInput') return status('等待密码输入', 'warning', 'key-round');
  if (st === 'failed') return status('连接失败', 'error', 'circle-alert');
  return status('未连接', 'neutral', 'circle-dot');
}

function dotTone(s) {
  const st = effectiveServerState(s);
  if (st === 'ready') return 'ready';
  if (st === 'connecting') return 'connecting';
  if (st === 'reconnecting' || st === 'waitingForInput') return 'warning';
  if (st === 'failed') return 'error';
  return '';
}

function mcpStateBadge(m) {
  if (!m.enabled || m.state === 'disabled') return status('已停用', 'neutral', 'circle-pause');
  if (m.state === 'available') return status(`可用 · ${m.tools?.length || 0} 个工具`, 'success', 'check');
  if (m.state === 'checking') return status('正在探测…', 'info', 'loader');
  if (m.state === 'missingCredential') return status('缺少凭据', 'warning', 'key-round');
  return status('不可用 · 启动失败', 'error', 'circle-alert');
}

function hydrateIcons() {
  $$('mdui-select').forEach(select => {
    if (!select.querySelector('[slot=end-icon]')) {
      select.insertAdjacentHTML('beforeend', icon('chevron-down', 'end-icon'));
    }
  });
  if (globalThis.lucide) lucide.createIcons({ attrs: { width: 18, height: 18 } });
}

function toast(msg) {
  const sb = $('#aw-snackbar');
  if (!sb) return;
  sb.textContent = msg;
  sb.open = true;
}

let dialogSaveHandler = null;
function openDialog(title, htmlContent, onSave, saveText = '保存', hideCancel = false) {
  const dlg = $('#aw-dialog');
  dlg.headline = title;
  $('#aw-dialog-content').innerHTML = htmlContent;
  const cancelBtn = $('#aw-dialog-cancel');
  const saveBtn = $('#aw-dialog-save');
  cancelBtn.hidden = hideCancel;
  saveBtn.textContent = saveText;
  dialogSaveHandler = onSave;
  dlg.open = true;
  hydrateIcons();
}

/* ---------------- VIEW 1: SERVER LIST ---------------- */
function serverRowMarkup(s) {
  const st = effectiveServerState(s);
  const mcps = serverMcpsList(s.alias);
  const enabledMcps = mcps.filter(m => m.enabled);
  const availMcps = enabledMcps.filter(m => m.state === 'available');
  const totalTools = availMcps.reduce((acc, m) => acc + (m.tools?.length || 0), 0);
  const banner = st === 'failed' || (s.alias === state.selectedServer && state.scenario === 'pubkeyOnlyError')
    ? `<div class="aw-server-row-banner error"><div class="aw-row">${icon('circle-alert')}<span>${escapeHTML(s.errorMessage || '该服务器未提供密码认证（Permission denied (publickey)），请配置 SSH 密钥或启动 ssh-agent。')}</span></div><div class="aw-row">${btn('配置私钥','editServerConn','text','key-round',`data-server="${s.alias}"`)}${btn('重试连接','testServer','tonal','refresh-cw',`data-server="${s.alias}"`)}</div></div>`
    : st === 'waitingForInput'
    ? `<div class="aw-server-row-banner warning"><div class="aw-row">${icon('key-round')}<span>免密探测（BatchMode=yes）未通过，服务端公布了 password 认证方式，需要输入密码。</span></div>${btn('输入 SSH 密码','promptPassword','filled','log-in',`data-server="${s.alias}"`)}</div>`
    : st === 'connecting'
    ? `<div class="aw-server-row-banner info"><div style="flex:1"><div class="aw-between" style="margin-bottom:6px"><span>正在通过受控通道幂等上传 <code>pl-remote-helper.zst</code> 至 <code>$HOME/.anywork/remote-helper/v10/</code>…</span><span class="aw-mono">68% · 校验 SHA-256</span></div><mdui-linear-progress value="0.68"></mdui-linear-progress></div></div>`
    : '';

  return `<article class="aw-server-row" data-server-row="${escapeHTML(s.alias)}">
    <div class="aw-server-row-main aw-server-grid">
      <button type="button" class="aw-server-open" data-action="openDetail" data-server="${escapeHTML(s.alias)}" aria-label="查看服务器 ${escapeHTML(s.alias)} 配置详情">
        <span class="aw-logo">${icon(s.icon || 'server')}<span class="aw-logo-dot ${dotTone(s)}"></span></span>
        <div style="min-width:0">
          <div class="aw-row" style="gap:6px">
            <span class="aw-server-alias">${escapeHTML(s.alias)}</span>
            ${s.managed ? chip('受管块') : `<span class="aw-mini-pill">${icon('lock')}手写只读</span>`}
          </div>
          <div class="aw-server-target">${escapeHTML(s.username)}@${escapeHTML(s.hostName)}:${s.port}</div>
          <div class="aw-server-auth-meta">
            ${s.identityFile ? `<span class="aw-mini-pill">${icon('key-round')}密钥：<code>${escapeHTML(s.identityFile)}</code></span>` : `<span class="aw-mini-pill">${icon('shield')}ssh-agent 免密探测</span>`}
            ${s.hasPassword ? `<span class="aw-mini-pill">${icon('lock-keyhole')}已存系统凭据库密码</span>` : ''}
          </div>
        </div>
      </button>

      <div class="aw-conn-col">
        ${connStatusBadge(s)}
        <span class="aw-conn-sub">
          ${st === 'ready' ? `${escapeHTML(s.arch.split('-')[0])} · 远程助手 ${escapeHTML(s.helperVersion.split(' ')[0])}`
            : st === 'reconnecting' ? `退避 ${s.delaySeconds || 4}s · 30s 租约保护中`
            : !s.managed ? '手写条目 · 直接编辑 ~/.ssh/config'
            : 'OpenSSH 与远程助手由本机统一管理'}
        </span>
      </div>

      <div class="aw-cap-col">
        <div class="aw-cap-badges">
          <button type="button" class="aw-mini-pill interactive" data-action="openServerMcp" data-server="${escapeHTML(s.alias)}" title="进入该服务器的专属 MCP 服务管理页">
            ${icon('network')}<strong>远端 MCP ${enabledMcps.length}</strong>${totalTools ? ` (${totalTools} 工具)` : ''}
          </button>
          <button type="button" class="aw-mini-pill interactive" data-action="openDetailTab" data-server="${escapeHTML(s.alias)}" data-tab="env" title="配置远端环境变量与工具链">
            ${icon('terminal')}环境变量 ${s.envVars.length}
          </button>
          <button type="button" class="aw-mini-pill interactive" data-action="openDetailTab" data-server="${escapeHTML(s.alias)}" data-tab="lsp" title="查看远端 LSP 与技能源">
            ${icon('code')}LSP ${s.lspServers.length}
          </button>
          ${s.projects.length ? `<span class="aw-mini-pill">${icon('folder-git-2')}${s.projects.length} 个项目</span>` : ''}
        </div>
        <span class="aw-conn-sub">${escapeHTML(s.roleTag)} · ${escapeHTML(s.osInfo)}</span>
      </div>

      <div class="aw-row-actions">
        ${btn('MCP 管理', 'openServerMcp', 'tonal', 'network', `data-server="${escapeHTML(s.alias)}"`)}
        ${btn('打开项目', 'browseRemoteDir', 'text', 'folder-open', `data-server="${escapeHTML(s.alias)}"`)}
        ${iconBtn('重新连接（加载最新远端环境）', 'reconnectServer', 'refresh-cw', `data-server="${escapeHTML(s.alias)}"`)}
        <mdui-dropdown placement="bottom-end">
          <mdui-button-icon slot="trigger" aria-label="${escapeHTML(s.alias)}更多操作">${icon('ellipsis')}</mdui-button-icon>
          <mdui-menu>
            <mdui-menu-item data-action="openDetail" data-server="${escapeHTML(s.alias)}">${icon('sliders-horizontal', 'icon')}服务器配置中心</mdui-menu-item>
            <mdui-menu-item data-action="openServerMcp" data-server="${escapeHTML(s.alias)}">${icon('network', 'icon')}管理服务器专属 MCP</mdui-menu-item>
            <mdui-menu-item data-action="testServer" data-server="${escapeHTML(s.alias)}">${icon('cable', 'icon')}测试连接</mdui-menu-item>
            <mdui-menu-item data-action="viewSshConfigBlock" data-server="${escapeHTML(s.alias)}">${icon('file-code', 'icon')}查看 ~/.ssh/config 块</mdui-menu-item>
            <mdui-divider></mdui-divider>
            <mdui-menu-item data-action="editServerConn" data-server="${escapeHTML(s.alias)}" ${!s.managed ? 'disabled' : ''}>${icon('pencil', 'icon')}${s.managed ? '编辑连接与凭据' : '手写条目不可编辑'}</mdui-menu-item>
            <mdui-menu-item data-action="deleteServer" data-server="${escapeHTML(s.alias)}" ${!s.managed ? 'disabled' : ''} style="color:rgb(var(--mdui-color-error))">${icon('trash-2', 'icon')}删除服务器</mdui-menu-item>
          </mdui-menu>
        </mdui-dropdown>
      </div>
    </div>
    ${banner}
  </article>`;
}

function listMarkup() {
  const emptyScenario = state.type === 'overview' && state.scenario === 'empty';
  const q = state.search.trim().toLowerCase();
  let list = emptyScenario ? [] : state.servers.filter(s => {
    if (state.listFilter === 'ready' && effectiveServerState(s) !== 'ready') return false;
    if (state.listFilter === 'issue' && !['reconnecting', 'failed', 'waitingForInput'].includes(effectiveServerState(s))) return false;
    if (state.listFilter === 'readonly' && s.managed) return false;
    if (!q) return true;
    return [s.alias, s.hostName, s.username, s.roleTag, s.osInfo].some(v => v.toLowerCase().includes(q));
  });

  const readyCount = state.servers.filter(s => effectiveServerState(s) === 'ready').length;
  const totalRemoteMcps = Object.values(state.serverMcps).reduce((n, arr) => n + arr.filter(x => x.enabled).length, 0);

  return `<div class="aw-page-header">
    <div>
      <div class="aw-row">${iconBtn('设置导航', 'mobileNav', 'menu', 'class="aw-menu-mobile"')}<h1>远程开发 (SSH)</h1></div>
      <p class="aw-page-subtitle">服务器列表直接同步自你的 <code>~/.ssh/config</code>；点击任一服务器可进入其专属的<strong>远端 MCP 服务管理</strong>、环境变量、LSP 与工作区策略中心。</p>
    </div>
    <div class="aw-row">
      ${btn('测试全部连接', 'testAllServers', 'tonal', 'cable')}
      ${btn('打开远端项目…', 'browseRemoteDir', 'outlined', 'folder-open', `data-server="${escapeHTML(state.selectedServer)}"`)}
      ${btn('添加服务器', 'goAddServer', 'filled', 'plus')}
    </div>
  </div>

  <mdui-card variant="filled" class="aw-telemetry-card">
    <div class="aw-telemetry-grid">
      <div class="aw-telemetry-item">
        <span class="aw-telemetry-label">${icon('server')}~/.ssh/config 主机总数</span>
        <div class="aw-telemetry-val">${emptyScenario ? 0 : state.servers.length} 台服务器</div>
        <span class="aw-telemetry-sub">${state.servers.filter(s => s.managed).length} 台 anywork 受管 · ${state.servers.filter(s => !s.managed).length} 台手写只读</span>
      </div>
      <div class="aw-telemetry-item">
        <span class="aw-telemetry-label">${icon('cpu')}活跃远端辅助进程 (v10)</span>
        <div class="aw-telemetry-val">${emptyScenario ? 0 : readyCount} 个实例在线</div>
        <span class="aw-telemetry-sub">HTTP/2 单条 stdio 多路复用 · 30s 租约</span>
      </div>
      <div class="aw-telemetry-item">
        <span class="aw-telemetry-label">${icon('network')}服务器专属 MCP 服务</span>
        <div class="aw-telemetry-val">${emptyScenario ? 0 : totalRemoteMcps} 个远端服务已启用</div>
        <span class="aw-telemetry-sub">支持按服务器独立创建、启停与重映射</span>
      </div>
      <div class="aw-telemetry-item">
        <span class="aw-telemetry-label">${icon('shield-check')}凭据与工作区隔离边界</span>
        <div class="aw-telemetry-val">系统凭据库 + 受限目录</div>
        <span class="aw-telemetry-sub">密码绝不落盘 config · POSIX 路径单点归一化</span>
      </div>
    </div>
  </mdui-card>

  <div class="aw-tools">
    <div class="aw-row" style="flex:1">
      <mdui-text-field id="aw-ssh-search" class="aw-search" variant="outlined" placeholder="搜索 Host 别名、IP、用户名或用途…" value="${escapeHTML(state.search)}" clearable>${icon('search', 'icon')}</mdui-text-field>
      <div class="aw-row" role="group" aria-label="筛选服务器状态">
        ${[['all', `全部 ${state.servers.length}`], ['ready', `已连接 ${readyCount}`], ['issue', '重连/需认证 2'], ['readonly', '手写只读 1']].map(([k, label]) =>
          `<mdui-chip selectable ${state.listFilter === k ? 'selected' : ''} data-action="filterServerList" data-filter="${k}">${label}</mdui-chip>`
        ).join('')}
      </div>
    </div>
    <div class="aw-tools-meta">点击服务器名称进入多维配置 · 点击「MCP 管理」直达该机 MCP 维护页</div>
  </div>

  <mdui-card variant="outlined" class="aw-server-card">
    <div class="aw-table-head aw-server-grid">
      <span>服务器身份 (~/.ssh/config)</span>
      <span>连接与远程助手</span>
      <span>服务器专属配置 (MCP / 环境 / LSP / 项目)</span>
      <span style="text-align:right">操作</span>
    </div>
    ${emptyScenario ? `<div class="aw-empty">
      ${icon('server')}
      <h2>尚未配置 SSH 服务器</h2>
      <p>OpenSSH 与轻量远程助手由本机统一管理。添加第一台远程服务器后，即可在远端打开项目并配置服务器专属的 MCP 服务与工具链。</p>
      ${btn('添加第一台服务器', 'goAddServer', 'filled', 'plus')}
    </div>` : !list.length ? `<div class="aw-empty">
      ${icon('search')}
      <h2>没有找到匹配的 SSH 服务器</h2>
      <p>试试其他搜索词，或切换筛选条件查看全部主机。</p>
      ${btn('清除筛选条件', 'clearServerSearch', 'tonal', 'rotate-ccw')}
    </div>` : list.map(serverRowMarkup).join('')}
  </mdui-card>`;
}

/* ---------------- VIEW 2: ADD SERVER ---------------- */
function sshConfigBlockText(f) {
  const alias = (f.alias || 'my-remote-server').trim();
  const host = (f.hostName || '192.168.1.10').trim();
  const port = (f.port || '22').trim();
  const user = (f.username || 'ubuntu').trim();
  const idFile = (f.identityFile || '').trim();
  return `<span class="aw-comment"># BEGIN anywork server: ${escapeHTML(alias)}</span>
Host ${escapeHTML(alias)}
    HostName ${escapeHTML(host)}
    Port ${escapeHTML(port)}
    User ${escapeHTML(user)}${idFile ? `\n    IdentityFile ${escapeHTML(idFile)}` : ''}
<span class="aw-comment"># END anywork server: ${escapeHTML(alias)}</span>`;
}

function addMarkup() {
  const f = state.addForm;
  const presets = [
    { key: 'gpu', title: 'GPU 训练与推理节点', sub: '预填 CUDA 环境变量与数据库/容器 MCP 模板', ico: 'cpu' },
    { key: 'linux', title: '标准 Linux 开发主机', sub: 'OpenSSH 免密优先探测 · 自动部署 musl 远程助手', ico: 'terminal' },
    { key: 'bastion', title: '企业内网 / 容器开发节点', sub: '支持配合 ~/.ssh/config 的 ProxyJump 跳转规则', ico: 'shield' }
  ];
  return `<div class="aw-topbar">
    <mdui-button variant="text" data-action="goList" class="aw-back">${icon('arrow-left', 'icon')}返回服务器列表</mdui-button>
    ${iconBtn('设置导航', 'mobileNav', 'menu', 'class="aw-menu-mobile"')}
  </div>
  <div class="aw-page-header">
    <div>
      <h1>添加 SSH 远程服务器</h1>
      <p class="aw-page-subtitle">以带标记的受管块原子写回 <code>~/.ssh/config</code>（原样保留文件中的其他手写配置与注释），并在创建后可直接配置该服务器的远端 MCP 服务与工具链。</p>
    </div>
  </div>

  <mdui-card variant="outlined" class="aw-setting-card" style="padding:20px 22px;margin-bottom:16px">
    <h3>1. 选择服务器场景预设</h3>
    <p class="aw-section-caption">选择预设可自动推荐合适的远端环境变量与常用服务器 MCP 服务组合</p>
    <div class="aw-preset-grid">
      ${presets.map(p => `<button type="button" class="aw-preset-btn ${state.addPreset === p.key ? 'selected' : ''}" data-action="pickAddPreset" data-preset="${p.key}">
        ${icon(p.ico)}
        <div><strong>${p.title}</strong><small>${p.sub}</small></div>
      </button>`).join('')}
    </div>

    <h3 style="margin-top:18px;margin-bottom:10px">2. 基础连接与 Host 身份</h3>
    <div class="aw-form-stack">
      <div class="aw-form-grid-2">
        <mdui-text-field id="aw-add-alias" label="别名 (Host)" value="${escapeHTML(f.alias)}" helper="写入 ~/.ssh/config 的唯一标识（不含空格或通配符，创建后不可改名）" variant="outlined" required>${icon('badge', 'icon')}</mdui-text-field>
        <mdui-text-field id="aw-add-host" label="主机地址 (HostName)" value="${escapeHTML(f.hostName)}" placeholder="192.168.1.10 / dev.example.com" helper="IP 地址或域名；若存在跳板机可在 ~/.ssh/config 配合 ProxyJump" variant="outlined" required>${icon('server', 'icon')}</mdui-text-field>
      </div>
      <div class="aw-form-grid-3">
        <mdui-text-field id="aw-add-user" label="用户名 (User)" value="${escapeHTML(f.username)}" variant="outlined" required>${icon('user', 'icon')}</mdui-text-field>
        <mdui-text-field id="aw-add-identity" label="私钥文件路径 (IdentityFile，可选)" value="${escapeHTML(f.identityFile)}" helper="留空时默认通过 ssh-agent 与默认密钥执行免密探测" variant="outlined">${icon('key-round', 'icon')}</mdui-text-field>
        <mdui-text-field id="aw-add-port" label="端口 (Port)" value="${escapeHTML(f.port)}" type="number" min="1" max="65535" variant="outlined"></mdui-text-field>
      </div>
      <div class="aw-form-grid-2">
        <mdui-text-field id="aw-add-password" label="SSH 密码（可选，存入系统凭据库）" type="password" value="${escapeHTML(f.password)}" placeholder="留空则优先使用公钥 / 连接时按需输入" helper="保存在操作系统凭据库 (ssh:<alias>)，绝不写入 ~/.ssh/config、SQLite 或日志" variant="outlined">${icon('lock-keyhole', 'icon')}</mdui-text-field>
        <div>
          <small style="display:block;margin-bottom:4px;font-weight:600">将写入 ~/.ssh/config 的受管标记块预览：</small>
          <div class="aw-code-preview" id="aw-ssh-block-preview">${sshConfigBlockText(f)}</div>
        </div>
      </div>
    </div>
  </mdui-card>

  <mdui-card variant="outlined" class="aw-setting-card" style="padding:18px 22px">
    <h3>3. 创建后初始化服务器专属能力</h3>
    <div class="aw-between" style="margin-top:12px;padding:10px 14px;border-radius:10px;background:rgb(var(--mdui-color-surface-container-low))">
      <div>
        <strong style="font-size:13px;display:block">预置常用远端 MCP 服务模板（PostgreSQL / Docker / 远端 Git）</strong>
        <small>创建服务器后自动初始化服务器专属 MCP 配置项，可在「服务器 MCP 专页」随时启停、修改或删除</small>
      </div>
      <mdui-switch id="aw-add-init-mcp" ${f.initDefaultMcp ? 'checked' : ''} aria-label="预置常用远端 MCP 服务"></mdui-switch>
    </div>
    <div class="aw-between" style="margin-top:16px;padding-top:14px;border-top:1px solid rgb(var(--mdui-color-outline-variant))">
      <span class="aw-muted" style="font-size:12px;display:inline-flex;align-items:center;gap:6px">${icon('shield-check')}每次连接固定优先以 <code>BatchMode=yes</code> 非交互探测免密，仅当免密失败且服务端支持密码时才触发密码认证</span>
      <div class="aw-row">
        ${btn('取消', 'goList', 'text')}
        ${btn('保存并进入服务器 MCP 配置', 'submitAddServer', 'filled', 'check')}
      </div>
    </div>
  </mdui-card>`;
}

/* ---------------- VIEW 3: DEDICATED SERVER MCP MANAGEMENT PAGE ---------------- */
function mcpEditorCardMarkup(s) {
  const f = state.mcpForm;
  const isEditing = Boolean(state.mcpEditingId);
  const cleanId = (f.id || 'my_mcp').replace(/[^a-zA-Z0-9_-]/g, '_');
  const validId = /^[a-zA-Z0-9_-]+$/.test(f.id || '');
  return `<div class="aw-editor-card" id="aw-mcp-editor-card">
    <div class="aw-between" style="margin-bottom:10px">
      <div>
        <div class="aw-row">
          <h2>${isEditing ? `编辑远端 MCP 服务：${escapeHTML(state.mcpEditingId)}` : `在服务器 ${escapeHTML(s.alias)} 上新建远端 MCP 服务`}</h2>
          ${status(isEditing ? '修改草稿' : '服务器专属作用域', 'info', 'server')}
        </div>
        <p class="aw-section-caption">stdio 类型的远端 MCP 由该服务器上的 <code>pl-remote-helper</code> 直接派生并监督子进程，工具经单条 HTTP/2 通道实时映射回本地会话。</p>
      </div>
      ${iconBtn('关闭编辑器', 'closeMcpCreator', 'x')}
    </div>

    ${!isEditing ? `<div>
      <small style="font-weight:600;display:block">快速选择远端 MCP 模板（点击自动填充下方参数）：</small>
      <div class="aw-preset-grid">
        ${mcpPresets.map(p => `<button type="button" class="aw-preset-btn ${state.mcpPreset === p.key ? 'selected' : ''}" data-action="pickMcpPreset" data-preset="${p.key}">
          ${icon(p.icon)}
          <div><strong>${escapeHTML(p.name)}</strong><small>${escapeHTML(p.desc)}</small></div>
        </button>`).join('')}
      </div>
    </div>` : ''}

    <div class="aw-form-stack">
      <div class="aw-form-grid-2">
        <mdui-text-field id="aw-mcp-id" label="服务 ID (server_id)" value="${escapeHTML(f.id)}" ${isEditing ? 'readonly' : ''} helper="${validId ? `模型可见工具前缀预览：mcp__${cleanId}__<tool_name>（最长 64 字符）` : '仅允许 ASCII 字母、数字、下划线 _ 与连字符 -'}" variant="outlined" required>${icon('hash', 'icon')}</mdui-text-field>
        <div>
          <small style="display:block;margin-bottom:6px;font-weight:600">传输方式 (Transport)</small>
          <mdui-segmented-button-group selects="single" value="${f.transport}" style="width:100%">
            <mdui-segmented-button value="stdio" data-action="setMcpTransport" data-transport="stdio">${icon('terminal', 'icon')}stdio（远端服务器进程）</mdui-segmented-button>
            <mdui-segmented-button value="streamableHttp" data-action="setMcpTransport" data-transport="streamableHttp">${icon('globe', 'icon')}Streamable HTTP（远端/内网端点）</mdui-segmented-button>
          </mdui-segmented-button-group>
        </div>
      </div>

      ${f.transport === 'stdio' ? `
        <div class="aw-form-grid-2">
          <mdui-text-field id="aw-mcp-cmd" label="远端启动命令 (command)" value="${escapeHTML(f.command)}" placeholder="uvx / npx / python3 / /opt/mcp/bin/server" helper="使用此服务器采集的登录 Shell PATH 或绝对路径" variant="outlined" required>${icon('play', 'icon')}</mdui-text-field>
          <mdui-text-field id="aw-mcp-cwd" label="远端工作目录 (cwd，POSIX 绝对路径)" value="${escapeHTML(f.cwd)}" placeholder="/home/ubuntu/workspace" helper="必须以 / 开头；留空默认使用远端用户主目录" variant="outlined">
            ${icon('folder', 'icon')}
            <mdui-button slot="end-icon" variant="text" data-action="browseMcpCwd" data-server="${escapeHTML(s.alias)}" style="height:28px;font-size:11px">浏览远端目录…</mdui-button>
          </mdui-text-field>
        </div>
        <div class="aw-form-grid-2">
          <mdui-text-field id="aw-mcp-args" label="命令参数 (args)" value="${escapeHTML(f.args)}" placeholder="-y @modelcontextprotocol/server-filesystem /data" helper="按空格或标准参数列表传递给远端 stdio 进程" variant="outlined">${icon('code', 'icon')}</mdui-text-field>
          <mdui-text-field id="aw-mcp-env" label="注入环境变量 (env 键值对，逗号分隔)" value="${escapeHTML(f.env)}" placeholder="PGPASSWORD=..., RUST_LOG=info" helper="敏感凭据存系统凭据库，按配置原样注入远端子进程" variant="outlined">${icon('key-round', 'icon')}</mdui-text-field>
        </div>
      ` : `
        <div class="aw-form-grid-2">
          <mdui-text-field id="aw-mcp-endpoint" label="远端或内网 HTTP 端点 (url)" value="${escapeHTML(f.endpoint)}" placeholder="http://127.0.0.1:9400/mcp" helper="由远端环境或可达内网提供的 Streamable HTTP 地址" variant="outlined" required>${icon('link', 'icon')}</mdui-text-field>
          <mdui-text-field id="aw-mcp-bearer" label="Bearer 令牌环境变量名 (bearer_token_env_var)" value="${escapeHTML(f.bearerEnv)}" placeholder="PROMETHEUS_MCP_TOKEN" helper="仅保存环境变量名，运行时读取并构造 Authorization 头" variant="outlined">${icon('shield', 'icon')}</mdui-text-field>
        </div>
        <mdui-text-field id="aw-mcp-headers" label="自定义请求头 (headers，可选)" value="${escapeHTML(f.headers)}" placeholder="X-Cluster-Region: cn-north-gpu" variant="outlined">${icon('sliders-horizontal', 'icon')}</mdui-text-field>
      `}

      <div class="aw-between" style="padding-top:10px;border-top:1px solid rgb(var(--mdui-color-outline-variant))">
        <small>${icon('info')} 保存后由 MCP 运行时增量协调（reconcile），正在执行的会话轮次继续持有原代次租约直至本轮结束。</small>
        <div class="aw-row">
          ${btn('取消', 'closeMcpCreator', 'text')}
          ${btn(isEditing ? '保存 MCP 修改' : '创建并启动探测', 'saveMcpForm', 'filled', 'check')}
        </div>
      </div>
    </div>
  </div>`;
}

function mcpItemMarkup(s, m) {
  const expanded = state.expandedMcps.includes(m.id) || (state.type === 'serverMcp' && state.scenario === 'mcpToolsExpanded');
  const isMissingCred = m.state === 'missingCredential' || (state.type === 'serverMcp' && state.scenario === 'mcpMissingCred' && m.id === 'github_enterprise_audit');
  const isFailed = m.state === 'unavailable';
  const summaryDesc = m.transport === 'stdio'
    ? `stdio · ${m.command} ${m.args} · cwd: ${m.cwd || '~'}`
    : `streamableHttp · ${m.endpoint}`;

  return `<mdui-collapse-item value="${escapeHTML(m.id)}" ${expanded ? 'data-expanded' : ''}>
    <mdui-list-item slot="header" class="aw-mcp-header" headline="${escapeHTML(m.id)}" description="${escapeHTML(summaryDesc)}">
      ${icon('chevron-right', 'icon')}
      <div slot="end-icon" class="aw-mcp-end-actions">
        ${chip(m.transport === 'stdio' ? 'stdio · 远端进程' : 'Streamable HTTP')}
        ${mcpStateBadge(m)}
        ${btn('重连', 'reconnectMcp', 'text', 'refresh-cw', `data-mcp="${escapeHTML(m.id)}" ${!m.enabled ? 'disabled' : ''}`)}
        ${iconBtn('编辑此 MCP 服务', 'editMcp', 'pencil', `data-mcp="${escapeHTML(m.id)}"`)}
        ${iconBtn('删除此 MCP 服务', 'deleteMcp', 'trash-2', `data-mcp="${escapeHTML(m.id)}" style="color:rgb(var(--mdui-color-error))"`)}
        <mdui-switch data-mcp-switch="${escapeHTML(m.id)}" ${m.enabled ? 'checked' : ''} aria-label="启用 ${escapeHTML(m.id)}"></mdui-switch>
      </div>
    </mdui-list-item>
    <div class="aw-mcp-body">
      ${isMissingCred ? notice(escapeHTML(m.errorMessage || '缺少凭据：环境变量未配置，服务暂未发起连接。'), 'warning', btn('立即补齐凭据', 'editMcp', 'tonal', 'key-round', `data-mcp="${escapeHTML(m.id)}"`)) : ''}
      ${isFailed ? notice(escapeHTML(m.errorMessage || '远端 MCP 进程启动失败，请检查命令路径或远端环境变量。'), 'error', `<div class="aw-row">${btn('修正命令', 'editMcp', 'tonal', 'pencil', `data-mcp="${escapeHTML(m.id)}"`)}${btn('重试连接', 'reconnectMcp', 'text', 'refresh-cw', `data-mcp="${escapeHTML(m.id)}"`)}</div>`) : ''}

      <div class="aw-mcp-config-grid">
        <div>
          <h4 style="margin:0 0 8px;font-size:12.5px">远端执行与传输参数</h4>
          <div class="aw-kv-list">
            <span class="aw-kv-key">归属服务器</span><code>${escapeHTML(s.alias)} (${escapeHTML(s.username)}@${escapeHTML(s.hostName)})</code>
            <span class="aw-kv-key">工具命名空间</span><code>mcp__${escapeHTML(m.id)}__*</code>
            ${m.transport === 'stdio' ? `
              <span class="aw-kv-key">启动命令</span><code>${escapeHTML(m.command)} ${escapeHTML(m.args)}</code>
              <span class="aw-kv-key">远端工作目录</span><code>${escapeHTML(m.cwd || '/home/' + s.username)}</code>
              <span class="aw-kv-key">环境变量</span><code>${escapeHTML(m.env || '继承远端登录 Shell 环境')}</code>
            ` : `
              <span class="aw-kv-key">HTTP 端点</span><code>${escapeHTML(m.endpoint)}</code>
              <span class="aw-kv-key">令牌变量</span><code>${escapeHTML(m.bearerEnv || '无')}</code>
              <span class="aw-kv-key">自定义头</span><code>${escapeHTML(m.headers || '无')}</code>
            `}
          </div>
        </div>
        <div>
          <h4 style="margin:0 0 8px;font-size:12.5px">运行健康度与租约维护</h4>
          <div class="aw-kv-list">
            <span class="aw-kv-key">当前状态</span><span>${m.enabled ? (m.state === 'available' ? '运行正常 · 已完成工具握手' : m.state === 'missingCredential' ? '等待凭据' : '启动异常') : '已手动停用'}</span>
            <span class="aw-kv-key">平滑代次</span><code>Generation #${m.generation || 1}（活跃轮次租约保护）</code>
            <span class="aw-kv-key">远端进程监督</span><code>${m.pid ? `PID ${m.pid} · pl-remote-helper 托管` : '无驻留子进程'}</code>
            <span class="aw-kv-key">最近探测</span><span>${escapeHTML(m.checkedAt || '刚刚')}</span>
          </div>
          <div class="aw-row" style="margin-top:10px">
            ${btn('编辑完整参数', 'editMcp', 'tonal', 'pencil', `data-mcp="${escapeHTML(m.id)}"`)}
            ${btn('重新握手探测', 'reconnectMcp', 'outlined', 'refresh-cw', `data-mcp="${escapeHTML(m.id)}"`)}
            ${btn('删除服务', 'deleteMcp', 'text', 'trash-2', `data-mcp="${escapeHTML(m.id)}" style="color:rgb(var(--mdui-color-error))"`)}
          </div>
        </div>
      </div>

      <div class="aw-tools-drawer">
        <div class="aw-tools-drawer-head">
          <strong>已注册并归一化的远端工具列表 (${m.tools?.length || 0})</strong>
          <span class="aw-muted">规范名上限 64 字符 · 点击可复制工具标识</span>
        </div>
        ${m.tools?.length ? `<div class="aw-tool-chips">
          ${m.tools.map(t => `<div class="aw-tool-item">
            <div class="aw-between">
              <code>${escapeHTML(t.fullName)}</code>
              <mdui-button-icon data-action="copyText" data-text="${escapeHTML(t.fullName)}" style="width:22px;height:22px" title="复制工具名">${icon('copy')}</mdui-button-icon>
            </div>
            <small>${escapeHTML(t.desc)}</small>
          </div>`).join('')}
        </div>` : `<small class="aw-muted">${m.enabled ? '当前服务尚未返回可用工具（请先解决凭据或连接问题后重新探测）。' : '服务已停用，启用后将自动握手并列出工具清单。'}</small>`}
      </div>
    </div>
  </mdui-collapse-item>`;
}

function mcpSectionBlock(s, standalonePage = false) {
  const allMcps = serverMcpsList(s.alias);
  const q = state.mcpSearch.trim().toLowerCase();
  const filtered = allMcps.filter(m => {
    if (state.mcpFilter === 'available' && (!m.enabled || m.state !== 'available')) return false;
    if (state.mcpFilter === 'issue' && !['missingCredential', 'unavailable'].includes(m.state)) return false;
    if (state.mcpFilter === 'disabled' && m.enabled) return false;
    if (!q) return true;
    return [m.id, m.command || '', m.args || '', m.endpoint || '', ...(m.tools || []).map(t => t.fullName)].some(x => x.toLowerCase().includes(q));
  });

  const enabledCount = allMcps.filter(m => m.enabled).length;
  const availCount = allMcps.filter(m => m.enabled && m.state === 'available').length;
  const totalTools = allMcps.filter(m => m.enabled && m.state === 'available').reduce((n, m) => n + (m.tools?.length || 0), 0);
  const showCreator = state.mcpCreatorOpen || (state.type === 'serverMcp' && state.scenario === 'mcpCreate');
  const allExpanded = filtered.length > 0 && filtered.every(m => state.expandedMcps.includes(m.id));

  return `
    <div class="aw-mcp-summary-grid">
      <mdui-card variant="outlined" class="aw-mcp-stat-card">
        <small class="aw-muted">本服务器专属 MCP 服务</small>
        <strong>${enabledCount} / ${allMcps.length} 已启用</strong>
        <small style="color:var(--aw-success)">${availCount} 个健康在线 · 独立于其他主机</small>
      </mdui-card>
      <mdui-card variant="outlined" class="aw-mcp-stat-card">
        <small class="aw-muted">已挂载远端 MCP 工具总数</small>
        <strong>${totalTools} 个工具</strong>
        <small>经 <code>pl-remote-helper</code> HTTP/2 通道实时代理</small>
      </mdui-card>
      <mdui-card variant="outlined" class="aw-mcp-stat-card">
        <small class="aw-muted">全局 MCP 在本机策略</small>
        <strong>${state.globalOverrides.filter(g => g.policy !== 'disable').length} 项生效 · 1 项禁用</strong>
        <small>支持按服务器覆盖路径或屏蔽不兼容本地服务</small>
      </mdui-card>
    </div>

    ${showCreator ? mcpEditorCardMarkup(s) : ''}

    <section class="aw-section">
      <div class="aw-section-heading">
        <div>
          <h2>服务器专属 MCP 服务列表 (${escapeHTML(s.alias)})</h2>
          <p class="aw-section-caption">在此创建的 MCP 服务绑定当前 SSH 服务器，在远端工作区会话中自动按 <code>mcp__{server_id}__{tool_name}</code> 注册工具。</p>
        </div>
        <div class="aw-row">
          ${filtered.length ? btn(allExpanded ? '收起全部详情' : '展开全部工具与详情', 'toggleExpandAllMcp', 'text', allExpanded ? 'chevrons-up' : 'chevrons-down') : ''}
          ${btn('刷新状态', 'refreshServerMcp', 'tonal', 'refresh-cw')}
          ${btn('全部重置', 'resetAllServerMcp', 'outlined', 'rotate-ccw')}
          ${btn('创建服务器 MCP', 'openMcpCreator', 'filled', 'plus')}
        </div>
      </div>

      <div class="aw-tools">
        <div class="aw-row" style="flex:1">
          <mdui-text-field id="aw-mcp-search" class="aw-search" variant="outlined" placeholder="搜索 MCP ID、命令、路径或工具名…" value="${escapeHTML(state.mcpSearch)}" clearable>${icon('search', 'icon')}</mdui-text-field>
          <div class="aw-row">
            ${[['all', `全部 ${allMcps.length}`], ['available', `可用 ${availCount}`], ['issue', '缺凭据/异常'], ['disabled', '已停用']].map(([k, label]) =>
              `<mdui-chip selectable ${state.mcpFilter === k ? 'selected' : ''} data-action="filterMcpList" data-filter="${k}">${label}</mdui-chip>`
            ).join('')}
          </div>
        </div>
        ${!standalonePage ? btn('在独立全屏视图中维护 ↗', 'openServerMcp', 'text', 'maximize-2', `data-server="${escapeHTML(s.alias)}"`) : ''}
      </div>

      ${!filtered.length ? `<mdui-card variant="outlined" class="aw-empty">
        ${icon('network')}
        <h2>${allMcps.length ? '没有匹配筛选条件的远端 MCP 服务' : '此服务器尚未配置专属 MCP 服务'}</h2>
        <p>可以为该远程服务器添加远端 PostgreSQL、Docker、Git 或内网 HTTP MCP 服务，由远端辅助进程直接在服务器本机拉起并管理生命周期。</p>
        ${btn('创建第一个服务器 MCP', 'openMcpCreator', 'filled', 'plus')}
      </mdui-card>` : `<mdui-card variant="outlined" class="aw-mcp-card">
        <mdui-collapse multiple>
          ${filtered.map(m => mcpItemMarkup(s, m)).join('<mdui-divider></mdui-divider>')}
        </mdui-collapse>
      </mdui-card>`}
    </section>

    <section class="aw-section">
      <div class="aw-section-heading">
        <div>
          <h2>全局 MCP 在本服务器的继承与覆盖策略</h2>
          <p class="aw-section-caption">主配置 <code>config.toml</code> 中的全局 MCP 服务进入此远程服务器会话时的行为（可重映射为远端 POSIX 路径，或屏蔽仅适用于本机 Windows/macOS 的服务）。</p>
        </div>
      </div>
      <mdui-card variant="outlined" class="aw-setting-card" style="overflow:hidden">
        <table class="aw-env-table">
          <thead>
            <tr>
              <th>全局 MCP ID</th>
              <th>来源与传输</th>
              <th>在 ${escapeHTML(s.alias)} 上的生效说明</th>
              <th style="text-align:right">本服务器覆盖策略</th>
            </tr>
          </thead>
          <tbody>
            ${state.globalOverrides.map(g => `<tr>
              <td><code>${escapeHTML(g.id)}</code></td>
              <td><span class="aw-mini-pill">${escapeHTML(g.transport)}</span> <small>${escapeHTML(g.source)}</small></td>
              <td>
                <span class="aw-status ${g.policy === 'disable' ? 'neutral' : g.policy === 'remap' ? 'info' : 'success'}">
                  ${g.policy === 'disable' ? '本机已屏蔽' : g.policy === 'remap' ? '路径已重映射' : '跟随全局'}
                </span>
                <small style="margin-left:6px">${escapeHTML(g.remapNote || g.effective)}</small>
              </td>
              <td style="text-align:right">
                <mdui-segmented-button-group selects="single" value="${g.policy}" style="height:28px">
                  <mdui-segmented-button value="inherit" data-action="setGlobalMcpPolicy" data-id="${g.id}" data-policy="inherit" style="height:28px;font-size:11px">跟随全局</mdui-segmented-button>
                  <mdui-segmented-button value="remap" data-action="setGlobalMcpPolicy" data-id="${g.id}" data-policy="remap" style="height:28px;font-size:11px">重映射路径</mdui-segmented-button>
                  <mdui-segmented-button value="disable" data-action="setGlobalMcpPolicy" data-id="${g.id}" data-policy="disable" style="height:28px;font-size:11px">在此机禁用</mdui-segmented-button>
                </mdui-segmented-button-group>
              </td>
            </tr>`).join('')}
          </tbody>
        </table>
      </mdui-card>
    </section>`;
}

function mcpPageMarkup() {
  const s = currentServer();
  return `<div class="aw-topbar">
    <div class="aw-row">
      <mdui-button variant="text" data-action="openDetail" data-server="${escapeHTML(s.alias)}" class="aw-back">${icon('arrow-left', 'icon')}返回 ${escapeHTML(s.alias)} 配置中心</mdui-button>
      <span class="aw-muted">/</span>
      <mdui-button variant="text" data-action="goList">${icon('server', 'icon')}全部服务器</mdui-button>
    </div>
    <div class="aw-row">
      <span class="aw-muted" style="font-size:12px">切换目标服务器：</span>
      <mdui-segmented-button-group selects="single" value="${escapeHTML(s.alias)}" aria-label="切换目标 SSH 服务器">
        ${state.servers.slice(0, 3).map(srv => `<mdui-segmented-button value="${escapeHTML(srv.alias)}" data-action="switchServer" data-server="${escapeHTML(srv.alias)}">${escapeHTML(srv.alias)}</mdui-segmented-button>`).join('')}
      </mdui-segmented-button-group>
    </div>
  </div>

  <div class="aw-page-header">
    <div class="aw-detail-identity">
      <span class="aw-logo large">${icon('network')}<span class="aw-logo-dot ${dotTone(s)}"></span></span>
      <div>
        <div class="aw-detail-title-row">
          <h1>${escapeHTML(s.alias)} · 远端 MCP 服务管理</h1>
          ${connStatusBadge(s)}
          ${chip('专页维护视图')}
        </div>
        <div class="aw-endpoint-line">
          <code>${escapeHTML(s.username)}@${escapeHTML(s.hostName)}:${s.port}</code>
          <span>·</span>
          <span>远端辅助进程 <code>${escapeHTML(s.helperVersion)}</code></span>
          <span>·</span>
          <span>支持创建、编辑、删除、工具检视与全局 MCP 策略覆盖</span>
        </div>
      </div>
    </div>
  </div>

  ${mcpSectionBlock(s, true)}`;
}

/* ---------------- VIEW 4: SERVER DETAIL & EXTENSIBLE CONFIGURATION HUB ---------------- */
function detailOverviewTab(s) {
  return `
    <section class="aw-section">
      <div class="aw-section-heading">
        <div>
          <h2>SSH 连接参数与凭据安全</h2>
          <p class="aw-section-caption">${s.managed ? '由 anywork 维护于 ~/.ssh/config 标记块中；每次建连先执行 BatchMode=yes 免密探测。' : '此主机来自 ~/.ssh/config 手写条目，以只读方式展示，请在配置文件中直接修改。'}</p>
        </div>
        <div class="aw-row">
          ${btn('查看 ~/.ssh/config 块', 'viewSshConfigBlock', 'outlined', 'file-code', `data-server="${escapeHTML(s.alias)}"`)}
          ${s.managed ? btn('编辑连接与密码', 'editServerConn', 'tonal', 'pencil', `data-server="${escapeHTML(s.alias)}"`) : ''}
        </div>
      </div>
      <mdui-card variant="outlined" class="aw-setting-card">
        <mdui-list>
          <mdui-list-item nonclickable headline="主机别名与端点 (Host / HostName / Port)" description="别名创建后不可改名；工作树租约与远程项目通过 ssh_alias 持久关联此身份">
            ${icon('server', 'icon')}
            <div slot="end-icon" class="aw-row">
              <code>${escapeHTML(s.alias)} → ${escapeHTML(s.username)}@${escapeHTML(s.hostName)}:${s.port}</code>
              ${iconBtn('复制 SSH 目标地址', 'copyText', 'copy', `data-text="${escapeHTML(s.username)}@${escapeHTML(s.hostName)}:${s.port}"`)}
            </div>
          </mdui-list-item>
          <mdui-divider></mdui-divider>
          <mdui-list-item nonclickable headline="公钥与 ssh-agent 免密认证" description="${s.identityFile ? `已指定 IdentityFile：${s.identityFile}` : '未指定单文件私钥，默认使用 ssh-agent 与 ~/.ssh/ 标准密钥'}">
            ${icon('key-round', 'icon')}
            <div slot="end-icon">${status(s.identityFile ? '已配置私钥路径' : 'ssh-agent 优先', 'success', 'check')}</div>
          </mdui-list-item>
          <mdui-divider></mdui-divider>
          <mdui-list-item nonclickable headline="SSH 密码凭据 (CredentialStore: ssh:${escapeHTML(s.alias)})" description="${s.hasPassword ? '已安全保存在操作系统凭据库（支持 Preserve / Replace / Clear 三态更新，绝不写入磁盘配置）' : '未保存密码；若免密探测未过且服务端允许密码认证，将按需弹窗并通过受控 SSH_ASKPASS 注入'}">
            ${icon('lock-keyhole', 'icon')}
            <div slot="end-icon" class="aw-row">
              ${s.hasPassword ? status('已存系统凭据库', 'success', 'shield-check') : status('未保存密码', 'neutral')}
              ${btn(s.hasPassword ? '更新或清除密码' : '配置密码', 'promptPassword', 'tonal', 'key-round', `data-server="${escapeHTML(s.alias)}"`)}
            </div>
          </mdui-list-item>
        </mdui-list>
      </mdui-card>
    </section>

    <section class="aw-section">
      <div class="aw-section-heading">
        <div>
          <h2>服务器专属配置矩阵（可扩展模块快捷入口）</h2>
          <p class="aw-section-caption">针对此远程服务器的独立配置项，按模块解耦并随远端辅助进程生命周期自动协调。</p>
        </div>
      </div>
      <div class="aw-mcp-summary-grid" style="grid-template-columns:repeat(2,minmax(0,1fr))">
        <mdui-card variant="outlined" class="aw-mcp-stat-card">
          <div class="aw-between">
            <span class="aw-status info">${icon('network')}远端 MCP 服务</span>
            ${btn('进入 MCP 专页维护 ↗', 'openServerMcp', 'tonal', 'arrow-up-right', `data-server="${escapeHTML(s.alias)}"`)}
          </div>
          <strong style="font-size:17px;margin-top:10px">${serverMcpsList(s.alias).filter(m => m.enabled).length} 个启用服务 · ${serverMcpsList(s.alias).reduce((n, m) => n + (m.tools?.length || 0), 0)} 个远端工具</strong>
          <small>支持在此服务器独立创建、修改、删除 stdio/HTTP MCP 服务，以及覆盖全局 MCP 策略。</small>
        </mdui-card>
        <mdui-card variant="outlined" class="aw-mcp-stat-card">
          <div class="aw-between">
            <span class="aw-status neutral">${icon('terminal')}环境与工具链覆盖</span>
            ${btn('配置环境与 PATH', 'switchDetailTab', 'text', 'sliders-horizontal', 'data-tab="env"')}
          </div>
          <strong style="font-size:17px;margin-top:10px">${s.envVars.length} 项环境变量 · ${s.toolchains.length} 项工具链探测</strong>
          <small>管理远端 Shell 采集环境、自定义环境变量（CUDA / 镜像源 / 代理）与二进制路径。</small>
        </mdui-card>
        <mdui-card variant="outlined" class="aw-mcp-stat-card">
          <div class="aw-between">
            <span class="aw-status neutral">${icon('code')}远端 LSP 与共享技能</span>
            ${btn('管理 LSP 与技能', 'switchDetailTab', 'text', 'code', 'data-tab="lsp"')}
          </div>
          <strong style="font-size:17px;margin-top:10px">${s.lspServers.length} 个远端语言服务 · ${s.skillDirs.length} 个技能目录源</strong>
          <small>监督远端 rust-analyzer / pyright / clangd 进程，合并远端与本地只读技能目录。</small>
        </mdui-card>
        <mdui-card variant="outlined" class="aw-mcp-stat-card">
          <div class="aw-between">
            <span class="aw-status neutral">${icon('folder-git-2')}工作区、端口转发与资源策略</span>
            ${btn('管理工作区与策略', 'switchDetailTab', 'text', 'gauge', 'data-tab="policy"')}
          </div>
          <strong style="font-size:17px;margin-top:10px">${s.projects.length} 个关联项目 · ${s.portForwards.length} 条端口映射 · 预算 ${escapeHTML(s.budgetLimit.split(' ')[0])}</strong>
          <small>浏览远端项目与 Git 工作树租约，维护隧道转发、辅助进程缓存与 ResourcePolicy 预算。</small>
        </mdui-card>
      </div>
    </section>`;
}

function detailEnvTab(s) {
  return `
    <section class="aw-section">
      <div class="aw-section-heading">
        <div>
          <h2>远端登录 Shell 环境采集快照</h2>
          <p class="aw-section-caption">Linux 远端辅助进程首次创建实例时通过受监督 Shell 提取一次导出变量；断线重连同一实例不重复执行启动脚本，点击「重新连接」可强制重新采集。</p>
        </div>
        ${btn('重新连接并重采环境', 'reconnectServer', 'tonal', 'refresh-cw', `data-server="${escapeHTML(s.alias)}"`)}
      </div>
      <mdui-card variant="outlined" class="aw-setting-card" style="padding:14px 18px">
        <div class="aw-kv-list">
          <span class="aw-kv-key">实际 Shell 描述符</span><code>${escapeHTML(s.shell)}</code>
          <span class="aw-kv-key">已采集 PATH</span><code>/home/${escapeHTML(s.username)}/.cargo/bin:/home/${escapeHTML(s.username)}/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin</code>
          <span class="aw-kv-key">共享继承范围</span><span>常规命令 (<code>exec</code>)、远端 Git、远端 LSP 与远端 stdio MCP 共享同一基础环境（请求级显式 <code>env</code> 最后覆盖）</span>
        </div>
      </mdui-card>
    </section>

    <section class="aw-section">
      <div class="aw-section-heading">
        <div>
          <h2>服务器专属环境变量覆盖</h2>
          <p class="aw-section-caption">针对此服务器注入的自定义环境变量（如 GPU 卡号、HuggingFace/Cargo 镜像源、内网代理或凭据引用）。</p>
        </div>
        ${btn('添加环境变量', 'addServerEnvModal', 'filled', 'plus')}
      </div>
      <mdui-card variant="outlined" class="aw-setting-card" style="overflow:hidden">
        ${s.envVars.length ? `<table class="aw-env-table">
          <thead>
            <tr><th>变量名 (Key)</th><th>当前值 / 凭据掩码</th><th>注入范围</th><th style="text-align:right">操作</th></tr>
          </thead>
          <tbody>
            ${s.envVars.map((ev, idx) => `<tr>
              <td><code>${escapeHTML(ev.key)}</code></td>
              <td><code>${escapeHTML(ev.value)}</code> ${ev.secret ? chip('系统凭据库保护') : ''}</td>
              <td><span class="aw-mini-pill">${escapeHTML(ev.scope)}</span></td>
              <td style="text-align:right">${iconBtn('删除变量', 'deleteServerEnv', 'trash-2', `data-idx="${idx}" style="color:rgb(var(--mdui-color-error))"`)}</td>
            </tr>`).join('')}
          </tbody>
        </table>` : `<div class="aw-empty" style="padding:32px"><h3>尚未添加自定义环境变量</h3><p>远端任务默认使用采集的登录 Shell 环境。</p>${btn('添加环境变量', 'addServerEnvModal', 'tonal', 'plus')}</div>`}
      </mdui-card>
    </section>

    <section class="aw-section">
      <div class="aw-section-heading">
        <div>
          <h2>远端工具链与运行时路径覆盖</h2>
          <p class="aw-section-caption">当服务器的 Node/npx、uvx、Git 或 Cargo 安装在非标准目录（如 Conda、NVM 或模块环境）时，可在此指定权威路径供远端 MCP 与 LSP 使用。</p>
        </div>
      </div>
      <mdui-card variant="outlined" class="aw-setting-card" style="overflow:hidden">
        <table class="aw-env-table">
          <thead>
            <tr><th>工具链类别</th><th>远端自动探测结果</th><th>显式覆盖路径（可选）</th><th style="text-align:right">状态</th></tr>
          </thead>
          <tbody>
            ${(s.toolchains.length ? s.toolchains : [
              { tool: 'git', detected: '/usr/bin/git', override: '' },
              { tool: 'node / npx', detected: '未探测', override: '' },
              { tool: 'python3 / uvx', detected: '未探测', override: '' }
            ]).map(tc => `<tr>
              <td><strong>${escapeHTML(tc.tool)}</strong></td>
              <td><code>${escapeHTML(tc.detected)}</code></td>
              <td><code>${escapeHTML(tc.override || '使用自动探测路径')}</code></td>
              <td style="text-align:right">${status(tc.override ? '手动指定' : '自动就绪', tc.override ? 'info' : 'success', 'check')}</td>
            </tr>`).join('')}
          </tbody>
        </table>
      </mdui-card>
    </section>`;
}

function detailLspSkillsTab(s) {
  return `
    <section class="aw-section">
      <div class="aw-section-heading">
        <div>
          <h2>远端语言服务监督 (Remote LSP)</h2>
          <p class="aw-section-caption">LSP 客户端运行在本地，语言服务器作为受监督子进程运行在远端 <code>pl-remote-helper</code> 上，复用同一随包资产与生命周期。</p>
        </div>
        <div class="aw-row">
          ${btn('探测远端语言服务', 'probeRemoteLsp', 'tonal', 'activity')}
          ${btn('重置工作区 LSP', 'resetRemoteLsp', 'outlined', 'rotate-ccw')}
        </div>
      </div>
      <mdui-card variant="outlined" class="aw-setting-card">
        ${s.lspServers.length ? `<mdui-list>
          ${s.lspServers.map((l, i) => `${i > 0 ? '<mdui-divider></mdui-divider>' : ''}
            <mdui-list-item nonclickable headline="${escapeHTML(l.name)} (${escapeHTML(l.lang)})" description="${escapeHTML(l.detail)} · 远端二进制：${escapeHTML(l.binary)}">
              ${icon('code', 'icon')}
              <div slot="end-icon" class="aw-row">
                ${status(l.state === 'available' ? '可用' : '正在索引', l.state === 'available' ? 'success' : 'info', l.state === 'available' ? 'check' : 'loader')}
                ${btn('重置', 'resetRemoteLsp', 'text', 'rotate-ccw')}
              </div>
            </mdui-list-item>`).join('')}
        </mdui-list>` : `<div class="aw-empty" style="padding:32px"><h3>当前服务器暂无活动的 LSP 进程</h3><p>打开该服务器上的远程项目后，将按项目语言自动探测并拉起远端语言服务器。</p></div>`}
      </mdui-card>
    </section>

    <section class="aw-section">
      <div class="aw-section-heading">
        <div>
          <h2>远端与本地混合技能目录 (Hybrid Skills)</h2>
          <p class="aw-section-caption">依据 <code>design/22-ssh-remote.md §22.3</code>，SSH 工作区技能由远端项目源、服务器共享只读目录与本机只读源按优先级合并而成。</p>
        </div>
        ${btn('添加服务器共享技能目录', 'addSkillDirModal', 'tonal', 'folder-plus')}
      </div>
      <mdui-card variant="outlined" class="aw-setting-card" style="overflow:hidden">
        <table class="aw-env-table">
          <thead>
            <tr><th>技能目录源</th><th>层级与职责</th><th>已发现技能数</th><th style="text-align:right">状态</th></tr>
          </thead>
          <tbody>
            ${(s.skillDirs.length ? s.skillDirs : [
              { path: '<workspace>/.agents/skills', kind: '远端项目级目录', count: 0, status: '按需扫描' },
              { path: '本地 ~/.agents/skills + 内置系统技能', kind: '本机只读源自动合并', count: 11, status: '已就绪' }
            ]).map(d => `<tr>
              <td><code>${escapeHTML(d.path)}</code></td>
              <td>${escapeHTML(d.kind)}</td>
              <td><strong>${d.count} 个技能</strong></td>
              <td style="text-align:right">${status(d.status, 'success', 'check')}</td>
            </tr>`).join('')}
          </tbody>
        </table>
      </mdui-card>
    </section>`;
}

function detailPolicyTab(s) {
  return `
    <section class="aw-section">
      <div class="aw-section-heading">
        <div>
          <h2>关联远程项目与 Git 工作树租约</h2>
          <p class="aw-section-caption">远端项目通过 <code>(ssh_alias, path)</code> 唯一绑定标准 POSIX 路径；支持 <code>local</code>（权威目录）与 <code>worktree</code>（远端 <code>.anywork/worktrees/</code> 独立检出）模式。</p>
        </div>
        ${btn('浏览远端目录并打开项目…', 'browseRemoteDir', 'filled', 'folder-open', `data-server="${escapeHTML(s.alias)}"`)}
      </div>
      <mdui-card variant="outlined" class="aw-setting-card">
        ${s.projects.length ? `<mdui-list>
          ${s.projects.map((p, i) => `${i > 0 ? '<mdui-divider></mdui-divider>' : ''}
            <mdui-list-item nonclickable headline="${escapeHTML(p.name)}" description="权威 POSIX 路径：${escapeHTML(p.path)} · 分支：${escapeHTML(p.branch)}">
              ${icon('folder-git-2', 'icon')}
              <div slot="end-icon" class="aw-row">
                ${p.worktrees ? status(`${p.worktrees} 个活动 Git 工作树`, 'info', 'git-branch') : chip('local 目录模式')}
                ${btn('浏览此目录', 'browseRemoteDir', 'text', 'folder-open', `data-server="${escapeHTML(s.alias)}" data-path="${escapeHTML(p.path)}"`)}
              </div>
            </mdui-list-item>`).join('')}
        </mdui-list>` : `<div class="aw-empty" style="padding:32px"><h3>尚未在此服务器打开远程项目</h3><p>点击右上角「浏览远端目录并打开项目」验证远端绝对 POSIX 路径并接入项目。</p></div>`}
      </mdui-card>
    </section>

    <section class="aw-section">
      <div class="aw-section-heading">
        <div>
          <h2>SSH 端口转发与内网服务映射（服务器扩展能力）</h2>
          <p class="aw-section-caption">为远端面板（如 TensorBoard、Jupyter、vLLM 或内网 Web 服务）配置随受管主机块维护的端口转发规则。</p>
        </div>
        ${btn('添加端口转发', 'addPortForwardModal', 'tonal', 'plus')}
      </div>
      <mdui-card variant="outlined" class="aw-setting-card" style="overflow:hidden">
        ${s.portForwards.length ? `<table class="aw-env-table">
          <thead>
            <tr><th>用途说明</th><th>转发方向</th><th>本机监听地址</th><th>远端目标地址</th><th style="text-align:right">状态</th></tr>
          </thead>
          <tbody>
            ${s.portForwards.map(pf => `<tr>
              <td><strong>${escapeHTML(pf.label)}</strong></td>
              <td><span class="aw-mini-pill">${escapeHTML(pf.type)}</span></td>
              <td><code>${escapeHTML(pf.local)}</code></td>
              <td><code>${escapeHTML(pf.remote)}</code></td>
              <td style="text-align:right">${status(pf.active ? '已启用' : '已停用', pf.active ? 'success' : 'neutral', 'check')}</td>
            </tr>`).join('')}
          </tbody>
        </table>` : `<div class="aw-empty" style="padding:28px"><h3>暂无端口转发规则</h3><p>可添加 LocalForward 规则将远端内网端口安全映射至本机回环地址。</p></div>`}
      </mdui-card>
    </section>

    <section class="aw-section">
      <div class="aw-section-heading">
        <div>
          <h2>动态资源预算 (ResourcePolicy) 与辅助进程缓存</h2>
          <p class="aw-section-caption">控制流与数据流共享统一资源预算并保证防饥饿准入；随包辅助进程幂等部署于 <code>$HOME/.anywork/remote-helper/&lt;version&gt;/&lt;digest&gt;/</code>。</p>
        </div>
        ${btn('清理过期辅助进程缓存', 'cleanHelperCache', 'outlined', 'sparkles')}
      </div>
      <mdui-card variant="outlined" class="aw-setting-card">
        <mdui-list>
          <mdui-list-item nonclickable headline="单机内存与流控预算上限 (ResourcePolicy Ceiling)" description="当前占用 ${escapeHTML(s.budgetUsed)} / ${escapeHTML(s.budgetLimit)} · 控制交换池拥有独立保底配额">
            ${icon('gauge', 'icon')}
            <div slot="end-icon">
              <mdui-select variant="outlined" value="auto" style="width:190px;--mdui-typescale-body-large-size:12px">
                <mdui-menu-item value="auto">自动（按远端 cgroup 计算）</mdui-menu-item>
                <mdui-menu-item value="256">手动上限 · 256 MB</mdui-menu-item>
                <mdui-menu-item value="512">手动上限 · 512 MB</mdui-menu-item>
                <mdui-menu-item value="1024">手动上限 · 1024 MB</mdui-menu-item>
              </mdui-select>
            </div>
          </mdui-list-item>
          <mdui-divider></mdui-divider>
          <mdui-list-item nonclickable headline="远端辅助进程资产目录 ($HOME/.anywork/remote-helper/)" description="当前活动版本：${escapeHTML(s.helperVersion)} · 目标架构：${escapeHTML(s.arch)}（禁止模型用作临时 scratch 目录）">
            ${icon('package-check', 'icon')}
            <div slot="end-icon">${status('SHA-256 摘要已核验', 'success', 'shield-check')}</div>
          </mdui-list-item>
        </mdui-list>
      </mdui-card>
    </section>`;
}

function detailMarkup() {
  const s = currentServer();
  const mcps = serverMcpsList(s.alias);
  return `<div class="aw-topbar">
    <mdui-button variant="text" data-action="goList" class="aw-back">${icon('arrow-left', 'icon')}返回服务器列表</mdui-button>
    <div class="aw-row">
      <span class="aw-muted" style="font-size:12px">快速切换主机：</span>
      <mdui-segmented-button-group selects="single" value="${escapeHTML(s.alias)}" aria-label="切换主机">
        ${state.servers.slice(0, 4).map(srv => `<mdui-segmented-button value="${escapeHTML(srv.alias)}" data-action="switchServer" data-server="${escapeHTML(srv.alias)}">${escapeHTML(srv.alias)}</mdui-segmented-button>`).join('')}
      </mdui-segmented-button-group>
    </div>
  </div>

  <div class="aw-page-header">
    <div class="aw-detail-identity">
      <span class="aw-logo large">${icon(s.icon || 'server')}<span class="aw-logo-dot ${dotTone(s)}"></span></span>
      <div>
        <div class="aw-detail-title-row">
          <h1>${escapeHTML(s.alias)}</h1>
          ${connStatusBadge(s)}
          ${s.managed ? chip('~/.ssh/config 受管块') : chip('手写只读条目')}
          ${chip(s.roleTag)}
        </div>
        <div class="aw-endpoint-line">
          <code>${escapeHTML(s.username)}@${escapeHTML(s.hostName)}:${s.port}</code>
          <span>·</span>
          <span>${escapeHTML(s.osInfo)}</span>
          <span>·</span>
          <span>${escapeHTML(s.hardware)}</span>
        </div>
      </div>
    </div>
    <div class="aw-row">
      ${btn('测试连接', 'testServer', 'tonal', 'cable', `data-server="${escapeHTML(s.alias)}"`)}
      ${btn('重新连接', 'reconnectServer', 'outlined', 'refresh-cw', `data-server="${escapeHTML(s.alias)}"`)}
      ${btn('打开项目…', 'browseRemoteDir', 'outlined', 'folder-open', `data-server="${escapeHTML(s.alias)}"`)}
      ${btn('MCP 专页', 'openServerMcp', 'filled', 'network', `data-server="${escapeHTML(s.alias)}"`)}
    </div>
  </div>

  <mdui-card variant="filled" class="aw-telemetry-card">
    <div class="aw-telemetry-grid">
      <div class="aw-telemetry-item">
        <span class="aw-telemetry-label">${icon('cpu')}远端辅助进程 (pl-remote-helper)</span>
        <div class="aw-telemetry-val">${escapeHTML(s.helperVersion.split(' ')[0])} · ${escapeHTML(s.arch.split('-')[0])}</div>
        <span class="aw-telemetry-sub">${escapeHTML(s.leaseInfo)}</span>
      </div>
      <div class="aw-telemetry-item">
        <span class="aw-telemetry-label">${icon('network')}本服务器远端 MCP 服务</span>
        <div class="aw-telemetry-val">${mcps.filter(m => m.enabled).length} 启用 / ${mcps.reduce((n, m) => n + (m.tools?.length || 0), 0)} 个工具</div>
        <span class="aw-telemetry-sub">由远端辅助进程监督并注入当前主机关联会话</span>
      </div>
      <div class="aw-telemetry-item">
        <span class="aw-telemetry-label">${icon('terminal')}Shell 环境与 LSP 监督</span>
        <div class="aw-telemetry-val">${s.lspServers.length} 个 LSP · ${s.envVars.length} 项变量</div>
        <span class="aw-telemetry-sub">${escapeHTML(s.shell)}</span>
      </div>
      <div class="aw-telemetry-item">
        <span class="aw-telemetry-label">${icon('gauge')}资源预算 (ResourcePolicy)</span>
        <div class="aw-telemetry-val">${escapeHTML(s.budgetUsed)} / ${escapeHTML(s.budgetLimit.split(' ')[0])}</div>
        <span class="aw-telemetry-sub">控制流与数据流隔离 · 防饥饿分片准入</span>
      </div>
    </div>
  </mdui-card>

  <mdui-tabs class="aw-server-tabs" id="aw-server-tabs" value="${state.detailTab}" placement="top-start" variant="secondary">
    <mdui-tab value="overview">概览与连接认证</mdui-tab>
    <mdui-tab value="mcp">远端 MCP 服务 · ${mcps.length}</mdui-tab>
    <mdui-tab value="env">环境与工具链 · ${s.envVars.length}</mdui-tab>
    <mdui-tab value="lsp">语言服务与技能 · ${s.lspServers.length}</mdui-tab>
    <mdui-tab value="policy">工作区、端口与资源策略</mdui-tab>

    <mdui-tab-panel slot="panel" value="overview">${detailOverviewTab(s)}</mdui-tab-panel>
    <mdui-tab-panel slot="panel" value="mcp">${mcpSectionBlock(s, false)}</mdui-tab-panel>
    <mdui-tab-panel slot="panel" value="env">${detailEnvTab(s)}</mdui-tab-panel>
    <mdui-tab-panel slot="panel" value="lsp">${detailLspSkillsTab(s)}</mdui-tab-panel>
    <mdui-tab-panel slot="panel" value="policy">${detailPolicyTab(s)}</mdui-tab-panel>
  </mdui-tabs>`;
}

/* ---------------- DIALOGS & INTERACTIONS ---------------- */
function renderDirModalContent(s) {
  const curPath = state.dirBrowsePath || '/home/ubuntu';
  const node = remoteDirTree[curPath] || {
    parent: curPath.split('/').slice(0, -1).join('/') || '/',
    entries: [
      { name: 'src', path: `${curPath}/src`, note: '源码目录' },
      { name: 'configs', path: `${curPath}/configs`, note: '配置目录' }
    ]
  };
  const projName = curPath.split('/').filter(Boolean).pop() || 'remote-workspace';
  return `<div class="aw-form-stack">
    <small>绑定主机：<code>${escapeHTML(s.username)}@${escapeHTML(s.hostName)}:${s.port}</code>（别名 <code>${escapeHTML(s.alias)}</code> · 仅接受已验证的绝对 POSIX 路径）</small>
    <div class="aw-dir-path-bar">
      <mdui-text-field id="aw-dir-input" label="远端路径 (绝对 POSIX 路径)" value="${escapeHTML(curPath)}" variant="outlined">${icon('route', 'icon')}</mdui-text-field>
      ${btn('前往', 'dirGo', 'tonal', 'arrow-right')}
    </div>
    <div class="aw-dir-current">
      ${iconBtn('上一级目录', 'dirUp', 'arrow-up', node.parent ? `data-path="${escapeHTML(node.parent)}"` : 'disabled')}
      ${iconBtn('刷新当前目录', 'dirRefresh', 'refresh-cw')}
      <span>当前已验证目录：<strong>${escapeHTML(curPath)}</strong></span>
    </div>
    <div class="aw-dir-list">
      ${node.entries.map(e => `<button type="button" class="aw-dir-entry" data-action="dirEnter" data-path="${escapeHTML(e.path)}">
        <span class="aw-row">${icon('folder')}<strong>${escapeHTML(e.name)}</strong></span>
        <small class="aw-mono">${escapeHTML(e.note || e.path)}</small>
      </button>`).join('')}
    </div>
    <mdui-text-field id="aw-dir-proj-name" label="项目名称" value="${escapeHTML(projName)}" helper="打开后将在项目侧栏绑定 (ssh_alias: ${escapeHTML(s.alias)}, path: ${escapeHTML(curPath)})" variant="outlined">${icon('folder-git-2', 'icon')}</mdui-text-field>
  </div>`;
}

function openRemoteDirectoryModal(s, initPath) {
  if (initPath) state.dirBrowsePath = initPath;
  openDialog('选择远端目录并打开项目', renderDirModalContent(s), () => {
    const p = $('#aw-dir-input')?.value.trim() || state.dirBrowsePath;
    if (!p.startsWith('/')) {
      toast('远端路径必须以 / 开头，且必须是绝对 POSIX 路径');
      return false;
    }
    const name = $('#aw-dir-proj-name')?.value.trim() || p.split('/').filter(Boolean).pop() || 'remote-project';
    if (!s.projects.some(x => x.path === p)) {
      s.projects.push({ name, path: p, worktrees: 0, branch: 'main' });
    }
    toast(`已打开远程项目「${name}」(${s.alias}:${p})`);
    return true;
  }, '打开此目录');
}

function openPasswordModal(s) {
  openDialog('输入 SSH 密码', `<div class="aw-form-stack">
    <p style="font-size:13px;color:rgb(var(--mdui-color-on-surface-variant))">连接到 <code>${escapeHTML(s.username)}@${escapeHTML(s.hostName)}:${s.port}</code> 需要密码认证（服务端已公布 <code>password</code> 认证方式）。</p>
    <mdui-text-field id="aw-modal-ssh-pwd" label="SSH 密码" type="password" placeholder="输入服务器登录密码" variant="outlined" required>${icon('lock-keyhole', 'icon')}</mdui-text-field>
    <label class="aw-row" style="font-size:13px;cursor:pointer">
      <input type="checkbox" id="aw-modal-remember-pwd" checked />
      <span>保存密码到操作系统凭据库（账户键名 <code>ssh:${escapeHTML(s.alias)}</code>，不写入配置文件）</span>
    </label>
  </div>`, () => {
    const remember = $('#aw-modal-remember-pwd')?.checked !== false;
    s.hasPassword = remember;
    s.state = 'ready';
    if (state.type === 'connection' && state.scenario === 'passwordPrompt') {
      state.scenario = 'ready';
    }
    toast(`已通过受控 SSH_ASKPASS 完成认证并连接 ${s.alias}`);
    return true;
  }, '连接');
}

function openEditServerModal(s) {
  openDialog(`编辑 SSH 服务器：${s.alias}`, `<div class="aw-form-stack">
    <mdui-text-field label="别名 (Host)" value="${escapeHTML(s.alias)}" disabled helper="写入 ~/.ssh/config 的 Host 条目；创建后不可改名" variant="outlined">${icon('badge', 'icon')}</mdui-text-field>
    <div class="aw-form-grid-2">
      <mdui-text-field id="aw-edit-srv-host" label="主机 (HostName)" value="${escapeHTML(s.hostName)}" variant="outlined" required>${icon('server', 'icon')}</mdui-text-field>
      <mdui-text-field id="aw-edit-srv-port" label="端口 (Port)" value="${escapeHTML(s.port)}" type="number" variant="outlined"></mdui-text-field>
    </div>
    <div class="aw-form-grid-2">
      <mdui-text-field id="aw-edit-srv-user" label="用户名 (User)" value="${escapeHTML(s.username)}" variant="outlined" required>${icon('user', 'icon')}</mdui-text-field>
      <mdui-text-field id="aw-edit-srv-idfile" label="私钥文件 (IdentityFile，可选)" value="${escapeHTML(s.identityFile || '')}" helper="留空时使用 ssh-agent" variant="outlined">${icon('key-round', 'icon')}</mdui-text-field>
    </div>
    <mdui-text-field id="aw-edit-srv-pwd" label="密码（可选）" type="password" placeholder="${s.hasPassword ? '已保存密码，留空保持不变 (Preserve)' : '留空则使用密钥或连接时输入'}" helper="保存在系统凭据库，不会写入 ~/.ssh/config" variant="outlined">${icon('lock-keyhole', 'icon')}</mdui-text-field>
  </div>`, () => {
    s.hostName = $('#aw-edit-srv-host')?.value.trim() || s.hostName;
    s.port = Number($('#aw-edit-srv-port')?.value.trim()) || s.port;
    s.username = $('#aw-edit-srv-user')?.value.trim() || s.username;
    s.identityFile = $('#aw-edit-srv-idfile')?.value.trim() || '';
    if ($('#aw-edit-srv-pwd')?.value.trim()) s.hasPassword = true;
    toast(`已原子更新 ~/.ssh/config 中的 ${s.alias} 受管标记块`);
    return true;
  }, '保存');
}

function openSshConfigBlockModal(s) {
  const block = s.managed
    ? sshConfigBlockText(s)
    : `<span class="aw-comment"># 用户手写条目（anywork 原样保留，仅只读消费）</span>\nHost ${escapeHTML(s.alias)}\n    HostName ${escapeHTML(s.hostName)}\n    Port ${s.port}\n    User ${escapeHTML(s.username)}\n    ProxyJump bastion-entry\n    IdentityFile ${escapeHTML(s.identityFile || '~/.ssh/id_ed25519')}`;
  openDialog(`~/.ssh/config 条目预览：${s.alias}`, `<div class="aw-form-stack">
    <p style="font-size:12.5px;color:rgb(var(--mdui-color-on-surface-variant))">anywork 仅管理带 <code># BEGIN / END anywork server</code> 定界符的标记块，文件中其他手写条目、注释与换行符逐字节原样保留。</p>
    <div class="aw-code-preview">${block}</div>
  </div>`, () => true, '关闭', true);
}

const navGroups = [
  ['模型与智能体', [['账号', 'cloud'], ['智能体', 'users'], ['指令', 'align-left'], ['工作模式', 'workflow']]],
  ['工具与服务', [['技能', 'puzzle'], ['MCP', 'network'], ['LSP', 'code'], ['SSH', 'server']]],
  ['偏好设置', [['统计', 'chart-no-axes-combined'], ['安全', 'shield'], ['通用', 'sliders-horizontal'], ['机器人', 'bot']]]
];
$('#aw-nav').innerHTML = navGroups.map(([label, items]) =>
  `<mdui-list><mdui-list-subheader>${label}</mdui-list-subheader>${items.map(([name, ico]) =>
    `<mdui-list-item rounded ${name === 'SSH' ? 'active' : ''} data-nav="${name}">${icon(ico, 'icon')}${name}</mdui-list-item>`
  ).join('')}</mdui-list>`
).join('');

function renderSelectors() {
  const typeSelect = $('#aw-type');
  if (typeSelect && !typeSelect.children.length) {
    typeSelect.innerHTML = Object.entries(groups).map(([k, v]) => `<mdui-menu-item value="${k}">${v.label}</mdui-menu-item>`).join('');
  }
  if (typeSelect) typeSelect.value = state.type;

  const scenSelect = $('#aw-scenario');
  if (scenSelect) {
    const items = groups[state.type].states;
    scenSelect.innerHTML = items.map(([k, label]) => `<mdui-menu-item value="${state.type}:${k}">${label}</mdui-menu-item>`).join('');
    scenSelect.value = `${state.type}:${state.scenario}`;
  }

  const idx = allSteps.findIndex(x => x.type === state.type && x.scenario === state.scenario);
  const idxEl = $('#aw-scenario-index');
  if (idxEl) idxEl.textContent = `${idx + 1} / ${totalScenarios}`;

  const viewGroup = $('#aw-view-group');
  if (viewGroup) viewGroup.value = state.page;
}

function wireLocal() {
  const search = $('#aw-ssh-search');
  search?.addEventListener('input', () => {
    state.search = search.value;
    render();
  });
  const mcpSearch = $('#aw-mcp-search');
  mcpSearch?.addEventListener('input', () => {
    state.mcpSearch = mcpSearch.value;
    render();
  });

  const tabs = $('#aw-server-tabs');
  tabs?.addEventListener('change', e => {
    if (e.target === tabs && tabs.value && tabs.value !== state.detailTab) {
      state.detailTab = tabs.value;
      render();
    }
  });

  $$('mdui-collapse-item').forEach(item => {
    item.addEventListener('open', e => {
      if (e.target === item) {
        item.toggleAttribute('data-expanded', true);
        if (item.value && !state.expandedMcps.includes(item.value)) state.expandedMcps.push(item.value);
      }
    });
    item.addEventListener('close', e => {
      if (e.target === item) {
        item.toggleAttribute('data-expanded', false);
        state.expandedMcps = state.expandedMcps.filter(x => x !== item.value);
      }
    });
    item.updateComplete?.then(() => requestAnimationFrame(() => {
      if (!item.isConnected) return;
      if (state.expandedMcps.includes(item.value) || (state.type === 'serverMcp' && state.scenario === 'mcpToolsExpanded')) {
        item.active = true;
      }
      item.toggleAttribute('data-expanded', item.active);
    }));
  });

  $$('[data-mcp-switch]').forEach(sw => {
    sw.addEventListener('click', e => e.stopPropagation());
    sw.addEventListener('change', () => {
      const id = sw.dataset.mcpSwitch;
      const list = state.serverMcps[state.selectedServer] || [];
      const target = list.find(x => x.id === id);
      if (target) {
        target.enabled = sw.checked;
        if (sw.checked && target.state === 'disabled') target.state = 'available';
        render();
        toast(sw.checked ? `远端 MCP「${id}」已启用并进入后台探测` : `远端 MCP「${id}」已停用`);
      }
    });
  });

  ['alias', 'host', 'user', 'identity', 'port'].forEach(key => {
    const el = $(`#aw-add-${key}`);
    el?.addEventListener('input', () => {
      if (key === 'alias') state.addForm.alias = el.value;
      if (key === 'host') state.addForm.hostName = el.value;
      if (key === 'user') state.addForm.username = el.value;
      if (key === 'identity') state.addForm.identityFile = el.value;
      if (key === 'port') state.addForm.port = el.value;
      const preview = $('#aw-ssh-block-preview');
      if (preview) preview.innerHTML = sshConfigBlockText(state.addForm);
    });
  });

  ['id', 'cmd', 'cwd', 'args', 'env', 'endpoint', 'bearer', 'headers'].forEach(key => {
    const el = $(`#aw-mcp-${key}`);
    el?.addEventListener('input', () => {
      const map = { id: 'id', cmd: 'command', cwd: 'cwd', args: 'args', env: 'env', endpoint: 'endpoint', bearer: 'bearerEnv', headers: 'headers' };
      state.mcpForm[map[key]] = el.value;
      if (key === 'id') {
        const cleanId = (el.value || 'my_mcp').replace(/[^a-zA-Z0-9_-]/g, '_');
        el.helper = `模型可见工具前缀预览：mcp__${cleanId}__<tool_name>（最长 64 字符）`;
      }
    });
  });
}

function render() {
  renderSelectors();
  const main = $('#aw-main');
  if (state.page === 'add') main.innerHTML = addMarkup();
  else if (state.page === 'detail') main.innerHTML = detailMarkup();
  else if (state.page === 'mcp') main.innerHTML = mcpPageMarkup();
  else main.innerHTML = listMarkup();
  wireLocal();
  hydrateIcons();
}

function applyScenarioPreset(type, scenario) {
  state.type = type;
  state.scenario = scenario;
  if (type === 'overview') {
    state.page = 'list';
    state.listFilter = scenario === 'readonly' ? 'readonly' : 'all';
  } else if (type === 'connection') {
    state.selectedServer = scenario === 'pubkeyOnlyError' ? 'corp-sec-gateway' : 'gpu-a100-prod';
    state.page = 'list';
    if (scenario === 'passwordPrompt') {
      render();
      openPasswordModal(currentServer());
      return;
    }
    if (scenario === 'browseDir') {
      render();
      openRemoteDirectoryModal(currentServer(), '/home/ubuntu');
      return;
    }
  } else if (type === 'serverMcp') {
    state.selectedServer = 'gpu-a100-prod';
    state.page = 'mcp';
    state.mcpCreatorOpen = scenario === 'mcpCreate';
    state.mcpFilter = scenario === 'mcpMissingCred' ? 'issue' : 'all';
    if (scenario === 'mcpMissingCred') state.expandedMcps = ['github_enterprise_audit'];
    else if (scenario === 'mcpStartFailed') state.expandedMcps = ['docker_gpu_runtime'];
  } else if (type === 'serverExtensions') {
    state.selectedServer = 'gpu-a100-prod';
    state.page = 'detail';
    state.detailTab = scenario === 'extEnv' ? 'env' : scenario === 'extLspSkills' ? 'lsp' : 'policy';
  }
  render();
}

$('#aw-type').addEventListener('change', () => {
  const val = $('#aw-type').value;
  if (groups[val]) applyScenarioPreset(val, groups[val].states[0][0]);
});
$('#aw-scenario').addEventListener('change', () => {
  const [t, s] = String($('#aw-scenario').value).split(':');
  if (groups[t]) applyScenarioPreset(t, s);
});
$('#aw-prev-scenario').addEventListener('click', () => {
  const idx = allSteps.findIndex(x => x.type === state.type && x.scenario === state.scenario);
  const prev = allSteps[(idx - 1 + totalScenarios) % totalScenarios];
  applyScenarioPreset(prev.type, prev.scenario);
});
$('#aw-next-scenario').addEventListener('click', () => {
  const idx = allSteps.findIndex(x => x.type === state.type && x.scenario === state.scenario);
  const next = allSteps[(idx + 1) % totalScenarios];
  applyScenarioPreset(next.type, next.scenario);
});

['list', 'add', 'detail', 'mcp'].forEach(v => {
  $(`#aw-view-${v}`)?.addEventListener('click', () => {
    state.page = v;
    render();
  });
});

$('#aw-dialog-cancel').addEventListener('click', () => { $('#aw-dialog').open = false; });
$('#aw-dialog-save').addEventListener('click', () => {
  if (!dialogSaveHandler || dialogSaveHandler() !== false) {
    $('#aw-dialog').open = false;
    render();
  }
});

root.addEventListener('click', e => {
  const nav = e.target.closest('[data-nav]');
  if (nav) {
    const target = nav.dataset.nav;
    if (target === 'SSH') { state.page = 'list'; render(); }
    else if (target === 'MCP') { state.page = 'mcp'; render(); toast('已切换至服务器专属 MCP 与全局 MCP 映射视图'); }
    else if (target === '账号') { location.href = '../accounts-list/index.html'; }
    else toast(`当前设计稿聚焦「远程开发 (SSH) 与服务器专属配置」`);
    return;
  }

  const el = e.target.closest('[data-action]');
  if (!el) return;
  const action = el.dataset.action;
  const srvAlias = el.dataset.server || state.selectedServer;
  const srv = state.servers.find(x => x.alias === srvAlias) || currentServer();

  const dropdown = el.closest('mdui-dropdown');
  if (dropdown) dropdown.open = false;

  if (action === 'mobileNav') { $('#aw-shell').classList.toggle('aw-nav-open'); return; }
  if (action === 'goList') { state.page = 'list'; render(); return; }
  if (action === 'goAddServer') { state.page = 'add'; render(); return; }
  if (action === 'openDetail') { state.selectedServer = srv.alias; state.page = 'detail'; render(); return; }
  if (action === 'openDetailTab') { state.selectedServer = srv.alias; state.detailTab = el.dataset.tab || 'overview'; state.page = 'detail'; render(); return; }
  if (action === 'switchDetailTab') { state.detailTab = el.dataset.tab || 'overview'; render(); return; }
  if (action === 'openServerMcp') { state.selectedServer = srv.alias; state.page = 'mcp'; render(); return; }
  if (action === 'switchServer') { state.selectedServer = srv.alias; render(); toast(`已切换至服务器 ${srv.alias}`); return; }
  if (action === 'filterServerList') { state.listFilter = el.dataset.filter || 'all'; render(); return; }
  if (action === 'clearServerSearch') { state.search = ''; state.listFilter = 'all'; state.scenario = 'normal'; render(); return; }

  if (action === 'pickAddPreset') {
    const p = el.dataset.preset;
    state.addPreset = p;
    if (p === 'gpu') state.addForm = { ...state.addForm, alias: 'gpu-h100-cluster', hostName: '10.24.12.88', username: 'ubuntu', identityFile: '~/.ssh/id_ed25519_gpu' };
    if (p === 'linux') state.addForm = { ...state.addForm, alias: 'dev-ubuntu-box', hostName: '192.168.10.42', username: 'dev', identityFile: '~/.ssh/id_ed25519' };
    if (p === 'bastion') state.addForm = { ...state.addForm, alias: 'corp-inner-node', hostName: '172.20.4.15', username: 'zhourui', identityFile: '~/.ssh/id_ed25519_corp' };
    render();
    return;
  }

  if (action === 'submitAddServer') {
    const alias = ($('#aw-add-alias')?.value || state.addForm.alias).trim();
    const hostName = ($('#aw-add-host')?.value || state.addForm.hostName).trim();
    const username = ($('#aw-add-user')?.value || state.addForm.username).trim();
    const port = Number($('#aw-add-port')?.value || state.addForm.port) || 22;
    if (!alias || /[\s*?\[\]!#"'\\]/.test(alias) || alias.startsWith('-')) {
      toast('别名不能为空，且必须是单个合法词元');
      return;
    }
    if (!hostName || !username) {
      toast('请填写完整的主机地址与用户名');
      return;
    }
    const newSrv = {
      alias,
      hostName,
      port,
      username,
      identityFile: ($('#aw-add-identity')?.value || '').trim(),
      hasPassword: Boolean(($('#aw-add-password')?.value || '').trim()),
      managed: true,
      roleTag: state.addPreset === 'gpu' ? 'GPU 训练与推理节点' : '标准 Linux 开发主机',
      icon: state.addPreset === 'gpu' ? 'cpu' : 'server',
      state: 'ready',
      arch: 'x86_64-unknown-linux-musl',
      osInfo: 'Ubuntu 24.04 LTS (新接入)',
      hardware: '远程助手 v10 已握手',
      helperVersion: 'v10 (sha256:8f3a…c91b)',
      shell: '/bin/bash (登录环境已采集)',
      leaseInfo: '心跳 5s · 租约 30s · HTTP/2 流控正常',
      budgetUsed: '14 MB',
      budgetLimit: '512 MB',
      projects: [],
      envVars: state.addPreset === 'gpu' ? [{ key: 'CUDA_VISIBLE_DEVICES', value: '0,1', scope: 'exec / MCP / LSP', secret: false }] : [],
      toolchains: [],
      lspServers: [],
      skillDirs: [{ path: '<workspace>/.agents/skills', kind: '远端项目源', count: 0, status: '已启用' }],
      portForwards: []
    };
    state.servers = [newSrv, ...state.servers.filter(x => x.alias !== alias)];
    if (!state.serverMcps[alias]) {
      state.serverMcps[alias] = [
        {
          id: 'remote_git_inspector',
          scope: 'server',
          enabled: true,
          transport: 'stdio',
          command: 'uvx',
          args: `mcp-server-git --repository /home/${username}`,
          cwd: `/home/${username}`,
          env: '',
          state: 'available',
          checkedAt: '刚刚',
          generation: 1,
          pid: 51204,
          tools: [{ name: 'git_status', fullName: 'mcp__remote_git_inspector__git_status', desc: '查询远端仓库工作树与暂存区状态' }]
        }
      ];
    }
    state.selectedServer = alias;
    state.page = 'mcp';
    render();
    toast(`已写入 ~/.ssh/config 受管块「${alias}」，并进入该服务器的 MCP 配置专页`);
    return;
  }

  if (action === 'testServer' || action === 'reconnectServer') {
    srv.state = 'ready';
    if (state.type === 'connection') state.scenario = 'ready';
    render();
    toast(action === 'reconnectServer' ? `已重新连接 ${srv.alias} 并重新采集远端登录 Shell 与 MCP 状态` : `${srv.alias} 连接测试通过：remote-helper v10 握手成功`);
    return;
  }
  if (action === 'testAllServers') {
    toast('已并发发起全部 SSH 主机的免密探测与辅助进程握手');
    return;
  }
  if (action === 'promptPassword') { openPasswordModal(srv); return; }
  if (action === 'editServerConn') { openEditServerModal(srv); return; }
  if (action === 'viewSshConfigBlock') { openSshConfigBlockModal(srv); return; }
  if (action === 'browseRemoteDir' || action === 'browseMcpCwd') {
    openRemoteDirectoryModal(srv, el.dataset.path || '/home/ubuntu');
    return;
  }
  if (action === 'dirEnter' || action === 'dirUp') {
    state.dirBrowsePath = el.dataset.path || '/home/ubuntu';
    $('#aw-dialog-content').innerHTML = renderDirModalContent(currentServer());
    hydrateIcons();
    return;
  }
  if (action === 'dirGo' || action === 'dirRefresh') {
    const val = $('#aw-dir-input')?.value.trim() || '/home/ubuntu';
    if (!val.startsWith('/')) { toast('远端路径必须以 / 开头'); return; }
    state.dirBrowsePath = val;
    $('#aw-dialog-content').innerHTML = renderDirModalContent(currentServer());
    hydrateIcons();
    return;
  }
  if (action === 'deleteServer') {
    openDialog('删除 SSH 服务器？', `<p style="font-size:13px;color:rgb(var(--mdui-color-on-surface-variant))">确定从 <code>~/.ssh/config</code> 中移除受管标记块 <code>${escapeHTML(srv.alias)}</code>，并同步清除系统凭据库中的密码记录与专属 MCP 配置？</p>`, () => {
      state.servers = state.servers.filter(x => x.alias !== srv.alias);
      if (state.selectedServer === srv.alias && state.servers.length) state.selectedServer = state.servers[0].alias;
      state.page = 'list';
      toast(`已删除受管服务器 ${srv.alias}`);
      return true;
    }, '删除');
    return;
  }

  /* MCP Actions */
  if (action === 'filterMcpList') { state.mcpFilter = el.dataset.filter || 'all'; render(); return; }
  if (action === 'openMcpCreator') {
    state.mcpEditingId = null;
    state.mcpCreatorOpen = true;
    render();
    requestAnimationFrame(() => $('#aw-mcp-editor-card')?.scrollIntoView({ behavior: 'smooth', block: 'nearest' }));
    return;
  }
  if (action === 'closeMcpCreator') {
    state.mcpCreatorOpen = false;
    state.mcpEditingId = null;
    if (state.scenario === 'mcpCreate') state.scenario = 'mcpNormal';
    render();
    return;
  }
  if (action === 'pickMcpPreset') {
    const p = mcpPresets.find(x => x.key === el.dataset.preset);
    if (p) {
      state.mcpPreset = p.key;
      state.mcpForm = {
        id: p.id,
        transport: p.transport,
        command: p.command || 'uvx',
        args: p.args || '',
        cwd: p.cwd || '/home/ubuntu',
        env: p.env || '',
        endpoint: p.endpoint || 'http://127.0.0.1:9400/mcp',
        bearerEnv: p.bearerEnv || '',
        headers: p.headers || ''
      };
      render();
    }
    return;
  }
  if (action === 'setMcpTransport') {
    state.mcpForm.transport = el.dataset.transport || 'stdio';
    render();
    return;
  }
  if (action === 'editMcp') {
    const mcpId = el.dataset.mcp;
    const list = state.serverMcps[state.selectedServer] || [];
    const target = list.find(x => x.id === mcpId);
    if (target) {
      state.mcpEditingId = target.id;
      state.mcpCreatorOpen = true;
      state.mcpForm = {
        id: target.id,
        transport: target.transport,
        command: target.command || 'uvx',
        args: target.args || '',
        cwd: target.cwd || '/home/ubuntu',
        env: target.env || '',
        endpoint: target.endpoint || 'http://127.0.0.1:9400/mcp',
        bearerEnv: target.bearerEnv || '',
        headers: target.headers || ''
      };
      render();
      requestAnimationFrame(() => $('#aw-mcp-editor-card')?.scrollIntoView({ behavior: 'smooth', block: 'nearest' }));
    }
    return;
  }
  if (action === 'saveMcpForm') {
    const id = ($('#aw-mcp-id')?.value || state.mcpForm.id).trim();
    if (!/^[a-zA-Z0-9_-]+$/.test(id)) {
      toast('MCP 服务 ID 只能包含 ASCII 字母、数字、下划线 _ 和连字符 -');
      return;
    }
    const list = state.serverMcps[state.selectedServer] || (state.serverMcps[state.selectedServer] = []);
    const existingIdx = list.findIndex(x => x.id === (state.mcpEditingId || id));
    const entry = {
      id,
      scope: 'server',
      enabled: true,
      transport: state.mcpForm.transport,
      command: $('#aw-mcp-cmd')?.value.trim() || state.mcpForm.command,
      args: $('#aw-mcp-args')?.value.trim() || state.mcpForm.args,
      cwd: $('#aw-mcp-cwd')?.value.trim() || state.mcpForm.cwd,
      env: $('#aw-mcp-env')?.value.trim() || state.mcpForm.env,
      endpoint: $('#aw-mcp-endpoint')?.value.trim() || state.mcpForm.endpoint,
      bearerEnv: $('#aw-mcp-bearer')?.value.trim() || state.mcpForm.bearerEnv,
      headers: $('#aw-mcp-headers')?.value.trim() || state.mcpForm.headers,
      state: 'available',
      checkedAt: '刚刚',
      generation: existingIdx >= 0 ? (list[existingIdx].generation || 1) + 1 : 1,
      pid: state.mcpForm.transport === 'stdio' ? 52100 + Math.floor(Math.random() * 800) : undefined,
      tools: [
        { name: 'ping_status', fullName: `mcp__${id}__ping_status`, desc: '核验远端服务连通性与当前上下文权限边界' },
        { name: 'execute_query', fullName: `mcp__${id}__execute_query`, desc: '在远端服务器执行受控领域查询并返回结果' }
      ]
    };
    if (existingIdx >= 0) list[existingIdx] = entry;
    else list.unshift(entry);
    if (!state.expandedMcps.includes(id)) state.expandedMcps.push(id);
    state.mcpCreatorOpen = false;
    state.mcpEditingId = null;
    if (state.scenario === 'mcpCreate') state.scenario = 'mcpNormal';
    render();
    toast(`已保存服务器 ${state.selectedServer} 的远端 MCP 服务「${id}」并完成工具握手`);
    return;
  }
  if (action === 'deleteMcp') {
    const mcpId = el.dataset.mcp;
    openDialog('删除服务器专属 MCP 服务？', `<p style="font-size:13px;color:rgb(var(--mdui-color-on-surface-variant))">确定从服务器 <code>${escapeHTML(state.selectedServer)}</code> 移除远端 MCP 服务 <code>${escapeHTML(mcpId)}</code>？<br><br>正在进行中的会话轮次若持有该服务的当前代次租约，将在本轮结束后安全释放并回收远端子进程。</p>`, () => {
      state.serverMcps[state.selectedServer] = (state.serverMcps[state.selectedServer] || []).filter(x => x.id !== mcpId);
      toast(`已删除远端 MCP 服务「${mcpId}」`);
      return true;
    }, '确认删除');
    return;
  }
  if (action === 'reconnectMcp') {
    const mcpId = el.dataset.mcp;
    const list = state.serverMcps[state.selectedServer] || [];
    const target = list.find(x => x.id === mcpId);
    if (target) {
      target.state = 'available';
      target.generation = (target.generation || 1) + 1;
      target.checkedAt = '刚刚';
      if (!target.tools?.length) {
        target.tools = [{ name: 'status', fullName: `mcp__${target.id}__status`, desc: '重连握手后注册的远端工具' }];
      }
    }
    if (state.scenario === 'mcpStartFailed') state.scenario = 'mcpNormal';
    render();
    toast(`已重新连接远端 MCP「${mcpId}」，平滑切换至新代次租约`);
    return;
  }
  if (action === 'refreshServerMcp') {
    toast(`已刷新服务器 ${state.selectedServer} 上的全部远端 MCP 服务状态`);
    return;
  }
  if (action === 'resetAllServerMcp') {
    openDialog('重置当前服务器全部 MCP 服务？', `<p style="font-size:13px;color:rgb(var(--mdui-color-on-surface-variant))">将通过 <code>pl-remote-helper</code> 重新构建服务器 <code>${escapeHTML(state.selectedServer)}</code> 上已配置的全部 MCP 连接；当前进行中的任务继续使用重置前的代次连接。</p>`, () => {
      toast(`已重置 ${state.selectedServer} 的全部远端 MCP 服务`);
      return true;
    }, '全部重置');
    return;
  }
  if (action === 'toggleExpandAllMcp') {
    const list = serverMcpsList(state.selectedServer);
    const allIds = list.map(x => x.id);
    const allOpen = allIds.every(id => state.expandedMcps.includes(id));
    state.expandedMcps = allOpen ? [] : allIds;
    render();
    return;
  }
  if (action === 'setGlobalMcpPolicy') {
    const g = state.globalOverrides.find(x => x.id === el.dataset.id);
    if (g) {
      g.policy = el.dataset.policy;
      render();
      toast(`已更新全局 MCP「${g.id}」在 ${state.selectedServer} 上的覆盖策略`);
    }
    return;
  }

  /* Extension Tabs Actions */
  if (action === 'addServerEnvModal') {
    openDialog('添加服务器专属环境变量', `<div class="aw-form-stack">
      <mdui-text-field id="aw-new-env-key" label="环境变量名 (Key)" placeholder="例如 CUDA_VISIBLE_DEVICES / HTTP_PROXY" variant="outlined" required></mdui-text-field>
      <mdui-text-field id="aw-new-env-val" label="变量值 (Value)" placeholder="例如 0,1 或 http://10.0.0.1:7890" variant="outlined" required></mdui-text-field>
      <mdui-select id="aw-new-env-scope" label="作用范围" value="exec / MCP / LSP" variant="outlined">
        <mdui-menu-item value="exec / MCP / LSP">全部远端进程 (exec / MCP / LSP)</mdui-menu-item>
        <mdui-menu-item value="仅远端 MCP">仅远端 MCP 服务</mdui-menu-item>
        <mdui-menu-item value="exec / LSP">仅命令执行与 LSP</mdui-menu-item>
      </mdui-select>
    </div>`, () => {
      const k = $('#aw-new-env-key')?.value.trim();
      const v = $('#aw-new-env-val')?.value.trim();
      const sc = $('#aw-new-env-scope')?.value || 'exec / MCP / LSP';
      if (!k || !v) { toast('请填写变量名与变量值'); return false; }
      currentServer().envVars.push({ key: k, value: v, scope: sc, secret: false });
      toast(`已为 ${state.selectedServer} 添加环境变量 ${k}`);
      return true;
    }, '添加');
    return;
  }
  if (action === 'deleteServerEnv') {
    const idx = Number(el.dataset.idx);
    currentServer().envVars.splice(idx, 1);
    render();
    toast('已移除服务器环境变量');
    return;
  }
  if (action === 'addPortForwardModal') {
    openDialog('添加 SSH 端口转发规则', `<div class="aw-form-stack">
      <mdui-text-field id="aw-pf-label" label="用途名称" placeholder="例如 Jupyter Lab / Prometheus 面板" variant="outlined" required></mdui-text-field>
      <div class="aw-form-grid-2">
        <mdui-text-field id="aw-pf-local" label="本机监听地址" value="127.0.0.1:8888" variant="outlined" required></mdui-text-field>
        <mdui-text-field id="aw-pf-remote" label="远端目标地址" value="127.0.0.1:8888" variant="outlined" required></mdui-text-field>
      </div>
    </div>`, () => {
      const label = $('#aw-pf-label')?.value.trim() || '自定义端口映射';
      const local = $('#aw-pf-local')?.value.trim() || '127.0.0.1:8888';
      const remote = $('#aw-pf-remote')?.value.trim() || '127.0.0.1:8888';
      currentServer().portForwards.push({ id: `pf-${Date.now()}`, label, type: 'LocalForward', local, remote, active: true });
      toast(`已添加端口转发 ${local} -> ${remote}`);
      return true;
    }, '保存规则');
    return;
  }
  if (action === 'addSkillDirModal') {
    openDialog('添加服务器级共享技能目录', `<div class="aw-form-stack">
      <mdui-text-field id="aw-skill-dir-path" label="远端 POSIX 绝对路径" value="/opt/team-agents/skills" helper="作为只读技能源合并至该服务器上的所有项目工作区" variant="outlined" required></mdui-text-field>
    </div>`, () => {
      const p = $('#aw-skill-dir-path')?.value.trim() || '/opt/team-agents/skills';
      currentServer().skillDirs.push({ path: p, kind: '服务器级共享只读技能源', count: 3, status: '已启用' });
      toast(`已添加远端共享技能目录 ${p}`);
      return true;
    }, '添加目录');
    return;
  }
  if (action === 'probeRemoteLsp' || action === 'resetRemoteLsp') {
    toast(action === 'probeRemoteLsp' ? `已通过远端辅助进程探测 ${state.selectedServer} 的语言服务器环境` : `已重置 ${state.selectedServer} 的远端 LSP 实例`);
    return;
  }
  if (action === 'cleanHelperCache') {
    toast(`已清理 ${state.selectedServer} 上除当前 v10 摘要外的历史辅助进程缓存`);
    return;
  }
  if (action === 'copyText') {
    const t = el.dataset.text || '';
    navigator.clipboard?.writeText?.(t).catch(() => {});
    toast(`已复制：${t}`);
    return;
  }
});

Promise.all([
  'mdui-card', 'mdui-button', 'mdui-button-icon', 'mdui-segmented-button-group',
  'mdui-segmented-button', 'mdui-chip', 'mdui-select', 'mdui-switch',
  'mdui-text-field', 'mdui-list', 'mdui-list-item', 'mdui-list-subheader',
  'mdui-collapse', 'mdui-collapse-item', 'mdui-tabs', 'mdui-tab', 'mdui-tab-panel',
  'mdui-tooltip', 'mdui-avatar'
].map(t => customElements.whenDefined(t))).then(() => {
  render();
});
})();
