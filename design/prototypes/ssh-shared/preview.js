// Shared SSH remote development & server-scoped configuration prototype (Material 3 / Siamese Light Theme).
// Zero duplicate semantics, zero surface-vs-menu button duplication; all dynamic/extensible configs use dropdown menus.
document.getElementById("aw-preview-mount").innerHTML = `<div id="aw-ssh" class="mdui-theme-light" aria-label="SSH 远程开发与服务器配置 Material 3 设计预览">
  <mdui-card variant="outlined" class="aw-previewbar" aria-label="设计评审场景切换">
    <span class="aw-previewlabel"><i data-lucide="sliders-horizontal" aria-hidden="true"></i>场景预览</span>
    <mdui-select id="aw-type" label="设计维度" value="overview" variant="outlined"></mdui-select>
    <mdui-select id="aw-scenario" class="aw-state-select" label="展示状态" value="overview:normal" variant="outlined"></mdui-select>
    <div class="aw-stepper" aria-label="快速切换场景">
      <mdui-tooltip content="上一场景"><mdui-button-icon id="aw-prev-scenario" aria-label="上一场景"><i data-lucide="chevron-left" aria-hidden="true"></i></mdui-button-icon></mdui-tooltip>
      <span class="aw-scenario-index" id="aw-scenario-index">1 / 15</span>
      <mdui-tooltip content="下一场景"><mdui-button-icon id="aw-next-scenario" aria-label="下一场景"><i data-lucide="chevron-right" aria-hidden="true"></i></mdui-button-icon></mdui-tooltip>
    </div>
    <mdui-segmented-button-group selects="single" class="aw-view-group" id="aw-view-group" value="list" aria-label="视图切换">
      <mdui-segmented-button value="list" id="aw-view-list">服务器列表</mdui-segmented-button>
      <mdui-segmented-button value="detail" id="aw-view-detail">单机配置</mdui-segmented-button>
    </mdui-segmented-button-group>
  </mdui-card>
  <div class="aw-shell" id="aw-shell">
    <aside class="aw-sidebar">
      <div class="aw-brand"><mdui-avatar><i data-lucide="cat" aria-hidden="true"></i></mdui-avatar>糊来帮</div>
      <mdui-button variant="text" class="aw-back-chat" id="aw-back-chat" href="../project-sidebar/index.html"><span slot="icon"><i data-lucide="arrow-left" aria-hidden="true"></i></span>返回聊天</mdui-button>
      <nav id="aw-nav" aria-label="设置导航"></nav>
      <div class="aw-sidebar-bottom"><span class="aw-small-dot"></span>设置 · 远程开发</div>
    </aside>
    <main class="aw-main" id="aw-main"></main>
  </div>
  <div class="aw-preview-foot">
    <span><i data-lucide="palette" aria-hidden="true"></i>Material 3 · 暹罗浅色 · 零重复语义与全菜单化扩展</span>
    <span id="aw-coverage">示例数据 · 不修改真实 ~/.ssh/config</span>
  </div>
  <mdui-dialog id="aw-dialog" headline="服务器设置" close-on-esc>
    <div id="aw-dialog-content"></div>
    <mdui-button slot="action" variant="text" id="aw-dialog-cancel">取消</mdui-button>
    <mdui-button slot="action" variant="filled" id="aw-dialog-save">保存</mdui-button>
  </mdui-dialog>
  <mdui-snackbar id="aw-snackbar" placement="bottom" auto-close-delay="2600" closeable></mdui-snackbar>
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

const groups = {
  overview: {
    label: '服务器列表',
    states: [
      ['normal', '已配置多台服务器（默认）'],
      ['empty', '尚未配置服务器（空状态）']
    ]
  },
  connection: {
    label: '连接与认证状态',
    states: [
      ['ready', '已连接 · 远程助手就绪'],
      ['connecting', '首次连接 · 部署远程助手 (68%)'],
      ['reconnecting', '网络闪断 · 退避重连中'],
      ['passwordPrompt', '免密未过 · 弹窗输入密码'],
      ['pubkeyOnlyError', '认证失败 · 仅接受公钥'],
      ['browseDir', '浏览远端 POSIX 目录']
    ]
  },
  serverMcp: {
    label: '服务器 MCP 维护',
    states: [
      ['mcpNormal', '服务器专属 MCP 列表（默认）'],
      ['mcpCreate', '弹窗新建服务器 MCP（预设菜单）'],
      ['mcpMissingCred', 'MCP 缺少凭据提醒'],
      ['mcpStartFailed', 'MCP 启动失败状态'],
      ['mcpGlobalOverride', '全局 MCP 继承策略']
    ]
  },
  serverExtensions: {
    label: '服务器扩展配置菜单',
    states: [
      ['extConn', '配置菜单：连接与凭据'],
      ['extEnv', '配置菜单：环境变量与工具链'],
      ['extPorts', '配置菜单：端口转发规则'],
      ['extLspSkills', '配置菜单：语言服务与技能源'],
      ['extPolicy', '配置菜单：远程项目']
    ]
  }
};

const allSteps = Object.entries(groups).flatMap(([type, g]) => g.states.map(([s, label]) => ({ type, scenario: s, label })));
const totalScenarios = allSteps.length;

const mcpPresets = [
  { key: 'custom', name: '自定义远端 MCP 服务', transport: 'stdio', id: 'custom_remote_mcp', command: '/opt/mcp/bin/server', args: '--stdio', cwd: '/home/ubuntu', env: '' },
  { key: 'postgres', name: 'PostgreSQL 数据库 (uvx)', transport: 'stdio', id: 'postgres_prod', command: 'uvx', args: 'mcp-server-postgres postgresql://127.0.0.1:5432/ml_platform', cwd: '/srv/ml-platform', env: 'PGPASSWORD=••••••••' },
  { key: 'docker', name: 'Docker 容器引擎 (uvx)', transport: 'stdio', id: 'docker_engine', command: 'uvx', args: 'mcp-server-docker --socket unix:///var/run/docker.sock', cwd: '/home/ubuntu', env: '' },
  { key: 'filesystem', name: '远端受限目录访问 (npx)', transport: 'stdio', id: 'remote_dataset_fs', command: 'npx', args: '-y @modelcontextprotocol/server-filesystem /data/shared-datasets', cwd: '/data/shared-datasets', env: '' },
  { key: 'git', name: '远端 Git 仓库工具 (uvx)', transport: 'stdio', id: 'git_monorepo', command: 'uvx', args: 'mcp-server-git --repository /home/ubuntu/pure-lang', cwd: '/home/ubuntu/pure-lang', env: '' },
  { key: 'prometheus', name: '内网 HTTP 监控端点 (Streamable HTTP)', transport: 'streamableHttp', id: 'dcgm_metrics_http', endpoint: 'http://127.0.0.1:9400/mcp', bearerEnv: 'PROMETHEUS_MCP_TOKEN', headers: 'X-Cluster-Region: cn-north-gpu' }
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
    icon: 'cpu',
    state: 'ready',
    osShort: 'Ubuntu 24.04 · x86_64',
    shell: '/bin/bash',
    budgetUsed: '42 MB / 512 MB',
    projects: [
      { name: 'pure-lang', path: '/home/ubuntu/pure-lang', worktrees: 1, branch: 'main' },
      { name: 'llm-eval-harness', path: '/data/llm-eval-harness', worktrees: 0, branch: 'feat/v10-bench' }
    ],
    envVars: [
      { key: 'CUDA_VISIBLE_DEVICES', value: '0,1', scope: '全部远端任务', secret: false },
      { key: 'HF_ENDPOINT', value: 'https://hf-mirror.com', scope: 'exec / MCP', secret: false },
      { key: 'RUSTUP_DIST_SERVER', value: 'https://rsproxy.cn', scope: 'exec / LSP', secret: false },
      { key: 'INTERNAL_REGISTRY_TOKEN', value: 'glpat-••••••••92a1', scope: '仅远端 MCP', secret: true }
    ],
    toolchains: [
      { tool: 'node / npx', path: '/home/ubuntu/.nvm/versions/node/v22.9.0/bin' }
    ],
    lspServers: [
      { id: 'rust-analyzer', name: 'rust-analyzer', lang: 'Rust', state: 'available', detail: 'pure-lang', binary: '~/.cargo/bin/rust-analyzer' },
      { id: 'pyright', name: 'pyright-langserver', lang: 'Python', state: 'available', detail: 'llm-eval-harness', binary: '~/.local/bin/pyright-langserver' },
      { id: 'clangd', name: 'clangd', lang: 'C/CUDA', state: 'checking', detail: '索引中 74%', binary: '/usr/bin/clangd-18' }
    ],
    skillDirs: [
      { path: '<workspace>/.agents/skills', kind: '远端项目技能源', count: 6 },
      { path: '/opt/ai-infra/shared-skills', kind: '服务器共享只读源', count: 4 }
    ],
    portForwards: [
      { id: 'pf1', label: 'TensorBoard 面板', local: '127.0.0.1:6006', remote: '127.0.0.1:6006' },
      { id: 'pf2', label: 'vLLM 推理端口', local: '127.0.0.1:8000', remote: '127.0.0.1:8000' }
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
    icon: 'server',
    state: 'ready',
    osShort: 'Ubuntu 22.04 · aarch64',
    shell: '/bin/zsh',
    budgetUsed: '18 MB / 256 MB',
    projects: [
      { name: 'pl-remote-helper-musl', path: '/home/zhourui/pure-lang', worktrees: 2, branch: 'fix/arm64-stat' }
    ],
    envVars: [
      { key: 'CARGO_BUILD_TARGET', value: 'aarch64-unknown-linux-musl', scope: 'exec', secret: false }
    ],
    toolchains: [],
    lspServers: [
      { id: 'rust-analyzer', name: 'rust-analyzer', lang: 'Rust', state: 'available', detail: 'pl-remote-helper-musl', binary: '~/.cargo/bin/rust-analyzer' }
    ],
    skillDirs: [
      { path: '<workspace>/.agents/skills', kind: '远端项目技能源', count: 6 }
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
    icon: 'boxes',
    state: 'reconnecting',
    attempt: 3,
    osShort: 'Debian 12 · x86_64',
    shell: '/bin/bash',
    budgetUsed: '12 MB / 256 MB',
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
    icon: 'shield-alert',
    state: 'failed',
    errorMessage: '服务器未开启密码认证（Permission denied (publickey)），请检查私钥或 ssh-agent。',
    osShort: 'Rocky Linux 9',
    shell: '未采集',
    budgetUsed: '0 MB',
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
    icon: 'lock',
    state: 'disconnected',
    osShort: '手写 ~/.ssh/config 条目',
    shell: '按需采集',
    budgetUsed: '0 MB',
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
      enabled: true,
      transport: 'stdio',
      command: 'uvx',
      args: 'mcp-server-postgres postgresql://127.0.0.1:5432/ml_platform',
      cwd: '/srv/ml-platform',
      env: 'PGPASSWORD=••••••••',
      state: 'available',
      pid: 48291,
      tools: [
        { name: 'query', fullName: 'mcp__postgres_ml_meta__query', desc: '执行只读 SQL 查询并返回结果集' },
        { name: 'list_tables', fullName: 'mcp__postgres_ml_meta__list_tables', desc: '列出当前 schema 下的全部表与视图' },
        { name: 'describe_table', fullName: 'mcp__postgres_ml_meta__describe_table', desc: '查看指定表的字段类型与索引约束' },
        { name: 'explain_plan', fullName: 'mcp__postgres_ml_meta__explain_plan', desc: '分析 SQL 查询计划' }
      ]
    },
    {
      id: 'docker_gpu_runtime',
      enabled: true,
      transport: 'stdio',
      command: 'uvx',
      args: 'mcp-server-docker --socket unix:///var/run/docker.sock',
      cwd: '/home/ubuntu',
      env: 'DOCKER_API_VERSION=1.45',
      state: 'available',
      pid: 48304,
      tools: [
        { name: 'list_containers', fullName: 'mcp__docker_gpu_runtime__list_containers', desc: '列出远端容器状态' },
        { name: 'container_logs', fullName: 'mcp__docker_gpu_runtime__container_logs', desc: '读取远端容器标准输出日志' },
        { name: 'inspect_gpu_mounts', fullName: 'mcp__docker_gpu_runtime__inspect_gpu_mounts', desc: '检查 NVIDIA 容器设备挂载' }
      ]
    },
    {
      id: 'dcgm_cluster_metrics',
      enabled: true,
      transport: 'streamableHttp',
      endpoint: 'http://127.0.0.1:9400/mcp',
      bearerEnv: 'PROMETHEUS_MCP_TOKEN',
      headers: 'X-Cluster-Region: cn-north-gpu',
      state: 'available',
      tools: [
        { name: 'gpu_utilization', fullName: 'mcp__dcgm_cluster_metrics__gpu_utilization', desc: '读取 A100 SM 利用率、温度与显存' },
        { name: 'nccl_bandwidth', fullName: 'mcp__dcgm_cluster_metrics__nccl_bandwidth', desc: '查询 NVLink 通信吞吐' }
      ]
    },
    {
      id: 'github_enterprise_audit',
      enabled: true,
      transport: 'stdio',
      command: 'npx',
      args: '-y @modelcontextprotocol/server-github',
      cwd: '/home/ubuntu/pure-lang',
      env: 'GITHUB_PERSONAL_ACCESS_TOKEN=',
      state: 'missingCredential',
      errorMessage: '缺少环境变量 GITHUB_PERSONAL_ACCESS_TOKEN（可在右侧菜单编辑补齐）',
      tools: []
    },
    {
      id: 'legacy_redis_inspector',
      enabled: false,
      transport: 'stdio',
      command: 'uvx',
      args: 'mcp-server-redis redis://127.0.0.1:6379/0',
      cwd: '/home/ubuntu',
      env: '',
      state: 'disabled',
      tools: []
    }
  ],
  'dev-arm64-ubuntu': [
    {
      id: 'arm64_cross_fs',
      enabled: true,
      transport: 'stdio',
      command: 'npx',
      args: '-y @modelcontextprotocol/server-filesystem /opt/musl-toolchains',
      cwd: '/home/zhourui',
      env: '',
      state: 'available',
      pid: 19042,
      tools: [
        { name: 'read_file', fullName: 'mcp__arm64_cross_fs__read_file', desc: '读取交叉编译工具链头文件' },
        { name: 'list_directory', fullName: 'mcp__arm64_cross_fs__list_directory', desc: '列出 sysroot 目录' }
      ]
    }
  ]
};

const globalMcpOverrides = [
  { id: 'zhipu_search', transport: 'streamableHttp', source: '内置 (Zhipu)', policy: 'inherit', remapPath: '' },
  { id: 'zhipu_reader', transport: 'streamableHttp', source: '内置 (Zhipu)', policy: 'inherit', remapPath: '' },
  { id: 'filesystem', transport: 'stdio', source: 'Host mcp/filesystem.toml (/data/shared-datasets)', policy: 'remap', remapPath: '/data/shared-datasets' },
  { id: 'windows_local_automation', transport: 'stdio', source: 'Host mcp/windows_local_automation.toml (powershell.exe)', policy: 'disable', remapPath: '' }
];

const remoteDirTree = {
  '/home/ubuntu': {
    parent: '/home',
    entries: [
      { name: 'pure-lang', path: '/home/ubuntu/pure-lang', note: 'Git 仓库 · main' },
      { name: 'workspace-models', path: '/home/ubuntu/workspace-models', note: '目录' },
      { name: '.anywork', path: '/home/ubuntu/.anywork', note: '受管辅助进程与工作树' }
    ]
  },
  '/home/ubuntu/pure-lang': {
    parent: '/home/ubuntu',
    entries: [
      { name: 'code', path: '/home/ubuntu/pure-lang/code', note: '源码目录' },
      { name: 'design', path: '/home/ubuntu/pure-lang/design', note: '架构契约与原型' }
    ]
  },
  '/data': {
    parent: '/',
    entries: [
      { name: 'llm-eval-harness', path: '/data/llm-eval-harness', note: 'Git 仓库' },
      { name: 'shared-datasets', path: '/data/shared-datasets', note: '数据集目录' }
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
const rawPage = urlParams.get('page') || mountPage;
const initPage = rawPage === 'add' ? 'add' : (rawPage === 'detail' || rawPage === 'mcp') ? 'detail' : 'list';

let state = {
  type: 'overview',
  scenario: 'normal',
  page: initPage,
  selectedServer: urlParams.get('server') || 'gpu-a100-prod',
  configSection: rawPage === 'mcp' ? 'mcp' : (urlParams.get('section') || 'mcp'),
  search: '',
  mcpSearch: '',
  servers: JSON.parse(JSON.stringify(initialServers)),
  serverMcps: JSON.parse(JSON.stringify(initialServerMcps)),
  globalOverrides: JSON.parse(JSON.stringify(globalMcpOverrides)),
  addForm: {
    alias: 'gpu-h100-cluster',
    hostName: '10.24.12.88',
    port: '22',
    username: 'ubuntu',
    identityFile: '~/.ssh/id_ed25519_gpu',
    password: ''
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
      errorMessage: '启动失败 (exit 127)：远端 PATH 未找到 uvx（可在菜单「编辑配置」或「环境变量与工具链」中指定路径）'
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
  if (st === 'connecting') return status('部署远程助手 68%', 'info', 'loader');
  if (st === 'reconnecting') return status(`重连中 · 第 ${s.attempt || 3} 次`, 'warning', 'refresh-cw');
  if (st === 'waitingForInput') return status('需密码认证', 'warning', 'key-round');
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
  if (!m.enabled || m.state === 'disabled') return '';
  if (m.state === 'available') return status('就绪', 'success', 'check');
  if (m.state === 'missingCredential') return status('缺少凭据', 'warning', 'key-round');
  return status('启动失败', 'error', 'circle-alert');
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

/* ---------------- SERVER CONFIG MENU DEFINITIONS ---------------- */
function getServerConfigSections(s) {
  const mcps = serverMcpsList(s.alias);
  const enabledMcps = mcps.filter(m => m.enabled).length;
  const activeOverrides = state.globalOverrides.filter(g => g.policy !== 'inherit').length;
  return [
    { key: 'mcp', group: 'MCP 与工具服务', label: '远端 MCP 服务', icon: 'network', count: `${enabledMcps}/${mcps.length}` },
    { key: 'mcpGlobal', group: 'MCP 与工具服务', label: '全局 MCP 继承策略', icon: 'git-merge', count: activeOverrides ? `${activeOverrides} 覆盖` : '默认' },
    { key: 'conn', group: '连接与运行环境', label: '连接与凭据', icon: 'key-round', count: s.managed ? '受管' : '只读' },
    { key: 'env', group: '连接与运行环境', label: '环境变量与工具链', icon: 'terminal', count: `${s.envVars.length + s.toolchains.length}` },
    { key: 'ports', group: '开发与工作区扩展', label: '端口转发规则', icon: 'arrow-left-right', count: `${s.portForwards.length}` },
    { key: 'lsp', group: '开发与工作区扩展', label: '语言服务与技能源', icon: 'code', count: `${s.lspServers.length}` },
    { key: 'policy', group: '开发与工作区扩展', label: '远程项目', icon: 'folder-git-2', count: `${s.projects.length}` }
  ];
}

/* ---------------- VIEW 1: SERVER LIST (Zero Surface/Menu Duplication) ---------------- */
function serverSummaryText(s) {
  const mcps = serverMcpsList(s.alias).filter(m => m.enabled);
  const parts = [];
  if (mcps.length) parts.push(`${mcps.length} 个 MCP`);
  if (s.envVars.length) parts.push(`${s.envVars.length} 项变量`);
  if (s.portForwards.length) parts.push(`${s.portForwards.length} 个转发`);
  if (s.projects.length) parts.push(`${s.projects.length} 个项目`);
  return parts.length ? parts.join(' · ') : s.osShort;
}

function serverRowMarkup(s) {
  const st = effectiveServerState(s);
  const banner = st === 'failed' || (s.alias === state.selectedServer && state.scenario === 'pubkeyOnlyError')
    ? `<div class="aw-server-row-banner error"><div class="aw-row">${icon('circle-alert')}<span>${escapeHTML(s.errorMessage || '连接认证失败，请检查私钥或 ssh-agent。')}</span></div>${btn('重试', 'testServer', 'tonal', 'refresh-cw', `data-server="${s.alias}"`)}</div>`
    : st === 'waitingForInput'
    ? `<div class="aw-server-row-banner warning"><div class="aw-row">${icon('key-round')}<span>免密探测未通过，需要输入 SSH 密码。</span></div>${btn('输入密码', 'promptPassword', 'filled', 'log-in', `data-server="${s.alias}"`)}</div>`
    : st === 'connecting'
    ? `<div class="aw-server-row-banner info"><div style="flex:1"><div class="aw-between" style="margin-bottom:4px"><span>正在部署 <code>pl-remote-helper</code> (v11)…</span><span class="aw-mono">68%</span></div><mdui-linear-progress value="0.68"></mdui-linear-progress></div></div>`
    : '';

  return `<article class="aw-server-row" data-server-row="${escapeHTML(s.alias)}">
    <div class="aw-server-row-main aw-server-grid">
      <button type="button" class="aw-server-open" data-action="openDetail" data-server="${escapeHTML(s.alias)}" aria-label="打开 ${escapeHTML(s.alias)} 配置">
        <span class="aw-logo">${icon(s.icon || 'server')}<span class="aw-logo-dot ${dotTone(s)}"></span></span>
        <div style="min-width:0">
          <div class="aw-row" style="gap:6px">
            <span class="aw-server-alias">${escapeHTML(s.alias)}</span>
            ${!s.managed ? `<span class="aw-mini-pill">${icon('lock')}只读</span>` : ''}
          </div>
          <div class="aw-server-target">${escapeHTML(s.username)}@${escapeHTML(s.hostName)}:${s.port}</div>
        </div>
      </button>

      <div>${connStatusBadge(s)}</div>

      <div class="aw-summary-text" title="${escapeHTML(serverSummaryText(s))}">${escapeHTML(serverSummaryText(s))}</div>

      <mdui-dropdown placement="bottom-end">
        <mdui-button-icon slot="trigger" aria-label="${escapeHTML(s.alias)}操作菜单">${icon('ellipsis')}</mdui-button-icon>
        <mdui-menu>
          <mdui-menu-item data-action="browseRemoteDir" data-server="${escapeHTML(s.alias)}">${icon('folder-open', 'icon')}打开远端项目…</mdui-menu-item>
          <mdui-menu-item data-action="reconnectServer" data-server="${escapeHTML(s.alias)}">${icon('refresh-cw', 'icon')}重新连接</mdui-menu-item>
          <mdui-menu-item data-action="editServerConn" data-server="${escapeHTML(s.alias)}" ${!s.managed ? 'disabled' : ''}>${icon('pencil', 'icon')}编辑连接</mdui-menu-item>
          <mdui-divider></mdui-divider>
          <mdui-menu-item data-action="deleteServer" data-server="${escapeHTML(s.alias)}" ${!s.managed ? 'disabled' : ''} style="color:rgb(var(--mdui-color-error))">${icon('trash-2', 'icon')}删除服务器</mdui-menu-item>
        </mdui-menu>
      </mdui-dropdown>
    </div>
    ${banner}
  </article>`;
}

function listMarkup() {
  const emptyScenario = state.type === 'overview' && state.scenario === 'empty';
  const q = state.search.trim().toLowerCase();
  const list = emptyScenario ? [] : state.servers.filter(s => {
    if (!q) return true;
    return [s.alias, s.hostName, s.username, s.osShort].some(v => v.toLowerCase().includes(q));
  });
  const readyCount = state.servers.filter(s => effectiveServerState(s) === 'ready').length;

  return `<div class="aw-page-header">
    <div>
      <div class="aw-row">${iconBtn('设置导航', 'mobileNav', 'menu', 'class="aw-menu-mobile"')}<h1>SSH 远程服务器</h1></div>
      <p class="aw-page-subtitle">同步自 <code>~/.ssh/config</code>；点击服务器进入其 MCP 服务与扩展配置。</p>
    </div>
    ${btn('添加服务器', 'goAddServer', 'filled', 'plus')}
  </div>

  <div class="aw-tools">
    <mdui-text-field id="aw-ssh-search" class="aw-search" variant="outlined" placeholder="搜索服务器别名、地址或用户名…" value="${escapeHTML(state.search)}" clearable>${icon('search', 'icon')}</mdui-text-field>
    <div class="aw-tools-meta">${emptyScenario ? '共 0 台服务器' : `共 ${list.length} 台 · ${readyCount} 台已连接`}</div>
  </div>

  <mdui-card variant="outlined" class="aw-server-card">
    <div class="aw-table-head aw-server-grid">
      <span>服务器</span>
      <span>状态</span>
      <span>已启用配置</span>
      <span></span>
    </div>
    ${emptyScenario ? `<div class="aw-empty">
      ${icon('server')}
      <h2>尚未配置 SSH 服务器</h2>
      <p>添加远程服务器后，可在远端打开项目并配置该服务器的 MCP 服务与运行环境。</p>
      ${btn('添加服务器', 'goAddServer', 'filled', 'plus')}
    </div>` : !list.length ? `<div class="aw-empty">
      ${icon('search')}
      <h2>没有找到匹配的服务器</h2>
      <p>请尝试其他关键词或清除搜索条件。</p>
      ${btn('清除搜索', 'clearServerSearch', 'tonal')}
    </div>` : list.map(serverRowMarkup).join('')}
  </mdui-card>`;
}

/* ---------------- VIEW 2: COMPACT ADD SERVER ---------------- */
function sshConfigBlockText(f) {
  const alias = (f.alias || 'my-server').trim();
  const host = (f.hostName || '192.168.1.10').trim();
  const port = (f.port || '22').trim();
  const user = (f.username || 'ubuntu').trim();
  const idFile = (f.identityFile || '').trim();
  return `<span class="aw-comment"># BEGIN anywork server: ${escapeHTML(alias)}</span>\nHost ${escapeHTML(alias)}\n    HostName ${escapeHTML(host)}\n    Port ${escapeHTML(port)}\n    User ${escapeHTML(user)}${idFile ? `\n    IdentityFile ${escapeHTML(idFile)}` : ''}\n<span class="aw-comment"># END anywork server: ${escapeHTML(alias)}</span>`;
}

