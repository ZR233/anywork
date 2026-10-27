// Shared account design: shell, fixture data, and local-only interactions using Material 3 (MDUI) default components.
document.getElementById("aw-preview-mount").innerHTML = "<div id=\"aw-accounts\" class=\"mdui-theme-light\" aria-label=\"账号列表与详情 Material 3 全变体设计预览\">\n  <mdui-card variant=\"outlined\" class=\"aw-previewbar\" aria-label=\"设计评审场景切换\"><span class=\"aw-previewlabel\"><i data-lucide=\"sliders-horizontal\" aria-hidden=\"true\"></i>场景预览</span><mdui-select id=\"aw-type\" label=\"账户变体\" value=\"overview\" variant=\"outlined\"></mdui-select><mdui-select id=\"aw-scenario\" class=\"aw-state-select\" label=\"展示状态\" value=\"normal\" variant=\"outlined\"></mdui-select><div class=\"aw-stepper\" aria-label=\"快速切换场景\"><mdui-tooltip content=\"上一场景\"><mdui-button-icon id=\"aw-prev-scenario\" aria-label=\"上一场景\"><i data-lucide=\"chevron-left\" aria-hidden=\"true\"></i></mdui-button-icon></mdui-tooltip><span class=\"aw-scenario-index\" id=\"aw-scenario-index\">1 / 62</span><mdui-tooltip content=\"下一场景\"><mdui-button-icon id=\"aw-next-scenario\" aria-label=\"下一场景\"><i data-lucide=\"chevron-right\" aria-hidden=\"true\"></i></mdui-button-icon></mdui-tooltip></div><mdui-segmented-button-group selects=\"single\" class=\"aw-view-group\" id=\"aw-view-group\" value=\"list\" aria-label=\"视图切换\"><mdui-segmented-button value=\"list\" id=\"aw-view-list\">账号列表</mdui-segmented-button><mdui-segmented-button value=\"detail\" id=\"aw-view-detail\">账号详情</mdui-segmented-button><mdui-segmented-button value=\"model\" id=\"aw-view-model\">模型资料</mdui-segmented-button></mdui-segmented-button-group></mdui-card>\n  <div class=\"aw-shell\" id=\"aw-shell\"><aside class=\"aw-sidebar\"><div class=\"aw-brand\"><mdui-avatar><i data-lucide=\"cat\" aria-hidden=\"true\"></i></mdui-avatar>糊来帮</div><mdui-button variant=\"text\" class=\"aw-back-chat\" id=\"aw-back-chat\"><span slot=\"icon\"><i data-lucide=\"arrow-left\" aria-hidden=\"true\"></i></span>返回聊天</mdui-button><nav id=\"aw-nav\" aria-label=\"设置导航\"></nav><div class=\"aw-sidebar-bottom\"><span class=\"aw-small-dot\"></span>设置 · 本地工作空间</div></aside><main class=\"aw-main\" id=\"aw-main\"><div class=\"aw-loading\"><mdui-circular-progress></mdui-circular-progress>正在加载 Material 3 组件…</div></main></div>\n  <div class=\"aw-preview-foot\"><span><i data-lucide=\"palette\" aria-hidden=\"true\"></i>Material 3 · 暹罗浅色 · 标准组件</span><span id=\"aw-coverage\">示例数据 · 不连接真实账户</span></div>\n  <mdui-dialog id=\"aw-dialog\" headline=\"账号设置\" close-on-esc><div id=\"aw-dialog-content\"></div><mdui-button slot=\"action\" variant=\"text\" id=\"aw-dialog-cancel\">取消</mdui-button><mdui-button slot=\"action\" variant=\"filled\" id=\"aw-dialog-save\">保存</mdui-button></mdui-dialog>\n  <mdui-dialog id=\"aw-leave-dialog\" headline=\"放弃未保存的修改？\" description=\"你的修改还未保存，关闭后将恢复原有配置。\"><mdui-button slot=\"action\" variant=\"text\" id=\"aw-keep-editing\">继续编辑</mdui-button><mdui-button slot=\"action\" variant=\"filled\" id=\"aw-discard\">放弃修改</mdui-button></mdui-dialog>\n  <mdui-snackbar id=\"aw-snackbar\" placement=\"bottom\" auto-close-delay=\"2800\" closeable></mdui-snackbar>\n</div>";

