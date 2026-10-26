import 'package:anywork_client/models.dart';

/// 智能体成员身份上的共用判定。
///
/// 列表行、停止资格与概览文案都只能从同一处读取这些事实，避免同一语义出现第二份
/// 判据后互相漂移。
///
/// 退役成员：旧版 `planner` 子成员不再是合法角色。
///
/// 角色标签与停止资格共同使用该判据；`StudioThread.isRetiredAgent` 表达的是同一
/// 事实，角色字符串比较统一由 Client 导出的 [isRetiredAgentRole] 提供，这里只补
/// 「是子成员」这一条件，不另写一份字符串判据。
bool isRetiredAgentRow(StudioAgentView agent) =>
    agent.parentPath != null && isRetiredAgentRole(agent.role);