function addMarkup() {
  const f = state.addForm;
  return `<div class="aw-topbar">
    <mdui-button variant="text" data-action="goList" class="aw-back">${icon('arrow-left', 'icon')}返回服务器列表</mdui-button>
  </div>
  <div class="aw-page-header">
    <h1>添加 SSH 服务器</h1>
  </div>

  <mdui-card variant="outlined" class="aw-setting-card" style="padding:20px 22px">
    <div class="aw-form-stack">
      <div class="aw-form-grid-2">
        <mdui-text-field id="aw-add-alias" label="别名 (Host)" value="${escapeHTML(f.alias)}" helper="唯一标识，创建后不可改名" variant="outlined" required>${icon('badge', 'icon')}</mdui-text-field>
        <mdui-text-field id="aw-add-host" label="主机地址 (HostName)" value="${escapeHTML(f.hostName)}" placeholder="IP 或域名" variant="outlined" required>${icon('server', 'icon')}</mdui-text-field>
      </div>
      <div class="aw-form-grid-3">
        <mdui-text-field id="aw-add-user" label="用户名 (User)" value="${escapeHTML(f.username)}" variant="outlined" required>${icon('user', 'icon')}</mdui-text-field>
        <mdui-text-field id="aw-add-identity" label="私钥路径 (IdentityFile，可选)" value="${escapeHTML(f.identityFile)}" helper="留空则使用默认密钥或 ssh-agent" variant="outlined">${icon('key-round', 'icon')}</mdui-text-field>
        <mdui-text-field id="aw-add-port" label="端口 (Port)" value="${escapeHTML(f.port)}" type="number" min="1" max="65535" variant="outlined"></mdui-text-field>
      </div>
      <mdui-text-field id="aw-add-password" label="SSH 密码（可选，存入系统凭据库）" type="password" value="${escapeHTML(f.password)}" placeholder="留空则优先免密或连接时按需输入" variant="outlined">${icon('lock-keyhole', 'icon')}</mdui-text-field>

      <mdui-collapse>
        <mdui-collapse-item value="cfg-preview">
          <mdui-list-item slot="header" headline="预览 ~/.ssh/config 受管块" style="--min-height:38px">
            ${icon('file-code', 'icon')}
            ${icon('chevron-right', 'end-icon')}
          </mdui-list-item>
          <div style="padding:0 14px 12px">
            <div class="aw-code-preview" id="aw-ssh-block-preview">${sshConfigBlockText(f)}</div>
          </div>
        </mdui-collapse-item>
      </mdui-collapse>

      <div class="aw-row" style="justify-content:flex-end;padding-top:10px;border-top:1px solid rgb(var(--mdui-color-outline-variant))">
        ${btn('取消', 'goList', 'text')}
        ${btn('保存', 'submitAddServer', 'filled', 'check')}
      </div>
    </div>
  </mdui-card>`;
}

