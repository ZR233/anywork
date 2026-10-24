# 飞书机器人界面证据

截图统一作为 [PR #138](https://github.com/ZR233/anywork/pull/138) 附件提供，不随源码分发。
当前附件涵盖机器人总览、详情、窄窗口与长名称；对应实际验证范围见 PR 的版本说明。
原始截图、Driver 快照和运行日志保存在忽略的 `target/manual-gui/` 证据目录。

早期 Linux/Xvfb 的七张合成平台截图已从源码移出，并保留在本地证据目录中；
原始版本仍可从 Git 历史查阅。它们不能代替新版 Windows 界面或真实飞书的验证结果。
任何截图都不能单独证明附件完整性、输入去重、持久化或进程回收，需结合对应运行记录。

## Markdown 与流式输出的 Linux 隔离观察

新增的[固定版本截图与范围说明](https://github.com/ZR233/anywork/tree/fa4351f19248a110898e09a233657ad739900ebb)
保存在独立证据分支，不进入产品源码与发行包。包含七项权限说明、同一回复生成中和完成态；
由真实 Flutter/FRB/Studio runtime、隔离模型与飞书 peer 经 Driver 取证，关闭报告为
`clean`、`persistence=drained`、`issues=[]`。它们是 anywork 本地界面，不是飞书客户端；
CardKit 协议及故障恢复仍须结合独立观察记录，不能由图片外推为真实租户兼容性通过。
