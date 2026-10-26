// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get promptAccepted => '已受理';

  @override
  String get composerSendAndContinue => '发送并继续';

  @override
  String get appTitle => '糊来帮';

  @override
  String get trayShowWindow => '显示主窗口';

  @override
  String get trayExit => '退出';

  @override
  String get sidebarProjects => '项目';

  @override
  String get sidebarSessions => '会话';

  @override
  String get sidebarLoadingMore => '正在加载更多会话…';

  @override
  String get sidebarLoadError => '会话目录分页加载失败';

  @override
  String get shutdownTitle => '正在安全退出';

  @override
  String shutdownUpdateTitle(String version) {
    return '正在安装 $version 更新';
  }

  @override
  String get shutdownUpdateSaving => '正在停止会话并保存数据…';

  @override
  String get shutdownUpdateRestartHint => '保存完成后将显示安装进度，并自动重新打开应用。';

  @override
  String get shutdownUpdateExitHint => '保存完成后将显示安装进度，安装后保持关闭。';

  @override
  String get shutdownFinalizing => '正在结束';

  @override
  String get shutdownFinalizingHint => '必要诊断已记录，将自动退出。';

  @override
  String get shutdownPhaseStoppingSubscriptions => '正在停止订阅';

  @override
  String get shutdownPhaseCancellingTurns => '正在停止会话任务';

  @override
  String get shutdownPhaseFlushingPersistence => '正在保存会话';

  @override
  String get shutdownPhaseStoppingAgents => '正在停止协作智能体';

  @override
  String get shutdownPhaseStoppingMcp => '正在关闭 MCP';

  @override
  String get shutdownPhaseStoppingLsp => '正在关闭语言服务';

  @override
  String get shutdownPhaseStopped => '退出流程已完成';

  @override
  String shutdownPendingCommits(int count) {
    return '仍有 $count 项更改未保存';
  }

  @override
  String get sidebarCloseProject => '关闭项目';

  @override
  String get sidebarArchiveSession => '归档会话';

  @override
  String get sidebarArchiveSessionFailed => '无法归档该会话。';

  @override
  String get sidebarArchiveSessionBusy => '无法归档该会话，它可能仍在运行。';

  @override
  String sidebarArchiveSessionFailedReason(
    String reason,
    String correlationId,
  ) {
    return '无法归档该会话：$reason（诊断编号：$correlationId）';
  }

  @override
  String get sidebarArchiveSessionConfirmTitle => '归档会话';

  @override
  String get sidebarArchiveSessionConfirmBody =>
      '归档会停止该会话及其子会话的活动工作，并将它们移入已归档列表。会话历史、工作区、分支和未提交内容都会保留。是否继续？';

  @override
  String get sidebarArchiveSessionConfirmAction => '归档';

  @override
  String get sidebarRenameSession => '重命名会话';

  @override
  String get sidebarRenameSessionTitle => '重命名会话';

  @override
  String get sidebarRenameSessionInput => '会话标题';

  @override
  String get sidebarRenameSessionEmpty => '请输入会话标题。';

  @override
  String get sidebarRenameSessionTooLong => '会话标题最多 80 个字符。';

  @override
  String get sidebarRenameSessionFailed => '无法重命名该会话。';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '保存';

  @override
  String get sidebarNewSession => '新建会话';

  @override
  String get sidebarSessionWorktree => '会话工作树';

  @override
  String get sidebarOpenProject => '打开项目';

  @override
  String get sidebarSettings => '设置';

  @override
  String get runtimeFatalTitle => '糊来帮无法启动';

  @override
  String get runtimeFatalRetry => '重试';

  @override
  String persistenceDegraded(int count) {
    return '保存暂时不可用，尚有 $count 项更改未保存；可以继续会话。';
  }

  @override
  String persistenceRecovering(int count) {
    return '保存已恢复，正在补存此前未保存的 $count 项更改；可以继续会话。';
  }

  @override
  String persistenceBlocked(int count) {
    return '保存已阻塞，仍有 $count 项更改未保存，需要处理。';
  }

  @override
  String get persistenceExecutionPaused => '保存失败，执行已暂停。';

  @override
  String get persistenceSavingBackpressure => '存储压力较高，正在等待保存。';

  @override
  String get persistenceNewWorkPaused => '保存失败，新工作已暂停，进行中的工作正在收束。';

  @override
  String persistenceResumeReadyOtherSession(String session) {
    return '另一个会话「$session」已保存，等待继续执行。';
  }

  @override
  String persistenceExecutionPausedOtherSession(String session) {
    return '另一个会话「$session」保存失败，执行已暂停。';
  }

  @override
  String persistenceNewWorkPausedOtherSession(String session) {
    return '另一个会话「$session」保存失败，新工作已暂停，进行中的工作正在收束。';
  }

  @override
  String get persistenceRetry => '重试保存';

  @override
  String get threadUnopenedTitle => '会话尚未打开';

  @override
  String get threadUnopenedBody => '当前仅选中该会话。打开后会读取当前状态与历史；在你发送消息之前不会恢复任何执行。';

  @override
  String get threadOpenAction => '打开会话';

  @override
  String get timelineItemBodyLoad => '加载完整内容';

  @override
  String get timelineItemBodyLoading => '正在加载完整内容…';

  @override
  String get timelineItemBodyPending => '完整内容尚未写入历史，请稍后重试。';

  @override
  String get timelineItemBodyRetry => '重试';

  @override
  String get timelineItemBodyUnavailable => '当前数据源无法提供完整内容。';

  @override
  String get persistenceQueueTitle => '持久化诊断';

  @override
  String get persistenceQueueUnavailable => '当前数据源无法提供队列压力。';

  @override
  String persistenceQueuePending(int operations, int bytes) {
    return '排队：$operations 项操作，$bytes 字节';
  }

  @override
  String persistenceQueueInFlight(int bytes) {
    return '正在写入：$bytes 字节';
  }

  @override
  String persistenceQueueOldestAge(int millis) {
    return '最老未保存：$millis 毫秒';
  }

  @override
  String get persistenceQueuePressurePaused => '存储压力下已暂停新的推理准入。';

  @override
  String persistenceQueueError(String message) {
    return '最近错误：$message';
  }

  @override
  String get persistenceQueueRefresh => '刷新诊断';

  @override
  String get persistenceQueueShowDetails => '展开诊断';

  @override
  String get persistenceQueueHideDetails => '收起诊断';

  @override
  String get persistenceHistoryPaused => '会话历史保存已暂停';

  @override
  String get persistenceHistoryQueueFull => '历史队列已满';

  @override
  String get persistenceHistoryWriteFailed => '历史保存失败';

  @override
  String get persistenceHistoryRetrySave => '重试保存';

  @override
  String get persistenceHistoryResume => '继续执行';

  @override
  String get persistenceHistoryResumeHint => '重试保存成功后即可继续';

  @override
  String get persistenceStatisticsGap => '调用统计不完整；缺失的用量未知，不能按零计算。';

  @override
  String recoveryGlobalWarning(int count) {
    return '有 $count 个恢复问题需要处理';
  }

  @override
  String get recoveryArchiveNotice => '迁移无法继续，旧数据已归档。糊来帮现以初始配置运行；归档位置：';

  @override
  String get recoveryArchiveDismiss => '关闭归档提示';

  @override
  String get sidebarNew => '新建';

  @override
  String get sidebarOpen => '打开';

  @override
  String get shellNoSession => '新会话';

  @override
  String get startPageWelcome => '想从哪里开始？';

  @override
  String get preparationTitle => '正在准备会话';

  @override
  String get preparationSubtitle => '准备好工作空间后，将自动开始处理你的请求。';

  @override
  String get preparationFailedTitle => '环境准备未完成';

  @override
  String get preparationRetainedBody => '输入与附件已保留，可调整后重新发送。';

  @override
  String get preparationUnknownTitle => '尚未确认创建结果';

  @override
  String get preparationUnknownBody => '连接已中断，尚不能确认会话是否创建成功。请勿重复发送。';

  @override
  String get preparationCheckProject => '检查项目';

  @override
  String get preparationWorkspace => '准备工作区';

  @override
  String get preparationInitializeSession => '初始化会话';

  @override
  String get preparationSubmitPrompt => '提交请求';

  @override
  String get preparationWaiting => '等待开始准备…';

  @override
  String get preparationCheckingProject => '正在检查项目与会话配置…';

  @override
  String get preparationPreparingWorkspace => '正在准备会话工作区…';

  @override
  String get preparationResolvingRepository => '正在检查 Git 仓库与基线提交…';

  @override
  String get preparationCreatingWorktree => '正在创建工作树并检出文件…';

  @override
  String get preparationInitializingSession => '正在初始化会话环境…';

  @override
  String get preparationSubmittingPrompt => '正在提交你的第一条请求…';

  @override
  String get preparationMoreDetails => '更多详情';

  @override
  String get preparationProjectLabel => '项目';

  @override
  String get preparationRemoteLabel => '远程主机';

  @override
  String get preparationPathLabel => '工作区路径';

  @override
  String get preparationBranchLabel => '工作树分支';

  @override
  String get preparationDiagnosticLabel => '诊断编号';

  @override
  String get preparationStepComplete => '已完成';

  @override
  String get preparationStepPending => '待开始';

  @override
  String get preparationStepRunning => '进行中';

  @override
  String get preparationStepFailed => '未完成';

  @override
  String startPageProject(String project) {
    return '当前项目：$project';
  }

  @override
  String get startPageOpenProjectTitle => '请先打开项目';

  @override
  String get startPageOpenProjectBody => '从侧栏打开一个项目后即可发送第一条消息。';

  @override
  String shellSessionUpdated(String mode, String time) {
    return '$mode · 更新于 $time';
  }

  @override
  String get settingsBack => '返回';

  @override
  String get settingsBackToChat => '返回聊天';

  @override
  String get settingsWorkspaceGroup => '工作区';

  @override
  String get settingsSystemGroup => '系统';

  @override
  String get settingsAccountsTab => '账号';

  @override
  String get settingsInstructionsTab => '指令';

  @override
  String get settingsSkillsTab => '技能';

  @override
  String get settingsAgentsTab => '智能体';

  @override
  String get settingsMcpTab => 'MCP';

  @override
  String get settingsLspTab => 'LSP';

  @override
  String get settingsStatisticsTab => '统计';

  @override
  String get settingsSecurityTab => '安全';

  @override
  String get settingsGeneralTab => '通用';

  @override
  String get settingsSshTab => 'SSH';

  @override
  String get settingsBotsTab => '机器人';

  @override
  String get settingsBotsTitle => '飞书机器人';

  @override
  String get settingsBotsSubtitle => '本地配置、真实连接和入站授权是三件独立事实。';

  @override
  String get settingsBotsAdd => '添加机器人';

  @override
  String get settingsBotsEmptyTitle => '还没有机器人';

  @override
  String get settingsBotsEmptyBody =>
      '可以扫码创建飞书中国版应用，或连接已有应用。Secret 只在保存前停留在内存。';

  @override
  String get settingsBotsSelectTitle => '选择机器人';

  @override
  String get settingsBotsSelectBody => '选择一台机器人查看配置、连接和授权。';

  @override
  String get settingsBotsSetupTitle => '首次配置';

  @override
  String get settingsBotsSetupClose => '关闭配置';

  @override
  String get settingsBotsRisk =>
      '远程消息可能触发本机智能体工具。当前策略为 full-access。关联项目不是操作系统沙箱。';

  @override
  String get settingsBotsPermissions =>
      '申请范围（preset=false）：im:message:send_as_bot、im:message.p2p_msg:readonly、im:message.group_at_msg:readonly、im:chat:readonly、im:message:readonly、im:resource、cardkit:card:write。事件：im.message.receive_v1。保留图片与文件接收，新增流式卡片创建与更新。已有应用需由管理员补充卡片权限并发布；声明权限不等于已获批准。';

  @override
  String get settingsBotsName => '名称';

  @override
  String get settingsBotsProject => '关联项目';

  @override
  String get settingsBotsRiskAck => '我理解远程消息可能以 full-access 运行本机工具';

  @override
  String get settingsBotsScan => '创建并连接飞书应用';

  @override
  String get settingsBotsManual => '连接已有应用';

  @override
  String get settingsBotsAppId => 'App ID';

  @override
  String get settingsBotsSecret => 'App Secret';

  @override
  String get settingsBotsSave => '保存配置';

  @override
  String get settingsBotsPendingTitle => '未完成的本地保存';

  @override
  String get settingsBotsPendingPreparing => '正在准备凭据';

  @override
  String get settingsBotsPendingUncertain => '保存需要本地核实';

  @override
  String get settingsBotsPendingCleanup => '清理未完成';

  @override
  String get settingsBotsPendingCleanupCommitted => '配置已生效，清理仍待完成';

  @override
  String get settingsBotsPendingIdle => '空闲';

  @override
  String get settingsBotsVerify => '核实原操作';

  @override
  String get settingsBotsFactConfig => '配置';

  @override
  String get settingsBotsFactConnection => '连接';

  @override
  String get settingsBotsFactAuth => '授权';

  @override
  String get settingsBotsFactMissing => '尚无可用配置';

  @override
  String get settingsBotsConnectionConnected => '已连接';

  @override
  String get settingsBotsConnectionConnecting => '连接中';

  @override
  String get settingsBotsConnectionFailed => '失败';

  @override
  String get settingsBotsConnectionIdle => '未连接';

  @override
  String get settingsBotsAuthGranted => '已有本地入站授权';

  @override
  String get settingsBotsAuthPending => '配对待批准';

  @override
  String get settingsBotsAuthNone => '尚无入站信任';

  @override
  String get settingsBotsCredentialStored => '已持久保存';

  @override
  String get settingsBotsCredentialSession => '仅当前进程';

  @override
  String get settingsBotsCredentialMissing => '缺失';

  @override
  String get settingsBotsCredentialUnavailable => '不可用';

  @override
  String settingsBotsRegistrationStatus(String status) {
    return '注册状态：$status';
  }

  @override
  String get settingsBotsOpenLink => '在浏览器中继续';

  @override
  String get settingsBotsOpenFeishu => '打开飞书继续';

  @override
  String get settingsBotsContinueHint => '在飞书中确认创建应用，此页会自动更新注册结果。';

  @override
  String get settingsBotsScanOnlyHint => '用手机飞书扫描二维码并确认创建应用，此页会自动更新注册结果。';

  @override
  String get settingsBotsScanHint => '也可用手机飞书扫码。若客户端未打开，请使用浏览器入口或扫码继续。';

  @override
  String get settingsBotsOpenLinkFailed => '无法打开链接。请扫码继续，或尝试浏览器入口。';

  @override
  String get settingsBotsOpenChat => '在飞书中打开聊天';

  @override
  String get settingsBotsOpenChatBrowser => '通过浏览器打开';

  @override
  String get settingsBotsPolicyDenied => '飞书访问控制策略拒绝了此应用的 API 请求。';

  @override
  String get settingsBotsPolicyDeniedHint =>
      '应用已创建不代表 API 访问已获准。请联系所属组织管理员检查应用访问策略，确认允许后再重试连接。';

  @override
  String settingsBotsPlatformCode(String code) {
    return '飞书错误码：$code';
  }

  @override
  String get settingsBotsCopyLink => '复制链接';

  @override
  String get settingsBotsRegistrationBusy => '本地保存正在提交。此时取消会返回忙碌，不会显示已取消。';

  @override
  String get settingsBotsCancelRegistration => '取消注册';

  @override
  String get settingsBotsRegIdle => '空闲';

  @override
  String get settingsBotsRegPreparing => '准备中';

  @override
  String get settingsBotsRegWaiting => '等待飞书确认';

  @override
  String get settingsBotsRegSlowDown => '降频等待';

  @override
  String get settingsBotsRegCommitting => '提交中';

  @override
  String get settingsBotsRegCompleted => '已完成';

  @override
  String get settingsBotsRegDenied => '已拒绝';

  @override
  String get settingsBotsRegExpired => '已过期';

  @override
  String get settingsBotsRegCancelled => '已取消';

  @override
  String get settingsBotsRegFailed => '失败';

  @override
  String get settingsBotsQrFailed => '无法生成验证二维码。请使用当前可信链接的本地打开或复制入口。';

  @override
  String get settingsBotsAppIdLocked => '已有平台会话或持久记录后，不能原地更改 App ID。';

  @override
  String get settingsBotsProjectLocked => '已有 Thread 映射或受理输入后，不能原地更换关联项目。';

  @override
  String get settingsBotsEnabled => '启用连接';

  @override
  String get settingsBotsRetryConnection => '重试连接';

  @override
  String get settingsBotsTools => '允许项目工具';

  @override
  String get settingsBotsToolsHint =>
      '只控制关联项目根 Thread 的四项工具。本地所有者查询/发送和原会话自动回复不受此开关额外限制。';

  @override
  String get settingsBotsTrustedUsers => '可信用户';

  @override
  String get settingsBotsTrustedChats => '授权群';

  @override
  String get settingsBotsRevoke => '撤销';

  @override
  String get settingsBotsApprove => '批准';

  @override
  String get settingsBotsPairingHint => '未知私聊不会触发模型。批准后请对方重发；旧消息不会自动执行。';

  @override
  String get settingsBotsClearPairing => '清理请求';

  @override
  String get settingsBotsClearPairingHint =>
      '只清理这条本地配对请求，该用户当前的信任设置保持不变，旧消息也不会执行。';

  @override
  String get settingsBotsNoTrustedUsers => '还没有可信用户。手工接入初始信任列表为空。';

  @override
  String get settingsBotsNoTrustedChats => '群默认关闭。需要授权群，并且用户真正 @ 当前机器人。';

  @override
  String get settingsBotsConversations => '会话';

  @override
  String get settingsBotsRefreshConversations => '刷新';

  @override
  String get settingsBotsNewThread => '新建本机会话';

  @override
  String get settingsBotsMessages => '消息';

  @override
  String get settingsBotsSendHint => '以机器人身份发送';

  @override
  String get settingsBotsSend => '发送';

  @override
  String settingsBotsSendStatus(String status) {
    return '发送状态：$status';
  }

  @override
  String get settingsBotsSourceGroup => '群聊';

  @override
  String get settingsBotsSourceDirect => '私聊';

  @override
  String get settingsBotsEdit => '编辑配置';

  @override
  String get settingsBotsDismiss => '取消';

  @override
  String get settingsBotsPreserveSecret => '留空保留原有凭据，不会回显已保存的 Secret。';

  @override
  String get settingsBotsClearSecret => '移除已保存的凭据';

  @override
  String get settingsBotsOperationFailed =>
      '操作未能完成，请核对当前状态后明确重试；结果未知的发送不可安全重放。';

  @override
  String get settingsBotsModelReady => '简洁模式的模型路由及凭据已配置；这不代表已实时验证模型连通性。';

  @override
  String get settingsBotsModelMissing =>
      '请先在账号和模式中配置完整的简洁模式模型路由与凭据，再期待远程消息执行。保存飞书应用不会验证模型连通性。';

  @override
  String get settingsBotsManualGuide =>
      '在飞书中国版开发者后台开启机器人和长连接事件接收，订阅 im.message.receive_v1，申请上方列出的权限，并发布应用、确认可用范围。租户管理员可能需要审核权限。在这里保存后再启用连接。';

  @override
  String get settingsBotsFirstMessageGuide =>
      '真实连接后，请在飞书向机器人发送消息。未知发送者只会产生配对请求：在本机批准后，请对方重新发送。群执行还需要本机授权该群，并由用户真正 @ 当前机器人，@全体成员不算。';

  @override
  String get settingsBotsNewThreadWarning =>
      '为后续消息新建本地上下文？旧历史会保留，已经受理的消息和回复仍属于原上下文，不会移动到新会话。';

  @override
  String get settingsBotsApproveGroup => '授权此群';

  @override
  String get settingsBotsNextPage => '下一页';

  @override
  String get settingsBotsRefreshMessages => '应用时间范围 / 刷新消息';

  @override
  String get settingsBotsStartTime => '起始时间（Unix 秒，可空）';

  @override
  String get settingsBotsEndTime => '结束时间（Unix 秒，可空）';

  @override
  String get settingsBotsHistoryPermissions =>
      '仅显示应用有权访问的历史。群历史可能额外需要 im:message.group_msg，须在飞书单独开通；不会自动申请，也不会切换为用户身份兜底。';

  @override
  String get settingsBotsOpenConsole => '打开飞书开发者后台';

  @override
  String get settingsBotsOpenConsoleHint =>
      '打开飞书中国版官方开发者后台页面。进入后请选择与当前 App ID 对应的应用并打开权限管理；权限仍须管理员审核，应用也须发布并确认可用范围，这里不会自动申请或代替授权。';

  @override
  String get settingsBotsOpenConsoleFailed => '打开开发者后台失败，请重试。';

  @override
  String get settingsBotsConnectionReconnecting => '重连中';

  @override
  String get settingsBotsSendOperation => '发送操作';

  @override
  String get settingsBotsNoReplay => '部分消息可能已经送达。结果会保留，不会自动重放发送。';

  @override
  String get settingsBotsSendSucceeded => '全部送达';

  @override
  String get settingsBotsSendPartial => '部分送达';

  @override
  String get settingsBotsSendRejected => '明确拒绝';

  @override
  String get settingsBotsSendUnknown => '结果未知';

  @override
  String get settingsSshTitle => '远程开发';

  @override
  String get settingsSshSubtitle =>
      '服务器列表来自你的 ~/.ssh/config；anywork 只管理自己写入的标记块。';

  @override
  String get settingsSshAdd => '添加服务器';

  @override
  String get settingsSshEmpty => '尚未配置 SSH 服务器。';

  @override
  String get settingsSshManagedByCore => 'OpenSSH 与轻量远程助手由本机统一管理。';

  @override
  String get settingsSshTest => '测试连接';

  @override
  String get settingsSshReconnect => '重新连接';

  @override
  String get settingsSshReconnectHint => '重新连接以加载最新远程环境；正在运行的远程命令会中断。';

  @override
  String get settingsSshOpenProject => '打开项目';

  @override
  String get settingsSshEdit => '编辑';

  @override
  String get settingsSshDelete => '删除';

  @override
  String get settingsSshReady => '已连接';

  @override
  String get settingsSshDeleteTitle => '删除 SSH 服务器？';

  @override
  String settingsSshDeleteBody(String name) {
    return '确定删除 $name？请先移除使用该服务器的项目。';
  }

  @override
  String get settingsSshAlias => '别名（Host）';

  @override
  String get settingsSshProjectName => '项目名称';

  @override
  String get settingsSshHost => '主机';

  @override
  String get settingsSshUsername => '用户名';

  @override
  String get settingsSshPort => '端口';

  @override
  String get settingsSshIdentityFile => '私钥文件（可选）';

  @override
  String get settingsSshIdentityHelper => '留空时使用 ssh-agent。';

  @override
  String get settingsSshEditTitle => '编辑 SSH 服务器';

  @override
  String get settingsSshPassword => '密码（可选）';

  @override
  String get settingsSshPasswordHelper =>
      '保存在系统凭据库，不会写入 ~/.ssh/config；留空则使用密钥或连接时输入。';

  @override
  String get settingsSshPasswordSavedHint => '已保存密码，留空保持不变';

  @override
  String get settingsSshPasswordClear => '清除已保存密码';

  @override
  String get settingsSshPasswordClearedHint => '保存后将清除已保存的密码';

  @override
  String get settingsSshPasswordBadge => '已配置密码';

  @override
  String settingsSshKeyBadge(String path) {
    return '密钥：$path';
  }

  @override
  String get settingsSshAuthPromptTitle => '输入 SSH 密码';

  @override
  String settingsSshAuthPromptSubtitle(String target) {
    return '连接到 $target 需要密码认证。';
  }

  @override
  String get settingsSshAuthPasswordLabel => 'SSH 密码';

  @override
  String get settingsSshAuthPasswordRequired => '请输入 SSH 密码';

  @override
  String get settingsSshAuthRememberPassword => '保存密码到系统凭据库';

  @override
  String get settingsSshAuthConnect => '连接';

  @override
  String get settingsSshPasswordAuthUnavailable =>
      '该服务器未提供密码认证，请配置 SSH 密钥或启动 ssh-agent。';

  @override
  String get settingsSshReadOnlyEntry => '手写条目——请直接编辑 ~/.ssh/config。';

  @override
  String get settingsSshSave => '保存';

  @override
  String get settingsSshAliasRequired => '请输入别名';

  @override
  String get settingsSshAliasInvalid => '别名必须是单个词，不能含空格或通配字符';

  @override
  String get settingsSshAliasHelper => '写入 ~/.ssh/config 的 Host 条目；创建后不可改名。';

  @override
  String get settingsSshHostRequired => '请输入主机地址';

  @override
  String get settingsSshUsernameRequired => '请输入用户名';

  @override
  String get settingsSshPortInvalid => '端口必须是 1 到 65535 之间的数字';

  @override
  String get settingsSshChooseDirectory => '选择远端目录';

  @override
  String get settingsSshOpenThisDirectory => '打开此目录';

  @override
  String get settingsSshGo => '前往';

  @override
  String get settingsSshDirectoryPathLabel => '远端路径';

  @override
  String get settingsSshDirectoryPathHint => '/home/user/project';

  @override
  String get settingsSshPathRequired => '请输入远端目录路径';

  @override
  String get settingsSshPathAbsolute => '远端路径必须以 / 开头，且必须是绝对路径';

  @override
  String get settingsSshDirectoryEmpty => '此目录为空';

  @override
  String get settingsSshDirectoryEmptyHint => '此处没有子目录，但仍可打开当前目录。';

  @override
  String get settingsSshUp => '上一级目录';

  @override
  String get settingsSshOpenFailed => '无法打开该目录，请检查服务器后重试。';

  @override
  String get composerHint => '描述你的需求…';

  @override
  String get composerSend => '发送';

  @override
  String get composerStop => '停止';

  @override
  String get compileModeSimple => '简洁';

  @override
  String get compileModeTask => '任务';

  @override
  String get statusCost => '费用';

  @override
  String get statusTotalTokensLabel => '总词元数';

  @override
  String get statusModelLabel => '模型';

  @override
  String get statusCapabilitiesTitle => '当前启用项';

  @override
  String get statusSessionMode => '会话模式';

  @override
  String get statusSessionModeLocked => '会话运行或工作流活动期间无法切换会话模式';

  @override
  String get statusSelectorsNotReady => '会话设置尚未就绪或正在提交，暂时不能选择，请稍后重试。';

  @override
  String get statusModeNeedsProject => '请先选择项目，再设置会话模式。';

  @override
  String get composerWorkspaceModeLabel => '会话工作区';

  @override
  String get composerWorkspaceModeLocal => '本地目录';

  @override
  String get composerWorkspaceModeWorktree => '新建工作树';

  @override
  String get statusPlannerModel => '主智能体模型';

  @override
  String get statusModelRouteUnavailable => '当前模型不可用，查看原因';

  @override
  String statusModelRouteUnavailableDetail(String reason) {
    return '当前模型不可用：$reason';
  }

  @override
  String get statusModelRouteUnavailableFallback => '当前模型路由不可用，请检查账号和模型设置。';

  @override
  String get statusModelSwitchWhileRunning =>
      '会话正在执行或等待处理，暂时无法切换模型。请停止当前执行或等待完成后重试。';

  @override
  String get statusModelSwitchWhileInactive =>
      '会话正在关闭、已关闭或出现故障，无法切换模型。请恢复会话后重试。';

  @override
  String get statusModelNoticeDismiss => '关闭模型提示';

  @override
  String get statusExecutorModel => '执行者模型';

  @override
  String get statusReasoningEffort => '思考强度';

  @override
  String get statusContextLabel => '上下文';

  @override
  String get statusContextRemainingLabel => '距阈值';

  @override
  String statusContextOverLimitValue(String tokens) {
    return '超出 $tokens';
  }

  @override
  String get statusModelMaxContextLabel => '最大上下文';

  @override
  String get statusModelEffectiveWindowLabel => '有效窗口';

  @override
  String get statusAutoCompactLimitLabel => '压缩阈值';

  @override
  String get statusSessionUsageSection => '会话累计';

  @override
  String get statusInputTokensLabel => '输入';

  @override
  String get statusOutputTokensLabel => '输出';

  @override
  String get statusCostEstimateLabel => '估算费用';

  @override
  String get statusUsageIncompleteLabel => '不完整';

  @override
  String get statusCacheLabel => '缓存命中率';

  @override
  String get statusCacheHitTokensLabel => '缓存命中';

  @override
  String get statusCacheMissTokensLabel => '缓存未命中';

  @override
  String get statusCacheWriteTokensLabel => '缓存写入';

  @override
  String get statusReasoningTokensLabel => '推理词元数';

  @override
  String get statusInferenceCountLabel => '推理次数';

  @override
  String get statusCacheSavingsLabel => '缓存节省';

  @override
  String get statusUnpricedUsageLabel => '未计价';

  @override
  String get sessionAllAgentsCostTooltip => '会话全部智能体费用';

  @override
  String get sessionMoreActionsTooltip => '更多操作';

  @override
  String get sessionOpenWorkspace => '打开工作区';

  @override
  String get sessionOpenWith => '打开方式';

  @override
  String get sessionOpenInVsCode => '在 VS Code 中打开';

  @override
  String get sessionOpenInZed => '在 Zed 中打开';

  @override
  String get sessionOpenInTerminal => '在终端中打开';

  @override
  String get sessionVsCodeUnavailable => '未在这台机器上找到 VS Code';

  @override
  String get sessionZedUnavailable => '未在这台机器上找到 Zed';

  @override
  String get sessionTerminalUnavailableWindows =>
      '未找到 Windows Terminal（wt.exe）';

  @override
  String get sessionTerminalUnavailableLinux =>
      '未找到 xdg-terminal-exec 或 x-terminal-emulator';

  @override
  String get sessionTerminalUnavailableGeneric => '当前平台不支持外部终端';

  @override
  String get sessionVsCodeOpenFailed => '打开 VS Code 失败';

  @override
  String get sessionZedOpenFailed => '打开 Zed 失败';

  @override
  String get sessionTerminalOpenFailed => '打开终端失败';

  @override
  String get sessionOpenServerMissing => '该项目的 SSH 别名已不在 ~/.ssh/config 中';

  @override
  String get statusLastConfirmedAgentTokenSpeed => '最近已确认输出速度（含首字等待）';

  @override
  String get settingsStatisticsTitle => '统计';

  @override
  String get settingsStatisticsSubtitle => '按账号、配置模型与组内思考强度汇总最近成功调用。';

  @override
  String get settingsStatisticsSummaryTitle => '模型性能';

  @override
  String get settingsStatisticsHistoryTitle => '调用历史';

  @override
  String get settingsStatisticsAllModels => '全部模型';

  @override
  String get settingsStatisticsEmpty => '暂无调用历史。';

  @override
  String get settingsStatisticsSummaryEmpty => '暂无模型性能汇总。';

  @override
  String get settingsStatisticsFilteredEmpty => '当前筛选条件下没有调用记录。';

  @override
  String get settingsStatisticsGapTitle => '统计存在缺口';

  @override
  String get settingsStatisticsGapBody => '部分调用记录未能写入，汇总和历史可能不完整。';

  @override
  String get settingsStatisticsReadFailedTitle => '统计读取失败';

  @override
  String get settingsStatisticsReadFailedBody => '当前显示的数据可能已过期或不可用。';

  @override
  String get settingsStatisticsMismatchesOnly => '仅看不一致';

  @override
  String get settingsStatisticsMismatchEmpty => '当前筛选条件下没有模型不一致记录。';

  @override
  String get statisticsModel => '账号 / 模型';

  @override
  String get statisticsHistoryModelHeader => '模型';

  @override
  String get statisticsConfiguredModel => '配置模型';

  @override
  String get statisticsSentModel => '发送模型';

  @override
  String get statisticsReportedModel => '返回模型';

  @override
  String get statisticsUpstreamReportedModel => '上游响应模型';

  @override
  String get statisticsModelMatched => '一致';

  @override
  String get statisticsModelMismatched => '不一致';

  @override
  String get statisticsModelMismatchBadge => '模型不匹配';

  @override
  String get statisticsModelUnreported => '未报告';

  @override
  String get statisticsModelLegacyUnknown => '未采集';

  @override
  String get statisticsMetricNotCollected => '未采集';

  @override
  String get statisticsModelUnavailable => '无';

  @override
  String get statisticsReasoningEffort => '思考强度';

  @override
  String get statisticsReasoningEffortUnspecified => '未指定/未记录';

  @override
  String get statisticsSpeed => '输出 TPS（含首字等待）';

  @override
  String get statisticsSamples => '样本数';

  @override
  String get statisticsOutputTokens => '输出词元数';

  @override
  String get statisticsAverageTtft => '平均首字';

  @override
  String get statisticsAverageResponse => '平均总响应';

  @override
  String get statisticsCompletedAt => '完成时间';

  @override
  String get statisticsDecode => '首字后耗时';

  @override
  String get statisticsTotalResponse => '总响应耗时';

  @override
  String statisticsTtftSampleCount(int count) {
    return '$count 个首字样本';
  }

  @override
  String get settingsStatisticsThroughputNote =>
      '输出 TPS = 供应商确认的输出词元 × 1000 ÷ 总响应耗时（含首字等待）。总响应从产生结果的请求开始到归一化终态到达为止，不含失败重试、退避、工具执行与终态后的收集或保存；首字是首个非空文本、推理或工具输入增量，输出可含推理词元且不重复相加。首字后耗时只是诊断，不是硬件解码时间。旧统计口径的样本已丢弃，原始调用与账单保留。';

  @override
  String get statusTurnQueued => '排队中';

  @override
  String get statusTurnPreparing => '准备上下文';

  @override
  String get statusTurnResponding => '回复中';

  @override
  String get statusTurnPlanning => '规划中';

  @override
  String get statusTurnRunningTool => '运行工具';

  @override
  String get statusTurnWaitingForApproval => '等待工具授权';

  @override
  String get statusTurnWaitingForUserInput => '等待输入';

  @override
  String get statusTurnPersisting => '保存本轮结果';

  @override
  String get statusInteractionToolApproval => '等待工具授权';

  @override
  String get statusInteractionUserInput => '等待输入';

  @override
  String statusSkillsCount(int count) {
    return '$count 个技能';
  }

  @override
  String statusMcpCount(int count) {
    return '$count 个 MCP 服务器';
  }

  @override
  String statusLspCount(int count) {
    return '$count 个语言服务器';
  }

  @override
  String get statusLspIndexing => '索引中';

  @override
  String get statusLspBusy => '处理中';

  @override
  String statusLspActivityPercentage(int percentage) {
    return '$percentage%';
  }

  @override
  String statusAgentsCount(int count) {
    return '$count 个智能体';
  }

  @override
  String get statusSkillsSection => '技能';

  @override
  String get statusMcpSection => 'MCP';

  @override
  String get statusLspSection => 'LSP';

  @override
  String get agentDetailStatusQueued => '排队中';

  @override
  String get agentDetailStatusRunning => '运行中';

  @override
  String get agentDetailStatusCompleted => '已完成';

  @override
  String get agentDetailStatusErrored => '出错';

  @override
  String get agentDetailStatusInterrupted => '已中断';

  @override
  String get agentDetailStatusShutdown => '已关闭';

  @override
  String get agentDetailPathLabel => '路径';

  @override
  String get timelineEmptyTitle => '还没有消息';

  @override
  String get timelineEmptyMessage => '打开项目或开始会话后即可开始。';

  @override
  String get timelineExternalLinkOpenFailed => '无法打开此链接。';

  @override
  String get timelineAttachment => '附件';

  @override
  String get timelineImageLoadFailed => '无法加载此图片。';

  @override
  String get timelineImageRetry => '重试';

  @override
  String get timelineImageClose => '关闭图片预览';

  @override
  String get timelineImageCardTitle => '图片展示';

  @override
  String get timelineImageCardEmpty => '这张图片无法显示';

  @override
  String timelineRemoteImageSource(String host) {
    return '来自 $host 的外部图片';
  }

  @override
  String get timelineRemoteImageOpen => '点击后加载并预览';

  @override
  String get timelineJumpToLatest => '跳到最新';

  @override
  String get timelineNew => '新内容';

  @override
  String get timelineLoadEarlier => '加载更早消息';

  @override
  String get timelineBackToLive => '回到实时';

  @override
  String get timelineDetailUnavailable => '此内容已不可用';

  @override
  String get timelineReconnecting => '正在重新连接消息，当前内容已保留。';

  @override
  String get timelineConnectionFailed => '消息同步失败，当前内容已保留。';

  @override
  String get timelineReasoningFallback => '思考';

  @override
  String get timelineReasoningActive => '思考中';

  @override
  String get timelineReasoningEnded => '思考结束';

  @override
  String get timelineReasoningFailed => '思考失败';

  @override
  String get timelineReasoningCancelled => '思考已取消';

  @override
  String get timelineReasoningElapsedUnderSecond => '思考了不到 1 秒';

  @override
  String timelineReasoningElapsedSeconds(int seconds) {
    return '思考了 $seconds 秒';
  }

  @override
  String timelineReasoningElapsedMinutes(int minutes) {
    return '思考了 $minutes 分';
  }

  @override
  String timelineReasoningElapsedMinutesSeconds(int minutes, int seconds) {
    return '思考了 $minutes 分 $seconds 秒';
  }

  @override
  String get timelineReasoningSummary => '概要';

  @override
  String get timelineReasoningContent => '完整内容';

  @override
  String get timelineReasoningBudgetLimited => '已达思考预算';

  @override
  String get timelineToolFallback => '工具';

  @override
  String get timelineToolGroupTitle => '工具活动';

  @override
  String timelineToolGroupSummary(int count) {
    return '$count 个工具';
  }

  @override
  String timelineToolGroupSummaryRunning(int count, int runningCount) {
    return '$count 个工具，$runningCount 个运行中';
  }

  @override
  String timelineToolGroupSummaryIssues(int count, int issueCount) {
    return '$count 个工具，$issueCount 个需要注意';
  }

  @override
  String timelineToolGroupSummaryRunningWithIssues(
    int count,
    int runningCount,
    int issueCount,
  ) {
    return '$count 个工具，$runningCount 个运行中，$issueCount 个需要注意';
  }

  @override
  String timelineSkillActivated(String name) {
    return '已激活技能 · $name';
  }

  @override
  String timelineSkillAgentActivated(String name) {
    return '智能体已激活技能 · $name';
  }

  @override
  String get timelineParentAgent => '主智能体';

  @override
  String timelineSkillUserActivated(String name) {
    return '用户激活技能 · $name';
  }

  @override
  String get timelineAgentFallback => '智能体';

  @override
  String get timelineViewImageRead => '已读取图片';

  @override
  String timelineImagesViewed(int count) {
    return '已查看 $count 张图像';
  }

  @override
  String timelineImagesProduced(int count) {
    return '$count 张图像';
  }

  @override
  String get timelineViewImageReading => '正在读取图片';

  @override
  String get timelineViewImageFailed => '读取图片失败';

  @override
  String get timelineReadFileCompleted => '已读取';

  @override
  String get timelineReadFileReading => '正在读取';

  @override
  String get timelineReadFileFailed => '读取失败';

  @override
  String get timelineToolEditSucceeded => '已修改';

  @override
  String get timelineToolEditRunning => '正在修改';

  @override
  String get timelineToolEditFailed => '修改失败';

  @override
  String timelineToolPatchFilesMore(String first, int more) {
    return '$first，另 $more 个文件';
  }

  @override
  String get timelineSessionNoteName => '会话笔记';

  @override
  String get timelineToolCommandSucceeded => '已运行';

  @override
  String get timelineToolCommandRunning => '正在运行';

  @override
  String get timelineToolCommandFailed => '运行失败';

  @override
  String get timelineToolStdinSucceeded => '已写入输入';

  @override
  String get timelineToolStdinRunning => '正在写入输入';

  @override
  String get timelineToolStdinFailed => '输入写入失败';

  @override
  String get timelineToolElapsedUnderSecond => '用时不到 1 秒';

  @override
  String timelineToolElapsedSeconds(int seconds) {
    return '用时 $seconds 秒';
  }

  @override
  String timelineToolElapsedMinutes(int minutes) {
    return '用时 $minutes 分';
  }

  @override
  String timelineToolElapsedMinutesSeconds(int minutes, int seconds) {
    return '用时 $minutes 分 $seconds 秒';
  }

  @override
  String get timelineToolSearchSucceeded => '已搜索';

  @override
  String get timelineToolSearchRunning => '正在搜索';

  @override
  String get timelineToolSearchFailed => '搜索失败';

  @override
  String get timelineToolAgentSucceeded => '已启动子代理';

  @override
  String get timelineToolAgentRunning => '子代理运行中';

  @override
  String get timelineToolAgentFailed => '子代理失败';

  @override
  String get timelineToolMessageSucceeded => '已发送消息';

  @override
  String get timelineToolMessageRunning => '正在发送消息';

  @override
  String get timelineToolMessageFailed => '消息发送失败';

  @override
  String get timelineToolCreateSucceeded => '已新建目录';

  @override
  String get timelineToolCreateRunning => '正在新建目录';

  @override
  String get timelineToolCreateFailed => '新建目录失败';

  @override
  String get timelineToolDeleteSucceeded => '已删除';

  @override
  String get timelineToolDeleteRunning => '正在删除';

  @override
  String get timelineToolDeleteFailed => '删除失败';

  @override
  String get timelineToolCopySucceeded => '已复制';

  @override
  String get timelineToolCopyRunning => '正在复制';

  @override
  String get timelineToolCopyFailed => '复制失败';

  @override
  String get timelineToolMoveSucceeded => '已移动';

  @override
  String get timelineToolMoveRunning => '正在移动';

  @override
  String get timelineToolMoveFailed => '移动失败';

  @override
  String get timelineToolFetchSucceeded => '已获取网页';

  @override
  String get timelineToolFetchRunning => '正在获取网页';

  @override
  String get timelineToolFetchFailed => '获取网页失败';

  @override
  String get timelineToolPlanSucceeded => '已更新计划';

  @override
  String get timelineToolPlanRunning => '正在更新计划';

  @override
  String get timelineToolPlanFailed => '计划更新失败';

  @override
  String get timelineToolWorkflowSucceeded => '已更新工作流';

  @override
  String get timelineToolWorkflowRunning => '正在更新工作流';

  @override
  String get timelineToolWorkflowFailed => '工作流更新失败';

  @override
  String get timelineToolLspSucceeded => '已查询代码';

  @override
  String get timelineToolLspRunning => '正在查询代码';

  @override
  String get timelineToolLspFailed => '代码查询失败';

  @override
  String get timelineToolWaitSucceeded => '已等待';

  @override
  String get timelineToolWaitRunning => '正在等待';

  @override
  String get timelineToolWaitFailed => '等待失败';

  @override
  String timelineToolCompleted(String name) {
    return '$name 已完成';
  }

  @override
  String timelineToolFailed(String name) {
    return '$name 失败';
  }

  @override
  String timelineToolDenied(String name) {
    return '$name 被拒绝';
  }

  @override
  String timelineToolCancelled(String name) {
    return '$name 已取消';
  }

  @override
  String timelineToolAwaitingApproval(String name) {
    return '$name 等待授权';
  }

  @override
  String timelineToolRunning(String name) {
    return '$name 运行中';
  }

  @override
  String timelineToolExitCode(int code) {
    return '退出码 $code';
  }

  @override
  String get timelineToolTimedOut => '已超时';

  @override
  String get agentDetailStatusClosing => '正在关闭';

  @override
  String timelineToolQueued(String name) {
    return '$name 排队中';
  }

  @override
  String timelineToolCancelling(String name) {
    return '$name 正在取消';
  }

  @override
  String timelineToolInterrupted(String name) {
    return '$name 已中断';
  }

  @override
  String get timelineAgentSubagent => '子智能体';

  @override
  String get timelineAgentSubagentMessage => '子智能体消息';

  @override
  String get timelineAgentWaiting => '等待子智能体';

  @override
  String get timelineAgentClose => '关闭子智能体';

  @override
  String get timelineTodoListFallback => '待办列表';

  @override
  String get timelineTodoPending => '待处理';

  @override
  String get timelineTodoInProgress => '进行中';

  @override
  String get timelineTodoCompleted => '已完成';

  @override
  String get interactionQuestionsTitle => '几个问题想确认';

  @override
  String get interactionLastQuestion => '最后一题';

  @override
  String get interactionContinueAfterAnswer => '回答后继续';

  @override
  String get timelineRolledBack => '已从有效上下文回退';

  @override
  String get interactionSubmitEmptyAnswersHint => '未作答的问题将留空提交。';

  @override
  String interactionAnsweredPendingHint(int answeredCount, int pendingCount) {
    return '已答 $answeredCount 题 · $pendingCount 题待答';
  }

  @override
  String get interactionPreviousQuestion => '上一题';

  @override
  String get interactionNextQuestion => '下一题';

  @override
  String get interactionSubmitAnswers => '提交答案';

  @override
  String get interactionNeedInputTitle => '需要你的输入';

  @override
  String get interactionAnswerHint => '糊来帮会把这条回答作为当前问题的答案继续执行。';

  @override
  String get interactionAnswerButton => '回答';

  @override
  String get interactionAnswerLabel => '答案';

  @override
  String interactionQuestionProgress(int current, int total) {
    return '问题 $current/$total';
  }

  @override
  String interactionAnsweredCount(int count) {
    return '已答 $count 题';
  }

  @override
  String interactionQuestionTooltip(int index) {
    return '问题 $index';
  }

  @override
  String get interactionQuestionFallback => '问题';

  @override
  String get interactionOtherLabel => '其他';

  @override
  String get interactionSecretHint => '输入敏感信息';

  @override
  String get interactionTextHint => '输入你的回答…';

  @override
  String get interactionPermissionTitle => '需要权限';

  @override
  String get interactionPermissionSubtitle => '糊来帮希望调用以下工具';

  @override
  String get interactionPermissionFooterHint => '工具将在当前工作目录执行。';

  @override
  String get interactionReject => '拒绝';

  @override
  String get interactionApprove => '批准';

  @override
  String get interactionReasonLabel => '原因';

  @override
  String get interactionPlanConfirmTitle => '确认此计划？';

  @override
  String get interactionPlanConfirmSubtitle => '确认计划，或直接写下调整要求';

  @override
  String get interactionPlanReadyTitle => '实施计划已准备好';

  @override
  String get interactionPlanAwaitingConfirmation => '等待确认';

  @override
  String get interactionPlanApproved => '已批准';

  @override
  String get statusPlanEntry => '计划';

  @override
  String get interactionPlanViewDetails => '查看完整计划';

  @override
  String get interactionPlanDetailsTitle => '实施计划';

  @override
  String interactionPlanConfirmFooterHint(String mode) {
    return '确认后将在$mode模式进入文档编辑检查点。';
  }

  @override
  String get interactionPlanAdjust => '告诉糊来帮如何调整';

  @override
  String get interactionPlanConfirmAction => '确认并执行';

  @override
  String get interactionPlanAdjustHint => '输入要调整的要求…';

  @override
  String get interactionPlanAdjustSubmit => '提交修改';

  @override
  String get interactionPlanFeedbackHint => 'Enter 提交修改 · Shift+Enter 换行';

  @override
  String get planExpandReading => '展开阅读';

  @override
  String get planRestoreSplit => '恢复并排';

  @override
  String get planReceiptApproved => '计划已批准';

  @override
  String get planReceiptRevisionRequested => '已请求修改计划';

  @override
  String get planReceiptCancelled => '计划确认已取消';

  @override
  String get planReceiptAnswered => '计划确认已回答';

  @override
  String get planReceiptYourReply => '你的回复';

  @override
  String get planReceiptYourFeedback => '修改意见';

  @override
  String get planReceiptApproveReply => '批准实施该计划';

  @override
  String get settingsAccountsTitle => '账号';

  @override
  String get settingsAccountsSubtitle => '账号、凭据、模型和用量';

  @override
  String get settingsRefreshUsage => '刷新用量';

  @override
  String get settingsAddAccount => '添加账号';

  @override
  String get settingsSearchAccounts => '搜索账号';

  @override
  String get settingsNoAccountsMatchTitle => '没有匹配的账号';

  @override
  String get settingsNoAccountsMatchMessage => '清空搜索以查看所有已配置的账号。';

  @override
  String get settingsNoAccountsTitle => '没有账号';

  @override
  String get settingsNoAccountsMessage => '添加账号后可配置凭据和模型。';

  @override
  String get settingsDefaultAccount => '默认账号';

  @override
  String get settingsSetAsDefaultAccount => '设为默认';

  @override
  String get settingsOpenDetails => '打开详情';

  @override
  String get settingsAccountActions => '账号操作';

  @override
  String get settingsEditAccount => '编辑账号';

  @override
  String get settingsDeleteAccount => '删除账号';

  @override
  String get settingsNoAccountSelected => '未选择账号';

  @override
  String get settingsAccountTitle => '账号信息';

  @override
  String get settingsAccountModelsTitle => '模型';

  @override
  String get settingsAccountConnectionTitle => '连接';

  @override
  String get settingsAccountDefaultModelsTitle => '默认目录（尚未同步）';

  @override
  String get settingsAccountCustomModelsTitle => '手动模型';

  @override
  String get settingsAccountOnlineModelsTitle => '在线模型';

  @override
  String get settingsNewAccount => '新建账号';

  @override
  String get settingsAccountId => '账号 ID';

  @override
  String get settingsAccountTemplate => '账号模板';

  @override
  String get settingsCustomAccount => '自定义账号';

  @override
  String get settingsDefaultModel => '默认模型';

  @override
  String get settingsApiKey => 'API 密钥';

  @override
  String get settingsApiKeyKeepCurrent => 'API 密钥（留空以保留当前值）';

  @override
  String get settingsConfigured => '已配置';

  @override
  String get settingsMissing => '缺失';

  @override
  String get settingsDisplayName => '显示名称';

  @override
  String get settingsProtocolType => '协议类型';

  @override
  String get settingsBaseUrl => '基础 URL';

  @override
  String get settingsModelId => '模型标识';

  @override
  String get settingsReasoningEfforts => '思考强度';

  @override
  String get settingsEdit => '编辑';

  @override
  String get settingsCancel => '取消';

  @override
  String get settingsSave => '保存';

  @override
  String get settingsAddModel => '添加模型';

  @override
  String get settingsRemoveModel => '移除模型';

  @override
  String get settingsNoCustomModels => '没有手动模型';

  @override
  String get settingsNoOnlineModels => '没有在线模型';

  @override
  String get settingsNoBundledModels => '没有内置模型';

  @override
  String get settingsModelOriginOnline => '在线';

  @override
  String get settingsModelOriginBundled => '内置';

  @override
  String get settingsModelOriginManual => '手动';

  @override
  String get settingsRemoveManualModelConfirmTitle => '删除此手动模型？';

  @override
  String get settingsRemoveManualModelConfirmBody =>
      '此操作不可撤销。模型会离开有效目录，其连接方式和压缩阈值覆盖会被清除。历史调用、账单和会话费用保持不变。';

  @override
  String get settingsRemoveManualModelConfirmAction => '删除';

  @override
  String get settingsRemoveManualModelFailed => '无法删除此手动模型。';

  @override
  String get settingsManualModelIdConflict => '该标识已存在于在线或内置目录中。';

  @override
  String settingsBundledModels(int count) {
    return '$count 个内置模型';
  }

  @override
  String get settingsDefaultBadge => '默认';

  @override
  String get settingsReadyBadge => '就绪';

  @override
  String get settingsSetupBadge => '待配置';

  @override
  String get settingsUsageTitle => '用量';

  @override
  String settingsUsageUpdated(String updatedAt) {
    return '更新于 $updatedAt';
  }

  @override
  String get settingsUsageAvailableBalance => '可用余额';

  @override
  String get settingsUsageBalanceUnavailable => '余额不可用';

  @override
  String get settingsUsageBalanceSufficient => '余额充足';

  @override
  String get settingsUsageBalanceInsufficient => '余额不足';

  @override
  String get settingsUsageTotalBalance => '总可用余额';

  @override
  String get settingsUsageGrantedBalance => '赠金余额';

  @override
  String get settingsUsageToppedUpBalance => '充值余额';

  @override
  String settingsUsageGranted(String amount) {
    return '赠送 $amount';
  }

  @override
  String settingsUsageToppedUp(String amount) {
    return '充值 $amount';
  }

  @override
  String get settingsUsageRefreshing => '正在刷新用量…';

  @override
  String get settingsUsageChecking => '正在检查用量…';

  @override
  String get settingsUsageCheckingShort => '正在检查用量';

  @override
  String get settingsUsageNotLoaded => '用量未加载';

  @override
  String get settingsUsageUnsupported => '不支持';

  @override
  String get settingsUsageNotSupported => '不支持用量查询';

  @override
  String get settingsUsageMissingKey => '缺少密钥';

  @override
  String get settingsUsageFailed => '用量查询失败';

  @override
  String get settingsUsageQueryFailed => '用量查询失败';

  @override
  String get settingsUsageApiKeyMissing => '未配置账号 API 密钥';

  @override
  String settingsUsageUnsupportedForAccount(String accountName) {
    return '$accountName 不支持用量查询';
  }

  @override
  String get settingsUsageNotChecked => '未检查';

  @override
  String get settingsUsageUnavailable => '用量不可用';

  @override
  String get settingsUsageError => '无法加载用量';

  @override
  String get settingsUsageNoQuota => '没有返回额度详情。';

  @override
  String get settingsUsageTools => '工具';

  @override
  String get settingsUsageToken => '词元用量';

  @override
  String get settingsUsageSpend => '花费';

  @override
  String get settingsUsageRemaining => '剩余';

  @override
  String get settingsUsageUsed => '已用';

  @override
  String get settingsUsageFiveHourQuota => '5 小时额度';

  @override
  String get settingsUsageWeeklyQuota => '每周额度';

  @override
  String get settingsUsageMcpQuota => 'MCP 额度';

  @override
  String get settingsUsageQuota => '额度';

  @override
  String settingsUsageQuotaRemaining(String remaining, String total) {
    return '剩余 $remaining / $total';
  }

  @override
  String settingsUsageQuotaUsed(String current, String total) {
    return '已用 $current / $total';
  }

  @override
  String settingsUsagePercentRemaining(String percent) {
    return '剩余 $percent';
  }

  @override
  String settingsUsageReset(String time) {
    return '将于 $time 重置';
  }

  @override
  String get settingsInstructionsTitle => '指令';

  @override
  String get settingsInstructionsSubtitle => '注入到每轮对话；停止输入后自动保存。';

  @override
  String get settingsBaseInstructions => '基础指令';

  @override
  String get settingsDeveloperInstructions => '开发者指令';

  @override
  String get settingsUserContext => '用户上下文';

  @override
  String get settingsInstructionHint => '在这里添加项目指导';

  @override
  String get settingsSkillsTitle => '技能';

  @override
  String get settingsSkillsSubtitle => '禁用干扰较多的技能，或发现项目、用户与系统技能目录。';

  @override
  String get settingsDiscover => '发现';

  @override
  String get settingsDiscovering => '正在发现';

  @override
  String get settingsFilterSkills => '过滤技能';

  @override
  String get settingsOpenProjectToDiscoverSkills => '打开项目以发现技能';

  @override
  String get settingsNoSkillsMatchFilter => '没有匹配的技能';

  @override
  String get settingsSkillsDiscoverySources => '技能会从当前工作区以及已配置的用户/系统来源中发现。';

  @override
  String get settingsClearSearchOrDiscoverAgain => '清空搜索，或重新发现技能。';

  @override
  String get settingsNoSkillsTitle => '没有找到技能';

  @override
  String get settingsNoSkillsMessage => '换个过滤条件，或重新发现技能。';

  @override
  String get settingsRoleExplorerDescription => '探索代码并收集上下文。';

  @override
  String get settingsRolePlannerDescription => '理解需求、制定计划、协调子代理、整合与验证结果。';

  @override
  String get settingsRoleExecutorDescription => '落实修改并运行工具。';

  @override
  String get settingsRoleWorktreeExecutorDescription =>
      '在隔离的 Git 工作树中落实修改并运行工具。';

  @override
  String get settingsRoleReviewerDescription => '审查结果并验证风险。';

  @override
  String get settingsRoleFallbackDescription => '智能体角色';

  @override
  String get settingsModelField => '模型';

  @override
  String get settingsMcpTitle => 'MCP';

  @override
  String get settingsMcpSubtitle => 'MCP 服务器与内联端点。';

  @override
  String get settingsMcpRefresh => '刷新';

  @override
  String get settingsMcpReconnect => '重新连接';

  @override
  String get settingsMcpResetAll => '全部重置';

  @override
  String get settingsMcpResetConfirmTitle => '重置全部 MCP 服务器？';

  @override
  String get settingsMcpResetConfirmBody =>
      '将重新构建所有已配置的 MCP 连接；当前进行中的任务继续使用重置前的连接。';

  @override
  String get settingsMcpResetConfirmAction => '全部重置';

  @override
  String get settingsEndpoint => '端点';

  @override
  String get settingsMcpEmptyTitle => '没有 MCP 服务器';

  @override
  String get settingsMcpEmptyMessage => '已配置的 MCP 服务器会显示在这里。';

  @override
  String get settingsLspTitle => '语言服务器';

  @override
  String get settingsLspSubtitle => '显示项目最近一次语言服务器状态，可刷新、探测、修复或重置。';

  @override
  String get settingsLspRefresh => '刷新';

  @override
  String get settingsLspProbe => '探测';

  @override
  String get settingsLspRepair => '修复';

  @override
  String get settingsLspReset => '重置';

  @override
  String get settingsLspResetWorkspace => '重置工作区';

  @override
  String get settingsLspActivityIndexing => '正在索引';

  @override
  String get settingsLspActivityBusy => '忙碌';

  @override
  String get settingsLspEmptyTitle => '没有语言服务器';

  @override
  String get settingsLspEmptyMessage => '打开受支持的项目后，系统会自动关联相应的语言服务器。';

  @override
  String get settingsSecurityTitle => '安全';

  @override
  String get settingsSecuritySubtitle => '选择此工作区默认审批姿态。';

  @override
  String get settingsSecurityModeSubtitle =>
      '工具执行权限固定为完全访问；工作区与 worktree 边界不因此放宽。';

  @override
  String settingsCurrentMode(String mode) {
    return '当前：$mode';
  }

  @override
  String get settingsWorkspaceBoundary => '工作区边界策略保持不变。';

  @override
  String get settingsGeneralTitle => '通用';

  @override
  String get settingsGeneralSubtitle => '界面偏好保存到本地设置存储。';

  @override
  String get settingsFollowActiveTurn => '跟随当前轮次';

  @override
  String get settingsFollowActiveTurnSubtitle => '让新的时间线输出始终停留在最新轮次。';

  @override
  String get settingsCompactTimeline => '紧凑时间线';

  @override
  String get settingsCompactTimelineSubtitle => '减少消息间距，适合更密集阅读。';

  @override
  String get settingsWebSearchTitle => '网页搜索';

  @override
  String get settingsWebSearchSubtitle => '通过符合条件的 OpenAI 账户执行搜索；修改从下一轮次起生效。';

  @override
  String get settingsWebSearchConfiguredMode => '已配置模式';

  @override
  String get settingsWebSearchEffectiveMode => '有效模式';

  @override
  String get settingsWebSearchAccount => 'OpenAI 账号';

  @override
  String get settingsWebSearchModel => '搜索模型';

  @override
  String get settingsWebSearchMode => '模式';

  @override
  String get settingsWebSearchModeDisabled => '禁用';

  @override
  String get settingsWebSearchModeCached => '缓存';

  @override
  String get settingsWebSearchModeIndexed => '索引';

  @override
  String get settingsWebSearchModeLive => '实时';

  @override
  String get settingsWebSearchContextSize => '上下文大小';

  @override
  String get settingsWebSearchContextLow => '低';

  @override
  String get settingsWebSearchContextMedium => '中';

  @override
  String get settingsWebSearchContextHigh => '高';

  @override
  String get settingsServiceDefault => '服务默认值';

  @override
  String get settingsWebSearchAllowedDomains => '允许的域名';

  @override
  String get settingsWebSearchDomainsHint => 'example.com, docs.example.com';

  @override
  String get settingsWebSearchCountry => '国家';

  @override
  String get settingsWebSearchRegion => '地区';

  @override
  String get settingsWebSearchCity => '城市';

  @override
  String get settingsWebSearchTimezone => '时区';

  @override
  String get settingsWebSearchAvailable => '可用';

  @override
  String get settingsWebSearchDisabled => '已禁用';

  @override
  String get settingsWebSearchMissingCredential => '缺少凭证';

  @override
  String get settingsWebSearchUnsupportedAccount => '账号不支持';

  @override
  String get settingsWebSearchUnsupportedModel => '模型不支持';

  @override
  String get settingsWebSearchMissingCredentialReason =>
      '没有从 OpenAI 账号模板创建且凭证有效的账号，远程网页搜索已完全禁用。';

  @override
  String get settingsWebSearchUnsupportedAccountReason => '当前账号未提供这一路网页搜索后端。';

  @override
  String get settingsWebSearchUnsupportedModelReason => '当前路由无法提供函数工具或托管网页搜索。';

  @override
  String get settingsNotAvailable => '不可用';

  @override
  String get settingsSaveWebSearch => '保存网页搜索';

  @override
  String get settingsWebSearchUnsaved => '有未保存的搜索设置';

  @override
  String get settingsDeepSeekWebSearchTitle => 'DeepSeek 原生联网搜索';

  @override
  String get settingsDeepSeekWebSearchSubtitle =>
      '先由其它可用搜索优先处理；仅当其它搜索未配置、不可用或调用失败时，才由 DeepSeek 联网搜索兜底；搜索与抓取均按请求次数计费。';

  @override
  String get settingsDeepSeekWebSearchAccount => 'DeepSeek 账号';

  @override
  String get settingsDeepSeekWebSearchConfigured => '搜索已配置';

  @override
  String get settingsDeepSeekWebSearchEffective => '搜索当前有效';

  @override
  String get settingsDeepSeekWebSearchEnabled => '已启用';

  @override
  String get settingsDeepSeekWebSearchEnableLabel => '联网搜索';

  @override
  String get settingsDeepSeekWebFetchEnableLabel => '网页抓取';

  @override
  String get settingsDeepSeekWebFetchConfigured => '抓取已配置';

  @override
  String get settingsDeepSeekWebFetchEffective => '抓取当前有效';

  @override
  String get settingsStudioUpdateTitle => '糊来帮更新';

  @override
  String settingsStudioUpdateDisabled(String version) {
    return '当前版本 $version。仅 Windows 正式版会自动检查更新。';
  }

  @override
  String settingsStudioUpdateCurrent(String version) {
    return '当前版本：$version';
  }

  @override
  String settingsStudioUpdateChecking(String version) {
    return '当前版本 $version，正在检查更新…';
  }

  @override
  String settingsStudioUpdateLatest(String version) {
    return '当前版本 $version 已是最新版。';
  }

  @override
  String settingsStudioUpdateAvailable(String current, String latest) {
    return '已安装 $current，可升级到 $latest。';
  }

  @override
  String settingsStudioUpdateDownloading(String version, int progress) {
    return '正在下载 $version：$progress%';
  }

  @override
  String settingsStudioUpdateVerifying(String version) {
    return '正在验证 $version…';
  }

  @override
  String settingsStudioUpdateInstallerLaunched(String version) {
    return '$version 安装程序已启动。';
  }

  @override
  String settingsStudioUpdateFailed(String error) {
    return '更新失败：$error';
  }

  @override
  String get settingsStudioUpdatePreparing => '正在准备更新…';

  @override
  String get settingsStudioUpdateWhenReady => '下载完成后安装并重启';

  @override
  String get settingsStudioUpdateCancelling => '正在取消更新…';

  @override
  String get settingsStudioUpdateCancelled => '已取消更新，可随时重试。';

  @override
  String get settingsStudioUpdateCheck => '检查更新';

  @override
  String get settingsStudioUpdateInstall => '下载并重启更新';

  @override
  String get settingsStudioUpdateRestart => '安装并重启';

  @override
  String settingsStudioUpdateReady(String version) {
    return '$version 已下载，将在关闭糊来帮后自动安装。';
  }

  @override
  String get settingsStudioUpdateReleaseNotes => '发行说明';

  @override
  String get timelineWebSearchTitle => '网页搜索';

  @override
  String get timelineWebSearchSearching => '正在搜索网页';

  @override
  String get timelineWebSearchOpening => '正在打开网页';

  @override
  String get timelineWebSearchFinding => '正在页内查找';

  @override
  String get timelineWebSearchSearched => '已搜索网页';

  @override
  String get timelineWebSearchOpened => '已打开网页';

  @override
  String get timelineWebSearchFound => '已查找页面内容';

  @override
  String get timelineWebSearchFailed => '网页搜索失败';

  @override
  String get timelineWebSearchOpenFailed => '打开网页失败';

  @override
  String get timelineWebSearchFindFailed => '页内查找失败';

  @override
  String get timelineWebSearchResults => '结果链接';

  @override
  String get timelineLspQueryTitle => 'LSP 查询';

  @override
  String timelineLspQueryTitleWithDetail(String detail) {
    return 'LSP 查询 · $detail';
  }

  @override
  String get timelineLspCapabilitiesTitle => 'LSP 能力';

  @override
  String get modalityText => '文本';

  @override
  String get modalityImage => '视觉';

  @override
  String get modalityAudio => '音频';

  @override
  String get modalityVideo => '视频';

  @override
  String get modalityFile => '文件';

  @override
  String get composerAddUrlTitle => '添加 URL';

  @override
  String get composerAddUrlConfirm => '添加';

  @override
  String get composerAttachmentAddTooltip => '添加附件';

  @override
  String get composerAttachmentUnsupportedTooltip => '当前模型不支持附件';

  @override
  String get composerAttachmentPickLocal => '选择本地文件';

  @override
  String get composerAttachmentRemoveTooltip => '移除';

  @override
  String get composerClipboardImageUnsupported => '当前模型不支持粘贴图片。';

  @override
  String get composerClipboardReadFailed => '无法读取剪贴板图片。';

  @override
  String settingsModelOutputCapabilities(String capabilities) {
    return '输出：$capabilities';
  }

  @override
  String get settingsAgentsTitle => '智能体配置';

  @override
  String get settingsAgentsSubtitle =>
      '子代理可按用途配置和启用；目录模式仅限制内置工具的文件写入，不是操作系统沙箱。';

  @override
  String get settingsAgentsAddUserProfile => '添加用户智能体配置';

  @override
  String get settingsAgentsEditTooltip => '编辑';

  @override
  String get settingsAgentsRecoveryTitle => '恢复';

  @override
  String settingsWorktreeBase(String commit) {
    return '基线提交 $commit';
  }

  @override
  String settingsWorktreeHead(String commit) {
    return '当前提交 $commit';
  }

  @override
  String get settingsWorktreeHeadUnavailable => '当前提交暂不可用';

  @override
  String settingsWorktreeChangedFiles(String files) {
    return '变更文件：$files';
  }

  @override
  String get settingsWorktreeCleanup => '清理工作树（保留分支）';

  @override
  String get settingsWorktreeOwnerSession => '会话工作树';

  @override
  String get settingsWorktreeOwnerChild => '子智能体工作树';

  @override
  String get settingsAgentProfileAddTitle => '添加用户智能体配置';

  @override
  String get settingsAgentProfileEditTitle => '编辑用户智能体配置';

  @override
  String get settingsAgentProfileIdField => '智能体 ID';

  @override
  String get settingsAgentProfileDisplayNameField => '显示名称';

  @override
  String get settingsAgentProfileDescriptionField => '介绍';

  @override
  String get settingsAgentProfileWhenToUseField => '适用任务';

  @override
  String get settingsAgentProfileInstructionsField => '系统指令';

  @override
  String get settingsAgentProfileAccountField => '账号';

  @override
  String get settingsAgentProfileEffortDefault => '使用模型默认值';

  @override
  String get settingsAgentProfileWorkspaceModeField => '工作区模式';

  @override
  String get settingsAgentWorkspaceModeUnrestricted => '不受限';

  @override
  String get settingsAgentWorkspaceModeDirectory => '目录';

  @override
  String get settingsAgentWorkspaceModeWorktree => '工作树';

  @override
  String get settingsAgentWorkspaceModeReview => '跟随被审';

  @override
  String get settingsAgentProfileWorkspaceDirectoryHint =>
      '目录模式只约束项目内由内置工具执行的文件写入，并非操作系统级沙箱；命令行操作、Git 和 MCP 仍可能绕过此限制。';

  @override
  String get settingsAgentProfileWorkspaceReviewHint =>
      '跟随被审模式在派发时必须提供被审智能体 ID，工作区与访问边界与被审者保持一致；由系统指令约束只审查、不修改代码。';

  @override
  String get settingsAgentProfileEnabledTitle => '启用';

  @override
  String get settingsAgentProfileEnabledSubtitle =>
      '禁用后仍保留 TOML 文件，但不会出现在智能体工具目录中。';

  @override
  String get settingsAgentProfileSave => '原子保存 TOML';

  @override
  String get settingsAgentProfileRequired => '必填';

  @override
  String get settingsServiceCapabilitiesTitle => '服务能力';

  @override
  String get settingsCapabilitySourceField => '能力来源';

  @override
  String get settingsCapabilitySourceTemplate => '跟随模板默认';

  @override
  String get settingsCapabilitySourceExplicit => '显式覆盖';

  @override
  String get settingsHostedWebSearchField => '托管网页搜索';

  @override
  String get settingsHostedWebSearchDialectField => '托管网页搜索方言';

  @override
  String get settingsStandaloneWebSearchField => '独立网页搜索';

  @override
  String get settingsProgrammaticToolCallingField => '程序化工具调用';

  @override
  String get settingsCapabilityEnabled => '已启用';

  @override
  String get settingsCapabilityDisabled => '已禁用';

  @override
  String get settingsDefaultConnectionField => '默认连接';

  @override
  String get settingsCurrentConnectionField => '当前连接';

  @override
  String get settingsSupportedConnectionsLabel => '支持的连接';

  @override
  String get settingsAgentRoutesTitle => '系统智能体模型路由';

  @override
  String get settingsStateChecking => '检查中';

  @override
  String get settingsStateAvailable => '可用';

  @override
  String get settingsStateUnavailable => '不可用';

  @override
  String get settingsStateDisabled => '已禁用';

  @override
  String get settingsMcpStateMissingCredential => '缺少凭据';

  @override
  String get settingsLspActivityIdle => '空闲';

  @override
  String get roleExplorer => '探索者';

  @override
  String get rolePlanner => '主智能体';

  @override
  String get roleExecutor => '执行者';

  @override
  String get roleWorktreeExecutor => '工作树执行者';

  @override
  String get roleReviewer => '审查者';

  @override
  String get roleEmpty => '智能体';

  @override
  String get settingsNoCharge => '不计费';

  @override
  String get settingsNoChargeHelp =>
      '开启：声明此账号之后的模型调用不计费。关闭：清除计费类别覆盖，恢复自动推导。词元、缓存、性能统计和模型参考价格仍保留；其他类别在价格和用量可用时估算费用。';

  @override
  String get settingsModelAdvanced => '模型可选设置';

  @override
  String get settingsContextBudget => '上下文预算（词元）';

  @override
  String get settingsOutputBudget => '最大输出（词元）';

  @override
  String get settingsModelAutoCompactTitle => '上下文压缩阈值';

  @override
  String get settingsModelAutoCompactRestore => '恢复自动';

  @override
  String get settingsModelAutoCompactSaving => '正在自动应用…';

  @override
  String get settingsModelAutoCompactSaveFailed => '应用失败，已保留输入。';

  @override
  String get settingsModelAutoCompactRetry => '重试';

  @override
  String get settingsModelAutoCompactOverrideLabel => '配置方式';

  @override
  String get settingsModelAutoCompactEffectiveLabel => '生效';

  @override
  String get settingsModelAutoCompactUsingDefault => '自动';

  @override
  String get settingsModelAutoCompactInputLabel => '阈值（词元）';

  @override
  String get settingsModelAutoCompactInvalid => '请输入正整数词元数。';

  @override
  String get settingsModelAutoCompactHelp => '实际阈值不超过上下文容量的 90%，并预留最大输出预算。';

  @override
  String get settingsModelAutoCompactUnknownCapacity => '上下文容量未知，无法计算自动压缩阈值。';

  @override
  String get settingsPriceInput => '输入';

  @override
  String get settingsPriceOutput => '输出';

  @override
  String get settingsPriceCacheRead => '缓存读取';

  @override
  String get settingsPriceCacheWrite => '缓存写入';

  @override
  String get settingsSystemAgentsGroup => '系统子代理';

  @override
  String get settingsUserAgentsGroup => '用户子代理';

  @override
  String get settingsAppearanceGroup => '界面与会话';

  @override
  String get settingsNetworkGroup => '搜索与联网';

  @override
  String get settingsUpdatesGroup => '应用更新';

  @override
  String get settingsModelsGroup => '模型与智能体';

  @override
  String get settingsExtensionsGroup => '工具与服务';

  @override
  String get settingsPreferencesGroup => '偏好设置';

  @override
  String get settingsFilterAgents => '筛选智能体';

  @override
  String get timelineToolArguments => '参数';

  @override
  String get timelineToolOutput => '输出';

  @override
  String get costPurposeMain => '主对话';

  @override
  String get costPurposeSummary => '摘要';

  @override
  String get costPurposeReview => '审查';

  @override
  String get costPurposeTitle => '标题';

  @override
  String get costPurposeUnknown => '未知用途';

  @override
  String get timelineRawRecord => '原始历史记录';

  @override
  String get timelineRuntimeNotice => '运行时说明';

  @override
  String get timelineRuntimeNoticeDetail => '本次会话在被停止后继续执行。这条是运行时说明，不含用户输入。';

  @override
  String get sidebarSearch => '搜索项目与会话';

  @override
  String get sidebarAll => '全部';

  @override
  String get sidebarRunning => '进行中';

  @override
  String get sidebarAttention => '待处理';

  @override
  String get sidebarAddProject => '添加项目';

  @override
  String get sidebarLocalProject => '本地项目';

  @override
  String get sidebarLocalHint => '选择这台电脑上的文件夹';

  @override
  String get sidebarRemoteProject => '远程项目';

  @override
  String get sidebarRemoteHint => '通过 SSH 连接远程工作目录';

  @override
  String get sidebarContinue => '继续';

  @override
  String get sidebarBack => '返回';

  @override
  String get sidebarConnect => '连接并选择目录';

  @override
  String get sidebarSaveConnect => '保存并连接';

  @override
  String get sidebarSearchConnections => '搜索已配置连接';

  @override
  String get sidebarNoConnections => '还没有远程配置';

  @override
  String get sidebarNewConnection => '新建远程配置';

  @override
  String get sidebarNoResults => '没有匹配的项目或会话';

  @override
  String get sidebarEmptyProject => '还没有会话，点击项目右侧 ＋ 开始';

  @override
  String get sidebarEarlier => '查看更早会话';

  @override
  String get sidebarArchived => '已归档';

  @override
  String get sidebarRestore => '取消归档';

  @override
  String get sidebarPin => '置顶';

  @override
  String get sidebarUnpin => '取消置顶';

  @override
  String get sidebarNavigation => '项目导航';

  @override
  String get sidebarResize => '调整侧栏宽度；方向键调整，Home 恢复默认';

  @override
  String get planResize => '调整计划详情宽度；方向键调整，Home 恢复默认';

  @override
  String get sidebarLocal => '本地';

  @override
  String get sidebarDetailUpdatedNow => '刚刚更新';

  @override
  String sidebarDetailUpdatedMinutesAgo(int count) {
    return '$count 分钟前更新';
  }

  @override
  String sidebarDetailUpdatedHoursAgo(int count) {
    return '$count 小时前更新';
  }

  @override
  String sidebarDetailUpdatedDaysAgo(int count) {
    return '$count 天前更新';
  }

  @override
  String get sidebarNotChecked => '未检测';

  @override
  String get sidebarConnectionSaved => '配置已保存；连接失败，可修改后重试';

  @override
  String get sidebarCopyPath => '复制路径';

  @override
  String get sidebarRetry => '重试';

  @override
  String get settingsSshRemoteHelper => '远程助手';

  @override
  String statusThroughputValue(String value) {
    return '$value 词元/秒';
  }

  @override
  String get statusThroughputUnavailable => '—';

  @override
  String get workflowStatePlanning => '规划';

  @override
  String get workflowStateEditingDocuments => '编辑文档';

  @override
  String get workflowStateWorking => '实施';

  @override
  String get workflowStateIntegrating => '集成';

  @override
  String get workflowStateReviewing => '审查';

  @override
  String get workflowStateCompleted => '已完成';

  @override
  String get workflowStateStopped => '已停止';

  @override
  String get workflowModeSimple => '简洁';

  @override
  String get workflowModeTask => '任务';

  @override
  String get attachmentFallback => '附件';

  @override
  String get timelineAgentTimedOut => '已超时';

  @override
  String timelineToolUnknownStatus(String name, String status) {
    return '$name · $status';
  }

  @override
  String get timelineTodoStatusUnknown => '未知';

  @override
  String get settingsApiKeyOptional => 'API 密钥（可选）';

  @override
  String get modelProtocolResponses => 'Responses（响应式接口）';

  @override
  String get modelProtocolChatCompletions => 'Chat Completions（对话补全）';

  @override
  String get modelConnectionWebSocket => 'WS（WebSocket 长连接）';

  @override
  String get modelConnectionHttp => 'HTTP';

  @override
  String get settingsProtocolChatCompletionsHttp =>
      'Chat Completions（对话补全，HTTP）';

  @override
  String get settingsProtocolResponsesHttp => 'Responses（响应式接口，HTTP）';

  @override
  String settingsAgentRouteUnavailable(String route) {
    return '$route（不可用）';
  }

  @override
  String settingsPriceTierUnit(String currency) {
    return '每 100 万词元 $currency';
  }

  @override
  String get threadStatusIdle => '空闲';

  @override
  String get threadStatusCancelling => '正在停止当前执行';

  @override
  String get threadStatusClosed => '已关闭';

  @override
  String get toolStatusAwaitingApproval => '等待授权';

  @override
  String get toolStatusFailed => '失败';

  @override
  String get toolStatusDenied => '已拒绝';

  @override
  String get toolStatusCancelled => '已取消';

  @override
  String get toolStatusCancelling => '正在取消';

  @override
  String get settingsAccountCatalogUnavailable => '无法获取账号目录。';

  @override
  String get settingsAccountTemplateUnavailable => '无法获取账号模板。';

  @override
  String get settingsAccountMissingCredential => '缺少凭据';

  @override
  String get settingsSshStateDisconnected => '未连接';

  @override
  String get settingsSshStateConnecting => '连接中';

  @override
  String get settingsSshStateWaitingForInput => '等待输入';

  @override
  String get settingsSshStateReconnecting => '重新连接中';

  @override
  String get settingsSshStateFailed => '连接失败';

  @override
  String get settingsWorktreeStatePrepared => '已准备';

  @override
  String get settingsWorktreeStateActive => '使用中';

  @override
  String get settingsWorktreeStatePreserved => '已保留';

  @override
  String get settingsWorktreeStateCleanupRequested => '已请求清理';

  @override
  String get settingsWorktreeStateCleaned => '已清理';

  @override
  String get settingsWorktreeDirty => '有改动';

  @override
  String get settingsWorktreeClean => '无未提交改动';

  @override
  String get settingsWorktreeDirtyUnknown => '改动状态未知';

  @override
  String get settingsWorktreeChangedFilesUnknown => '尚未确认变更文件，请重试检查。';

  @override
  String get settingsWorktreeInspectionAvailable => '工作树已核实';

  @override
  String get settingsWorktreeInspectionMissing => '工作树缺失';

  @override
  String get settingsWorktreeInspectionIdentityMismatch => '工作树身份不匹配';

  @override
  String get settingsWorktreeInspectionUnavailable => '暂时无法检查';

  @override
  String get settingsWorktreeRetry => '重试检查';

  @override
  String get startupPreparing => '正在准备应用…';

  @override
  String get startupStorage => '正在打开本地数据…';

  @override
  String get startupConfiguration => '正在读取配置…';

  @override
  String get startupProjects => '正在读取项目…';

  @override
  String get startupResources => '正在准备技能资源…';

  @override
  String get startupState => '正在加载工作区…';

  @override
  String get workspaceLoading => '正在加载会话历史…';

  @override
  String get recoveryChecking => '正在检查历史会话和工作区…';

  @override
  String get recoveryCheckFailed => '历史会话和工作区检查未完成';

  @override
  String get agentRoleRetired => '该子代理角色已停用，仅可查看历史记录。';

  @override
  String get conversationActivityPreparing => '准备中';

  @override
  String get conversationActivityRunningTool => '执行中';

  @override
  String get conversationActivitySaveFailed => '保存故障';

  @override
  String get conversationActivitySavePaused => '保存已暂停';

  @override
  String get conversationActivityStoragePressure => '存储受限';

  @override
  String get conversationActivityResumeReady => '已保存，等待继续执行';

  @override
  String get conversationActivityResumeRequired => '等待保存恢复';

  @override
  String get conversationActivityStopping => '停止中';

  @override
  String get startupWaiting => '正在等待初始化步骤完成…';

  @override
  String get startupClosing => '正在关闭本地数据…';

  @override
  String get startupBackingUp => '正在备份无法恢复的数据…';

  @override
  String get startupResetting => '正在重建初始配置…';

  @override
  String get startupServices => '正在启动服务…';

  @override
  String get startupRecoveredNotice => '已备份无法恢复的数据，并恢复初始配置。备份位置：';

  @override
  String get settingsModelCatalogDefault => '内置模型列表';

  @override
  String get settingsModelCatalogCached => '上次成功的模型列表';

  @override
  String get settingsModelCatalogOnline => '该账号返回的模型列表';

  @override
  String get settingsModelCatalogChecked => '上次检查';

  @override
  String get settingsModelCatalogFailed => '启动时模型同步失败，继续使用当前列表。';

  @override
  String get settingsModelCatalogCacheWarning => '无法加载已保存的模型列表，当前使用内置列表。';

  @override
  String get settingsModelCatalogEmpty => '该账号没有模型。';

  @override
  String get settingsModelCatalogRestartHint => '重启应用可重新同步。';

  @override
  String get timelineActivityTitle => '思考与工具';

  @override
  String get timelineContextCompacted => '上下文已压缩';

  @override
  String timelineCompactionDetail(int before, int after) {
    return '压缩前 $before，压缩后 $after 词元';
  }

  @override
  String get timelineUserInputAnswered => '用户已回答';

  @override
  String get timelineUserInputAwaiting => '等待你的回答';

  @override
  String get timelineUserInputCancelled => '问答已取消';

  @override
  String timelineUserInputQuestionCount(int count) {
    return '$count 个问题';
  }

  @override
  String get timelineUserInputYourAnswer => '你的回答';

  @override
  String get timelineUserInputNoAnswer => '未提供回答';

  @override
  String get timelineUserInputSecretHidden => '敏感回答已隐藏';

  @override
  String get settingsModelParametersUnknown => '模型参数未知';

  @override
  String get settingsModelPriceUnknown => '价格未知';

  @override
  String modelTextFilterExcluded(String model, String reasons) {
    return '$model：不符合文本筛选条件（$reasons）';
  }

  @override
  String get modelTextInputUnsupported => '不支持文本输入';

  @override
  String get modelTextOutputUnsupported => '不支持文本输出';

  @override
  String get modelContextWindowUnknown => '上下文大小未知';

  @override
  String get modelTextFilterEmpty => '没有符合文本条件的模型，请在账号设置中查看参数';

  @override
  String get modeEditorTitle => '工作模式';

  @override
  String get modeEditorNewMode => '新建模式';

  @override
  String get modeEditorImportJson => '导入 JSON';

  @override
  String get modeEditorSearchHint => '查找名称或标识';

  @override
  String get modeEditorBuiltInGroup => '系统内置';

  @override
  String get modeEditorMyModesGroup => '我的模式';

  @override
  String get modeEditorNoMatches => '没有匹配的工作模式。';

  @override
  String get modeEditorCatalogReadOnlyHint => '系统模式只读。复制后可自定义阶段与路径。';

  @override
  String get modeEditorReadOnly => '只读';

  @override
  String get modeEditorUnsaved => '未保存';

  @override
  String get modeEditorUndo => '撤销';

  @override
  String get modeEditorRedo => '重做';

  @override
  String get modeEditorReload => '重新加载';

  @override
  String get modeEditorDuplicate => '复制';

  @override
  String get modeEditorDeleteMode => '删除模式';

  @override
  String get modeEditorSave => '保存';

  @override
  String get modeEditorTabFlow => '流程图';

  @override
  String get modeEditorTabJson => 'JSON 配置';

  @override
  String get modeEditorTabSettings => '模式设置';

  @override
  String get modeEditorTabPreview => '运行预演';

  @override
  String get modeEditorDraftUnsaved => '草稿未保存';

  @override
  String get modeEditorSelectOrCreate => '选择或新建一个工作模式。';

  @override
  String modeEditorOpenNotice(String id) {
    return '已打开 $id';
  }

  @override
  String modeEditorSaveValidationIssues(int count) {
    return '保存前校验发现 $count 个问题。';
  }

  @override
  String modeEditorPreSaveValidationFailed(String error) {
    return '保存前校验失败：$error';
  }

  @override
  String get modeEditorSaved => '模式已保存，将从下一轮开始生效。';

  @override
  String get modeEditorSaveFailed => '保存失败。';

  @override
  String get modeEditorReloaded => '已重新读取模式定义。';

  @override
  String get modeEditorReloadFailed => '重新加载失败。';

  @override
  String get modeEditorDeleteFailed => '删除失败。';

  @override
  String get modeEditorDeleted => '模式已删除，会话历史保留。';

  @override
  String get modeEditorCopySuffix => '副本';

  @override
  String get modeEditorCopyCreated => '已创建副本草稿，保存后出现在模式目录。';

  @override
  String get modeEditorDraftCreated => '已创建草稿。编辑并通过校验后保存。';

  @override
  String modeEditorImportReadFailed(String error) {
    return '无法读取模式 JSON：$error';
  }

  @override
  String get modeEditorImportObjectRequired => '模式 JSON 必须是对象。';

  @override
  String get modeEditorInvalidModeId => '模式标识必须形如 mode.example。';

  @override
  String get modeEditorBuiltInCannotOverwrite => '系统模式不可覆盖。';

  @override
  String get modeEditorImportedDraft => '配置已读取为草稿，保存后发布到模式目录。';

  @override
  String get modeEditorJsonCopied => '模式 JSON 已复制。';

  @override
  String modeEditorSchemaReadFailed(String error) {
    return '无法读取 Schema：$error';
  }

  @override
  String get modeEditorValidationPassed => '校验通过。';

  @override
  String modeEditorIssuesFound(int count) {
    return '发现 $count 个问题。';
  }

  @override
  String modeEditorValidationFailed(String error) {
    return '校验失败：$error';
  }

  @override
  String get modeEditorJsonApplied => 'JSON 已应用到当前草稿。';

  @override
  String get modeEditorJsonApplyFailed => 'JSON 无法应用。';

  @override
  String get modeEditorJsonApplyFix => 'JSON 无法应用，请先修正语法或字段。';

  @override
  String get modeEditorPreviewReasonDefault => '手动确认阶段完成和转换条件';

  @override
  String modeEditorPreviewFailed(String error) {
    return '预演失败：$error';
  }

  @override
  String modeEditorMaxStates(int count) {
    return '最多支持 $count 个状态。';
  }

  @override
  String get modeEditorNewFinalState => '新的结束状态';

  @override
  String get modeEditorNewStage => '新的工作阶段';

  @override
  String get modeEditorFinalStateAdded => '结束状态已添加。请添加进入路径。';

  @override
  String get modeEditorStageAdded => '阶段已添加。请添加进入和后续转换。';

  @override
  String get modeEditorContinueGuardPlaceholder => '满足条件时继续。';

  @override
  String get modeEditorTransitionAdded => '转换已添加，请补充允许转换的条件。';

  @override
  String get modeEditorNeedTwoStates => '至少需要两个状态才能添加转换。';

  @override
  String get modeEditorLayoutReset => '已重新排布。布局不改变工作流定义。';

  @override
  String get modeEditorWorkflowEnabled => '工作流已启用。';

  @override
  String get modeEditorWorkflow => '工作流';

  @override
  String get modeEditorWorkflowGoalText => '按阶段完成当前任务并保留可核对的路径。';

  @override
  String get modeEditorStart => '开始';

  @override
  String get modeEditorStageInstructionsPlaceholder => '说明本阶段需要完成的工作。';

  @override
  String get modeEditorStageCriterionPlaceholder => '本阶段目标已满足。';

  @override
  String get modeEditorDone => '完成';

  @override
  String get modeEditorTransitionGuardPlaceholder => '工作结果已经满足目标。';

  @override
  String get modeEditorPromptDescription => '描述这个工作模式的职责、工作顺序和边界。';

  @override
  String get modeEditorPortIn => '进入';

  @override
  String get modeEditorPortOut => '继续';

  @override
  String get modeEditorGuardRequiredShort => '条件待填写';

  @override
  String get modeEditorDuplicateTransition => '同一起点与目标之间已经存在转换。';

  @override
  String get modeEditorInitialBadge => '初始';

  @override
  String get modeEditorStageAction => '阶段';

  @override
  String get modeEditorFinalLabel => '终态';

  @override
  String get modeEditorTransitionAction => '转换';

  @override
  String get modeEditorValidate => '校验';

  @override
  String get modeEditorAutoLayout => '自动排布';

  @override
  String get modeEditorZoomOut => '缩小';

  @override
  String get modeEditorZoomIn => '放大';

  @override
  String get modeEditorFitView => '适应视图';

  @override
  String get modeEditorFlowInspector => '流程属性';

  @override
  String get modeEditorNoWorkflow => '此模式没有工作流';

  @override
  String get modeEditorNoWorkflowReadOnlyHint => '复制为自定义模式后可以添加阶段和转换。';

  @override
  String get modeEditorNoWorkflowEnableHint => '启用工作流后会添加初始阶段和结束状态，可继续增删。';

  @override
  String get modeEditorEnableWorkflow => '启用工作流';

  @override
  String get modeEditorUnsavedTitle => '草稿尚未保存';

  @override
  String get modeEditorUnsavedBody => '保存当前修改后继续，或放弃这次草稿修改。';

  @override
  String get modeEditorCancel => '取消';

  @override
  String get modeEditorDiscard => '放弃修改';

  @override
  String get modeEditorSaveAndContinue => '保存并继续';

  @override
  String get modeEditorNewWorkMode => '新建工作模式';

  @override
  String get modeEditorModeName => '模式名称';

  @override
  String get modeEditorModeNameHint => '例如：研究报告';

  @override
  String get modeEditorModeNameRequired => '请输入模式名称。';

  @override
  String get modeEditorModeId => '模式标识';

  @override
  String get modeEditorModeIdFormat => '标识必须形如 mode.example，仅含小写字母、数字、- 和 _。';

  @override
  String get modeEditorModeIdExists => '模式标识已存在。';

  @override
  String get modeEditorStartingPoint => '选择起点';

  @override
  String get modeEditorMinimalWorkflow => '最简工作流';

  @override
  String get modeEditorNoWorkflowTemplate => '无工作流';

  @override
  String get modeEditorCreateMode => '创建模式';

  @override
  String get modeEditorImportDialogTitle => '导入模式配置';

  @override
  String get modeEditorImportDialogBody =>
      '粘贴模式 JSON。内置模式不可覆盖；同 ID 的自定义配置会作为待保存草稿打开。';

  @override
  String get modeEditorLoadAsDraft => '读取为草稿';

  @override
  String get modeEditorSchemaDialogTitle => '模式 JSON Schema';

  @override
  String get modeEditorClose => '关闭';

  @override
  String get modeEditorDeleteDialogTitle => '删除这个工作模式？';

  @override
  String modeEditorDeleteDialogBody(String displayName) {
    return '移除「$displayName」的模式定义；不删除会话历史。';
  }

  @override
  String get modeEditorConfirmDelete => '确认删除';

  @override
  String get modeEditorRemoveStateTitle => '删除这个状态？';

  @override
  String modeEditorRemoveStateBody(String title, int transitionCount) {
    return '删除「$title」及相关的 $transitionCount 条转换。可通过撤销恢复。';
  }

  @override
  String get modeEditorDeleteState => '删除状态';

  @override
  String get modeEditorRemoveWorkflowTitle => '移除工作流？';

  @override
  String get modeEditorRemoveWorkflowBody =>
      '模式仍可聊天，但不再提供阶段图和 workflow 工具。保存前可以撤销。';

  @override
  String get modeEditorRemoveWorkflow => '移除工作流';

  @override
  String get modeEditorStateIdInvalid => '标识仅含小写字母、数字、- 和 _。';

  @override
  String get modeEditorStateIdExists => '状态标识已存在。';

  @override
  String get modeEditorRenameStateTitle => '修改状态标识';

  @override
  String get modeEditorStateId => '状态标识';

  @override
  String get modeEditorApply => '应用';

  @override
  String get modeEditorAddTransition => '添加转换';

  @override
  String get modeEditorSourceState => '起点状态';

  @override
  String get modeEditorChooseSource => '请选择起点。';

  @override
  String get modeEditorTargetState => '目标状态';

  @override
  String get modeEditorChooseTarget => '请选择目标。';

  @override
  String get modeEditorTransitionGuard => '何时允许转换';

  @override
  String get modeEditorTransitionGuardHint => '例如：用户确认范围后';

  @override
  String get modeEditorGuardRequiredField => '请填写转换条件。';

  @override
  String get modeEditorCollapse => '收起';

  @override
  String get modeEditorNoWorkflowPeriod => '当前模式没有工作流。';

  @override
  String get modeEditorInspectorSelectHint => '选择画布中的阶段或转换以编辑完整字段。';

  @override
  String get modeEditorRenameId => '修改标识';

  @override
  String get modeEditorStageTitle => '阶段名称';

  @override
  String get modeEditorStageKind => '阶段类型';

  @override
  String get modeEditorAtomicStage => '工作阶段';

  @override
  String get modeEditorFinalState => '结束状态';

  @override
  String get modeEditorInitialStateSwitch => '作为初始状态';

  @override
  String get modeEditorInitialStateLockedHint => '工作流总保留一个初始状态；请在其他阶段启用。';

  @override
  String get modeEditorInitialStateHint => '进入此模式后从该阶段开始。';

  @override
  String get modeEditorStageInstructions => '阶段说明';

  @override
  String get modeEditorCompletionCriteria => '完成标准（每行一条）';

  @override
  String get modeEditorAtomicCriteriaRequired =>
      '工作阶段至少需要一条完成标准，保存前由 Rust 编译器校验。';

  @override
  String get modeEditorOutgoingTransitions => '后续转换';

  @override
  String get modeEditorAdd => '添加';

  @override
  String get modeEditorNoOutgoing => '没有后续转换。';

  @override
  String get modeEditorDeleteTransition => '删除转换';

  @override
  String get modeEditorStateTransition => '状态转换';

  @override
  String get modeEditorTransitionRuleHint => '同一起点与目标之间只允许一条转换；允许多个后继、自环和循环。';

  @override
  String modeEditorValidationIssuesCount(int count) {
    return '$count 个问题';
  }

  @override
  String get modeEditorNotValidated => '尚未校验';

  @override
  String get modeEditorApplyJson => '应用 JSON';

  @override
  String get modeEditorCopyJson => '复制 JSON';

  @override
  String get modeEditorSchemaLabel => 'Schema';

  @override
  String get modeEditorReadOnlyCopyHint => '只读模式可复制或校验';

  @override
  String get modeEditorJsonHint => '模式 JSON 保留六个顶层字段和 editor 布局。';

  @override
  String get modeEditorModeSettingsTitle => '模式设置';

  @override
  String get modeEditorModeSettingsSubtitle => '执行定义与编辑布局分开保存；布局不改变工作流身份。';

  @override
  String get modeEditorDisplayName => '模式名称';

  @override
  String get modeEditorDescription => '模式描述';

  @override
  String get modeEditorOrder => '排序';

  @override
  String get modeEditorRawPrompt => '原始 Prompt';

  @override
  String get modeEditorRawPromptHelper => '这是模式注入的完整提示词，不经过 GUI 改写。';

  @override
  String get modeEditorWorkflowTitle => '工作流名称';

  @override
  String get modeEditorWorkflowGoal => '工作流目标';

  @override
  String get modeEditorInitialStateLabel => '初始状态';

  @override
  String modeEditorWorkflowSummary(int states, int transitions) {
    return '$states 个状态 · $transitions 条转换';
  }

  @override
  String get modeEditorNoWorkflowToolHint => '没有工作流时不会生成阶段图，也不会提供 workflow 工具。';

  @override
  String get modeEditorPreviewUnavailable => '该模式没有工作流，无法运行预演。';

  @override
  String get modeEditorRunPreview => '运行预演';

  @override
  String get modeEditorPreviewSubtitle => '有界重放使用生产 Rust 状态机；预演不修改配置中的初始状态。';

  @override
  String get modeEditorStartPreview => '开始预演';

  @override
  String get modeEditorRestart => '重新开始';

  @override
  String get modeEditorTransitionReason => '转换原因';

  @override
  String get modeEditorTransitionReasonHint => '手动确认阶段完成和转换条件';

  @override
  String get modeEditorTransitionReasonHelper => '推进到后继状态时作为本次转换的原因。';

  @override
  String modeEditorAllowedNextStates(int count) {
    return '允许的下一状态 · $count';
  }

  @override
  String get modeEditorTerminalReached => '已到达终态。重新开始预演不会改写保存的初始状态。';

  @override
  String get modeEditorPreviewIntroText =>
      '从当前 JSON 文档开始预演。每次推进只接受当前状态的一条合法转换，路径与转换历史会保留在本次预演中。';

  @override
  String get modeEditorPreviewAccepted => '预演已接受。';

  @override
  String get modeEditorPreviewRejected => '预演被拒绝。';

  @override
  String get modeEditorCurrentStage => '当前阶段';

  @override
  String get modeEditorPath => '路径';

  @override
  String get modeEditorAdvance => '推进';

  @override
  String get modeEditorPreviewHistory => '本次预演历史';

  @override
  String get modeDeletedUsingSnapshot => '已删除模式使用快照';

  @override
  String get modeDeletedChooseAnother => '该模式已删除，请重新选择';

  @override
  String get modeSnapshotBadge => '快照';

  @override
  String get modeDeletedBadge => '已删除';

  @override
  String get settingsAccountProtocol => '账号协议';

  @override
  String get statisticsGroupTotal => '本组汇总';

  @override
  String get statisticsAllEfforts => '全部强度';

  @override
  String get statisticsEffortBreakdownTitle => '组内思考强度';

  @override
  String get accountProtocolOpenAi => 'OpenAI';

  @override
  String get accountProtocolDeepSeek => 'DeepSeek';

  @override
  String get accountProtocolZhipu => '智谱';

  @override
  String get accountProtocolMiMo => 'MiMo';

  @override
  String get accountProtocolXai => 'xAI';

  @override
  String get accountProtocolCustom => '自定义（OpenAI 兼容）';

  @override
  String get timelineWaitToolsTitle => '等待工具完成';

  @override
  String get timelineWaitMessagesTitle => '等待子代理或新消息';

  @override
  String get timelineWaitTimerTitle => '计时器';

  @override
  String get timelineWaitTimerElapsed => '计时完成';

  @override
  String get timelineWaitReady => '已有等待来源就绪';

  @override
  String get timelineWaitMessagesReady => '已有新消息';

  @override
  String get timelineWaitTimedOut => '等待超时';

  @override
  String get timelineWaitCancelled => '等待已取消';

  @override
  String get timelineWaitFailed => '等待失败';

  @override
  String get timelineWaitInterrupted => '等待已中断';

  @override
  String timelineWaitTargetCount(int count) {
    return '$count 个任务';
  }

  @override
  String get timelineWaitMessageSource => '新消息';

  @override
  String timelineWaitMaxDuration(String duration) {
    return '最多 $duration';
  }

  @override
  String timelineWaitTimerDuration(String duration) {
    return '$duration';
  }

  @override
  String get timelineWaitMessagesMayWake => '新消息可以提前唤醒';

  @override
  String get timelineWaitAnyReadyRule => '任一所选任务或新消息就绪即返回';

  @override
  String get timelineWaitDiagnostics => '诊断信息';

  @override
  String get timelineWaitUnknownStatus => '未知';

  @override
  String get timelineWaitStatusRunning => '运行中';

  @override
  String get timelineWaitStatusSucceeded => '已成功';

  @override
  String get timelineWaitStatusFailed => '已失败';

  @override
  String get timelineWaitStatusCancelled => '已取消';

  @override
  String get timelineWaitStatusInterrupted => '已中断';

  @override
  String get conversationActivityWaitingTools => '等待工具完成';

  @override
  String get conversationActivityWaitingMessages => '等待子代理或新消息';

  @override
  String get conversationActivityWaitingTimer => '计时器';

  @override
  String get settingsModelAutoCompactAdjusted => '已根据模型上下文容量与输出预留调整生效阈值。';

  @override
  String get modelContextParametersInvalid => '上下文参数不一致';

  @override
  String get modelInputBudgetExhausted => '预留输出后没有可用输入容量';

  @override
  String get statusCompactNow => '立即压缩';

  @override
  String get statusCompacting => '正在压缩…';

  @override
  String get statusCompactionFailed => '压缩失败，请重试。';

  @override
  String get settingsModelAutoCompactCustom => '自定义';

  @override
  String get acpAccountPickerTitle => '添加账号';

  @override
  String get acpAccountPickerNativeGroup => '模型 API 账号';

  @override
  String get acpAccountPickerAcpGroup => 'Agent 接入（ACP）';

  @override
  String get acpAccountNoApiKeyHint => '无需 API key，登录由官方程序完成。';

  @override
  String get acpAccountSaveAndConnect => '保存并连接';

  @override
  String acpAccountSavedConnectIncomplete(String reason) {
    return '账号已保存，连接未完成：$reason';
  }

  @override
  String acpAccountSaveFailed(String reason) {
    return '无法保存该接入：$reason';
  }

  @override
  String get acpAccountProviderChip => 'ACP';

  @override
  String get acpAccountScopeNotice => '本版本仅支持账号配置与登录；ACP 聊天与模型选择尚未接入。';

  @override
  String get acpAccountRemoveNotLogout => '删除接入不等于注销官方程序。';

  @override
  String get acpAccountRemoveFailed => '无法删除该接入。';

  @override
  String get acpAuthUnchecked => '尚未检查连接。';

  @override
  String get acpAuthChecking => '正在检查连接…';

  @override
  String get acpAuthRequiredTitle => '需要登录';

  @override
  String get acpAuthRequiredBody => '官方程序报告了以下登录方式。';

  @override
  String get acpAuthMethodLabel => '登录方式';

  @override
  String get acpAuthLogin => '登录';

  @override
  String get acpAuthAuthenticatingTitle => '等待登录';

  @override
  String get acpAuthAuthenticatingBody => '请在官方登录窗口中完成登录；本页会继续跟随同一次登录。';

  @override
  String get acpAuthVerifyingTitle => '正在验证登录…';

  @override
  String get acpAuthVerifiedTitle => '已连接';

  @override
  String acpAuthVerifiedAt(String time) {
    return '验证于 $time';
  }

  @override
  String get acpAuthRecheck => '重新检查';

  @override
  String get acpAuthCheck => '检查连接';

  @override
  String get acpAuthCancel => '取消登录';

  @override
  String get acpAuthCancelCheck => '取消检查';

  @override
  String get acpAuthCancelling => '正在取消…';

  @override
  String get acpAuthCancelled => '已取消。';

  @override
  String get acpAuthFailedTitle => '连接失败';

  @override
  String get acpAuthTerminalOnly => '该 server 只提供终端登录方式，本版本不支持。';

  @override
  String get acpAuthUnsupportedOnly => '该 server 只提供本版本尚未实现的登录方式。';

  @override
  String get acpAuthClosingTitle => '正在收束';

  @override
  String get acpAuthClosingBody => '协议交互已结束，进程与管道仍在收尾；收束完成前不会开始新的尝试。';

  @override
  String get acpAuthServerUnknown => '服务端未提供身份信息。';

  @override
  String get acpAuthMethodSelectHint => '选择登录方式';

  @override
  String get acpAuthMethodRequired => '请先选择登录方式。';

  @override
  String get acpAuthRowClosing => '收束中';

  @override
  String get acpAccountInstallOpen => '打开官方说明';

  @override
  String get acpAuthNoMethods => '服务端没有提供可用的登录方式。';

  @override
  String get acpAuthRetry => '重试';

  @override
  String get acpAuthEditConfig => '编辑配置';

  @override
  String get acpAuthDone => '完成';

  @override
  String get acpAuthDiagnostics => '技术细节';

  @override
  String acpAuthStageLabel(String stage) {
    return '阶段：$stage';
  }

  @override
  String acpAuthCodeLabel(String code) {
    return '原因：$code';
  }

  @override
  String get acpAuthRowUnchecked => '未检查';

  @override
  String get acpAuthRowChecking => '检查中';

  @override
  String get acpAuthRowRequired => '需要登录';

  @override
  String get acpAuthRowAuthenticating => '登录中';

  @override
  String get acpAuthRowVerifying => '验证中';

  @override
  String get acpAuthRowVerified => '已连接';

  @override
  String get acpAuthRowCancelling => '取消中';

  @override
  String get acpAuthRowCancelled => '已取消';

  @override
  String get acpAuthRowFailed => '连接失败';

  @override
  String get acpAccountDetailsSummary => '官方 ACP 接入，无需 API Key。';

  @override
  String get acpAccountConnectionInfoTitle => '连接信息';

  @override
  String get acpAccountProviderLabel => '提供方';

  @override
  String acpAuthFailureSummary(String reason, String stage) {
    return '$reason（$stage）';
  }

  @override
  String get acpFailureCodeStartup => '进程启动失败';

  @override
  String get acpFailureCodeMissingExecutable => '未找到 server 程序';

  @override
  String get acpFailureCodeIo => '读写错误';

  @override
  String get acpFailureCodeUnsupportedVersion => '协议版本不受支持';

  @override
  String get acpFailureCodeUnsupportedMethod => '登录方式不受支持';

  @override
  String get acpFailureCodeAuthentication => '登录失败';

  @override
  String get acpFailureCodeProbe => '连接检查失败';

  @override
  String get acpFailureCodeProtocol => '协议错误';

  @override
  String get acpFailureCodeTransport => '传输错误';

  @override
  String get acpFailureCodeTimeout => '超时';

  @override
  String get acpFailureCodeResourceLimit => '资源预算已用尽';

  @override
  String get acpFailureCodeCancelled => '已取消';

  @override
  String get acpFailureCodeStaleOperation => '操作已被取代';

  @override
  String get acpFailureCodeConfigChanged => '配置已变更';

  @override
  String get acpFailureCodeCleanup => '清理失败';

  @override
  String get acpFailureCodeInternal => '内部错误';

  @override
  String get acpFailureStageProcess => '进程启动阶段';

  @override
  String get acpFailureStageConfig => '读取配置阶段';

  @override
  String get acpFailureStageInitialize => '初始化阶段';

  @override
  String get acpFailureStageAuthenticate => '登录阶段';

  @override
  String get acpFailureStageProbe => '连接检查阶段';

  @override
  String get acpFailureStageClose => '关闭会话阶段';

  @override
  String get acpFailureStageCleanup => '清理阶段';

  @override
  String get studioFailureCodeNotInitialized => '尚未初始化';

  @override
  String get studioFailureCodeRuntimeStopped => '运行时已停止';

  @override
  String get studioFailureCodeInstanceBusy => '另有操作正在进行';

  @override
  String get studioFailureCodeInvalidArgument => '请求参数无效';

  @override
  String get studioFailureCodeNotFound => '未找到';

  @override
  String get studioFailureCodeBusy => '忙';

  @override
  String get studioFailureCodeConflict => '冲突';

  @override
  String get studioFailureCodeStaleRevision => '版本已过期';

  @override
  String get studioFailureCodePermissionDenied => '权限不足';

  @override
  String get studioFailureCodeCancelled => '已取消';

  @override
  String get studioFailureCodeCancellationTooLate => '取消已过晚';

  @override
  String get studioFailureCodeOverloaded => '负载过高';

  @override
  String get studioFailureCodeUnavailable => '不可用';

  @override
  String get studioFailureCodeProtocol => '协议错误';

  @override
  String get studioFailureCodeStorage => '存储错误';

  @override
  String get studioFailureCodeUpdate => '更新错误';

  @override
  String get studioFailureCodeInternal => '内部错误';

  @override
  String get acpAuthCancellingBody => '正在等待官方登录窗口与其进程结束。';

  @override
  String get acpAuthCancelledBody => '当前没有进行中的尝试，可重新检查或登录。';

  @override
  String acpAuthCommandFailure(String reason) {
    return '请求未被接受。$reason';
  }

  @override
  String get acpAuthCommandUnavailable => '请求未能完成。';

  @override
  String get botsOverviewHint => '把会话带到飞书，随时查询、协作与传递文件。';

  @override
  String get botsPlatformFeishu => '飞书';

  @override
  String get botsModelTitle => '模型与思考';

  @override
  String get botsModelHint => '应用于这个机器人的所有聊天，从下一轮开始生效。';

  @override
  String get botsAccessTitle => '联系人与群授权';

  @override
  String get botsAccessHint => '只有已授权的联系人和群可以使用机器人。';

  @override
  String get botsConnectionSettings => '连接与设置';

  @override
  String get botsWorkspace => '专用工作目录';

  @override
  String get botsPlatformTools => '飞书消息与测试发送';

  @override
  String get botsManagedModel => '由机器人统一设置';

  @override
  String get settingsSshNextPage => '下一页';

  @override
  String acpInstallUnsupportedPlatform(String version) {
    return '此平台没有 $version 的官方受管发行。';
  }

  @override
  String get acpFailureStagePrepare => '准备受管服务器';

  @override
  String get acpFailureCodePreparationRequired => '受管服务器尚未准备';

  @override
  String get acpFailureCodeInstallationInvalid => '已准备的服务器不完整或已损坏';

  @override
  String get acpFailureCodeUnsupportedPlatform => '此平台没有官方受管发行';

  @override
  String get acpFailureCodeServerVersionMismatch => '服务器版本不是受支持的版本';

  @override
  String get acpInstallFactVersion => '版本';

  @override
  String get acpInstallFactTarget => '平台';

  @override
  String get acpInstallFactStage => '阶段';

  @override
  String get acpInstallFactRetries => '自动重试';

  @override
  String acpInstallRetryValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已重试 $count 次',
      zero: '没有重试',
    );
    return '$_temp0';
  }

  @override
  String acpInstallProgressDownloaded(String done, String total) {
    return '已下载 $done / $total';
  }

  @override
  String acpInstallProgressUnknown(String done) {
    return '已下载 $done，总量未知';
  }

  @override
  String acpInstallProgressVerified(String done, String total) {
    return '已校验 $done / $total';
  }

  @override
  String acpInstallProgressVerifiedUnknown(String done) {
    return '已校验 $done，总量未知';
  }

  @override
  String acpInstallProgressExtracted(String done, String total) {
    return '已解压 $done / $total';
  }

  @override
  String acpInstallProgressExtractedUnknown(String done) {
    return '已解压 $done，总量未知';
  }

  @override
  String acpInstallProgressProcessed(String done, String total) {
    return '已处理 $done / $total';
  }

  @override
  String acpInstallProgressProcessedUnknown(String done) {
    return '已处理 $done，总量未知';
  }

  @override
  String acpInstallProgressPercent(int percent) {
    return '$percent%';
  }

  @override
  String acpInstallSpeed(String speed) {
    return '$speed/秒';
  }

  @override
  String get acpInstallStageResolve => '读取官方清单';

  @override
  String get acpInstallStageWaitForLock => '等待安装锁';

  @override
  String get acpInstallStageDownload => '下载安装包';

  @override
  String get acpInstallStageVerify => '校验安装包';

  @override
  String get acpInstallStageExtract => '解压文件';

  @override
  String get acpInstallStagePublish => '写入安装目录';

  @override
  String get acpInstallStageClose => '收束下载';

  @override
  String get acpInstallStart => '下载并准备';

  @override
  String get acpInstallRestart => '重新准备';

  @override
  String get acpInstallCancel => '取消下载';

  @override
  String get acpInstallCancelling => '正在取消…';

  @override
  String get acpInstallCancelSharedHint => '准备是共享操作：取消只中止当前准备，不影响已保存的账号。';

  @override
  String get acpInstallUsePrepared => '使用已准备的服务器';

  @override
  String acpInstallUsePreparedHint(String version, String target) {
    return '可显式认领已准备好的 $version（$target）。';
  }

  @override
  String get acpInstallReadyTitle => '服务器已就绪';

  @override
  String get acpInstallReadyBody => '准备不会保存账号，也不会登录。';

  @override
  String get acpInstallReusedBadge => '复用已安装版本';

  @override
  String get acpInstallFailureRetry => '重试准备';

  @override
  String get acpInstallTrustOfficialHttps => '信任边界：官方 HTTPS 来源，未提供发行方摘要。';

  @override
  String get acpInstallPendingAdmission => '正在受理准备请求…';

  @override
  String acpInstallCommandFailed(String reason) {
    return '请求未被接受。$reason';
  }

  @override
  String acpInstallFailureSummary(String reason, String stage) {
    return '$reason（$stage）';
  }

  @override
  String get acpInstallFailureCodeUnsupportedPlatform => '当前平台不受支持';

  @override
  String get acpInstallFailureCodeSourceRejected => '来源被拒绝';

  @override
  String get acpInstallFailureCodeNetwork => '网络错误';

  @override
  String get acpInstallFailureCodeTimeout => '超时';

  @override
  String get acpInstallFailureCodeTooLarge => '安装包超出上限';

  @override
  String get acpInstallFailureCodeChecksumMismatch => '摘要不一致';

  @override
  String get acpInstallFailureCodeInvalidArchive => '安装包无效';

  @override
  String get acpInstallFailureCodeMissingExecutable => '包内缺少 server 程序';

  @override
  String get acpInstallFailureCodeCacheCorrupt => '现有安装已损坏';

  @override
  String get acpInstallFailureCodeIo => '文件系统错误';

  @override
  String get acpInstallFailureCodeBusy => '另有准备操作正在进行';

  @override
  String get acpInstallFailureCodeStaleOperation => '准备操作已被取代';

  @override
  String get acpInstallFailureCodeCancelled => '已取消';

  @override
  String get acpInstallFailureCodeResourceClose => '清理失败';

  @override
  String get acpAccountTermsOpen => '服务条款';

  @override
  String get acpAccountTermsTitle => '官方条款';

  @override
  String get delegationSettingsTitle => '子智能体分发';

  @override
  String get delegationDefaultMode => '默认分发模式';

  @override
  String get delegationDefaultPreference => '默认自动选模偏好';

  @override
  String get delegationModeLabel => '分发模式';

  @override
  String get delegationPreferenceLabel => '自动选模偏好';

  @override
  String get delegationProfile => '固定 Profile';

  @override
  String get delegationAutomatic => '自动选模';

  @override
  String get delegationEconomy => '经济';

  @override
  String get delegationBalanced => '平衡';

  @override
  String get delegationFast => '快速';

  @override
  String get delegationOnlyAutomatic => '仅自动选模时生效；固定 Profile 模式下保留该值。';

  @override
  String get delegationEconomyHint => '满足任务能力与质量要求后，优先降低预计整体成本；未知价格不当免费。';

  @override
  String get delegationBalancedHint => '综合任务适配、近期评价、成本与完成时间，不降低质量要求。';

  @override
  String get delegationFastHint => '满足能力、质量与审查要求后，优先缩短整体完成时间。';

  @override
  String get delegationFollowDefault => '跟随默认';

  @override
  String get delegationSessionSettings => '会话设置';

  @override
  String get delegationInherited => '提交前跟随最新默认值';

  @override
  String get delegationOverride => '仅此草稿';

  @override
  String get delegationFrozen => '创建会话时已保存 · 只读';

  @override
  String get delegationModelNotRecorded => '模型未记录';

  @override
  String get settingsModelEnabled => '启用';

  @override
  String get settingsModelEnabledHint => '统一用于新的模型选择与子智能体分发，不打断在途调用。';

  @override
  String get settingsModelDisabled => '已禁用，不能用于新选择';

  @override
  String get settingsModelSaving => '保存中…';

  @override
  String get settingsModelSaveFailed => '尚未保存，开关显示上次确认的值。可再次切换重试。';

  @override
  String get settingsBillingKind => '计费类别';

  @override
  String get settingsBillingAutomatic => '自动推导 · 无显式覆盖';

  @override
  String get settingsBillingMetered => '按量计费';

  @override
  String get settingsBillingSubscription => '订阅 / 套餐';

  @override
  String get settingsBillingUnknown => '未知';

  @override
  String get settingsBillingEffective => '有效计费类别';

  @override
  String get settingsBillingOverride => '显式覆盖';

  @override
  String get settingsBillingHint =>
      '不计费仅影响之后的调用；其他类别按可用价格和用量估算。订阅不代表套餐仍有效、额度充足或零费用；模型参考价格始终保留。';

  @override
  String get settingsModelDetails => '模型详情';

  @override
  String get modelDetailLoading => '正在读取模型详情…';

  @override
  String get modelDetailUnknown => '未知 / 未核实';

  @override
  String get modelDetailAvailable => '本地配置满足新选择准入';

  @override
  String get modelDetailAvailabilityHint => '本地可用不保证远端健康、订阅有效或额度充足。';

  @override
  String get modelDetailSummary => '简介与任务适配';

  @override
  String get modelDetailLimitations => '局限';

  @override
  String get modelDetailCapabilities => '能力与限制';

  @override
  String get modelDetailEfforts => '合法思考强度';

  @override
  String get modelDetailNoEffort => '不提供思考强度参数';

  @override
  String get modelDetailPricing => '价格（每百万 token）';

  @override
  String get modelDetailPriceInput => '输入';

  @override
  String get modelDetailPriceOutput => '输出';

  @override
  String get modelDetailPriceCacheRead => '缓存读取';

  @override
  String get modelDetailPriceCacheWrite => '缓存写入';

  @override
  String get modelDetailSources => '来源与核验';

  @override
  String get modelDetailOfficial => '官方文档';

  @override
  String get modelDetailBenchmark => '独立基准';

  @override
  String get modelDetailCommunity => '社区反馈';

  @override
  String get modelDetailVerifiedAt => '核验日期';

  @override
  String get modelDetailMeasurement => '测量条件';

  @override
  String get modelDetailPerformance => '本地调用性能';

  @override
  String get modelDetailThroughput => 'Tokens/s（含首字等待）';

  @override
  String get modelDetailTtft => '平均首字延迟（毫秒）';

  @override
  String get modelDetailSamples => '调用样本数';

  @override
  String get modelDetailTtftSamples => '首字样本数';

  @override
  String get modelDetailUpdatedAt => '更新时间';

  @override
  String get modelDetailPerformanceHint =>
      '本机观察结果受账号、网络、思考强度与任务影响，不是供应商承诺，也不是任务评价。';

  @override
  String get modelDetailEvaluations => '最近最终任务评价（最多 10 条）';

  @override
  String get modelDetailEvaluationsEmpty => '此账号与模型尚无最终任务评价。';

  @override
  String get modelDetailEvaluationsHint =>
      '每个子智能体仅保留一条有效最终评价。少量样本不代表统计显著；无法判断不是低分。';

  @override
  String get modelDetailEvaluationPassed => '通过';

  @override
  String get modelDetailEvaluationFailed => '未通过';

  @override
  String get modelDetailEvaluationNotRated => '无法判断';

  @override
  String get modelDetailQuality => '质量';

  @override
  String get modelDetailInstructionFollowing => '指令遵循';

  @override
  String get modelDetailTaskReasoning => '推理';

  @override
  String get modelDetailTaskCoding => '编码';

  @override
  String get modelDetailTaskTooling => '工具调用与编排';

  @override
  String get modelDetailTaskLongContext => '长上下文';

  @override
  String get modelDetailTaskMultimodal => '多模态';

  @override
  String get modelDetailTaskGeneral => '通用';

  @override
  String get modelDetailRetry => '重新读取详情';

  @override
  String get modelDetailClose => '关闭';

  @override
  String get modelDetailStale => '该模型的 canonical 身份已变化，请重新读取详情。';

  @override
  String get composerContinue => '继续';

  @override
  String get composerContinueTooltip => '不添加新内容，继续被中断的工作';

  @override
  String get composerStopping => '正在停止';

  @override
  String get composerContinuing => '正在继续';

  @override
  String get composerContinueReasonUserStop => '已被用户停止';

  @override
  String get composerContinueReasonHostShutdown => '应用退出时该会话仍在运行';

  @override
  String get composerContinueReasonProcessInterrupted => '进程中断';

  @override
  String get composerContinueReasonStepLimit => '步骤预算已用完';

  @override
  String get composerContinueReasonExecutionFailed => '执行失败';

  @override
  String get composerContinueReasonUnknown => '执行已中断';

  @override
  String get composerBlockedStorage => '保存尚未完成，暂时不能继续。';

  @override
  String get composerBlockedModel => '当前模型不可用，暂时不能继续。';

  @override
  String get composerBlockedWorkspace => '会话工作区不可用，暂时不能继续。';

  @override
  String get composerBlockedArchived => '该会话已归档，不能继续。';

  @override
  String get composerBlockerUnknown => '上一次操作未能确认，请先核对会话状态再重试。';

  @override
  String get composerFailureChildRequiresParentScheduling => '子智能体只能由主智能体调度。';

  @override
  String get composerFailureContinuationUnavailable => '当前没有可继续的中断工作。';

  @override
  String get composerFailureContinuationClaimed => '继续已被受理，正在准备。';

  @override
  String get composerFailureStaleContinuation => '观察到的继续点已经过期。';

  @override
  String get composerFailureStaleExecution => '观察到的执行已结束或被新的执行替代。';

  @override
  String get composerFailureExecutionInProgress => '会话仍在执行或清理中。';

  @override
  String get composerFailureInteractionNotHosted => '该交互在主会话处理。';

  @override
  String get composerFailureStaleInteraction => '该交互已被更新，请重新打开。';

  @override
  String agentStopSemantics(String name) {
    return '停止成员 $name';
  }

  @override
  String get agentStopping => '正在停止';

  @override
  String get agentStopWaitingScheduling => '已停止，等待主智能体调度';

  @override
  String agentStopFailed(String message) {
    return '停止未被接受：$message';
  }

  @override
  String get composerAgentReadOnlyTitle => '子智能体会话（只读）';

  @override
  String get composerAgentReadOnlyWaiting => '等待主智能体调度该成员。';

  @override
  String get composerAgentReadOnlyScope =>
      '历史、进展、模型与工作区仅供查看；需要它继续工作时，请在主会话向主智能体表达要求。';

  @override
  String get composerAgentReadOnlyPending => '待决问题或权限请求在主会话处理。';

  @override
  String childInteractionFrom(String agent) {
    return '来自 $agent';
  }

  @override
  String childInteractionRevision(int revision) {
    return '版本 $revision';
  }

  @override
  String get childInteractionAnswerSaved => '答案已保存，是否继续该成员由主智能体决定。';

  @override
  String get childInteractionApprovalResolved =>
      '原权限等待已决议；批准时原调用可能继续，拒绝时不执行该调用。';

  @override
  String childInteractionDecideFailed(String message) {
    return '决定未被接受：$message';
  }

  @override
  String childInteractionLoadFailed(String message) {
    return '无法读取子任务待决交互：$message';
  }

  @override
  String get childInteractionRetry => '重新读取';

  @override
  String get childInteractionDecisionAccepted => '决定已受理，等待会话确认。';
}