/* ---------------- VIEW 3: UNIFIED SERVER WORKSPACE (Single Toolbar + Menu) ---------------- */
function renderMcpRow(m) {
  const isMissingCred = m.state === 'missingCredential' || (state.type === 'serverMcp' && state.scenario === 'mcpMissingCred' && m.id === 'github_enterprise_audit');
  const isFailed = m.state === 'unavailable';
  const cmdSummary = m.transport === 'stdio'
    ? `stdio · ${m.command} ${m.args}`
    : `HTTP · ${m.endpoint}`;
  const subText = isMissingCred ? (m.errorMessage || '缺少凭据环境变量') : isFailed ? (m.errorMessage || '远端进程启动失败') : cmdSummary;
  const subCls = isMissingCred ? 'warn' : isFailed ? 'err' : '';
  const tools = m.tools || [];

  return `<div class="aw-mcp-row">
    <div class="aw-mcp-row-info">
      <div class="aw-mcp-row-title">
        <span>${escapeHTML(m.id)}</span>
        ${mcpStateBadge(m)}
      </div>
      <div class="aw-mcp-row-sub ${subCls}" title="${escapeHTML(subText)}">${escapeHTML(subText)}</div>
    </div>

    <div class="aw-mcp-row-actions">
      ${tools.length ? `<mdui-dropdown placement="bottom-end">
        <mdui-button slot="trigger" variant="outlined" style="height:28px;font-size:12px">
          ${icon('wrench', 'icon')}工具 (${tools.length}) ${icon('chevron-down', 'end-icon')}
        </mdui-button>
        <mdui-menu class="aw-tools-menu-panel">
          <mdui-list-subheader>点击复制工具标识 (mcp__${escapeHTML(m.id)}__*)</mdui-list-subheader>
          ${tools.map(t => `<div class="aw-tool-menu-row" data-action="copyText" data-text="${escapeHTML(t.fullName)}">
            <div class="aw-between"><code>${escapeHTML(t.name)}</code><small class="aw-mono">复制</small></div>
            <small>${escapeHTML(t.desc)}</small>
          </div>`).join('')}
        </mdui-menu>
      </mdui-dropdown>` : ''}

      <mdui-switch data-mcp-switch="${escapeHTML(m.id)}" ${m.enabled ? 'checked' : ''} aria-label="启用 ${escapeHTML(m.id)}"></mdui-switch>

      <mdui-dropdown placement="bottom-end">
        <mdui-button-icon slot="trigger" aria-label="${escapeHTML(m.id)}操作菜单">${icon('ellipsis')}</mdui-button-icon>
        <mdui-menu>
          <mdui-menu-item data-action="editMcpModal" data-mcp="${escapeHTML(m.id)}">${icon('pencil', 'icon')}编辑配置</mdui-menu-item>
          <mdui-menu-item data-action="reconnectMcp" data-mcp="${escapeHTML(m.id)}" ${!m.enabled ? 'disabled' : ''}>${icon('refresh-cw', 'icon')}重新探测</mdui-menu-item>
          <mdui-menu-item data-action="inspectMcpRuntime" data-mcp="${escapeHTML(m.id)}">${icon('info', 'icon')}运行详情</mdui-menu-item>
          <mdui-divider></mdui-divider>
          <mdui-menu-item data-action="deleteMcp" data-mcp="${escapeHTML(m.id)}" style="color:rgb(var(--mdui-color-error))">${icon('trash-2', 'icon')}删除</mdui-menu-item>
        </mdui-menu>
      </mdui-dropdown>
    </div>
  </div>`;
}