(() => {
const root=document.getElementById('aw-accounts');const $=s=>root.querySelector(s);const $$=s=>Array.from(root.querySelectorAll(s));
const LOGOS={deepseek:'data:image/svg+xml;base64,PHN2ZyBoZWlnaHQ9IjFlbSIgc3R5bGU9ImZsZXg6bm9uZTtsaW5lLWhlaWdodDoxIiB2aWV3Qm94PSIwIDAgMjQgMjQiIHdpZHRoPSIxZW0iIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHRpdGxlPkRlZXBTZWVrPC90aXRsZT48cGF0aCBkPSJNMjMuNzQ4IDQuNDgyYy0uMjU0LS4xMjQtLjM2NC4xMTMtLjUxMi4yMzQtLjA1MS4wMzktLjA5NC4wOS0uMTM3LjEzNi0uMzcyLjM5Ny0uODA2LjY1Ny0xLjM3My42MjYtLjgyOS0uMDQ2LTEuNTM3LjIxNC0yLjE2My44NDgtLjEzMy0uNzgyLS41NzUtMS4yNDgtMS4yNDctMS41NDgtLjM1Mi0uMTU2LS43MDgtLjMxMS0uOTU1LS42NS0uMTcyLS4yNDEtLjIxOS0uNTEtLjMwNS0uNzc0LS4wNTUtLjE2LS4xMS0uMzIzLS4yOTMtLjM1LS4yLS4wMzEtLjI3OC4xMzYtLjM1Ni4yNzYtLjMxMy41NzItLjQzNCAxLjIwMi0uNDIyIDEuODQuMDI3IDEuNDM2LjYzMyAyLjU4IDEuODM4IDMuMzkzLjEzNy4wOTMuMTcyLjE4Ny4xMjkuMzIzLS4wODIuMjgtLjE4LjU1Mi0uMjY2LjgzMy0uMDU1LjE3OS0uMTM3LjIxNy0uMzI5LjE0YTUuNTI2IDUuNTI2IDAgMDEtMS43MzYtMS4xOGMtLjg1Ny0uODI4LTEuNjMxLTEuNzQyLTIuNTk3LTIuNDU4YTExLjM2NSAxMS4zNjUgMCAwMC0uNjg5LS40NzFjLS45ODUtLjk1Ny4xMy0xLjc0My4zODgtMS44MzYuMjctLjA5OC4wOTMtLjQzMi0uNzc5LS40MjgtLjg3Mi4wMDQtMS42Ny4yOTUtMi42ODcuNjg0YTMuMDU1IDMuMDU1IDAgMDEtLjQ2NS4xMzcgOS41OTcgOS41OTcgMCAwMC0yLjg4My0uMTAyYy0xLjg4NS4yMS0zLjM5IDEuMTAyLTQuNDk3IDIuNjIzQy4wODIgOC42MDYtLjIzMSAxMC42ODQuMTUyIDEyLjg1Yy40MDMgMi4yODQgMS41NjkgNC4xNzUgMy4zNiA1LjY1MyAxLjg1OCAxLjUzMyAzLjk5NyAyLjI4NCA2LjQzOCAyLjE0IDEuNDgyLS4wODUgMy4xMzMtLjI4NCA0Ljk5NC0xLjg2LjQ3LjIzNC45NjIuMzI3IDEuNzguMzk3LjYzLjA1OSAxLjIzNi0uMDMgMS43MDUtLjEyOC43MzUtLjE1Ni42ODQtLjgzNy40MTktLjk2MS0yLjE1NS0xLjAwNC0xLjY4Mi0uNTk1LTIuMTEzLS45MjYgMS4wOTYtMS4yOTYgMi43NDYtMi42NDIgMy4zOTItNy4wMDMuMDUtLjM0Ny4wMDctLjU2NSAwLS44NDUtLjAwNC0uMTcuMDM1LS4yMzcuMjMtLjI1NmE0LjE3MyA0LjE3MyAwIDAwMS41NDUtLjQ3NWMxLjM5Ni0uNzYzIDEuOTYtMi4wMTUgMi4wOTMtMy41MTcuMDItLjIzLS4wMDQtLjQ2Ny0uMjQ3LS41ODh6TTExLjU4MSAxOGMtMi4wODktMS42NDItMy4xMDItMi4xODMtMy41Mi0yLjE2LS4zOTIuMDI0LS4zMjEuNDcxLS4yMzUuNzYzLjA5LjI4OC4yMDcuNDg2LjM3MS43MzkuMTE0LjE2Ny4xOTIuNDE2LS4xMTMuNjAzLS42NzMuNDE2LTEuODQyLS4xNC0xLjg5Ny0uMTY3LTEuMzYxLS44MDItMi41LTEuODYtMy4zMDEtMy4zMDctLjc3NC0xLjM5My0xLjIyNC0yLjg4Ny0xLjI5OC00LjQ4Mi0uMDItLjM4Ni4wOTMtLjUyMi40NzctLjU5MmE0LjY5NiA0LjY5NiAwIDAxMS41MjktLjAzOWMyLjEzMi4zMTIgMy45NDYgMS4yNjUgNS40NjggMi43NzQuODY4Ljg2IDEuNTI1IDEuODg3IDIuMjAyIDIuODkxLjcyIDEuMDY2IDEuNDk0IDIuMDgyIDIuNDggMi45MTQuMzQ4LjI5Mi42MjUuNTE0Ljg5MS42NzctLjgwMi4wOS0yLjE0LjExLTMuMDU0LS42MTR6bTEtNi40NGEuMzA2LjMwNiAwIDAxLjQxNS0uMjg3LjMwMi4zMDIgMCAwMS4yLjI4OC4zMDYuMzA2IDAgMDEtLjMxLjMwNy4zMDMuMzAzIDAgMDEtLjMwNC0uMzA4em0zLjExIDEuNTk2Yy0uMi4wODEtLjM5OS4xNTEtLjU5LjE2YTEuMjQ1IDEuMjQ1IDAgMDEtLjc5OC0uMjU0Yy0uMjc0LS4yMy0uNDctLjM1OC0uNTUyLS43NThhMS43MyAxLjczIDAgMDEuMDE2LS41ODhjLjA3LS4zMjctLjAwOC0uNTM3LS4yMzktLjcyNy0uMTg3LS4xNTYtLjQyNi0uMTk5LS42ODgtLjE5OWEuNTU5LjU1OSAwIDAxLS4yNTQtLjA3OGMtLjExLS4wNTQtLjItLjE5LS4xMTQtLjM1OC4wMjgtLjA1NC4xNi0uMTg2LjE5Mi0uMjEuMzU2LS4yMDIuNzY3LS4xMzYgMS4xNDYuMDE2LjM1Mi4xNDQuNjE4LjQwOCAxLjAwMS43ODIuMzkxLjQ1MS40NjIuNTc2LjY4NS45MTQuMTc2LjI2NS4zMzYuNTM3LjQ0NS44NDguMDY3LjE5NS0uMDE5LjM1NC0uMjUuNDUyeiIgZmlsbD0iIzRENkJGRSI+PC9wYXRoPjwvc3ZnPg==',openai:'data:image/svg+xml;base64,PHN2ZyBmaWxsPSJjdXJyZW50Q29sb3IiIGZpbGwtcnVsZT0iZXZlbm9kZCIgaGVpZ2h0PSIxZW0iIHN0eWxlPSJmbGV4Om5vbmU7bGluZS1oZWlnaHQ6MSIgdmlld0JveD0iMCAwIDI0IDI0IiB3aWR0aD0iMWVtIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjx0aXRsZT5PcGVuQUk8L3RpdGxlPjxwYXRoIGQ9Ik0yMS41NSAxMC4wMDRhNS40MTYgNS40MTYgMCAwMC0uNDc4LTQuNTAxYy0xLjIxNy0yLjA5LTMuNjYyLTMuMTY2LTYuMDUtMi42NkE1LjU5IDUuNTkgMCAwMDEwLjgzMSAxQzguMzkuOTk1IDYuMjI0IDIuNTQ2IDUuNDczIDQuODM4QTUuNTUzIDUuNTUzIDAgMDAxLjc2IDcuNDk2YTUuNDg3IDUuNDg3IDAgMDAuNjkxIDYuNSA1LjQxNiA1LjQxNiAwIDAwLjQ3NyA0LjUwMmMxLjIxNyAyLjA5IDMuNjYyIDMuMTY1IDYuMDUgMi42NkE1LjU4NiA1LjU4NiAwIDAwMTMuMTY4IDIzYzIuNDQzLjAwNiA0LjYxLTEuNTQ2IDUuMzYxLTMuODRhNS41NTMgNS41NTMgMCAwMDMuNzE1LTIuNjYgNS40ODggNS40ODggMCAwMC0uNjkzLTYuNDk3di4wMDF6bS04LjM4MSAxMS41NThhNC4xOTkgNC4xOTkgMCAwMS0yLjY3NS0uOTU0Yy4wMzQtLjAxOC4wOTMtLjA1LjEzMi0uMDc0bDQuNDQtMi41M2EuNzEuNzEgMCAwMC4zNjQtLjYyM3YtNi4xNzZsMS44NzcgMS4wNjljLjAyLjAxLjAzMy4wMjkuMDM2LjA1djUuMTE1Yy0uMDAzIDIuMjc0LTEuODcgNC4xMTgtNC4xNzQgNC4xMjN6TTQuMTkyIDE3Ljc4YTQuMDU5IDQuMDU5IDAgMDEtLjQ5OC0yLjc2M2MuMDMyLjAyLjA5LjA1NS4xMzEuMDc4bDQuNDQgMi41M2MuMjI1LjEzLjUwNC4xMy43MyAwbDUuNDItMy4wODh2Mi4xMzhhLjA2OC4wNjggMCAwMS0uMDI3LjA1N0w5LjkgMTkuMjg4Yy0xLjk5OSAxLjEzNi00LjU1Mi40Ni01LjcwNy0xLjUxaC0uMDAxek0zLjAyMyA4LjIxNkE0LjE1IDQuMTUgMCAwMTUuMTk4IDYuNDFsLS4wMDIuMTUxdjUuMDZhLjcxMS43MTEgMCAwMC4zNjQuNjI0bDUuNDIgMy4wODctMS44NzYgMS4wN2EuMDY3LjA2NyAwIDAxLS4wNjMuMDA1bC00LjQ4OS0yLjU1OWMtMS45OTUtMS4xNC0yLjY3OS0zLjY1OC0xLjUzLTUuNjNoLjAwMXptMTUuNDE3IDMuNTRsLTUuNDItMy4wODhMMTQuODk2IDcuNmEuMDY3LjA2NyAwIDAxLjA2My0uMDA2bDQuNDg5IDIuNTU3YzEuOTk4IDEuMTQgMi42ODMgMy42NjIgMS41MjkgNS42MzNhNC4xNjMgNC4xNjMgMCAwMS0yLjE3NCAxLjgwN1YxMi4zOGEuNzEuNzEgMCAwMC0uMzYzLS42MjN6bTEuODY3LTIuNzczYTYuMDQgNi4wNCAwIDAwLS4xMzItLjA3OGwtNC40NC0yLjUzYS43MzEuNzMxIDAgMDAtLjcyOSAwbC01LjQyIDMuMDg4VjcuMzI1YS4wNjguMDY4IDAgMDEuMDI3LS4wNTdMMTQuMSA0LjcxM2MyLTEuMTM3IDQuNTU1LS40NiA1LjcwNyAxLjUxMy40ODcuODMzLjY2NCAxLjgwOS40OTkgMi43NTdoLjAwMXptLTExLjc0MSAzLjgxbC0xLjg3Ny0xLjA2OGEuMDY1LjA2NSAwIDAxLS4wMzYtLjA1MVY2LjU1OWMuMDAxLTIuMjc3IDEuODczLTQuMTIyIDQuMTgxLTQuMTIuOTc2IDAgMS45Mi4zMzggMi42NzEuOTU0LS4wMzQuMDE4LS4wOTIuMDUtLjEzMS4wNzNsLTQuNDQgMi41M2EuNzEuNzEgMCAwMC0uMzY1LjYyM2wtLjAwMyA2LjE3M3YuMDAyem0xLjAyLTIuMTY4TDEyIDkuMjVsMi40MTQgMS4zNzV2Mi43NUwxMiAxNC43NWwtMi40MTUtMS4zNzV2LTIuNzV6Ij48L3BhdGg+PC9zdmc+',xai:'data:image/svg+xml;base64,PHN2ZyBmaWxsPSJjdXJyZW50Q29sb3IiIGZpbGwtcnVsZT0iZXZlbm9kZCIgaGVpZ2h0PSIxZW0iIHN0eWxlPSJmbGV4Om5vbmU7bGluZS1oZWlnaHQ6MSIgdmlld0JveD0iMCAwIDI0IDI0IiB3aWR0aD0iMWVtIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjx0aXRsZT5Hcm9rPC90aXRsZT48cGF0aCBkPSJNNi40NjkgOC43NzZMMTYuNTEyIDIzaC00LjQ2NEwyLjAwNSA4Ljc3Nkg2LjQ3em0tLjAwNCA3LjlsMi4yMzMgMy4xNjRMNi40NjcgMjNIMmw0LjQ2NS02LjMyNHpNMjIgMi41ODJWMjNoLTMuNjU5VjcuNzY0TDIyIDIuNTgyek0yMiAxbC05Ljk1MiAxNC4wOTUtMi4yMzMtMy4xNjNMMTcuNTMzIDFIMjJ6Ij48L3BhdGg+PC9zdmc+',zhipu:'data:image/svg+xml;base64,PHN2ZyB2aWV3Qm94PSIwIDAgMzEuNSAyNi41MjczIiBmaWxsPSJibGFjayIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KICA8dGl0bGU+WmhpcHU8L3RpdGxlPgogIDwhLS0gWiBzeW1ib2wgZnJvbSBodHRwczovL3d3dy56aGlwdWFpLmNuL2xvZ28uc3ZnOyBvcmlnaW5hbCBwYXRocyB1bmNoYW5nZWQuIC0tPgogIDxwYXRoIGQ9Ik0xNi41Mzc2IDAuMDMwNzM3NEwxNC4zMzI2IDMuMTMyMjNDMTQuMTYxNyAzLjM3NTc3IDEzLjkzMzEgMy41NzQxNSAxMy42NjY3IDMuNzEwMDFDMTMuNDAwNCAzLjg0NTg2IDEzLjEwNDUgMy45MTUwNCAxMi44MDQ4IDMuOTExNUgwLjc4NzU5OFYwLjAxNTE1MkgxNi41Mzc2VjAuMDMwNzM3NFoiLz4KICA8cGF0aCBkPSJNMzEuNSAwLjAzMjE2NTVMMTIuNiAyNi41MjczSDBMMTguOSAwLjAzMjE2NTVIMzEuNVoiLz4KICA8cGF0aCBkPSJNMTQuOTYyNCAyNi41MjcyTDE3LjE4MzIgMjMuNDEwMUMxNy4zNTY0IDIzLjE2ODkgMTcuNTg1NiAyMi45NzIzIDE3Ljg1MTMgMjIuODM2OEMxOC4xMTcxIDIyLjcwMTIgMTguNDExOSAyMi42MzA2IDE4LjcxMDkgMjIuNjMwOEgzMC43MTI0VjI2LjUyNzJIMTQuOTYyNFoiLz4KPC9zdmc+Cg=='};
const escapeHTML=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const icon=(name,slot='')=>`<span${slot?` slot="${slot}"`:''}><i data-lucide="${name}" aria-hidden="true"></i></span>`;
const btn=(label,action,variant='text',ico='',attrs='')=>`<mdui-button variant="${variant}" data-action="${action}" ${attrs}>${ico?icon(ico,'icon'):''}${label}</mdui-button>`;
const iconBtn=(label,action,ico,attrs='')=>`<mdui-tooltip content="${escapeHTML(label)}"><mdui-button-icon aria-label="${escapeHTML(label)}" data-action="${action}" ${attrs}>${icon(ico)}</mdui-button-icon></mdui-tooltip>`;
const chip=(label,ico='')=>`<mdui-chip class="aw-chip-sm" tabindex="-1">${ico?icon(ico,'icon'):''}${label}</mdui-chip>`;
const status=(text,tone='neutral',ico='')=>`<span class="aw-status ${tone}">${ico?icon(ico):''}${text}</span>`;
const logo=(a,large=false)=>`<span class="aw-logo${large?' large':''}">${LOGOS[a.brand]?`<img src="${LOGOS[a.brand]}" alt="">`:icon(a.kind==='acp'?'orbit':a.brand==='local'?'server':'box')}</span>`;

const groups={
 overview:{label:'常见账户',states:[['normal','全部账户']]},
 balance:{label:'余额账户',states:[['normal','余额充足'],['credit','包含赠金'],['multi','多币种余额'],['partial','金额字段缺失'],['low','余额不足'],['notStarted','查询未开始'],['loading','首次查询中'],['refreshing','刷新中 · 保留旧值'],['stale','查询失败 · 保留旧值'],['failed','查询失败 · 无旧值'],['missing','凭据缺失']]},
 subscription:{label:'订阅账户',states:[['normal','多周期额度'],['quotaLow','低额度提醒'],['exhausted','额度已用尽'],['quotaMissing','额度信息缺失'],['refreshing','刷新中 · 保留旧值'],['stale','查询失败 · 保留旧值']]},
 metered:{label:'按量付费 · 无查询',states:[['normal','不支持余额查询'],['missing','凭据缺失']]},
 free:{label:'不计费账户',states:[['normal','本地服务'],['override','手动覆盖计费策略']]},
 unknown:{label:'未知计费类别',states:[['normal','策略尚未识别'],['failed','查询失败 · 类别不变']]},
 acpAuth:{label:'ACP · 认证状态',states:[['unchecked','尚未检查'],['checking','正在检查'],['required','需要登录'],['terminal','终端登录方式'],['unsupportedMethod','不支持的登录方式'],['noMethods','未提供登录方式'],['authenticating','等待完成登录'],['verifying','正在验证'],['verified','已验证'],['closing','正在关闭资源'],['cancelling','正在取消'],['cancelled','已取消'],['authFailed','认证失败']]},
 acpInstall:{label:'ACP · 安装状态',states:[['idle','尚未准备'],['resolve','解析安装版本'],['waitForLock','等待安装锁'],['download','正在下载'],['verify','校验安装包'],['extract','解压安装包'],['publish','准备安装文件'],['close','回收安装资源'],['ready','已准备完成'],['installCancelling','正在取消'],['installCancelled','已取消'],['installFailed','安装失败'],['unsupportedPlatform','平台不支持']]},
 models:{label:'模型目录与编辑',states:[['normal','在线 / 内置 / 手动'],['syncing','模型同步中'],['syncFailed','同步失败 · 保留目录'],['noDiscovery','不支持在线发现'],['modelEmpty','暂无模型'],['thresholdError','阈值校验错误'],['thresholdFailed','阈值保存失败'],['long','长账号名与模型名']]},
 boundaries:{label:'列表边界',states:[['initial','首次加载'],['empty','还没有账号'],['noResults','搜索无结果'],['long','长账号名与模型名']]}
};
const allSteps=Object.entries(groups).flatMap(([type,g])=>g.states.map(([s,label])=>({type,scenario:s,label})));
const totalScenarios=allSteps.length;

let state={type:'overview',scenario:'normal',page:document.getElementById('aw-preview-mount').dataset.page,selected:'deepseek',search:'',defaultId:'zhipu',modelEnabled:{flash:true,pro:true,bundled:false,manual:true},threshold:'475000',modelPrefs:{},modelNames:{},deletedModels:[],manualModels:[],billingSelections:{},selectedModel:'flash',modelTab:'reviews',reviewFilter:'all',reviewSort:'recent',reviewVisible:4,reviewExpanded:[],detailScroll:0,detailExpanded:['flash'],deleted:[],editedNames:{},listScroll:0};
const defaultAccounts=[
 {id:'deepseek',name:'DeepSeek',brand:'deepseek',kind:'balance',endpoint:'https://api.deepseek.com',billing:'metered'},
 {id:'openai',name:'OpenAI',brand:'openai',kind:'metered',endpoint:'https://api.openai.com/v1',billing:'metered'},
 {id:'xai',name:'xAI',brand:'xai',kind:'metered',endpoint:'https://api.x.ai/v1',billing:'metered'},
 {id:'zhipu',name:'Zhipu Coding Plan',brand:'zhipu',kind:'subscription',endpoint:'https://open.bigmodel.cn/api/coding/paas/v4',billing:'subscription'},
 {id:'ollama',name:'Ollama',brand:'local',kind:'free',endpoint:'http://localhost:11434/v1',billing:'noCharge'},
 {id:'acp',name:'Antigravity',brand:'acp',kind:'acp',endpoint:'受管应用 · ACP 接入',billing:'unknown'}
];

function savedRestore(snapshot){
 const p=snapshot?.privateContent;if(!p)return;
 if(groups[p.type])state.type=p.type;
 if(groups[state.type].states.some(([k])=>k===p.scenario))state.scenario=p.scenario;
 if(['list','detail','model'].includes(p.page))state.page=p.page;
 if(typeof p.selected==='string')state.selected=p.selected;
 if(typeof p.search==='string')state.search=p.search.slice(0,120);
 if(typeof p.selectedModel==='string')state.selectedModel=p.selectedModel;
 if(['overview','pricing','reviews'].includes(p.modelTab))state.modelTab=p.modelTab;
 if(p.billingSelections&&typeof p.billingSelections==='object')state.billingSelections=Object.fromEntries(Object.entries(p.billingSelections).filter(([k,v])=>k.length<100&&['auto','metered','subscription','noCharge','unknown'].includes(v)));
}
savedRestore(window.openai?.widgetState);

function save(){
 window.openai?.setWidgetState?.({
  modelContent:{design:'账号列表与详情',accountVariant:groups[state.type].label,scenario:groups[state.type].states.find(([k])=>k===state.scenario)?.[1],page:state.page,model:state.page==='model'?currentModel().name:null,modelTab:state.page==='model'?state.modelTab:null},
  privateContent:{type:state.type,scenario:state.scenario,page:state.page,selected:state.selected,search:state.search,selectedModel:state.selectedModel,modelTab:state.modelTab,billingSelections:state.billingSelections}
 })?.catch(()=>{});
}

function currentAccounts(){
 let list=defaultAccounts.map(a=>({...a,name:state.editedNames[a.id]||a.name}));
 if(state.type==='unknown')list=[{id:'custom',name:'自定义账号',brand:'custom',kind:'unknown',endpoint:'https://api.example.com/v1',billing:'unknown'},...list];
 if(state.type==='free'&&state.scenario==='override'&&(!Object.hasOwn(state.billingSelections,'deepseek')||state.billingSelections.deepseek==='noCharge')){
  list[0]={...list[0],kind:'free',override:true,billing:'noCharge'};
 }
 if(state.scenario==='long')list[0]={...list[0],name:'DeepSeek · 产品研发团队的共享工作空间账号'};
 return list.filter(a=>!state.deleted.includes(a.id));
}
function selectedAccount(){return currentAccounts().find(a=>a.id===state.selected)||currentAccounts()[0]||defaultAccounts[0];}
function targetId(){return ({balance:'deepseek',subscription:'zhipu',metered:'openai',free:state.scenario==='override'?'deepseek':'ollama',unknown:'custom',acpAuth:'acp',acpInstall:'acp',models:'deepseek',boundaries:'deepseek'})[state.type]||'deepseek';}
function scenario(a){return a.id===targetId()?state.scenario:'normal';}
function hydrateIcons(){
 $$('mdui-select').forEach(select=>{if(!select.querySelector('[slot=end-icon]'))select.insertAdjacentHTML('beforeend',icon('chevron-down','end-icon'));});
 if(globalThis.lucide)lucide.createIcons({attrs:{width:18,height:18}});
}
function toast(message){$('#aw-snackbar').textContent=message;$('#aw-snackbar').open=true;}
function notice(message,tone='warning',action=''){return `<div class="aw-notice ${tone}">${icon(tone==='error'?'circle-alert':tone==='success'?'circle-check':'info')}<div class="aw-notice-text">${message}</div>${action}</div>`;}
function billingName(kind){return ({metered:'按量付费',subscription:'订阅',noCharge:'不计费',unknown:'未知计费'})[kind]||'未知计费';}
function accountStatus(a){
 if(a.kind==='acp'){const stage=acpStage(scenario(a));return status(stage.title,stage.tone,stage.ico);}
 return status(billingName(effectiveBilling(a)),'neutral');
}
function balanceHealth(a){
 const s=scenario(a);
 if(a.kind!=='balance'||['missing','loading','notStarted','failed'].includes(s))return '';
 const low=s==='low';
 return `<span class="aw-balance-health${low?' error':''}">${icon(low?'circle-alert':'circle-check')}${low?'余额不足':'余额充足'}</span>`;
}
function shortEndpoint(a){
 if(a.kind==='acp')return '受管应用 · ACP 接入';
 if(a.id==='ollama')return 'localhost:11434 · 本地服务';
 return a.endpoint.replace(/^https?:\/\//,'').replace(/\/v\d+$/,'');
}

function amount(value,currency='¥',main=false){
 return `<div class="aw-metric-value${main?' main':''}">${value===null?'—':`<span class="aw-currency">${currency}</span>${value}`}</div>`;
}
function balanceCells(s='normal',currency='¥',healthBadge=''){
 let total='2,595.22',grant='0.00',paid='2,595.22';
 if(s==='credit'){grant='120.00';paid='2,475.22';}
 if(s==='low'){total='0.00';paid='0.00';}
 if(s==='partial')grant=null;
 if(currency==='$'){total='82.40';grant='2.40';paid='80.00';}
 return `<div class="aw-balance-grid"><div class="aw-balance-item"><span class="aw-metric-label">可用余额${s==='multi'?` · ${currency==='¥'?'CNY':'USD'}`:''}${healthBadge}</span>${amount(total,currency,true)}</div><div class="aw-balance-item"><span class="aw-metric-label">赠金</span>${amount(grant,currency)}</div><div class="aw-balance-item"><span class="aw-metric-label">充值余额</span>${amount(paid,currency)}</div></div>`;
}
function quotaCells(s,detail=false){
 const vals=s==='quotaLow'?[8,25,98.9]:s==='exhausted'?[0,0,12]:s==='quotaMissing'?[null,25,null]:[94,25,98.9];
 const resets=['今天 14:12 重置','明天 12:00 重置','11/15 09:16 重置'];
 return `<div class="aw-quota-grid">${['5 小时额度','每周额度','MCP 额度'].map((l,i)=>{
  const v=vals[i];
  const stateCls=v===0?'error':v!==null&&v<=25?'warn':'';
  const alertNote=detail&&v!==null&&v<=25?` · ${v===0?'额度已用尽':'额度较低'}`:'';
  return `<div class="aw-quota ${stateCls}"><div class="aw-quota-head"><span class="aw-metric-label">${l}</span><span class="aw-quota-value">${v===null?'未提供':`剩余 ${v}%`}</span></div>${v===null?'':`<mdui-linear-progress value="${v/100}" aria-label="${l}剩余${v}%"></mdui-linear-progress>`}<small>${(s==='quotaMissing'&&i!==1?'重置时间未提供':resets[i])+alertNote}</small></div>`;
 }).join('')}</div>`;
}
function rowAmount(a){
 const s=scenario(a);
 if(a.kind==='acp'){
  const stage=acpStage(s);
  return `<div class="aw-empty-value">${stage.summary}<span class="aw-inline-note">${stage.description}</span></div>${s==='download'?'<mdui-linear-progress value="0.46" style="margin-top:6px" aria-label="下载进度46%"></mdui-linear-progress>':''}`;
 }
 if(s==='missing')return `<div class="aw-empty-value" style="color:rgb(var(--mdui-color-error))">凭据尚未配置<span class="aw-inline-note">请在账号设置中添加 API 密钥</span></div>`;
 if(s==='loading'||s==='notStarted')return `<div class="aw-empty-value">${s==='loading'?'正在查询用量…':'等待查询'}<span class="aw-inline-note">${s==='loading'?'请求进行中':'尚无余额记录'}</span></div>${s==='loading'?'<mdui-linear-progress style="margin-top:6px" aria-label="正在查询"></mdui-linear-progress>':''}`;
 if(s==='failed')return `<div class="aw-empty-value" style="color:rgb(var(--mdui-color-error))">暂时无法获取用量<span class="aw-inline-note">连接超时 · 可重试</span></div>`;
 let body='';
 if(a.kind==='balance'){
  const hb=balanceHealth(a);
  body=s==='multi'?`<div class="aw-balance-multi"><div><span class="aw-metric-label">可用余额 · CNY${hb}</span>${amount('2,595.22','¥',true)}</div><div><span class="aw-metric-label">可用余额 · USD</span>${amount('82.40','$',true)}</div></div>`:balanceCells(s,'¥',hb);
 }else if(a.kind==='subscription'){
  body=quotaCells(s);
 }else if(a.kind==='free'){
  body=a.override?`<div class="aw-empty-value">按不计费策略估算<span class="aw-inline-note">手动覆盖 · 供应商仍可能实际收费</span></div>`:`<div class="aw-empty-value aw-muted">本地运行 · 无需余额</div>`;
 }else{
  body=a.kind==='unknown'?`<div class="aw-empty-value aw-muted">计费类别待确认<span class="aw-inline-note">暂未提供用量数据</span></div>`:`<div class="aw-empty-value aw-muted">暂不支持余额查询</div>`;
 }
 if(s==='stale')body+=`<div class="aw-query-note error">${icon('circle-alert')}刷新失败 · 保留 10:24 的查询结果</div>`;
 if(s==='refreshing')body+=`<div class="aw-query-note">${icon('refresh-cw')}正在刷新 · 保留 10:24 的查询结果</div>`;
 return body;
}

const acpMap={
 normal:['已验证','success','check','可连接会话','安装与认证检查已完成','检查连接','checkAcp',false],
 unchecked:['尚未检查','neutral','circle-help','等待首次检查','先检查本机安装与认证状态','检查连接','checkAcp',false],
 checking:['正在检查','','loader','检查安装与认证','正在读取服务状态，尚未确认可用','取消','cancelAcp',true],
 required:['需要登录','warning','log-in','等待完成账户认证','通过服务提供的登录方式继续','登录','loginAcp',false],
 terminal:['需要登录','warning','terminal','需要在终端登录','服务端仅提供终端登录方式，完成后返回验证','我已完成，验证','verifyAcp',false],
 unsupportedMethod:['无法登录','error','circle-alert','不支持此登录方式','服务端宣告的认证方式目前无法在应用中使用','重新检查','checkAcp',false],
 noMethods:['需要登录','warning','circle-help','未提供登录方式','服务端没有提供可执行的认证方法','重新检查','checkAcp',false],
 authenticating:['等待登录','','log-in','请在授权窗口继续','完成登录后返回此处验证；可随时取消','取消','cancelAcp',true],
 verifying:['正在验证','','loader','确认认证是否生效','正在验证账户连接，不会重复发起登录','取消','cancelAcp',true],
 verified:['已验证','success','check','可连接会话','安装与认证检查已完成','检查连接','checkAcp',false],
 closing:['正在关闭','','loader','正在回收连接资源','关闭完成后再确认本次操作的最终状态','','',true],
 cancelling:['正在取消','','loader','正在等待操作结束','取消请求已发出，仍在回收资源','','',true],
 cancelled:['已取消','neutral','circle-minus','本次认证已取消','账户配置已保留，可以重新检查','重新检查','checkAcp',false],
 authFailed:['认证失败','error','circle-alert','暂时无法完成认证','连接超时，账户配置已保留，可重新尝试','重试','checkAcp',false],
 idle:['尚未准备','neutral','download','需要准备受管程序','先下载并准备此接入所需的官方程序','准备安装','installAcp',false],
 resolve:['准备中','','loader','正在解析安装版本','正在确认与当前平台匹配的安装文件','取消','cancelInstall',true],
 waitForLock:['等待中','','clock','等待另一安装操作','同一程序的准备正在进行，完成后继续','取消','cancelInstall',true],
 download:['下载中','','download','已下载 46%','74 MB / 160 MB · 4.2 MB/s','取消','cancelInstall',true],
 verify:['校验中','','shield-check','正在校验安装文件','确认下载文件完整性','取消','cancelInstall',true],
 extract:['解压中','','package-open','正在解压安装文件','准备受管程序的运行文件','取消','cancelInstall',true],
 publish:['准备中','','package-check','正在发布已准备安装','安装即将就绪','取消','cancelInstall',true],
 close:['正在结束','','loader','正在回收安装资源','仍在等待安装操作完成，不代表已经就绪','','',true],
 ready:['已准备','success','check','受管程序已就绪','使用这份安装继续检查与认证','使用并连接','connectAcp',false],
 installCancelling:['正在取消','','loader','等待安装操作退出','正在回收下载与安装资源','','',true],
 installCancelled:['已取消','neutral','circle-minus','安装已取消','账号配置已保留，可以重新准备','重新准备','installAcp',false],
 installFailed:['安装失败','error','circle-alert','下载失败，请重试','网络连接中断，尚未发布新安装','重试安装','installAcp',false],
 unsupportedPlatform:['平台不支持','warning','monitor-x','此平台暂无受管发行','当前宿主无法自动安装这个接入程序','','',false]
};
function acpStage(s){const a=acpMap[s]||acpMap.normal;return {title:a[0],tone:a[1],ico:a[2],summary:a[3],description:a[4],action:a[5],actionId:a[6],busy:a[7]};}

function rowMenu(a){
 return `<mdui-dropdown placement="bottom-end"><mdui-button-icon slot="trigger" aria-label="${escapeHTML(a.name)}更多操作">${icon('ellipsis')}</mdui-button-icon><mdui-menu>${a.kind==='acp'?`<mdui-menu-item data-action="rowCheck" data-id="${a.id}">${icon('refresh-cw','icon')}检查连接</mdui-menu-item>`:`<mdui-menu-item data-action="rowRefresh" data-id="${a.id}" ${['metered','unknown','free'].includes(a.kind)?'disabled':''}>${icon('refresh-cw','icon')}刷新用量</mdui-menu-item><mdui-menu-item data-action="setDefault" data-id="${a.id}">${icon('star','icon')}${state.defaultId===a.id?'当前默认账号':'设为默认'}</mdui-menu-item>`}<mdui-menu-item data-action="edit" data-id="${a.id}">${icon('pencil','icon')}编辑账号</mdui-menu-item><mdui-divider></mdui-divider><mdui-menu-item data-action="delete" data-id="${a.id}" style="color:rgb(var(--mdui-color-error))">${icon('trash-2','icon')}删除账号</mdui-menu-item></mdui-menu></mdui-dropdown>`;
}
function accountRow(a){
 return `<article class="aw-account-row"><button type="button" class="aw-open-account aw-row-grid" data-open-account="${a.id}" aria-label="打开 ${escapeHTML(a.name)} 的详情"><div class="aw-identity">${logo(a)}<div class="aw-name-wrap"><div class="aw-name-line"><span class="aw-name">${escapeHTML(a.name)}</span>${state.defaultId===a.id?chip('默认'):''}</div><div class="aw-identity-description">${escapeHTML(shortEndpoint(a))}</div></div></div><div class="aw-row-status">${accountStatus(a)}</div><div class="aw-row-amount">${rowAmount(a)}</div></button>${rowMenu(a)}</article>`;
}
function listMarkup(){
 const initial=state.type==='boundaries'&&state.scenario==='initial',empty=state.type==='boundaries'&&state.scenario==='empty';
 const noResults=state.type==='boundaries'&&state.scenario==='noResults';
 let accounts=currentAccounts();
 if(state.type!=='overview'&&state.type!=='boundaries'){
  const target=targetId();
  accounts.sort((a,b)=>(b.id===target?1:0)-(a.id===target?1:0));
 }
 const query=noResults?'不存在的账号':state.search;
 accounts=accounts.filter(a=>a.name.toLowerCase().includes(query.toLowerCase()));
 return `<div class="aw-page-header"><div><div class="aw-row">${iconBtn('设置导航','mobileNav','menu','class="aw-menu-mobile"')}<h1>账号</h1></div><p class="aw-page-subtitle">管理模型服务与受管接入，查看实时余额与订阅额度。</p></div><div class="aw-row">${btn('刷新用量','refreshAll','tonal','refresh-cw')}${btn('添加账号','add','filled','plus')}</div></div><div class="aw-tools"><mdui-text-field id="aw-search" class="aw-search" variant="outlined" placeholder="搜索账号名称…" aria-label="搜索账号" value="${escapeHTML(query)}" clearable>${icon('search','icon')}</mdui-text-field><div class="aw-tools-meta">${initial?'正在加载账户…':`共 ${empty?0:accounts.length} 个账号 · 更新于 10:24`}</div></div><mdui-card variant="outlined" class="aw-account-card"><div class="aw-table-head aw-row-grid"><span>账号</span><span>计费与状态</span><span>余额与额度</span></div>${initial?Array.from({length:4},()=>'<div class="aw-skeleton-row"><div class="aw-skeleton-block" style="width:38px;height:38px;border-radius:10px"></div><div class="aw-skeleton-block" style="width:24%"></div><div class="aw-skeleton-block" style="width:38%;margin-left:auto"></div></div>').join(''):empty?`<div class="aw-empty">${icon('cloud')}<h2>连接你的第一个账号</h2><p>添加模型服务账号，或连接已有的 ACP 受管应用。</p>${btn('添加账号','add','filled','plus')}</div>`:!accounts.length?`<div class="aw-empty">${icon('search')}<h2>没有找到匹配的账号</h2><p>试试其他名称，或清除当前搜索条件。</p>${btn('清除搜索','clearSearch','tonal')}</div>`:accounts.map(accountRow).join('')}</mdui-card>`;
}

function balanceDetail(a){
 const s=scenario(a);
 let errors='';
 if(s==='stale')errors=notice('刷新失败，当前保留 10:24 的最近有效结果。','error',btn('重试','refresh','text'));
 if(s==='missing')return `<mdui-card variant="outlined" class="aw-muted-card"><mdui-list><mdui-list-item nonclickable headline="添加凭据以查询用量" description="此账号仍按量付费；凭据未配置不代表免费。">${icon('key-round','icon')}${btn('配置凭据','edit','filled','','slot="end-icon"')}</mdui-list-item></mdui-list></mdui-card>`;
 if(s==='failed')return `<mdui-card variant="outlined" class="aw-muted-card"><mdui-list><mdui-list-item nonclickable headline="暂时无法获取用量" description="连接超时，尚无可用的历史查询结果。">${icon('cloud-off','icon')}${btn('重新查询','refresh','tonal','refresh-cw','slot="end-icon"')}</mdui-list-item></mdui-list></mdui-card>`;
 if(s==='loading'||s==='notStarted')return `<mdui-card variant="outlined" class="aw-muted-card"><mdui-list><mdui-list-item nonclickable headline="${s==='loading'?'正在查询余额':'尚未查询用量'}" description="余额信息将在查询完成后显示。">${icon('clock','icon')}${s==='loading'?'':btn('查询用量','refresh','tonal','refresh-cw','slot="end-icon"')}</mdui-list-item></mdui-list>${s==='loading'?'<mdui-linear-progress aria-label="正在查询余额"></mdui-linear-progress>':''}</mdui-card>`;
 if(a.kind==='free')return `<mdui-card variant="outlined" class="aw-muted-card"><mdui-list><mdui-list-item nonclickable headline="${a.override?'已手动覆盖为不计费策略':'本地服务运行中，无需余额'}" description="${a.override?'此设置仅影响本地费用估算，供应商仍可能实际收费。':'直接调用本机模型服务，不展示余额或订阅额度。'}">${icon('server','icon')}</mdui-list-item></mdui-list></mdui-card>`;
 if(['metered','unknown'].includes(a.kind))return `<mdui-card variant="outlined" class="aw-muted-card"><mdui-list><mdui-list-item nonclickable headline="${a.kind==='unknown'?'计费类别尚未识别':'此服务暂不支持余额查询'}" description="${a.kind==='unknown'?'可在下方账号设置中指定估算策略；查询失败不会改变计费类别。':'已启用的模型可正常调用，实际费用以供应商账单结算为准。'}">${icon(a.kind==='unknown'?'circle-help':'wallet','icon')}</mdui-list-item></mdui-list></mdui-card>`;
 const subscription=a.kind==='subscription';
 return `${errors}<mdui-card variant="filled" class="aw-balance-card"><div class="aw-card-header"><div class="aw-row"><h2>${subscription?'订阅额度':'账户余额'}</h2>${subscription?'':balanceHealth(a)}</div><div class="aw-row"><small>${s==='refreshing'?'正在刷新…':'更新于 10:24'}</small>${iconBtn('刷新账户用量','refresh','refresh-cw')}</div></div>${subscription?quotaCells(s,true):s==='multi'?`<div class="aw-multicurrency-detail">${balanceCells(s,'¥')}</div><div class="aw-multicurrency-detail">${balanceCells(s,'$')}</div>`:balanceCells(s)}${s==='refreshing'?'<mdui-linear-progress style="margin-top:14px" aria-label="刷新中"></mdui-linear-progress>':''}${s==='partial'?'<p class="aw-page-subtitle" style="margin-top:10px">赠金字段未提供，以 — 表示，不计为 0。</p>':''}${s==='multi'?'<p class="aw-page-subtitle" style="margin-top:10px">各币种分别展示，不进行跨币种折算汇总。</p>':''}</mdui-card>`;
}

function billingSelection(a){if(Object.hasOwn(state.billingSelections,a.id))return state.billingSelections[a.id];return a.override?'noCharge':'auto';}
function effectiveBilling(a){const value=billingSelection(a);return value==='auto'?(a.override?'metered':a.billing):value;}
function settingsMarkup(a){
 const s=scenario(a),missing=s==='missing',value=billingSelection(a);
 const protocol=a.id==='deepseek'?'DeepSeek API':'OpenAI-compatible';
 return `<section class="aw-section"><div class="aw-section-heading"><h2>账号设置</h2></div><mdui-card variant="outlined" class="aw-setting-card"><mdui-list><mdui-list-item nonclickable headline="API 密钥" description="${a.id==='ollama'?'本地服务无需配置凭据':missing?'尚未配置 · 请添加密钥以启用服务':'已安全配置'}">${icon('key-round','icon')}${a.id==='ollama'?'':btn(missing?'配置':'更新','edit','tonal','','slot="end-icon"')}</mdui-list-item><mdui-divider></mdui-divider><mdui-list-item nonclickable headline="计费方式" description="仅影响本应用费用估算，实际费用以供应商结算为准">${icon('credit-card','icon')}<div slot="end-icon" class="aw-billing-end"><mdui-select id="aw-billing-inline" aria-label="计费方式" variant="outlined" value="${value}" data-account="${a.id}"><mdui-menu-item value="auto">自动（${billingName(a.override?'metered':a.billing)}）</mdui-menu-item><mdui-menu-item value="metered">按量付费</mdui-menu-item><mdui-menu-item value="subscription">订阅</mdui-menu-item><mdui-menu-item value="noCharge">不计费</mdui-menu-item><mdui-menu-item value="unknown">未知</mdui-menu-item></mdui-select><span class="aw-save-state" id="aw-billing-save-status" role="status">${icon('check')}${Object.hasOwn(state.billingSelections,a.id)?'已保存 · ':''}${value==='auto'?'自动识别':'手动覆盖'}</span></div></mdui-list-item><mdui-divider></mdui-divider><mdui-collapse><mdui-collapse-item value="advanced"><mdui-list-item slot="header" headline="高级信息" description="${a.id}-demo · ${protocol} · HTTP">${icon('sliders-horizontal','icon')}${icon('chevron-right','end-icon')}</mdui-list-item><div class="aw-advanced-content"><span>账号 ID</span><code>${a.id}-demo</code><span>接口协议</span><span>${protocol}</span><span>默认连接</span><span>HTTP · 支持按模型覆盖</span></div></mdui-collapse-item></mdui-collapse></mdui-list></mdui-card></section>`;
}

const reviewExamples=[
 {id:'r10',score:5,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 27 日',time:'2026-10-27T10:12',title:'修改范围准确，边界情况也照顾到了',task:'修复账号用量刷新后的状态显示',text:'能先沿调用链定位问题，再用较小的改动完成修复。刷新失败时保留旧余额，缺失字段没有被误显示成 0；补充的验证也覆盖了关键边界。结论与任务证据一致。',tags:['边界完整','改动克制'],category:'代码任务',evidence:'检查了成功、失败保留旧值、凭据缺失与多币种四种场景；示例结果均符合任务要求。'},
 {id:'r9',score:5,evaluator:'DeepSeek-V4-Pro',provider:'DeepSeek',date:'10 月 27 日',time:'2026-10-27T09:30',title:'信息整理清楚，拿到结果就能继续工作',task:'整理模型接入文档与配置说明',text:'把分散的配置项整理成了容易查阅的说明，调用限制、失败原因和排查步骤放在合适的位置。内容没有堆砌，读者能快速找到下一步该做什么。',tags:['结构清晰','表达简洁'],category:'文档整理',evidence:'核对了配置字段、示例和引用，任务输出包含完整的使用路径与已知限制。'},
 {id:'r8',score:4,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 26 日',time:'2026-10-26T17:20',title:'主要需求完成，错误提示还可以更具体',task:'实现账号搜索与空状态',text:'搜索和返回后的条件恢复都符合要求，空列表与无结果也能区分。个别失败提示只说明了操作失败，没有指出重试入口，建议把恢复动作一起呈现。',tags:['交互完整','提示待细化'],category:'界面实现',evidence:'搜索行为通过；两处异常提示缺少明确恢复动作，因此保留改进意见。'},
 {id:'r7',score:5,evaluator:'DeepSeek-V4-Pro',provider:'DeepSeek',date:'10 月 26 日',time:'2026-10-26T14:08',title:'工具使用有条理，验证结果容易复核',task:'排查模型目录同步失败',text:'先缩小问题范围，再对照请求和返回结果验证推断。没有把重试成功当作根因修复，最终说明能够对应到具体证据，并保留了尚未验证的部分。',tags:['证据充分','工具使用合理'],category:'问题排查',evidence:'对照了请求身份、错误返回与缓存状态，结论附有可复核的示例步骤。'},
 {id:'r6',score:5,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 25 日',time:'2026-10-25T18:05',title:'长文档中的约束没有丢失',task:'根据设计文档拆解账户重构计划',text:'在较长的设计材料中保留了数据所有权、界面导航和资源回收约束。计划分组合理，依赖关系说得清楚，没有将设计稿中的示例数值当成真实产品要求。',tags:['约束完整','结构清晰'],category:'长文分析',evidence:'核对了原文中的功能保留清单、迁移边界和验收要求，未发现关键约束遗漏。'},
 {id:'r5',score:3,evaluator:'DeepSeek-V4-Pro',provider:'DeepSeek',date:'10 月 25 日',time:'2026-10-25T11:42',title:'基本可用，取消路径还需要补齐',task:'实现后台操作取消与状态反馈',text:'正常完成路径较完整，但取消后仍可能留下等待状态，结果说明也没有区分“已请求取消”和“操作已结束”。建议补充收尾验证，再判断任务是否真正完成。',tags:['取消路径待补齐','验证不足'],category:'代码任务',evidence:'正常完成通过；取消后资源等待与最终状态缺少完整证据，因此给出待改进评价。'},
 {id:'r4',score:5,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 24 日',time:'2026-10-24T16:10',title:'数据转换细致，没有把未知值当成零',task:'整理不同供应商的余额结构',text:'能清楚区分余额、赠金和充值余额，并按币种分别组织。对供应商没有返回的字段保留了缺失语义，展示说明和转换逻辑一致。',tags:['边界完整','数据准确'],category:'数据处理',evidence:'示例覆盖多币种、空值和赠金；不同币种没有被合并统计。'},
 {id:'r3',score:4,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 24 日',time:'2026-10-24T10:25',title:'改动有效，交付说明可以再精简',task:'调整设置页布局与响应式规则',text:'窄窗下的内容重排自然，按钮没有遮挡，信息层级比原来清晰。交付说明稍长，重复列出了部分实现细节；如果把验证范围集中说明，会更容易阅读。',tags:['布局清晰','说明略长'],category:'界面实现',evidence:'宽屏、窄屏与长文本样例均可使用；改进点集中在交付表达。'},
 {id:'r2',score:5,evaluator:'DeepSeek-V4-Pro',provider:'DeepSeek',date:'10 月 23 日',time:'2026-10-23T15:32',title:'定位快速，修复与问题直接对应',task:'修复模型开关与折叠箭头互相干扰',text:'识别到了交互事件冒泡的问题，开关和展开动作的职责划分清晰。修复后分别验证了鼠标和键盘操作，没有引入多余状态或新的配置来源。',tags:['工具使用合理','改动克制'],category:'问题排查',evidence:'检查了独立切换、键盘聚焦及返回后的状态，示例结果满足要求。'},
 {id:'r1',score:5,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 23 日',time:'2026-10-23T09:18',title:'任务完成度高，也明确说清了限制',task:'制作账号详情的交互设计稿',text:'保留了主要入口，模型信息、价格和评价的层次明确。所有模拟数据都有说明，能区分界面验证与真实供应商能力，交付结果方便继续评审。',tags:['交互完整','表达简洁'],category:'界面设计',evidence:'详情导航、模型展开和空态均可查看；未把本地模拟结果外推为真实服务验证。'}
];
const addedFlashReviews=[
 {id:'r14',score:5,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 27 日',time:'2026-10-27T14:40',title:'打开就能用，小细节也处理得很顺手',task:'优化账号列表的状态与余额排版',text:'计费方式和余额状态终于分清楚了。账号名称、状态、金额各自对齐，扫一眼就知道该看哪里；窄窗口下也没有挤在一起，整体比之前清爽。',tags:['布局清晰','交互完整'],category:'界面设计',evidence:'模拟核对了普通余额、低余额、订阅和查询失败四类条目；金额与标签没有互相遮挡。'},
 {id:'r13',score:4,evaluator:'DeepSeek-V4-Pro',provider:'DeepSeek',date:'10 月 27 日',time:'2026-10-27T13:28',title:'完成得很快，最后的检查还能再细一点',task:'补充文件导出的失败提示',text:'提示内容直白，重试入口也容易找到。主要流程已经可用，不过长文件名的换行没有一起验证，建议交付前补上这个场景。',tags:['表达简洁','长名称待验证'],category:'界面实现',evidence:'模拟成功与失败路径均可操作，超长文件名的布局检查未提供。'},
 {id:'r12',score:2,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 27 日',time:'2026-10-27T12:06',title:'看起来完成了，实际还缺少关键步骤',task:'增加网络断开后的恢复操作',text:'界面上有了重试按钮，但重试时没有清楚区分旧请求和新请求。连续点击后可能出现重复状态，任务目标只完成了一部分。',tags:['并发处理待补齐','验证不足'],category:'问题修复',evidence:'模拟连续重试场景出现重复提示，未提供请求去重和迟到结果处理的验证。'},
 {id:'r11',score:1,evaluator:'DeepSeek-V4-Pro',provider:'DeepSeek',date:'10 月 27 日',time:'2026-10-27T11:15',title:'结果与要求不符，需要重新检查任务目标',task:'保留配置并调整默认模型',text:'任务要求只调整默认选择，输出却同时改动了其他配置。虽然有完成说明，但没有证明原有配置得到保留，本次结果不满足验收条件。',tags:['范围控制不足','需要重新处理'],category:'配置任务',evidence:'模拟差异包含不在要求内的配置修改，且没有配置保全的验证记录。'}
];
const proReviewExamples=[
 {id:'pro6',score:5,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 27 日',time:'2026-10-27T14:18',title:'复杂的问题也能讲清楚取舍',task:'审查异步任务的取消与资源回收',text:'不只关注正常路径，也把取消、超时和迟到回调分别展开了。建议与实际调用顺序对应，方便实现者逐条处理，审查结论很有可操作性。',tags:['证据充分','边界完整'],category:'代码审查',evidence:'模拟审查覆盖四种退出路径，每条结论都有对应的调用顺序说明。'},
 {id:'pro5',score:4,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 26 日',time:'2026-10-26T18:05',title:'方案稳妥，就是解释稍微长了些',task:'比较两种配置保存方案',text:'冲突处理和错误传播都考虑到了，选型理由也比较完整。重复说明的部分可以缩短，把最终建议和适用条件提前会更好读。',tags:['方案清晰','说明略长'],category:'方案分析',evidence:'模拟方案覆盖同账户并发更新，存在两段重复的背景说明。'},
 {id:'pro4',score:5,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 26 日',time:'2026-10-26T12:45',title:'从日志中找到了真正的问题点',task:'排查目录同步偶发失败',text:'按时间顺序对照配置版本、请求和提交结果，识别出旧请求覆盖新配置的风险。给出的修复建议直接针对问题，没有添加多余的轮询。',tags:['定位准确','改动克制'],category:'问题排查',evidence:'模拟轨迹显示旧请求晚于新配置完成；建议通过请求代次阻止旧结果发布。'},
 {id:'pro3',score:3,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 25 日',time:'2026-10-25T16:32',title:'方向没问题，迁移步骤还不够具体',task:'规划存储结构调整',text:'清楚解释了目标结构与约束，但现有数据如何迁移、失败后怎样恢复还停留在概述。需要补充可以执行的步骤才能用于实施。',tags:['结构清晰','迁移步骤待补齐'],category:'架构设计',evidence:'模拟输出未覆盖迁移中断后的恢复入口，无法据此直接实施。'},
 {id:'pro2',score:5,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 24 日',time:'2026-10-24T11:50',title:'既给出了修复，也说明了为什么有效',task:'修复模型开关状态回退',text:'明确指出了旧快照覆盖新意图的触发条件，修复后补上顺序反转的验证。说明简洁，可以从复现步骤一直跟到最终结果。',tags:['验证完整','表达简洁'],category:'代码任务',evidence:'模拟回归先复现状态回退，再通过相同输入验证修复。'},
 {id:'pro1',score:4,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 23 日',time:'2026-10-23T09:05',title:'长资料梳理得不错，来源标注可再明确',task:'整理跨模块的配置契约',text:'整理后的结构容易查阅，能保留多个模块之间的职责边界。有两处结论没有对应来源，建议把引用补齐，方便后来的人复核。',tags:['结构清晰','引用待补齐'],category:'文档整理',evidence:'模拟核对主要契约一致，两条设计结论缺少明确出处。'}
];
const nativeReviewExamples=[
 {id:'native6',score:5,evaluator:'DeepSeek-V4-Pro',provider:'DeepSeek',date:'10 月 27 日',time:'2026-10-27T13:20',title:'结果清楚，基本不需要再返工',task:'整理会议记录与后续事项',text:'把讨论结论、待确认问题和后续动作分得很清楚。责任人与时间没有混在正文里，核对原文后也没有漏掉重要限制。',tags:['结构清晰','信息完整'],category:'信息整理',evidence:'模拟对照了原始会议记录，行动项与讨论结论一一对应。'},
 {id:'native5',score:4,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 26 日',time:'2026-10-26T15:35',title:'代码可以直接接着用，命名还可以更统一',task:'补充查询结果的展示逻辑',text:'加载、空值和错误状态处理完整，正常使用没有阻碍。少量变量命名与周围代码不一致，统一后维护起来会更轻松。',tags:['边界完整','命名待统一'],category:'代码任务',evidence:'模拟用例覆盖空结果、部分数据和失败返回；发现两处命名不一致。'},
 {id:'native4',score:3,evaluator:'DeepSeek-V4-Pro',provider:'DeepSeek',date:'10 月 25 日',time:'2026-10-25T18:14',title:'正文质量不错，但有一项要求遗漏了',task:'生成产品功能说明',text:'内容易读，功能描述也准确，不过没有写出离线场景的限制。需要结合原始要求补上这一段，避免读者误解支持范围。',tags:['表达清楚','需求遗漏'],category:'文档写作',evidence:'模拟验收清单中的离线限制没有出现在最终说明中。'},
 {id:'native3',score:5,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 24 日',time:'2026-10-24T16:08',title:'图表和文字能互相印证',task:'整理测试结果并生成摘要',text:'统计口径保持一致，成功、失败和未运行没有混在一起。摘要能快速看到本轮覆盖范围，细节也有对应的结果记录。',tags:['数据准确','证据充分'],category:'结果分析',evidence:'模拟汇总与逐条记录数量一致，未运行用例单独列出。'},
 {id:'native2',score:2,evaluator:'DeepSeek-V4-Pro',provider:'DeepSeek',date:'10 月 23 日',time:'2026-10-23T14:27',title:'建议有参考价值，关键结论缺少验证',task:'定位启动速度变慢的原因',text:'列出了可能原因，却没有用同条件数据逐项排除。最终把猜测写成了确定结论，需要补充测量才能判断是否找到了真正原因。',tags:['证据不足','结论待验证'],category:'性能排查',evidence:'模拟输出缺少基线对照，也没有能够支持结论的测量记录。'},
 {id:'native1',score:4,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 22 日',time:'2026-10-22T10:42',title:'步骤实用，跟着操作就能完成',task:'编写开发环境准备指南',text:'安装、配置和检查步骤顺序合理，常见问题也有对应说明。建议补充工具版本的适用范围，降低不同环境下的试错成本。',tags:['步骤清楚','版本范围待补齐'],category:'操作指南',evidence:'模拟环境中按顺序完成准备，指南尚未列出最低支持版本。'}
];
const manualReviewExamples=[
 {id:'manual4',score:4,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 27 日',time:'2026-10-27T11:32',title:'简单任务很顺手，输出也比较克制',task:'从文本中提取待办事项',text:'提取的事项基本完整，没有把背景讨论也变成任务。两个相近事项还可以再合并一下，整体已经能够直接使用。',tags:['表达简洁','信息完整'],category:'文本处理',evidence:'模拟输入包含八项待办，全部提取；其中两项内容相近。'},
 {id:'manual3',score:5,evaluator:'DeepSeek-V4-Pro',provider:'DeepSeek',date:'10 月 26 日',time:'2026-10-26T15:04',title:'格式稳定，适合接到后续流程里',task:'输出结构化配置摘要',text:'字段齐全，类型与约定一致，缺失值处理也清楚。多组输入下都保持相同结构，后续程序可以直接消费。',tags:['结构稳定','数据准确'],category:'结构化输出',evidence:'模拟验证了五组输入，输出均通过字段和类型校验。'},
 {id:'manual2',score:3,evaluator:'GPT-5',provider:'OpenAI',date:'10 月 25 日',time:'2026-10-25T10:16',title:'短文本表现正常，长输入时有遗漏',task:'总结较长的技术文档',text:'摘要可读性不错，但输入变长后漏掉了结尾的两项约束。建议更明确地核对章节覆盖，再把总结标记为完成。',tags:['表达清楚','长文覆盖待补齐'],category:'长文分析',evidence:'模拟原文共七节，最终摘要没有涵盖最后一节的限制。'},
 {id:'manual1',score:2,evaluator:'DeepSeek-V4-Pro',provider:'DeepSeek',date:'10 月 24 日',time:'2026-10-24T09:38',title:'还不适合直接处理这类多步骤任务',task:'连续调用工具完成文件整理',text:'第一步结果正确，但后续沿用了过期的路径，失败后也没有调整计划。需要加强工具结果检查与错误恢复。',tags:['工具结果待核对','恢复能力待改进'],category:'工具调用',evidence:'模拟第二次工具调用使用了旧路径，任务未完成且没有有效恢复步骤。'}
];

function accountModelsList(a){
 const s=scenario(a),mixed=state.type==='models';
 const noDiscovery=s==='noDiscovery'||a.id==='ollama';
 const list=[{id:'flash',name:state.modelNames.flash||(a.id==='deepseek'?'DeepSeek-V4.1-Flash':'默认模型'),source:noDiscovery?'manual':'online'}];
 if(a.id==='deepseek')list.push({id:'pro',name:state.modelNames.pro||'DeepSeek-V4-Pro',source:'online'});
 if(mixed&&s==='normal'){
  list.push({id:'bundled',name:state.modelNames.bundled||'内置模型示例',source:'bundled'});
  list.push({id:'manual',name:state.modelNames.manual||'自定义推理模型',source:'manual'});
 }
 state.manualModels.forEach(m=>list.push({id:m.id,name:state.modelNames[m.id]||m.name,source:'manual'}));
 return list.filter(m=>!state.deletedModels.includes(m.id));
}

function currentModel(){
 const a=selectedAccount(),id=state.selectedModel;
 const manual=state.manualModels.find(m=>m.id===id);
 const source=id==='bundled'?'bundled':id.startsWith('manual')||a.id==='ollama'?'manual':'online';
 let name=state.modelNames[id]||manual?.name||({flash:a.id==='deepseek'?'DeepSeek-V4.1-Flash':'默认模型',pro:'DeepSeek-V4-Pro',bundled:'内置模型示例',manual:'自定义推理模型'})[id]||'自定义模型';
 if(state.scenario==='long'&&id==='flash')name='DeepSeek-V4.1-Flash · 研发团队长名称模型配置';
 return {id,name,source,sourceLabel:({online:'在线目录',bundled:'内置目录',manual:'手动添加'})[source],account:a,hasSamples:a.id==='deepseek'&&id==='flash',context:id==='flash'?'1.05M':'128K',enabled:state.modelEnabled[id]!==false};
}

function reviewData(){
 const m=currentModel();
 let data=m.account.id==='deepseek'&&m.id==='flash'?[...addedFlashReviews,...reviewExamples]:m.account.id==='deepseek'&&m.id==='pro'?proReviewExamples:m.source==='manual'?manualReviewExamples:nativeReviewExamples;
 return data.slice(0,10).map(r=>({...r,id:`${m.account.id}-${m.id}-${r.id}`}));
}
function stars(score){
 return `<span class="aw-stars" role="img" aria-label="${score} 星，满分 5 星">${[1,2,3,4,5].map(n=>`<span class="${n<=score?'aw-star-filled':'aw-star-empty'}">${icon('star')}</span>`).join('')}</span>`;
}
function reviewCard(r){
 const expanded=state.reviewExpanded.includes(r.id);
 return `<mdui-card variant="outlined" class="aw-review-card" data-review="${r.id}"><div class="aw-review-card-top"><div class="aw-review-score-row">${stars(r.score)}<span class="aw-review-score-num">${r.score}.0</span>${chip(r.category)}</div><div class="aw-review-evaluator">${chip('评价模型')}<strong>${r.evaluator}</strong><span>(${r.provider})</span><span>·</span><time class="aw-review-time" datetime="${r.time}">${r.date}</time></div></div><h3>${r.title}</h3><div class="aw-review-task-line">${chip('任务')}${r.task}</div><p class="aw-review-body">${r.text}</p><div class="aw-review-card-bottom"><div class="aw-review-tags">${r.tags.map(t=>`<span class="aw-status ${/待|不足|略长|遗漏|需要|不完整/.test(t)?'warning':'success'}">${t}</span>`).join('')}</div>${btn('评价依据','reviewEvidence','text','chevron-down',`class="aw-evidence-btn${expanded?' expanded':''}" data-review-id="${r.id}" aria-expanded="${expanded}" aria-controls="aw-evidence-${r.id}"`)}</div><div class="aw-review-evidence" id="aw-evidence-${r.id}" ${expanded?'':'hidden'}><strong>核验与评价依据</strong>${r.evidence}</div></mdui-card>`;
}
function filteredReviews(){
 let data=reviewData().filter(r=>state.reviewFilter==='all'||(state.reviewFilter==='positive'?r.score>=4:r.score<4));
 return [...data].sort((a,b)=>state.reviewSort==='highest'?b.score-a.score||b.time.localeCompare(a.time):state.reviewSort==='lowest'?a.score-b.score||b.time.localeCompare(a.time):b.time.localeCompare(a.time));
}
function reviewListMarkup(){
 const list=filteredReviews(),visible=list.slice(0,state.reviewVisible);
 return `${visible.map(reviewCard).join('')}${list.length>visible.length?`<div class="aw-reviews-more">${btn(`展开其余 ${list.length-visible.length} 条评价`,'moreReviews','outlined','chevron-down')}</div>`:''}${!list.length?'<mdui-card variant="outlined" class="aw-empty"><h3>当前筛选条件下暂无评价</h3><p>切换到「全部」查看其余任务评价。</p></mdui-card>':''}`;
}
function reviewsPageContent(){
 const m=currentModel(),reviews=reviewData();
 if(!reviews.length)return `<mdui-card variant="outlined" class="aw-empty">${icon('message-square-text')}<h2>还没有使用评价</h2><p>此模型完成任务并收到评价后，评价内容与评价模型会显示在这里。</p></mdui-card>`;
 const average=reviews.reduce((n,r)=>n+r.score,0)/reviews.length;
 const highlights={};
 reviews.forEach(r=>r.tags.forEach(t=>{if(!/待|不足|略长|遗漏|需要|不完整/.test(t))highlights[t]=(highlights[t]||0)+1;}));
 const positive=reviews.filter(r=>r.score>=4).length;
 return `<mdui-card variant="filled" class="aw-review-summary"><div class="aw-review-summary-layout"><div class="aw-review-summary-score"><div class="aw-score-number">${average.toFixed(1)}<span>/ 5</span></div>${stars(Math.round(average))}<small>基于最近 ${reviews.length} 次任务评价</small></div><div class="aw-rating-bars">${[5,4,3,2,1].map(n=>{const count=reviews.filter(r=>r.score===n).length;return `<div class="aw-rating-line"><span>${n} 星</span><mdui-linear-progress value="${count/reviews.length}" aria-label="${n}星评价${count}条"></mdui-linear-progress><span>${count} 条</span></div>`;}).join('')}</div></div><div class="aw-review-summary-foot"><div class="aw-review-highlights">${Object.entries(highlights).sort((a,b)=>b[1]-a[1]).slice(0,4).map(([tag,n])=>chip(`${tag} · ${n}`)).join('')}</div><small>执行模型：<b>${escapeHTML(m.name)}</b> · 任务结束后由评价模型自动生成</small></div></mdui-card><div class="aw-review-controls"><div class="aw-review-filters" role="group" aria-label="按评分筛选">${[['all',`全部 ${reviews.length}`],['positive',`4–5 星 ${positive}`],['improve',`待改进 ${reviews.length-positive}`]].map(([key,label])=>`<mdui-chip selectable ${state.reviewFilter===key?'selected':''} data-action="filterReviews" data-filter="${key}">${label}</mdui-chip>`).join('')}</div><mdui-select id="aw-review-sort" class="aw-review-sort" value="${state.reviewSort}" variant="outlined" aria-label="评价排序"><mdui-menu-item value="recent">最近优先</mdui-menu-item><mdui-menu-item value="highest">评分从高到低</mdui-menu-item><mdui-menu-item value="lowest">评分从低到高</mdui-menu-item></mdui-select></div><div id="aw-review-list" class="aw-review-list" aria-live="polite">${reviewListMarkup()}</div>`;
}
function modelOverviewContent(m){
 const prefs=modelPrefs(m.id);
 const protocol=m.account.id==='deepseek'?'DeepSeek API':'OpenAI-compatible';
 return `<mdui-card variant="outlined" class="aw-model-overview"><mdui-list><mdui-list-item nonclickable headline="输入 / 输出模态" description="${m.id==='flash'?'文本、视觉 → 文本':'文本 → 文本'}">${icon('layers','icon')}<div slot="end-icon" class="aw-capabilities">${chip('流式输出')}${chip('思考推理')}${chip('工具调用')}</div></mdui-list-item><mdui-divider></mdui-divider><mdui-list-item nonclickable headline="上下文与自动压缩阈值" description="最大窗口 ${m.context} tokens · 自动压缩阈值 ${Number(prefs.threshold).toLocaleString()} tokens（${prefs.auto?'自动策略':'手动覆盖'}）">${icon('SlidersHorizontal' in globalThis?'sliders-horizontal':'gauge','icon')}</mdui-list-item><mdui-divider></mdui-divider><mdui-list-item nonclickable headline="传输协议与目录状态" description="${prefs.connection==='http'?'HTTP · 手动覆盖':'HTTP · 自动'} · ${protocol} · ${m.sourceLabel}（10:24 同步）">${icon('network','icon')}</mdui-list-item></mdui-list></mdui-card><section class="aw-section"><div class="aw-section-heading"><h2>实测性能样本</h2><small>${m.hasSamples?'基于最近 10 次任务调用统计':'尚无调用样本'}</small></div>${m.hasSamples?`<mdui-card variant="filled" class="aw-model-overview" style="background:rgb(var(--mdui-color-surface-container-low))"><div class="aw-model-performance"><div><small>首字延迟 · 中位数</small><strong>0.8 <small>s</small></strong></div><div><small>输出吞吐率 · 中位数</small><strong>68 <small>tokens/s</small></strong></div><div><small>样本数量</small><strong>10 <small>次任务</small></strong></div></div></mdui-card>`:'<mdui-card variant="outlined" class="aw-muted-card"><mdui-list><mdui-list-item nonclickable headline="尚无性能样本" description="完成模型调用后，将在此汇总首字延迟与输出吞吐率。">'+icon('activity','icon')+'</mdui-list-item></mdui-list></mdui-card>'}</section>`;
}
function modelPricingContent(m){
 return `${m.hasSamples?`<mdui-card variant="outlined" class="aw-pricing-card">${[['≤ 128K','标准上下文区间','2.00','0.20','3.00'],['128K – 1.05M','长上下文区间','4.00','0.40','6.00']].map(([range,desc,input,cached,output])=>`<div class="aw-price-tier"><div class="aw-price-tier-heading"><span>上下文长度 ${range}</span><small>${desc} · CNY / 100 万 tokens</small></div><div class="aw-price-grid"><div><small>输入 · 未命中缓存</small><strong>¥ ${input}</strong><small>每 100 万 tokens</small></div><div><small>输入 · 命中缓存</small><strong>¥ ${cached}</strong><small>每 100 万 tokens</small></div><div><small>输出</small><strong>¥ ${output}</strong><small>每 100 万 tokens</small></div></div></div>`).join('')}</mdui-card><p class="aw-review-disclaimer">${icon('info')}示例费率仅供排版预览；正式环境展示数据来源与更新时间，实际账单以供应商结算为准。</p>`:'<mdui-card variant="outlined" class="aw-empty">'+icon('receipt-text')+'<h2>尚无可用价格数据</h2><p>供应商未提供报价，费用不会被显示为 0；实际费用以供应商结算为准。</p></mdui-card>'}`;
}
function modelPageMarkup(){
 const m=currentModel(),reviews=reviewData(),siblings=accountModelsList(m.account);
 return `<div class="aw-topbar"><mdui-button variant="text" data-action="backModel" class="aw-back">${icon('arrow-left','icon')}返回 ${escapeHTML(m.account.name)}</mdui-button><div class="aw-row">${siblings.length>1?`<mdui-segmented-button-group selects="single" value="${m.id}" aria-label="切换当前账号模型">${siblings.map(item=>`<mdui-segmented-button value="${item.id}" data-action="switchModel" data-model="${item.id}">${escapeHTML(item.name)}</mdui-segmented-button>`).join('')}</mdui-segmented-button-group>`:''}${iconBtn('设置导航','mobileNav','menu','class="aw-menu-mobile"')}</div></div><div class="aw-page-header aw-model-page-head"><div class="aw-detail-identity">${logo(m.account,true)}<div><h1>${escapeHTML(m.name)}</h1><div class="aw-model-page-meta"><span>${escapeHTML(m.account.name)}</span><span>·</span><span>${m.sourceLabel}</span><span>·</span><span>${m.context} 上下文</span></div></div></div><label class="aw-page-model-toggle">启用模型<mdui-switch data-model-switch="${m.id}" ${m.enabled?'checked':''} aria-label="启用 ${escapeHTML(m.name)}"></mdui-switch></label></div><mdui-tabs class="aw-model-tabs" id="aw-model-tabs" value="${state.modelTab}" placement="top-start" variant="secondary"><mdui-tab value="overview">规格与性能</mdui-tab><mdui-tab value="pricing">阶梯价格</mdui-tab><mdui-tab value="reviews">使用评价${reviews.length?` · ${reviews.length}`:''}</mdui-tab><mdui-tab-panel slot="panel" value="overview">${modelOverviewContent(m)}</mdui-tab-panel><mdui-tab-panel slot="panel" value="pricing">${modelPricingContent(m)}</mdui-tab-panel><mdui-tab-panel slot="panel" value="reviews">${reviewsPageContent()}</mdui-tab-panel></mdui-tabs>`;
}

function updateReviewList(){
 $('#aw-review-list').innerHTML=reviewListMarkup();
 $$('[data-action=filterReviews]').forEach(chipEl=>{
  chipEl.selected=chipEl.dataset.filter===state.reviewFilter;
 });
 hydrateIcons();save();
}
function wireModelPage(){
 const billing=$('#aw-billing-inline');
 billing?.addEventListener('change',e=>{
  if(e.target!==billing)return;
  const id=billing.dataset.account,value=billing.value;
  if(!['auto','metered','subscription','noCharge','unknown'].includes(value))return;
  const a=currentAccounts().find(account=>account.id===id);
  if(!a||billingSelection(a)===value)return;
  state.billingSelections[id]=value;
  const saved=$('#aw-billing-save-status');
  saved.innerHTML=icon('check')+'已保存 · '+(value==='auto'?'自动识别':'手动覆盖');
  hydrateIcons();save();
 });
 const tabs=$('#aw-model-tabs');
 tabs?.addEventListener('change',e=>{if(e.target===tabs&&['overview','pricing','reviews'].includes(tabs.value)&&tabs.value!==state.modelTab){state.modelTab=tabs.value;save();}});
 const sort=$('#aw-review-sort');
 sort?.addEventListener('change',e=>{if(e.target===sort&&['recent','highest','lowest'].includes(sort.value)&&sort.value!==state.reviewSort){state.reviewSort=sort.value;updateReviewList();}});
}
function openModel(id='flash'){
 state.detailScroll=window.scrollY;
 state.detailExpanded=$$('.aw-model-card mdui-collapse-item').filter(item=>item.active).map(item=>item.value);
 state.selectedModel=id;
 state.modelTab='reviews';
 state.reviewFilter='all';
 state.reviewSort='recent';
 state.reviewVisible=4;
 state.reviewExpanded=[];
 state.page='model';
 render();save();
 requestAnimationFrame(()=>$('#aw-main').scrollIntoView({block:'start'}));
}
function modelPrefs(id){return state.modelPrefs[id]||(state.modelPrefs[id]={threshold:id==='flash'?'475000':'64000',auto:false,connection:'auto'});}
function modelItem(id,name,source='online',expanded=false){
 if(state.deletedModels.includes(id))return '';
 name=state.modelNames[id]||name;
 const prefs=modelPrefs(id);
 const s=state.scenario,enabled=state.modelEnabled[id]!==false;
 const long=s==='long';
 const displayTitle=long&&id==='flash'?'DeepSeek-V4.1-Flash · 研发团队长名称模型配置':name;
 const specSummary=id==='flash'?'1.05M 上下文 · 文本与视觉 · 流式 / 思考 / 工具调用':source==='manual'?'128K 上下文 · 用户自定义模型 · 工具调用':'128K 上下文 · 文本生成 · 流式 / 思考 / 工具调用';
 return `<mdui-collapse-item value="${id}" ${expanded?'data-expanded':''}><mdui-list-item slot="header" class="aw-model-header" headline="${escapeHTML(displayTitle)}" description="${specSummary}">${icon('chevron-right','icon')}<div slot="end-icon" class="aw-model-end-actions">${btn('详情与评价','modelInfo','text','arrow-up-right',`data-model="${id}"`)}${`<mdui-switch ${enabled?'checked':''} data-model-switch="${id}" aria-label="启用 ${escapeHTML(name)}"></mdui-switch>`}</div></mdui-list-item><div class="aw-model-body"><div class="aw-threshold-row"><mdui-text-field variant="outlined" label="上下文自动压缩阈值" helper="上限为上下文窗口的 90%（${id==='flash'?'945,000':'115,200'} tokens），预留输出预算" value="${s==='thresholdError'?'0':escapeHTML(prefs.threshold)}" data-threshold="${id}" type="number" min="1" step="1"><span slot="suffix">tokens</span></mdui-text-field><div class="aw-row" style="padding-top:8px">${btn('恢复自动','thresholdAuto','tonal','rotate-ccw',`data-model="${id}"`)}<small data-threshold-status="${id}">${s==='thresholdFailed'?'保存失败':prefs.auto?'自动策略':'手动覆盖'}</small></div></div><div class="aw-threshold-error" data-threshold-error="${id}" ${s!=='thresholdError'?'hidden':''}>请输入正整数，且不超过当前模型可用上下文上限。</div>${s==='thresholdFailed'?`<div class="aw-query-note error">草稿已保留${btn('重试保存','retryThreshold','text')}</div>`:''}<div class="aw-model-config-bar"><div class="aw-row"><span class="aw-muted">连接方式：</span><strong>${prefs.connection==='http'?'HTTP · 手动覆盖':'HTTP · 自动'}</strong>${btn('更改','connection','text','',`data-model="${id}"`)}</div><div class="aw-row">${source==='manual'?`${btn('编辑','editModel','text','pencil',`data-model="${id}"`)}${btn('删除','deleteModel','text','trash-2',`data-model="${id}"`)}`:''}${btn('模型详情、价格与评价','modelInfo','tonal','arrow-up-right',`data-model="${id}"`)}</div></div></div></mdui-collapse-item>`;
}
function modelsMarkup(a){
 const s=scenario(a),mixed=state.type==='models',empty=s==='modelEmpty';
 const noDiscovery=s==='noDiscovery'||a.id==='ollama';
 const manualItems=[...(mixed&&s==='normal'?[{id:'manual',name:'自定义推理模型'}]:[]),...state.manualModels].filter(m=>!state.deletedModels.includes(m.id));
 const bundledItems=(mixed&&s==='normal'?[{id:'bundled',name:'内置模型示例'}]:[]).filter(m=>!state.deletedModels.includes(m.id));
 return `<section class="aw-section"><div class="aw-section-heading"><div><h2>模型目录</h2><p class="aw-section-caption">${noDiscovery?'此账号不支持在线发现，可手动添加所需模型':s==='syncing'?'正在同步在线模型目录…':'最近同步 10:24 · 同步不会覆盖已有开关与阈值设置'}</p></div><div class="aw-row">${btn('添加模型','addModel','text','plus')}${noDiscovery?'':btn('同步目录','syncModels','tonal','refresh-cw',s==='syncing'?'loading disabled':'')}</div></div>${s==='syncFailed'?notice('模型同步失败，已保留最近有效目录与全部自定义配置。','error',btn('重试','syncModels','text')):''}${s==='syncing'?'<mdui-linear-progress aria-label="同步模型目录" style="margin:0 0 12px"></mdui-linear-progress>':''}${empty?`<mdui-card variant="outlined" class="aw-empty"><h3>暂时没有可用模型</h3><p>同步供应商目录，或手动添加你自己的模型。</p>${btn('添加模型','addModel','tonal','plus')}</mdui-card>`:`<div class="aw-group-bar"><mdui-list-subheader>${noDiscovery?'手动模型':'在线目录'}</mdui-list-subheader><small>${a.id==='deepseek'?'2':'1'} 个模型</small></div><mdui-card variant="outlined" class="aw-model-card"><mdui-collapse value="flash">${modelItem('flash',a.id==='deepseek'?'DeepSeek-V4.1-Flash':'默认模型',noDiscovery?'manual':'online',true)}${a.id==='deepseek'?'<mdui-divider></mdui-divider>'+modelItem('pro','DeepSeek-V4-Pro','online'):''}</mdui-collapse></mdui-card>`}${bundledItems.length?`<div class="aw-group-bar"><mdui-list-subheader>内置默认目录</mdui-list-subheader><small>${bundledItems.length} 个模型</small></div><mdui-card variant="outlined" class="aw-model-card"><mdui-collapse>${bundledItems.map(m=>modelItem(m.id,m.name,'bundled')).join('<mdui-divider></mdui-divider>')}</mdui-collapse></mdui-card>`:''}${manualItems.length?`<div class="aw-group-bar"><mdui-list-subheader>手动添加</mdui-list-subheader><small>${manualItems.length} 个模型</small></div><mdui-card variant="outlined" class="aw-model-card"><mdui-collapse>${manualItems.map(m=>modelItem(m.id,m.name,'manual')).join('<mdui-divider></mdui-divider>')}</mdui-collapse></mdui-card>`:''}</section>`;
}
function acpDetail(a){
 const s=scenario(a),stage=acpStage(s),install=state.type==='acpInstall';
 return `<mdui-card variant="filled" class="aw-balance-card"><div class="aw-card-header"><h2>${install?'受管安装进度':'连接与认证状态'}</h2><small>${install?'官方固定版本 v1.4.1':'受管接入'}</small></div><div class="aw-acp-stage"><mdui-avatar style="width:46px;height:46px">${icon(stage.ico)}</mdui-avatar><div><h2>${stage.summary}</h2><p>${stage.description}</p></div></div>${stage.busy?`<div class="aw-acp-progress"><mdui-linear-progress ${s==='download'?'value="0.46"':''} aria-label="${stage.summary}"></mdui-linear-progress>${s==='download'?'<small>当前下载进度 · 示例数值</small>':''}</div>`:''}<div class="aw-acp-actions">${stage.action?btn(stage.action,stage.actionId,stage.busy?'outlined':'filled',stage.actionId.includes('cancel')?'x':''):''}${s==='authenticating'?btn('我已完成登录','verifyAcp','tonal'):''}${['checking','verifying','closing','cancelling','close','installCancelling'].includes(s)?'<small>操作完成后将自动更新状态</small>':''}</div>${install?`<div class="aw-install-steps">${[['resolve','解析'],['download','下载'],['verify','校验'],['extract','解压'],['publish','准备'],['ready','就绪']].map(([k,label])=>`<mdui-chip class="aw-chip-sm" ${k===s?'elevated':''}>${icon(k===s?'circle-dot':'circle','icon')}${label}</mdui-chip>`).join('')}</div>`:''}</mdui-card><section class="aw-section"><div class="aw-section-heading"><h2>接入设置</h2></div><mdui-card variant="outlined" class="aw-setting-card"><mdui-list><mdui-list-item nonclickable headline="安装状态" description="ACP · 官方受管程序（版本 1.4.1）">${icon('package-check','icon')}${!install?btn('查看安装','showInstall','tonal','','slot="end-icon"'):`<span slot="end-icon" class="aw-muted">${stage.title}</span>`}</mdui-list-item><mdui-divider></mdui-divider><mdui-list-item nonclickable headline="认证方式" description="${s==='terminal'?'终端登录':s==='noMethods'?'服务端未提供':s==='unsupportedMethod'?'当前方式不受支持':'服务提供的登录流程'}">${icon('shield-check','icon')}</mdui-list-item><mdui-divider></mdui-divider><mdui-collapse><mdui-collapse-item value="acp-adv"><mdui-list-item slot="header" headline="高级信息" description="antigravity-demo · ${['verified','normal'].includes(s)?'Antigravity · 示例身份':'身份尚未获取'}">${icon('sliders-horizontal','icon')}${icon('chevron-right','end-icon')}</mdui-list-item><div class="aw-advanced-content"><span>账号 ID</span><code>antigravity-demo</code><span>服务身份</span><span>${['verified','normal'].includes(s)?'Antigravity · 示例身份':'尚未获取'}</span><span>安装来源</span><span>官方受管发行</span></div></mdui-collapse-item></mdui-collapse></mdui-list></mdui-card></section>`;
}
function detailMarkup(){
 const a=selectedAccount();
 return `<div class="aw-topbar"><mdui-button variant="text" data-action="back" class="aw-back">${icon('arrow-left','icon')}返回账号列表</mdui-button>${iconBtn('设置导航','mobileNav','menu','class="aw-menu-mobile"')}</div><div class="aw-page-header"><div class="aw-detail-identity">${logo(a,true)}<div><div class="aw-detail-title-row"><h1>${escapeHTML(a.name)}</h1>${accountStatus(a)}${state.defaultId===a.id?chip('默认账号'):''}</div><div class="aw-endpoint"><code>${escapeHTML(a.endpoint)}</code></div></div></div><div class="aw-row">${a.kind!=='acp'&&state.defaultId!==a.id?btn('设为默认','setDefault','text','star',`data-id="${a.id}"`):''}${btn('编辑账号','edit','outlined','pencil')}</div></div>${a.kind==='acp'?acpDetail(a):balanceDetail(a)+settingsMarkup(a)+modelsMarkup(a)}`;
}

function renderSelectors(){
 const type=$('#aw-type');
 if(type.children.length===0){
  type.innerHTML=Object.entries(groups).map(([k,g])=>`<mdui-menu-item value="${k}">${g.label}</mdui-menu-item>`).join('');
  Promise.all(Array.from(type.children,item=>item.updateComplete)).then(()=>type.requestUpdate());
 }
 if(type.value!==state.type)type.value=state.type;
 const scenarioSelect=$('#aw-scenario');
 if(scenarioSelect.dataset.group!==state.type){
  scenarioSelect.innerHTML=groups[state.type].states.map(([k,l])=>`<mdui-menu-item value="${state.type}:${k}">${l}</mdui-menu-item>`).join('');
  scenarioSelect.dataset.group=state.type;
 }
 const qualifiedValue=state.type+':'+state.scenario;
 if(scenarioSelect.value!==qualifiedValue)scenarioSelect.value=qualifiedValue;
 const stepIdx=allSteps.findIndex(x=>x.type===state.type&&x.scenario===state.scenario);
 $('#aw-scenario-index').textContent=`${stepIdx>=0?stepIdx+1:1} / ${totalScenarios}`;
 const viewGroup=$('#aw-view-group');
 if(viewGroup&&viewGroup.value!==state.page)viewGroup.value=state.page;
 $('#aw-view-model').disabled=selectedAccount().kind==='acp'||(state.type==='boundaries'&&state.scenario!=='long');
 $('#aw-view-detail').disabled=state.type==='boundaries'&&state.scenario!=='long';
 $('#aw-coverage').textContent=`共 ${totalScenarios} 个预览场景 · 金额、价格、性能与评价均为设计样例，不连接真实账户`;
}
function render(){
 if(state.type==='boundaries'&&state.scenario!=='long')state.page='list';
 if(state.page==='model'&&selectedAccount().kind==='acp')state.page='detail';
 renderSelectors();
 $('#aw-main').innerHTML=state.page==='list'?listMarkup():state.page==='model'?modelPageMarkup():detailMarkup();
 hydrateIcons();
 wireLocal();
}
function navigate(page,id){
 if(page==='detail'){state.listScroll=window.scrollY;state.selected=id||targetId();}
 state.page=page;render();save();
 if(page==='list')requestAnimationFrame(()=>window.scrollTo({top:state.listScroll,behavior:'instant'}));
}
function setScenario(s,type=state.type){
 state.type=type;state.scenario=s;state.selected=targetId();
 if(state.page==='model')state.page='detail';
 render();save();
}
function stepScenario(delta){
 const idx=allSteps.findIndex(x=>x.type===state.type&&x.scenario===state.scenario);
 const next=allSteps[(idx+delta+allSteps.length)%allSteps.length];
 if(next){state.search='';setScenario(next.scenario,next.type);}
}

let dialogDirty=false,dialogSave=null,dialogIntent='';
function openDialog(title,html,onSave,saveLabel='保存'){
 const dialog=$('#aw-dialog');
 dialog.headline=title;
 $('#aw-dialog-content').innerHTML=html;
 $('#aw-dialog-save').textContent=saveLabel;
 $('#aw-dialog-save').hidden=!onSave;
 $('#aw-dialog-cancel').textContent=onSave?'取消':'关闭';
 dialogSave=onSave;dialogDirty=false;dialog.open=true;
 hydrateIcons();
}
function closeDialog(){
 if(dialogDirty){$('#aw-leave-dialog').open=true;return;}
 $('#aw-dialog').open=false;
}
function editAccount(a,adding=false){
 dialogIntent='edit';
 openDialog(adding?'添加账号':'编辑账号',`<p class="aw-dialog-copy">${adding?'选择账号类型，所有操作仅更新当前设计预览。':'留空密钥可保留已配置的凭据。'}</p><div class="aw-dialog-form">${adding?'<mdui-select id="aw-edit-kind" label="账号类型" value="native" variant="outlined"><mdui-menu-item value="native">模型服务 · Native</mdui-menu-item><mdui-menu-item value="acp">应用接入 · ACP</mdui-menu-item></mdui-select>':''}<mdui-text-field id="aw-edit-name" label="账号名称" value="${adding?'':escapeHTML(a.name)}" variant="outlined" required></mdui-text-field>${a.kind!=='acp'?`<div id="aw-native-fields" class="aw-dialog-form"><mdui-text-field id="aw-edit-endpoint" label="Endpoint" value="${escapeHTML(a.endpoint)}" variant="outlined"></mdui-text-field><mdui-text-field id="aw-edit-secret" label="API 密钥" type="password" placeholder="不填写则保留已有凭据" variant="outlined" autocomplete="off"></mdui-text-field></div><p id="aw-acp-add-note" class="aw-dialog-copy" hidden>保存接入后，可以继续准备受管程序并完成登录。</p>`:''}</div>`,()=>{
  const field=$('#aw-edit-name'),name=field.value.trim();
  if(!name){field.setCustomValidity('请输入账号名称');field.reportValidity();return false;}
  if(adding){
   const kind=$('#aw-edit-kind').value==='acp'?'acp':'metered';
   const id='added'+Date.now();
   defaultAccounts.push({id,name,brand:'custom',kind,billing:'unknown',endpoint:kind==='acp'?'受管应用 · ACP 接入':$('#aw-edit-endpoint')?.value||'https://api.example.com/v1'});
  }else state.editedNames[a.id]=name;
  if(state.scenario==='missing')state.scenario='normal';
  toast('账号已在预览中保存');
  return true;
 },adding?'添加账号':'保存');
}
function refresh(a,all=false){
 if(a.kind==='acp'){runAcp('checking','verified');return;}
 if(['metered','unknown','free'].includes(a.kind)){toast('此账号不支持用量查询');return;}
 const type=a.kind==='subscription'?'subscription':'balance';
 state.type=type;state.scenario='refreshing';state.selected=a.id;
 render();
 setTimeout(()=>{state.scenario='normal';render();save();toast(all?'可查询账号的用量已刷新':'用量已刷新');},700);
}
function runAcp(start,end,install=false){
 state.type=install?'acpInstall':'acpAuth';state.scenario=start;state.selected='acp';
 render();
 setTimeout(()=>{if(state.scenario===start){state.scenario=end;render();save();}},900);
}
function wireLocal(){
 wireModelPage();
 $$('mdui-collapse-item').forEach(item=>{
  item.addEventListener('open',e=>{if(e.target===item)item.toggleAttribute('data-expanded',true);});
  item.addEventListener('close',e=>{if(e.target===item)item.toggleAttribute('data-expanded',false);});
  item.updateComplete.then(()=>requestAnimationFrame(()=>{if(item.isConnected)item.toggleAttribute('data-expanded',item.active);}));
 });
 const search=$('#aw-search');
 search?.addEventListener('input',()=>{
  state.search=search.value;
  if(state.type==='boundaries'&&state.scenario==='noResults'){state.type='overview';state.scenario='normal';}
  const template=document.createElement('template');
  template.innerHTML=listMarkup();
  const nextCard=template.content.querySelector('.aw-account-card');
  const nextMeta=template.content.querySelector('.aw-tools-meta');
  $('.aw-account-card').replaceWith(nextCard);
  $('.aw-tools-meta').textContent=nextMeta.textContent;
  renderSelectors();hydrateIcons();save();
 });
 $$('[data-model-switch]').forEach(sw=>{
  sw.addEventListener('click',e=>e.stopPropagation());
  sw.addEventListener('change',()=>{state.modelEnabled[sw.dataset.modelSwitch]=sw.checked;toast(sw.checked?'模型已启用':'模型已停用');});
 });
 $$('.aw-model-end-actions [data-action="modelInfo"]').forEach(b=>{
  b.addEventListener('click',e=>{e.stopPropagation();openModel(b.dataset.model);});
 });
 $$('[data-threshold]').forEach(field=>{
  let timer;
  field.addEventListener('input',()=>{
   clearTimeout(timer);
   const id=field.dataset.threshold;
   const n=Number(field.value),valid=/^[1-9]\d*$/.test(field.value)&&n<=(id==='flash'?945000:115200);
   const error=$(`[data-threshold-error="${id}"]`);
   error.hidden=valid;
   const label=$(`[data-threshold-status="${id}"]`);
   label.textContent=valid?'正在保存…':'未保存';
   if(valid){
    const value=field.value;
    timer=setTimeout(()=>{modelPrefs(id).threshold=value;modelPrefs(id).auto=false;label.textContent='已保存 · 手动覆盖';},450);
   }
  });
 });
}

const navGroups=[
 ['模型与智能体',[['账号','cloud'],['智能体','users'],['指令','align-left'],['工作模式','workflow']]],
 ['工具与服务',[['技能','puzzle'],['MCP','network'],['LSP','code'],['SSH','server']]],
 ['偏好设置',[['统计','chart-no-axes-combined'],['安全','shield'],['通用','sliders-horizontal'],['机器人','bot']]]
];
$('#aw-nav').innerHTML=navGroups.map(([label,items])=>`<mdui-list><mdui-list-subheader>${label}</mdui-list-subheader>${items.map(([name,ico])=>`<mdui-list-item rounded ${name==='账号'?'active':''} data-nav="${name}">${icon(ico,'icon')}${name}</mdui-list-item>`).join('')}</mdui-list>`).join('');

$('#aw-type').addEventListener('change',()=>{
 const value=$('#aw-type').value;
 if(!groups[value]||value===state.type)return;
 state.type=value;state.scenario=groups[state.type].states[0][0];state.search='';state.selected=targetId();
 if(state.page==='model')state.page='detail';
 render();save();
});
$('#aw-scenario').addEventListener('change',()=>{
 const [type,value]=String($('#aw-scenario').value).split(':');
 if(type!==state.type||value===state.scenario||!groups[state.type].states.some(([k])=>k===value))return;
 setScenario(value);
});
$('#aw-prev-scenario').addEventListener('click',()=>stepScenario(-1));
$('#aw-next-scenario').addEventListener('click',()=>stepScenario(1));
$('#aw-view-list').addEventListener('click',()=>navigate('list'));
$('#aw-view-detail').addEventListener('click',()=>navigate('detail',state.type==='overview'?state.selected:targetId()));
$('#aw-view-model').addEventListener('click',()=>{if(state.page!=='model')openModel('flash');});
$('#aw-back-chat').addEventListener('click',()=>toast('当前设计稿聚焦账号列表与详情'));
$('#aw-dialog-content').addEventListener('input',()=>{dialogDirty=true;});
$('#aw-dialog-content').addEventListener('change',e=>{
 dialogDirty=true;
 if(e.target.id==='aw-edit-kind'){
  const acp=e.target.value==='acp';
  $('#aw-native-fields').hidden=acp;
  $('#aw-acp-add-note').hidden=!acp;
 }
});
$('#aw-dialog-cancel').addEventListener('click',closeDialog);
$('#aw-dialog').addEventListener('close',e=>{if(e.target===$('#aw-dialog')&&dialogDirty){e.preventDefault();$('#aw-leave-dialog').open=true;}});
$('#aw-dialog-save').addEventListener('click',()=>{if(!dialogSave||dialogSave()!==false){dialogDirty=false;$('#aw-dialog').open=false;render();}});
$('#aw-keep-editing').addEventListener('click',()=>{$('#aw-leave-dialog').open=false;});
$('#aw-discard').addEventListener('click',()=>{dialogDirty=false;$('#aw-leave-dialog').open=false;$('#aw-dialog').open=false;});

root.addEventListener('click',e=>{
 const row=e.target.closest('[data-open-account]');
 if(row){navigate('detail',row.dataset.openAccount);return;}
 const nav=e.target.closest('[data-nav]');
 if(nav){if(nav.dataset.nav==='账号')navigate('list');else toast('当前设计稿聚焦账号列表与详情');return;}
 const el=e.target.closest('[data-action]');
 if(!el)return;
 const action=el.dataset.action;
 const a=el.dataset.id?currentAccounts().find(a=>a.id===el.dataset.id)||selectedAccount():selectedAccount();
 const dropdown=el.closest('mdui-dropdown');
 if(dropdown)dropdown.open=false;
 if(action==='back'){navigate('list');return;}
 if(action==='mobileNav'){$('#aw-shell').classList.toggle('aw-nav-open');return;}
 if(action==='modelInfo'){openModel(el.dataset.model);return;}
 if(action==='switchModel'){
  if(el.dataset.model&&el.dataset.model!==state.selectedModel){
   state.selectedModel=el.dataset.model;
   state.reviewVisible=4;
   state.reviewExpanded=[];
   render();save();
  }
  return;
 }
 if(action==='backModel'){
  state.page='detail';render();
  const collapse=$('.aw-model-card mdui-collapse');
  if(collapse)collapse.value=state.detailExpanded;
  save();
  requestAnimationFrame(()=>window.scrollTo({top:state.detailScroll,behavior:'instant'}));
  return;
 }
 if(action==='filterReviews'){state.reviewFilter=el.dataset.filter;state.reviewVisible=4;updateReviewList();return;}
 if(action==='moreReviews'){state.reviewVisible=10;updateReviewList();return;}
 if(action==='reviewEvidence'){
  const id=el.dataset.reviewId,expanded=!state.reviewExpanded.includes(id);
  state.reviewExpanded=expanded?[...state.reviewExpanded,id]:state.reviewExpanded.filter(x=>x!==id);
  $('#aw-evidence-'+id).hidden=!expanded;
  el.classList.toggle('expanded',expanded);
  el.setAttribute('aria-expanded',String(expanded));
  return;
 }
 if(action==='clearSearch'){state.search='';state.type='overview';state.scenario='normal';render();save();return;}
 if(action==='add'){editAccount(defaultAccounts[0],true);return;}
 if(action==='edit'){editAccount(a);return;}
 if(action==='delete'){openDialog('删除这个账号？',`<p class="aw-dialog-copy">将从预览中移除「${escapeHTML(a.name)}」。历史调用和账单不会在这个设计操作中删除。</p>`,()=>{state.deleted.push(a.id);state.page='list';toast('已从预览移除账号');return true;},'删除账号');return;}
 if(action==='setDefault'){state.defaultId=a.id;render();toast('已设为默认账号');return;}
 if(['refresh','rowRefresh','refreshAll'].includes(action)){refresh(action==='refreshAll'?defaultAccounts[0]:a,action==='refreshAll');return;}
 if(action==='syncModels'){
  state.type='models';state.scenario='syncing';render();
  setTimeout(()=>{if(state.scenario==='syncing'){state.scenario='normal';render();toast('模型目录已同步，保留已有配置');}},700);
  return;
 }
 if(action==='thresholdAuto'){
  const id=el.dataset.model;
  modelPrefs(id).threshold=id==='flash'?'900000':'100000';
  modelPrefs(id).auto=true;
  render();toast('已恢复自动压缩策略');
  return;
 }
 if(action==='retryThreshold'){state.scenario='normal';render();toast('压缩阈值已保存');return;}
 if(action==='connection'){
  openDialog('模型连接方式',`<div class="aw-dialog-form"><mdui-select id="aw-connection" label="连接方式" value="${modelPrefs(el.dataset.model).connection}" variant="outlined"><mdui-menu-item value="auto">自动 · HTTP</mdui-menu-item><mdui-menu-item value="http">HTTP</mdui-menu-item><mdui-menu-item value="ws" disabled>WebSocket · 当前协议不支持</mdui-menu-item></mdui-select></div>`,()=>{modelPrefs(el.dataset.model).connection=$('#aw-connection').value;toast('模型连接方式已保存');return true;});
  return;
 }
 if(action==='addModel'||action==='editModel'){
  openDialog(action==='addModel'?'添加手动模型':'编辑手动模型',`<div class="aw-dialog-form"><mdui-text-field id="aw-model-name" variant="outlined" label="模型名称" value="${action==='addModel'?'':'自定义推理模型'}" required></mdui-text-field><mdui-text-field variant="outlined" label="模型 ID" value="${action==='addModel'?'':'custom-model'}"></mdui-text-field></div>`,()=>{
   const name=$('#aw-model-name').value.trim();
   if(!name){$('#aw-model-name').reportValidity();return false;}
   if(action==='addModel')state.manualModels.push({id:'manual'+Date.now(),name});
   else{
    const m=state.manualModels.find(m=>m.id===el.dataset.model);
    if(m)m.name=name;
    state.modelNames[el.dataset.model]=name;
   }
   toast('手动模型已保存');return true;
  },action==='addModel'?'添加模型':'保存');
  return;
 }
 if(action==='deleteModel'){
  openDialog('删除手动模型？','<p class="aw-dialog-copy">同时移除该模型的配置覆盖，保留历史调用和账单。</p>',()=>{state.manualModels=state.manualModels.filter(m=>m.id!==el.dataset.model);state.deletedModels.push(el.dataset.model);toast('手动模型已从预览移除');return true;},'删除');
  return;
 }
 if(action==='showInstall'){setScenario('ready','acpInstall');return;}
 if(action==='installAcp'){runAcp('download','ready',true);return;}
 if(action==='connectAcp'||action==='checkAcp'||action==='rowCheck'){runAcp('checking',state.scenario==='required'?'required':'verified');return;}
 if(action==='loginAcp'){setScenario('authenticating','acpAuth');return;}
 if(action==='verifyAcp'){runAcp('verifying','verified');return;}
 if(action==='cancelAcp'){runAcp('cancelling','cancelled');return;}
 if(action==='cancelInstall'){runAcp('installCancelling','installCancelled',true);return;}
});

window.addEventListener('openai:set_globals',e=>{
 if(e.detail?.globals?.widgetState){
  const before=JSON.stringify([state.type,state.scenario,state.page,state.selected,state.search,state.selectedModel,state.modelTab,state.billingSelections]);
  savedRestore(e.detail.globals.widgetState);
  if(before!==JSON.stringify([state.type,state.scenario,state.page,state.selected,state.search,state.selectedModel,state.modelTab,state.billingSelections]))render();
 }
});
Promise.all(['mdui-card','mdui-button','mdui-button-icon','mdui-segmented-button-group','mdui-segmented-button','mdui-chip','mdui-select','mdui-switch','mdui-text-field','mdui-list','mdui-list-item','mdui-list-subheader','mdui-collapse','mdui-collapse-item','mdui-tabs','mdui-tab','mdui-tab-panel','mdui-tooltip','mdui-avatar'].map(t=>customElements.whenDefined(t))).then(()=>{render();});
})();