function sectionMcpContent(s) {
  const allMcps = serverMcpsList(s.alias);
  const q = state.mcpSearch.trim().toLowerCase();
  const filtered = allMcps.filter(m => {
    if (!q) return true;
    return [m.id, m.command || '', m.args || '', m.endpoint || ''].some(x => x.toLowerCase().includes(q));
  });

  if (!filtered.length) {
    return `<mdui-card variant="outlined" class="aw-empty">
      ${icon('network')}
      <h2>${allMcps.length ? '未找到匹配的 MCP 服务' : '尚未配置此服务器的专属 MCP'}</h2>
      <p>点击右上角「添加 MCP 服务」从预设模板菜单创建远端 stdio 或 HTTP 服务。</p>
    </mdui-card>`;
  }
  return `<mdui-card variant="outlined" class="aw-setting-card">
    ${filtered.map(renderMcpRow).join('')}
  </mdui-card>`;
}

function sectionMcpGlobalContent() {
  return `<mdui-card variant="outlined" class="aw-setting-card" style="overflow:hidden">
    <table class="aw-env-table">
      <thead>
        <tr>
          <th>全局 MCP ID</th>
          <th>来源与远端路径说明</th>
          <th style="text-align:right;width:190px">本机策略</th>
        </tr>
      </thead>
      <tbody>
        ${state.globalOverrides.map(g => `<tr>
          <td><code>${escapeHTML(g.id)}</code></td>
          <td><small>${escapeHTML(g.transport)} · ${escapeHTML(g.source)}</small></td>
          <td style="text-align:right">
            <mdui-select variant="outlined" value="${g.policy}" data-global-mcp-select="${escapeHTML(g.id)}" style="width:170px;--mdui-typescale-body-large-size:12px">
              <mdui-menu-item value="inherit">跟随全局</mdui-menu-item>
              <mdui-menu-item value="remap">重映射远端路径</mdui-menu-item>
              <mdui-menu-item value="disable">在此服务器禁用</mdui-menu-item>
            </mdui-select>
          </td>
        </tr>`).join('')}
      </tbody>
    </table>
  </mdui-card>`;
}

function sectionConnContent(s) {
  return `<mdui-card variant="outlined" class="aw-setting-card">
    <mdui-list>
      <mdui-list-item nonclickable headline="主机地址与端口" description="${s.managed ? '~/.ssh/config 受管块' : '~/.ssh/config 手写只读条目'}">
        ${icon('server', 'icon')}
        <div slot="end-icon" class="aw-row">
          <code>${escapeHTML(s.username)}@${escapeHTML(s.hostName)}:${s.port}</code>
          ${iconBtn('复制地址', 'copyText', 'copy', `data-text="${escapeHTML(s.username)}@${escapeHTML(s.hostName)}:${s.port}"`)}
        </div>
      </mdui-list-item>
      <mdui-divider></mdui-divider>
      <mdui-list-item nonclickable headline="公钥认证" description="${s.identityFile ? `私钥路径：${s.identityFile}` : '默认使用 ssh-agent 与标准密钥'}">
        ${icon('key-round', 'icon')}
        <div slot="end-icon">${status(s.identityFile ? '指定私钥' : 'ssh-agent', 'success', 'check')}</div>
      </mdui-list-item>
      <mdui-divider></mdui-divider>
      <mdui-list-item nonclickable headline="系统凭据库密码" description="${s.hasPassword ? `已存于 ssh:${s.alias}，绝不写入配置文件` : '未保存密码，免密未过时按需弹窗'}">
        ${icon('lock-keyhole', 'icon')}
        <div slot="end-icon">${s.hasPassword ? status('已保存', 'success') : status('未保存', 'neutral')}</div>
      </mdui-list-item>
    </mdui-list>
  </mdui-card>`;
}

function sectionEnvContent(s) {
  return `<mdui-card variant="outlined" class="aw-setting-card" style="overflow:hidden">
    <table class="aw-env-table">
      <thead>
        <tr><th>类别 / 变量名</th><th>值或覆盖路径</th><th>作用域</th><th style="text-align:right"></th></tr>
      </thead>
      <tbody>
        ${s.envVars.map((ev, idx) => `<tr>
          <td><code>${escapeHTML(ev.key)}</code></td>
          <td><code>${escapeHTML(ev.value)}</code> ${ev.secret ? chip('凭据库') : ''}</td>
          <td><span class="aw-mini-pill">${escapeHTML(ev.scope)}</span></td>
          <td style="text-align:right">${iconBtn('移除', 'deleteServerEnv', 'trash-2', `data-idx="${idx}" style="color:rgb(var(--mdui-color-error))"`)}</td>
        </tr>`).join('')}
        ${s.toolchains.map((tc, idx) => `<tr>
          <td><strong>${escapeHTML(tc.tool)}</strong></td>
          <td><code>${escapeHTML(tc.path)}</code></td>
          <td><span class="aw-mini-pill">工具链路径覆盖</span></td>
          <td style="text-align:right">${iconBtn('移除', 'deleteToolchain', 'trash-2', `data-idx="${idx}" style="color:rgb(var(--mdui-color-error))"`)}</td>
        </tr>`).join('')}
        ${!s.envVars.length && !s.toolchains.length ? `<tr><td colspan="4" style="text-align:center;padding:24px;color:rgb(var(--mdui-color-on-surface-variant))">默认继承远端登录 Shell (${escapeHTML(s.shell)})，右上角菜单可添加变量或工具路径覆盖。</td></tr>` : ''}
      </tbody>
    </table>
  </mdui-card>`;
}

function sectionPortsContent(s) {
  return `<mdui-card variant="outlined" class="aw-setting-card" style="overflow:hidden">
    ${s.portForwards.length ? `<table class="aw-env-table">
      <thead>
        <tr><th>名称</th><th>本机监听</th><th>远端目标</th><th style="text-align:right"></th></tr>
      </thead>
      <tbody>
        ${s.portForwards.map((pf, idx) => `<tr>
          <td><strong>${escapeHTML(pf.label)}</strong></td>
          <td><code>${escapeHTML(pf.local)}</code></td>
          <td><code>${escapeHTML(pf.remote)}</code></td>
          <td style="text-align:right">${iconBtn('删除转发', 'deletePortForward', 'trash-2', `data-idx="${idx}" style="color:rgb(var(--mdui-color-error))"`)}</td>
        </tr>`).join('')}
      </tbody>
    </table>` : `<div class="aw-empty" style="padding:28px"><h3>暂无端口转发规则</h3><p>点击右上角添加 LocalForward 端口映射。</p></div>`}
  </mdui-card>`;
}

function sectionLspContent(s) {
  return `<mdui-card variant="outlined" class="aw-setting-card">
    <mdui-list>
      <mdui-list-subheader>远端 LSP 进程</mdui-list-subheader>
      ${s.lspServers.length ? s.lspServers.map(l => `
        <mdui-list-item nonclickable headline="${escapeHTML(l.name)} (${escapeHTML(l.lang)})" description="${escapeHTML(l.detail)} · ${escapeHTML(l.binary)}">
          ${icon('code', 'icon')}
          <div slot="end-icon">${status(l.state === 'available' ? '就绪' : '索引中', l.state === 'available' ? 'success' : 'info')}</div>
        </mdui-list-item>
      `).join('<mdui-divider></mdui-divider>') : `<mdui-list-item nonclickable headline="暂无活动 LSP 进程" description="打开远程项目后按语言自动拉起"></mdui-list-item>`}
      <mdui-divider></mdui-divider>
      <mdui-list-subheader>技能目录源 (Skills)</mdui-list-subheader>
      ${(s.skillDirs.length ? s.skillDirs : [{ path: '<workspace>/.agents/skills', kind: '远端项目技能源', count: 0 }]).map((d, idx) => `
        <mdui-list-item nonclickable headline="${escapeHTML(d.path)}" description="${escapeHTML(d.kind)}">
          ${icon('puzzle', 'icon')}
          <div slot="end-icon" class="aw-row">
            ${chip(`${d.count} 个技能`)}
            ${idx > 0 ? iconBtn('移除目录', 'deleteSkillDir', 'trash-2', `data-idx="${idx}" style="color:rgb(var(--mdui-color-error))"`) : ''}
          </div>
        </mdui-list-item>
      `).join('')}
    </mdui-list>
  </mdui-card>`;
}

function sectionPolicyContent(s) {
  return `<mdui-card variant="outlined" class="aw-setting-card">
    <mdui-list>
      <mdui-list-subheader>已关联远程项目 (${s.projects.length})</mdui-list-subheader>
      ${s.projects.length ? s.projects.map((p, idx) => `
        <mdui-list-item nonclickable headline="${escapeHTML(p.name)}" description="${escapeHTML(p.path)} · 分支 ${escapeHTML(p.branch)}">
          ${icon('folder-git-2', 'icon')}
          <div slot="end-icon" class="aw-row">
            ${p.worktrees ? chip(`${p.worktrees} 个工作树`) : chip('local 目录')}
            ${iconBtn('移除项目关联', 'removeProject', 'trash-2', `data-idx="${idx}" style="color:rgb(var(--mdui-color-error))"`)}
          </div>
        </mdui-list-item>
      `).join('<mdui-divider></mdui-divider>') : `<mdui-list-item nonclickable headline="尚未关联远程项目" description="可通过右上角「打开项目」接入远端目录"></mdui-list-item>`}
      <mdui-divider></mdui-divider>
    </mdui-list>
  </mdui-card>`;
}

function moduleRightActionMarkup(activeKey) {
  if (activeKey === 'mcp') return btn('添加 MCP 服务', 'openMcpModal', 'filled', 'plus');
  if (activeKey === 'env') {
    return `<mdui-dropdown placement="bottom-end">
      <mdui-button slot="trigger" variant="filled">${icon('plus', 'icon')}添加配置 ${icon('chevron-down', 'end-icon')}</mdui-button>
      <mdui-menu>
        <mdui-menu-item data-action="addServerEnvModal">${icon('terminal', 'icon')}添加环境变量…</mdui-menu-item>
        <mdui-menu-item data-action="addToolchainModal">${icon('wrench', 'icon')}覆盖工具链路径…</mdui-menu-item>
      </mdui-menu>
    </mdui-dropdown>`;
  }
  if (activeKey === 'ports') return btn('添加端口转发', 'addPortForwardModal', 'filled', 'plus');
  if (activeKey === 'lsp') {
    return `<mdui-dropdown placement="bottom-end">
      <mdui-button slot="trigger" variant="tonal">${icon('sliders-horizontal', 'icon')}维护操作 ${icon('chevron-down', 'end-icon')}</mdui-button>
      <mdui-menu>
        <mdui-menu-item data-action="addSkillDirModal">${icon('folder-plus', 'icon')}添加共享技能目录…</mdui-menu-item>
        <mdui-menu-item data-action="resetRemoteLsp">${icon('rotate-ccw', 'icon')}重置远端 LSP 进程</mdui-menu-item>
      </mdui-menu>
    </mdui-dropdown>`;
  }
  if (activeKey === 'policy') return btn('清理远端缓存', 'cleanHelperCache', 'tonal', 'sparkles');
  return '';
}

function serverWorkspaceMarkup() {
  const s = currentServer();
  const sections = getServerConfigSections(s);
  const activeKey = sections.some(x => x.key === state.configSection) ? state.configSection : 'mcp';
  const currentSec = sections.find(x => x.key === activeKey) || sections[0];
  const groupsOrder = ['MCP 与工具服务', '连接与运行环境', '开发与工作区扩展'];

  let bodyHtml = '';
  if (activeKey === 'mcp') bodyHtml = sectionMcpContent(s);
  else if (activeKey === 'mcpGlobal') bodyHtml = sectionMcpGlobalContent();
  else if (activeKey === 'env') bodyHtml = sectionEnvContent(s);
  else if (activeKey === 'ports') bodyHtml = sectionPortsContent(s);
  else if (activeKey === 'lsp') bodyHtml = sectionLspContent(s);
  else if (activeKey === 'policy') bodyHtml = sectionPolicyContent(s);
  else bodyHtml = sectionConnContent(s);

  return `<div class="aw-topbar">
    <mdui-button variant="text" data-action="goList" class="aw-back">${icon('arrow-left', 'icon')}返回服务器列表</mdui-button>
  </div>

  <div class="aw-page-header" style="margin-bottom:14px">
    <div class="aw-detail-identity">
      <span class="aw-logo large">${icon(s.icon || 'server')}<span class="aw-logo-dot ${dotTone(s)}"></span></span>
      <div>
        <div class="aw-row" style="gap:8px">
          <mdui-dropdown placement="bottom-start">
            <button type="button" slot="trigger" class="aw-server-title-trigger" title="点击切换目标服务器">
              <span>${escapeHTML(s.alias)}</span>
              ${icon('chevron-down')}
            </button>
            <mdui-menu>
              <mdui-list-subheader>切换服务器 (${state.servers.length})</mdui-list-subheader>
              ${state.servers.map(srv => `<mdui-menu-item data-action="switchServer" data-server="${escapeHTML(srv.alias)}">
                ${icon(srv.alias === s.alias ? 'check' : 'server', 'icon')}
                <span>${escapeHTML(srv.alias)} <small class="aw-muted">(${escapeHTML(srv.hostName)})</small></span>
              </mdui-menu-item>`).join('')}
            </mdui-menu>
          </mdui-dropdown>
          ${connStatusBadge(s)}
          ${!s.managed ? chip('只读') : ''}
        </div>
        <div class="aw-endpoint-line">
          <code>${escapeHTML(s.username)}@${escapeHTML(s.hostName)}:${s.port}</code>
          <span>·</span>
          <span>${escapeHTML(s.osShort)}</span>
        </div>
      </div>
    </div>

    <div class="aw-row">
      ${btn('打开项目…', 'browseRemoteDir', 'tonal', 'folder-open', `data-server="${escapeHTML(s.alias)}"`)}
      <mdui-dropdown placement="bottom-end">
        <mdui-button-icon slot="trigger" aria-label="服务器操作菜单">${icon('ellipsis')}</mdui-button-icon>
        <mdui-menu>
          <mdui-menu-item data-action="reconnectServer" data-server="${escapeHTML(s.alias)}">${icon('refresh-cw', 'icon')}重新连接</mdui-menu-item>
          <mdui-menu-item data-action="viewSshConfigBlock" data-server="${escapeHTML(s.alias)}">${icon('file-code', 'icon')}查看 ~/.ssh/config 块</mdui-menu-item>
          <mdui-menu-item data-action="editServerConn" data-server="${escapeHTML(s.alias)}" ${!s.managed ? 'disabled' : ''}>${icon('pencil', 'icon')}编辑连接与密码</mdui-menu-item>
          <mdui-divider></mdui-divider>
          <mdui-menu-item data-action="deleteServer" data-server="${escapeHTML(s.alias)}" ${!s.managed ? 'disabled' : ''} style="color:rgb(var(--mdui-color-error))">${icon('trash-2', 'icon')}删除服务器</mdui-menu-item>
        </mdui-menu>
      </mdui-dropdown>
    </div>
  </div>

  <div class="aw-module-toolbar" role="navigation" aria-label="服务器配置项与操作栏">
    <div class="aw-row" style="flex:1">
      <mdui-dropdown placement="bottom-start">
        <button type="button" slot="trigger" class="aw-menu-trigger-btn" aria-label="选择服务器配置模块">
          ${icon(currentSec.icon)}
          <span>${escapeHTML(currentSec.label)}</span>
          <span class="aw-menu-badge">${escapeHTML(currentSec.count)}</span>
          ${icon('chevron-down')}
        </button>
        <mdui-menu style="min-width:260px">
          ${groupsOrder.map((grp, gi) => `
            ${gi > 0 ? '<mdui-divider></mdui-divider>' : ''}
            <mdui-list-subheader>${escapeHTML(grp)}</mdui-list-subheader>
            ${sections.filter(sec => sec.group === grp).map(sec => `
              <mdui-menu-item data-action="switchConfigSection" data-section="${sec.key}">
                ${icon(sec.key === activeKey ? 'check' : sec.icon, 'icon')}
                <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;width:100%">
                  <span>${escapeHTML(sec.label)}</span>
                  <span class="aw-menu-badge">${escapeHTML(sec.count)}</span>
                </div>
              </mdui-menu-item>
            `).join('')}
          `).join('')}
        </mdui-menu>
      </mdui-dropdown>

      ${activeKey === 'mcp' ? `<mdui-text-field id="aw-mcp-search" class="aw-search" variant="outlined" placeholder="搜索 MCP 服务…" value="${escapeHTML(state.mcpSearch)}" clearable style="max-width:220px;--mdui-typescale-body-large-size:12px">${icon('search', 'icon')}</mdui-text-field>` : ''}
    </div>

    ${moduleRightActionMarkup(activeKey)}
  </div>

  ${bodyHtml}`;
}

/* ---------------- DIALOGS ---------------- */
function openMcpEditorModal(s, editingId = null) {
  const list = state.serverMcps[s.alias] || [];
  const existing = editingId ? list.find(x => x.id === editingId) : null;
  const f = existing ? {
    preset: 'custom',
    id: existing.id,
    transport: existing.transport,
    command: existing.command || 'uvx',
    args: existing.args || '',
    cwd: existing.cwd || `/home/${s.username}`,
    env: existing.env || '',
    endpoint: existing.endpoint || 'http://127.0.0.1:9400/mcp',
    bearerEnv: existing.bearerEnv || '',
    headers: existing.headers || ''
  } : {
    preset: 'postgres',
    id: 'postgres_prod',
    transport: 'stdio',
    command: 'uvx',
    args: 'mcp-server-postgres postgresql://127.0.0.1:5432/ml_platform',
    cwd: '/srv/ml-platform',
    env: 'PGPASSWORD=••••••••',
    endpoint: 'http://127.0.0.1:9400/mcp',
    bearerEnv: 'PROMETHEUS_MCP_TOKEN',
    headers: ''
  };

  const formHtml = `<div class="aw-form-stack">
    ${!existing ? `<mdui-select id="aw-modal-mcp-preset" label="预设模板（可选）" value="${escapeHTML(f.preset)}" variant="outlined">
      ${mcpPresets.map(p => `<mdui-menu-item value="${p.key}">${escapeHTML(p.name)}</mdui-menu-item>`).join('')}
    </mdui-select>` : ''}

    <div class="aw-form-grid-2">
      <mdui-text-field id="aw-modal-mcp-id" label="服务 ID (server_id)" value="${escapeHTML(f.id)}" ${existing ? 'readonly' : ''} helper="工具前缀：mcp__<id>__*" variant="outlined" required></mdui-text-field>
      <mdui-select id="aw-modal-mcp-transport" label="传输方式" value="${escapeHTML(f.transport)}" variant="outlined">
        <mdui-menu-item value="stdio">stdio（远端进程）</mdui-menu-item>
        <mdui-menu-item value="streamableHttp">Streamable HTTP（远端端点）</mdui-menu-item>
      </mdui-select>
    </div>

    <div id="aw-modal-mcp-stdio-fields" ${f.transport === 'stdio' ? '' : 'hidden'} class="aw-form-stack">
      <div class="aw-form-grid-2">
        <mdui-text-field id="aw-modal-mcp-cmd" label="启动命令 (command)" value="${escapeHTML(f.command)}" variant="outlined" required></mdui-text-field>
        <mdui-text-field id="aw-modal-mcp-cwd" label="远端工作目录 (cwd)" value="${escapeHTML(f.cwd)}" variant="outlined"></mdui-text-field>
      </div>
      <mdui-text-field id="aw-modal-mcp-args" label="命令参数 (args)" value="${escapeHTML(f.args)}" variant="outlined"></mdui-text-field>
      <mdui-text-field id="aw-modal-mcp-env" label="环境变量 (KEY=VAL)" value="${escapeHTML(f.env)}" variant="outlined"></mdui-text-field>
    </div>

    <div id="aw-modal-mcp-http-fields" ${f.transport === 'streamableHttp' ? '' : 'hidden'} class="aw-form-stack">
      <mdui-text-field id="aw-modal-mcp-endpoint" label="远端 HTTP 端点 (url)" value="${escapeHTML(f.endpoint)}" variant="outlined"></mdui-text-field>
      <div class="aw-form-grid-2">
        <mdui-text-field id="aw-modal-mcp-bearer" label="Bearer 令牌变量名" value="${escapeHTML(f.bearerEnv)}" variant="outlined"></mdui-text-field>
        <mdui-text-field id="aw-modal-mcp-headers" label="自定义请求头" value="${escapeHTML(f.headers)}" variant="outlined"></mdui-text-field>
      </div>
    </div>
  </div>`;

  openDialog(existing ? `编辑 MCP：${existing.id}` : `添加服务器 MCP (${s.alias})`, formHtml, () => {
    const id = ($('#aw-modal-mcp-id')?.value || f.id).trim();
    if (!/^[a-zA-Z0-9_-]+$/.test(id)) {
      toast('服务 ID 仅允许字母、数字、下划线与连字符');
      return false;
    }
    const transport = $('#aw-modal-mcp-transport')?.value || f.transport;
    const arr = state.serverMcps[s.alias] || (state.serverMcps[s.alias] = []);
    const idx = arr.findIndex(x => x.id === (existing ? existing.id : id));
    const entry = {
      id,
      enabled: true,
      transport,
      command: $('#aw-modal-mcp-cmd')?.value.trim() || f.command,
      args: $('#aw-modal-mcp-args')?.value.trim() || f.args,
      cwd: $('#aw-modal-mcp-cwd')?.value.trim() || f.cwd,
      env: $('#aw-modal-mcp-env')?.value.trim() || f.env,
      endpoint: $('#aw-modal-mcp-endpoint')?.value.trim() || f.endpoint,
      bearerEnv: $('#aw-modal-mcp-bearer')?.value.trim() || f.bearerEnv,
      headers: $('#aw-modal-mcp-headers')?.value.trim() || f.headers,
      state: 'available',
      pid: transport === 'stdio' ? 51400 : undefined,
      tools: existing?.tools?.length ? existing.tools : [
        { name: 'status', fullName: `mcp__${id}__status`, desc: '检查远端服务状态' },
        { name: 'query', fullName: `mcp__${id}__query`, desc: '执行远端服务查询' }
      ]
    };
    if (idx >= 0) arr[idx] = entry;
    else arr.unshift(entry);
    toast(`已保存 MCP 服务「${id}」`);
    return true;
  }, existing ? '保存' : '创建');

  const presetEl = $('#aw-modal-mcp-preset');
  presetEl?.addEventListener('change', () => {
    const p = mcpPresets.find(x => x.key === presetEl.value);
    if (!p) return;
    f.preset = p.key;
    f.id = p.id;
    f.transport = p.transport;
    f.command = p.command || 'uvx';
    f.args = p.args || '';
    f.cwd = p.cwd || `/home/${s.username}`;
    f.env = p.env || '';
    f.endpoint = p.endpoint || 'http://127.0.0.1:9400/mcp';
    f.bearerEnv = p.bearerEnv || '';
    f.headers = p.headers || '';
    $('#aw-modal-mcp-id').value = f.id;
    $('#aw-modal-mcp-transport').value = f.transport;
    $('#aw-modal-mcp-cmd').value = f.command;
    $('#aw-modal-mcp-args').value = f.args;
    $('#aw-modal-mcp-cwd').value = f.cwd;
    $('#aw-modal-mcp-env').value = f.env;
    $('#aw-modal-mcp-endpoint').value = f.endpoint;
    $('#aw-modal-mcp-bearer').value = f.bearerEnv;
    $('#aw-modal-mcp-headers').value = f.headers;
    $('#aw-modal-mcp-stdio-fields').hidden = f.transport !== 'stdio';
    $('#aw-modal-mcp-http-fields').hidden = f.transport !== 'streamableHttp';
  });

  const transEl = $('#aw-modal-mcp-transport');
  transEl?.addEventListener('change', () => {
    f.transport = transEl.value;
    $('#aw-modal-mcp-stdio-fields').hidden = f.transport !== 'stdio';
    $('#aw-modal-mcp-http-fields').hidden = f.transport !== 'streamableHttp';
  });
}

function renderDirModalContent(s) {
  const curPath = state.dirBrowsePath || '/home/ubuntu';
  const node = remoteDirTree[curPath] || {
    parent: curPath.split('/').slice(0, -1).join('/') || '/',
    entries: [
      { name: 'src', path: `${curPath}/src`, note: '目录' },
      { name: 'configs', path: `${curPath}/configs`, note: '目录' }
    ]
  };
  const projName = curPath.split('/').filter(Boolean).pop() || 'remote-workspace';
  return `<div class="aw-form-stack">
    <small>主机：<code>${escapeHTML(s.username)}@${escapeHTML(s.hostName)}:${s.port}</code></small>
    <div class="aw-dir-path-bar">
      <mdui-text-field id="aw-dir-input" label="远端绝对 POSIX 路径" value="${escapeHTML(curPath)}" variant="outlined">${icon('route', 'icon')}</mdui-text-field>
      ${btn('前往', 'dirGo', 'tonal', 'arrow-right')}
    </div>
    <div class="aw-dir-current">
      ${iconBtn('上一级', 'dirUp', 'arrow-up', node.parent ? `data-path="${escapeHTML(node.parent)}"` : 'disabled')}
      ${iconBtn('刷新', 'dirRefresh', 'refresh-cw')}
      <span><strong>${escapeHTML(curPath)}</strong></span>
    </div>
    <div class="aw-dir-list">
      ${node.entries.map(e => `<button type="button" class="aw-dir-entry" data-action="dirEnter" data-path="${escapeHTML(e.path)}">
        <span class="aw-row">${icon('folder')}<strong>${escapeHTML(e.name)}</strong></span>
        <small class="aw-mono">${escapeHTML(e.note || e.path)}</small>
      </button>`).join('')}
    </div>
    <mdui-text-field id="aw-dir-proj-name" label="项目名称" value="${escapeHTML(projName)}" variant="outlined">${icon('folder-git-2', 'icon')}</mdui-text-field>
  </div>`;
}

function openRemoteDirectoryModal(s, initPath) {
  if (initPath) state.dirBrowsePath = initPath;
  openDialog('浏览远端目录并打开项目', renderDirModalContent(s), () => {
    const p = $('#aw-dir-input')?.value.trim() || state.dirBrowsePath;
    if (!p.startsWith('/')) {
      toast('远端路径必须以 / 开头');
      return false;
    }
    const name = $('#aw-dir-proj-name')?.value.trim() || p.split('/').filter(Boolean).pop() || 'remote-project';
    if (!s.projects.some(x => x.path === p)) {
      s.projects.push({ name, path: p, worktrees: 0, branch: 'main' });
    }
    toast(`已打开远程项目「${name}」`);
    return true;
  }, '打开');
}

function openPasswordModal(s) {
  openDialog('输入 SSH 密码', `<div class="aw-form-stack">
    <p style="font-size:13px;color:rgb(var(--mdui-color-on-surface-variant))">连接到 <code>${escapeHTML(s.username)}@${escapeHTML(s.hostName)}:${s.port}</code> 需要密码认证。</p>
    <mdui-text-field id="aw-modal-ssh-pwd" label="SSH 密码" type="password" variant="outlined" required>${icon('lock-keyhole', 'icon')}</mdui-text-field>
    <label class="aw-row" style="font-size:13px;cursor:pointer">
      <input type="checkbox" id="aw-modal-remember-pwd" checked />
      <span>保存到系统凭据库（<code>ssh:${escapeHTML(s.alias)}</code>）</span>
    </label>
  </div>`, () => {
    s.hasPassword = $('#aw-modal-remember-pwd')?.checked !== false;
    s.state = 'ready';
    if (state.type === 'connection' && state.scenario === 'passwordPrompt') state.scenario = 'ready';
    toast(`已连接 ${s.alias}`);
    return true;
  }, '连接');
}

function openEditServerModal(s) {
  openDialog(`编辑连接：${s.alias}`, `<div class="aw-form-stack">
    <mdui-text-field label="别名 (Host)" value="${escapeHTML(s.alias)}" disabled variant="outlined"></mdui-text-field>
    <div class="aw-form-grid-2">
      <mdui-text-field id="aw-edit-srv-host" label="主机地址 (HostName)" value="${escapeHTML(s.hostName)}" variant="outlined" required></mdui-text-field>
      <mdui-text-field id="aw-edit-srv-port" label="端口 (Port)" value="${escapeHTML(s.port)}" type="number" variant="outlined"></mdui-text-field>
    </div>
    <div class="aw-form-grid-2">
      <mdui-text-field id="aw-edit-srv-user" label="用户名 (User)" value="${escapeHTML(s.username)}" variant="outlined" required></mdui-text-field>
      <mdui-text-field id="aw-edit-srv-idfile" label="私钥路径 (可选)" value="${escapeHTML(s.identityFile || '')}" variant="outlined"></mdui-text-field>
    </div>
    <mdui-text-field id="aw-edit-srv-pwd" label="密码（可选，存入系统凭据库）" type="password" placeholder="${s.hasPassword ? '已保存，留空保持不变' : '留空不保存密码'}" variant="outlined"></mdui-text-field>
  </div>`, () => {
    s.hostName = $('#aw-edit-srv-host')?.value.trim() || s.hostName;
    s.port = Number($('#aw-edit-srv-port')?.value.trim()) || s.port;
    s.username = $('#aw-edit-srv-user')?.value.trim() || s.username;
    s.identityFile = $('#aw-edit-srv-idfile')?.value.trim() || '';
    if ($('#aw-edit-srv-pwd')?.value.trim()) s.hasPassword = true;
    toast(`已更新 ${s.alias}`);
    return true;
  }, '保存');
}

function openSshConfigBlockModal(s) {
  const block = s.managed
    ? sshConfigBlockText(s)
    : `<span class="aw-comment"># 用户手写条目（只读）</span>\nHost ${escapeHTML(s.alias)}\n    HostName ${escapeHTML(s.hostName)}\n    Port ${s.port}\n    User ${escapeHTML(s.username)}`;
  openDialog(`~/.ssh/config 配置块：${s.alias}`, `<div class="aw-code-preview">${block}</div>`, () => true, '关闭', true);
}

/* ---------------- NAVIGATION & WIRING ---------------- */
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
  if (viewGroup) viewGroup.value = state.page === 'list' ? 'list' : 'detail';
}

function wireLocal() {
  const search = $('#aw-ssh-search');
  search?.addEventListener('input', () => { state.search = search.value; render(); });
  const mcpSearch = $('#aw-mcp-search');
  mcpSearch?.addEventListener('input', () => { state.mcpSearch = mcpSearch.value; render(); });

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
        toast(sw.checked ? `已启用 MCP「${id}」` : `已停用 MCP「${id}」`);
      }
    });
  });

  $$('[data-global-mcp-select]').forEach(sel => {
    sel.addEventListener('change', () => {
      const id = sel.dataset.globalMcpSelect;
      const item = state.globalOverrides.find(g => g.id === id);
      if (item) {
        item.policy = sel.value;
        render();
        toast(`已更新全局 MCP「${id}」策略`);
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
}

function render() {
  renderSelectors();
  const main = $('#aw-main');
  if (state.page === 'add') main.innerHTML = addMarkup();
  else if (state.page === 'detail') main.innerHTML = serverWorkspaceMarkup();
  else main.innerHTML = listMarkup();
  wireLocal();
  hydrateIcons();
}

function applyScenarioPreset(type, scenario) {
  state.type = type;
  state.scenario = scenario;
  if (type === 'overview') {
    state.page = 'list';
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
    state.page = 'detail';
    state.configSection = scenario === 'mcpGlobalOverride' ? 'mcpGlobal' : 'mcp';
    if (scenario === 'mcpCreate') {
      render();
      openMcpEditorModal(currentServer(), null);
      return;
    }
  } else if (type === 'serverExtensions') {
    state.selectedServer = 'gpu-a100-prod';
    state.page = 'detail';
    const map = { extConn: 'conn', extEnv: 'env', extPorts: 'ports', extLspSkills: 'lsp', extPolicy: 'policy' };
    state.configSection = map[scenario] || 'conn';
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

['list', 'detail'].forEach(v => {
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
    else if (target === 'MCP') { state.page = 'detail'; state.configSection = 'mcp'; render(); }
    else if (target === '账号') { location.href = '../accounts-list/index.html'; }
    else toast(`当前设计稿聚焦「SSH 远程服务器与单机配置」`);
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
  if (action === 'openDetail') {
    state.selectedServer = srv.alias;
    state.page = 'detail';
    render();
    return;
  }
  if (action === 'switchConfigSection') {
    state.configSection = el.dataset.section || 'mcp';
    state.page = 'detail';
    render();
    return;
  }
  if (action === 'switchServer') {
    state.selectedServer = srv.alias;
    render();
    toast(`已切换至 ${srv.alias}`);
    return;
  }
  if (action === 'clearServerSearch') { state.search = ''; state.scenario = 'normal'; render(); return; }

  if (action === 'submitAddServer') {
    const alias = ($('#aw-add-alias')?.value || state.addForm.alias).trim();
    const hostName = ($('#aw-add-host')?.value || state.addForm.hostName).trim();
    const username = ($('#aw-add-user')?.value || state.addForm.username).trim();
    const port = Number($('#aw-add-port')?.value || state.addForm.port) || 22;
    if (!alias || !hostName || !username) {
      toast('请填写完整的别名、主机地址与用户名');
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
      icon: 'server',
      state: 'ready',
      osShort: 'Linux · x86_64',
      shell: '/bin/bash',
      budgetUsed: '14 MB / 512 MB',
      projects: [],
      envVars: [],
      toolchains: [],
      lspServers: [],
      skillDirs: [{ path: '<workspace>/.agents/skills', kind: '远端项目技能源', count: 0 }],
      portForwards: []
    };
    state.servers = [newSrv, ...state.servers.filter(x => x.alias !== alias)];
    if (!state.serverMcps[alias]) state.serverMcps[alias] = [];
    state.selectedServer = alias;
    state.page = 'detail';
    state.configSection = 'mcp';
    render();
    toast(`已添加服务器「${alias}」`);
    return;
  }

  if (action === 'testServer' || action === 'reconnectServer') {
    srv.state = 'ready';
    if (state.type === 'connection') state.scenario = 'ready';
    render();
    toast(`已重新连接 ${srv.alias}`);
    return;
  }
  if (action === 'promptPassword') { openPasswordModal(srv); return; }
  if (action === 'editServerConn') { openEditServerModal(srv); return; }
  if (action === 'viewSshConfigBlock') { openSshConfigBlockModal(srv); return; }
  if (action === 'browseRemoteDir') {
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
    openDialog('删除服务器？', `<p style="font-size:13px;color:rgb(var(--mdui-color-on-surface-variant))">确定从 <code>~/.ssh/config</code> 移除受管块 <code>${escapeHTML(srv.alias)}</code> 及关联密码？</p>`, () => {
      state.servers = state.servers.filter(x => x.alias !== srv.alias);
      if (state.selectedServer === srv.alias && state.servers.length) state.selectedServer = state.servers[0].alias;
      state.page = 'list';
      toast(`已删除 ${srv.alias}`);
      return true;
    }, '删除');
    return;
  }

  /* MCP Actions */
  if (action === 'openMcpModal') { openMcpEditorModal(srv, null); return; }
  if (action === 'editMcpModal') { openMcpEditorModal(srv, el.dataset.mcp); return; }
  if (action === 'inspectMcpRuntime') {
    const m = (state.serverMcps[srv.alias] || []).find(x => x.id === el.dataset.mcp);
    if (!m) return;
    openDialog(`运行详情：${m.id}`, `<div class="aw-code-preview">服务器: ${escapeHTML(srv.alias)} (${escapeHTML(srv.username)}@${escapeHTML(srv.hostName)})
传输方式: ${escapeHTML(m.transport)}
${m.transport === 'stdio' ? `命令: ${escapeHTML(m.command)} ${escapeHTML(m.args)}\n工作目录: ${escapeHTML(m.cwd || '~')}\n远端 PID: ${m.pid || '未启动'}` : `端点: ${escapeHTML(m.endpoint)}`}
已注册工具数: ${m.tools?.length || 0}</div>`, () => true, '关闭', true);
    return;
  }
  if (action === 'reconnectMcp') {
    const mcpId = el.dataset.mcp;
    const m = (state.serverMcps[srv.alias] || []).find(x => x.id === mcpId);
    if (m) { m.enabled = true; m.state = 'available'; }
    render();
    toast(`已重新探测「${mcpId}」`);
    return;
  }
  if (action === 'deleteMcp') {
    const mcpId = el.dataset.mcp;
    openDialog('删除 MCP 服务？', `<p style="font-size:13px;color:rgb(var(--mdui-color-on-surface-variant))">确定从服务器 <code>${escapeHTML(srv.alias)}</code> 删除远端 MCP 服务 <code>${escapeHTML(mcpId)}</code>？</p>`, () => {
      state.serverMcps[srv.alias] = (state.serverMcps[srv.alias] || []).filter(x => x.id !== mcpId);
      toast(`已删除「${mcpId}」`);
      return true;
    }, '删除');
    return;
  }

  /* Server Extension Actions */
  if (action === 'addServerEnvModal') {
    openDialog(`添加环境变量 (${srv.alias})`, `<div class="aw-form-stack">
      <mdui-text-field id="aw-env-key" label="变量名 (Key)" placeholder="CUDA_VISIBLE_DEVICES" variant="outlined" required></mdui-text-field>
      <mdui-text-field id="aw-env-val" label="变量值 (Value)" placeholder="0,1" variant="outlined" required></mdui-text-field>
      <mdui-select id="aw-env-scope" label="作用范围" value="全部远端任务" variant="outlined">
        <mdui-menu-item value="全部远端任务">全部远端任务 (exec / MCP / LSP)</mdui-menu-item>
        <mdui-menu-item value="仅远端 MCP">仅远端 MCP 子进程</mdui-menu-item>
      </mdui-select>
    </div>`, () => {
      const k = $('#aw-env-key')?.value.trim();
      const v = $('#aw-env-val')?.value.trim();
      if (!k) { toast('请输入变量名'); return false; }
      srv.envVars.push({ key: k, value: v, scope: $('#aw-env-scope')?.value || '全部远端任务', secret: false });
      toast(`已添加变量 ${k}`);
      return true;
    }, '添加');
    return;
  }
  if (action === 'deleteServerEnv') {
    const idx = Number(el.dataset.idx);
    if (Number.isInteger(idx)) { srv.envVars.splice(idx, 1); render(); toast('已移除环境变量'); }
    return;
  }
  if (action === 'addToolchainModal') {
    openDialog(`覆盖工具链路径 (${srv.alias})`, `<div class="aw-form-stack">
      <mdui-select id="aw-tc-name" label="工具类别" value="python3 / uvx" variant="outlined">
        <mdui-menu-item value="python3 / uvx">python3 / uvx</mdui-menu-item>
        <mdui-menu-item value="node / npx">node / npx</mdui-menu-item>
        <mdui-menu-item value="cargo / rustc">cargo / rustc</mdui-menu-item>
      </mdui-select>
      <mdui-text-field id="aw-tc-path" label="远端绝对路径" placeholder="/opt/conda/bin/uvx" variant="outlined" required></mdui-text-field>
    </div>`, () => {
      const tool = $('#aw-tc-name')?.value || 'python3 / uvx';
      const path = $('#aw-tc-path')?.value.trim();
      if (!path) return false;
      const ex = srv.toolchains.find(t => t.tool === tool);
      if (ex) ex.path = path;
      else srv.toolchains.push({ tool, path });
      toast(`已保存 ${tool} 路径覆盖`);
      return true;
    }, '保存');
    return;
  }
  if (action === 'deleteToolchain') {
    const idx = Number(el.dataset.idx);
    if (Number.isInteger(idx)) { srv.toolchains.splice(idx, 1); render(); toast('已移除路径覆盖'); }
    return;
  }
  if (action === 'addPortForwardModal') {
    openDialog(`添加端口转发 (${srv.alias})`, `<div class="aw-form-stack">
      <mdui-text-field id="aw-pf-label" label="名称说明" placeholder="JupyterLab" variant="outlined" required></mdui-text-field>
      <div class="aw-form-grid-2">
        <mdui-text-field id="aw-pf-local" label="本机监听地址" value="127.0.0.1:8888" variant="outlined" required></mdui-text-field>
        <mdui-text-field id="aw-pf-remote" label="远端目标地址" value="127.0.0.1:8888" variant="outlined" required></mdui-text-field>
      </div>
    </div>`, () => {
      const label = $('#aw-pf-label')?.value.trim() || '端口转发';
      const local = $('#aw-pf-local')?.value.trim() || '127.0.0.1:8888';
      const remote = $('#aw-pf-remote')?.value.trim() || '127.0.0.1:8888';
      srv.portForwards.push({ id: 'pf' + Date.now(), label, local, remote });
      toast(`已添加端口转发：${label}`);
      return true;
    }, '添加');
    return;
  }
  if (action === 'deletePortForward') {
    const idx = Number(el.dataset.idx);
    if (Number.isInteger(idx)) { srv.portForwards.splice(idx, 1); render(); toast('已删除端口转发'); }
    return;
  }
  if (action === 'addSkillDirModal') {
    openDialog(`添加共享技能目录 (${srv.alias})`, `<div class="aw-form-stack">
      <mdui-text-field id="aw-skill-dir-input" label="远端只读技能目录路径" value="/opt/team-skills" variant="outlined" required></mdui-text-field>
    </div>`, () => {
      const p = $('#aw-skill-dir-input')?.value.trim();
      if (!p || !p.startsWith('/')) { toast('请输入以 / 开头的远端路径'); return false; }
      srv.skillDirs.push({ path: p, kind: '服务器共享只读源', count: 3 });
      toast(`已挂载远端技能目录 ${p}`);
      return true;
    }, '添加');
    return;
  }
  if (action === 'deleteSkillDir') {
    const idx = Number(el.dataset.idx);
    if (Number.isInteger(idx)) { srv.skillDirs.splice(idx, 1); render(); toast('已移除共享技能目录'); }
    return;
  }
  if (action === 'removeProject') {
    const idx = Number(el.dataset.idx);
    if (Number.isInteger(idx)) { srv.projects.splice(idx, 1); render(); toast('已移除项目关联'); }
    return;
  }
  if (action === 'resetRemoteLsp') { toast(`已重置 ${srv.alias} 的远端 LSP 服务`); return; }
  if (action === 'cleanHelperCache') { toast(`已清理 ${srv.alias} 上非活动版本的辅助进程缓存`); return; }
  if (action === 'copyText') {
    const txt = el.dataset.text || '';
    navigator.clipboard?.writeText(txt).catch(() => {});
    toast(`已复制：${txt}`);
  }
});

render();
})();
