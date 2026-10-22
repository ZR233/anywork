# T1.A 初始连接失败定向取证：第 1 轮（轮次未完成，未取得四字段）

## 0. 结论

- 本任务按 v1 合同执行，预算最多 3 轮独立官方 `timeline-history`（不带 displacement）。本轮**实际启动 1 轮**，
  该轮**未完成**：已归档日志停在 `pl-studio-bridge` release 构建；等待该 exec task 的调用以
  `remoteDisconnected` 返回，已归档命令输出另记录到 wrapper 收到 `signal 15` → `KeyboardInterrupt`
  与 `Session terminated`。**`SIGTERM` 的发送方、`remoteDisconnected` 与该 signal 之间的详细因果链未知**；
  本轮也**未观察到** app／VM service／Driver 旅程启动，因此**没有产生任何 `last` / `lastWhileBusy`
  超时诊断快照**，**四字段不可得**（不是"缺键"，也不是"合法 null"，而是**没有快照**）。
- 依合同 §4.5 / §4.6 / §4.7（任一轮失败即停止、仅在前一轮官方全通过后才开下一轮、SSH 中断不重复启动、
  不把取消／截断／权限等待算通过），campaign **停在第 1 轮**，剩余轮次**未使用**；
  是否授权替代轮次由 root 决定。
- **没有任何产品侧连接失败样本**：本轮既不是功能通过，也不是产品失败证据；旧 a1 的 `connection:"failed"`
  原因**仍然未知**，本轮不提供任何归因。本报告不修改、不并入旧 raw 已审报告。

## 1. 授权、写范围与未改动声明

- 唯一正式写文件：`reports/frontend-refactor/t1a-connection-investigation.md`（本文件，新建）。
- 遵循冻结合同 `t1a-initial-connection-investigation-contract.md` v1
  （SHA-256 `f03a1ea18b3d1682a2777ce6f127471add9a04109d54122c007ba538eaa5650f`）与四字段诊断合同
  `t1a-connection-diagnostics-contract.md`（SHA-256 `9e03436698e4d4bf8e4c0901400b53b0cdbc53080d6683015071e9769324836a`）。
- 本轮**未**修改：旧 raw 已审报告 `t1a-native-acceptance.md`（保持 SHA
  `feafa086b12fb6ab5459336cb48585decdbc48bba630904cb42a0465acdefedc`）、四份冻结脚本（SHA 见 §9）、
  五文件诊断实现、design、生产／生成／manifest／CI／配置、任何旧原件与旧数据根。
- 本轮**未**运行 raw probe、未加 `--timeline-displacement`、未重复 root 的 displacement 矩阵、
  未直调 `flutter build/run`、未占 1420、未 `xhost +`、未全局 `pkill`、未改用户配置／凭据、未 stage/commit/push。
- 新增的只有一个只读提取器，位于本执行者自己的 session scratch（不改原脚本、不改成功断言）：
  `extract_connection_diagnostics.py`，SHA `933851c7cc86291e6f716f607b54adf4de9fde086155ed040cb18cfa413bc615`。

## 2. 基线与输入身份核对（运行前，只读）

| 项 | 核对结果 |
| --- | --- |
| HEAD / 分支 / 贡献基线 | `b98432fa809446d57be87a8b96379455ec8a4828` / `pure-session-thread-65e3ee582f0d4-82` / `f6cb327ceb3416dca181790575711588571d3ec7` |
| 输入身份清单 | SHA `4e49b01d64b012a0b5d4d79fc32230e783b0420522e857e57468c006c076a150`；`head` 与上述一致 |
| 清单计数 | SDK 20 / APP 21 / controls 73 / generated 88 / adjacent 6 / new diagnostics 5 / deleted 3，均与授权一致 |
| 先行设计 | `design/26-timeline-content.md` = `ee4577dbb9b96763d1932e71e33d6504249d7375d95f2eda9f735aafbfc9dc60` |
| 完整计划 | `reports/frontend-refactor/implementation-plan.md` = `d0fadef80c426bb9d2fea9213ac15fa9614247e4b2c241c85d385a190d2ea7f7` |
| 五文件诊断实现 | 全部与清单一致（hash 见 §9），运行前逐项计算确认 |
| owned 进程 | 启动前本 workspace 无 acceptance／fixture／GUI／Driver／Xvfb 进程（`[]`） |

## 3. 实际编排（第 1 轮）

- 复用**冻结未改**的自身 harness `run_timeline_acceptance.py`（SHA `dd3f87be…d514`），传入全新标签
  `t1a-connection-diag-1`；该脚本先做 owned 进程清零断言，再要求输出目录与 xauth 均不存在。
- 平台与形状（与合同 §4.3 一致；下例省略本会话绝对路径）：

  ```bash
  GDK_BACKEND=x11 xvfb-run -a -f <own-absolute-xauth> -e <own-xvfb-log> \
    -s '-screen 0 2560x1600x24' \
    script -q -e -c 'cargo xtask manual-gui --scenario timeline-history \
      --retain-environment --output <own-new-output>' /dev/null
  ```

- 保留 30 s 外层运输心跳（只维持 stdout 活动），未改官方 90 s 超时、50 ms 采样、旅程动作、fixture 与成功判据。
- 命令实际执行 task：`task:call_00_sSGhqXeqX2QtKGAUWPth9523`（该 task 以 `remoteDisconnected` 返回失败，见 §4），
  命令输出归档于本会话 commands（SHA `40ebbb85afefa1e0b75f969451158514f4e2dcfb1310c21cc328fbd42de9d7c4`）。

## 4. 第 1 轮事实时间线（`t1a-connection-diag-1`）

1. harness 通过 owned 进程清零断言（`{"owned_acceptance_processes": []}`）。
2. `cargo build -p pl-studio-acceptance`、`cargo build --locked -p pl-provider-fixture` 均 Finished（复用既有构建）。
3. `manual-gui` 启动：预检 rustc；创建全新隔离环境（新 home／project，fixture ready 文件已写出）。
4. GUI 侧进入 `flutter pub get` → 远程 helper 资源构建（`startup_stage=build_remote_helpers elapsed_ms=899`）
   → `cargo build --locked -p pl-studio-bridge --release`，日志停在 `Compiling pl-studio-bridge …`。
5. 外层 30 s 运输心跳打印一次（`acceptance_heartbeat elapsed_seconds=30 pid=976363`）。
6. 等待该 exec task 的调用以 `remoteDisconnected` 返回（task 终态为失败）。
7. 本会话归档的命令输出另有两段观察：wrapper 的
   `KeyboardInterrupt: acceptance interrupted by signal 15`，以及随后的
   `Session terminated, killing shell...`；即 wrapper 在执行中收到了 `signal 15`。
8. 恢复后核查：**本 workspace 无任何 owned 进程残留**（acceptance／fixture／GUI／Driver／Xvfb 全部不存在）。

**因果边界（不做超出原件的断言）**：`SIGTERM` 由谁发送、它与 `remoteDisconnected` 的先后与因果关系、
以及该 signal 是否就是 task 失败的直接原因，**都没有任何已保留原件可以证明**，本报告不作断言。
可以确定的只是代码层面的责任划分：冻结 wrapper 的 `finally` 分支在 child 尚存时会先尝试对所属进程组
`killpg(SIGTERM)`，超时再 `SIGKILL` 并 `wait`；这表示**代码里存在该分支**，
**不等于**本轮该分支的每一步都已实际执行。本轮既没有 native exit report，也没有后代回收报告，
因此**不能声称已取得真实 exit code 或完整的后代回收报告**；唯一可核的现状是恢复后的
owned-process scan 为 `[]`。

**停点性质**：已归档日志停在 bridge **构建期**。按当前 launcher 顺序
（`xtask/src/flutter/mod.rs` 的 `run_gui_native_launch`：先 `ensure_flutter_dependencies`，再
`prepare_remote_helpers`、`prepare_bridge_artifacts`，然后 `run_flutter_with_process_mode` 构建，
构建后对 bundle 产物做存在性检查，最后才 `Command::new(executable)` 启动；`manual_gui.rs` 的 history
旅程也是先 `start_timeline_history_gui` 再 `wait_for_vm` 才启动 Driver），
**构建完成前不会进入启动阶段**。因此本轮**未观察到** app 启动、VM service、Driver 连接与旅程 stage 文件
（`timeline-history-stage.txt` 不存在）。"20k 输入未发生"的依据是三件事同时成立：
构建停点 + 无 Driver／stage 文件 + fixture 摘要 `0/20000`；**不单凭 `requests.json` 为空**下此结论。
这是**编排层未完成**，不是产品侧 `connection:"failed"` 样本。

本轮残留原件（本会话 artifacts，`t1a-connection-diag-1/`）：

| 原件 | 内容（只列判定所需标量） |
| --- | --- |
| `environment-Ag4Dg1/fixture-ready.json` | 已生成 loopback ready（scenario `timeline-history`），证明 fixture 曾就绪 |
| `environment-Ag4Dg1/requests.json` | `0` 条请求 → 本轮未观察到任何模型请求，即**没有 413 证据**（不推广为"排除所有请求体上限相关问题"） |
| `environment-Ag4Dg1/fixture.log` | fixture stdout 以失败摘要结束：`fixture_status=failed`、accepted 0、rejected 0、`consumed_steps=0/3`、`Error: fixture stress stream incomplete: emitted 0/20000 data events`。该失败与"required 20k prompt 未到达"一致；不是剧本拒绝，也没有请求体上限的证据 |
| `environment-Ag4Dg1/timeline-history-live-gui.log` | 54 行，最后一行是 `Compiling pl-studio-bridge`；**未观察到** app 启动与 VM service |
| `environment-Ag4Dg1/home/config.toml`、`environment-Ag4Dg1/timeline-history-project/` | 官方 harness 创建的隔离环境；project 目录仅 120 KB，没有任何会话内容产生 |
| `operations.json` / `verdict.json` | `[]` / `{"human_verdict":"pending"}`（未产生人工判定） |

未产生：`timeline-history-live-exit.json`、`-native-exit.json`、`-driver.log`、`-stage.txt`、
`fixture-status.json`、`fixture-report.json`、`retained-environment.json`（这些由 harness 在阶段收尾／正常保留时写出）。
因此本轮**没有**真实 PID 退出报告与后代回收报告可供引用；只能确认"当前无进程残留"。

## 5. 四字段状态（本轮）

首条件超时需要读取 `last` / `lastWhileBusy` 中的
`connectionErrorType`、`connectionErrorCode`、`connectionErrorRetryable`、`connectionErrorCorrelationId`。

| 字段 | 本轮值 | 原因 |
| --- | --- | --- |
| `connectionErrorType` | **不可得** | 没有超时诊断快照（旅程未启动） |
| `connectionErrorCode` | **不可得** | 同上 |
| `connectionErrorRetryable` | **不可得** | 同上 |
| `connectionErrorCorrelationId` | **不可得** | 同上 |

只读提取器对本文档化结果给出的机器判据：

```json
{"driverLogPresent": false, "timeoutDumpPresent": false, "stage": null,
 "connectionFailedSnapshots": [], "missingDiagnosticOrFactKeys": []}
```

明确区分三种情形：**没有快照（本轮）** ≠ **有快照但缺键（诊断失败）** ≠ **有快照且值为合法 null（未知／无错误）**。
本轮不补任何默认值，也不据此推断任何错误分类。

## 6. 停止判定（campaign 到此结束，剩余轮次未使用）

依据合同：

- §4.5「任何一轮失败立即停止整个 campaign，保存和检查该轮全部证据后报告 root；不为取得绿再开下一轮」；
- §4.6「仅在该轮官方旅程全部通过、中央 shutdown clean、GUI／Driver／fixture／Xvfb 及后代已确认回收后，才允许下一轮」；
- §4.7「SSH 中断不等于子进程退出，不重复启动；恢复后先核原任务与所属进程／报告。无法确认则停止并向 root 报告，
  不把取消、截断或权限等待算通过」。

本轮既未全通过、也未取得产品侧失败，因此**不满足开下一轮的前提**；同时我也**不把它记成产品失败**。
故：campaign 停在此处，`t1a-connection-diag-2/3` **未启动**、相应输出与 xauth 均不存在（无预建残留）。
是否要用新一轮替代这次未完成的轮次，属 root 的编排决定；我不擅自消耗剩余预算。

## 7. 未覆盖与不外推

- **没有**任何产品侧 `connection:"failed" / generation:0` 新样本，因此本任务的核心目标（新失败的四字段）**未取得**。
- 旧 a1 原因**仍未知**；本轮不提供归因、也不排除任何类别（Busy / Conflict / 环境 / 时序均未测）。
- 不覆盖：app 启动后行为、Timeline 连接、ACK、query、close、native 退出、后代回收、fixture 主流程、
  位移矩阵、截图人眼判定、Windows／真实供应商、release 形态。
- 不涉及任何预算／流控结论；无性能百分比（本轮没有可比测量）。
- 本轮唯一可确认的阻塞事实是：exec task 以 `remoteDisconnected` 返回失败，且归档命令输出记录到 wrapper
  的 `signal 15` → `KeyboardInterrupt` → `Session terminated`；两者的发送方、先后与因果链未知，
  其根因（网络／SSH／宿主）不在本任务证据范围，交 root。

## 8. 复算入口（不含本机绝对路径）

```bash
# 第 1 轮（已执行，未完成）：冻结 harness，全新 label
python3 <scratch>/run_timeline_acceptance.py t1a-connection-diag-1

# 只读提取（本轮已执行；对失败的轮次输出四字段或明确"无快照/缺键"）
python3 <scratch>/extract_connection_diagnostics.py <artifacts>/t1a-connection-diag-1 t1a-connection-diag-1
```

提取器行为：只在 `timeline-history-live-driver.log` 里存在的 JSON 对象中读取，缺键列入
`missingDiagnosticOrFactKeys`，合法 null 保留 null；不提取 message／details／stack／正文／凭据。

## 9. 证据与内容身份

### 9.1 本轮原件（本会话 artifacts，未入库）

| 文件（相对 `t1a-connection-diag-1/`） | SHA-256 |
| --- | --- |
| `environment-Ag4Dg1/fixture-ready.json` | `aed92b28af07097d797500833447fc04d586bd07f7f91a0025bda8401aaac027` |
| `environment-Ag4Dg1/fixture.log` | `ceaa19604321e919a509540ec102a8e7992a39a15029e349a28c2aad2a91cf58` |
| `environment-Ag4Dg1/requests.json` | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| `environment-Ag4Dg1/timeline-history-live-gui.log` | `3b3f6c7b0cb29934fd3cc6b86500cd3b76f60c0b8e63c22dfe2a0eefe7bfa67f` |
| `environment-Ag4Dg1/home/config.toml` | `02a2ef384632463da799ae64fc6dca6c7196e3a9ec81d7d4753ab688252ce771` |
| `operations.json` | `37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570` |
| `verdict.json` | `5b478a6e0dbab5f4cf4eb5da12a0fb3255266f1e8c767eb9cfc0970957cb4286` |
| `connection-diagnostics.json`（提取器输出） | `9028167724b078da5523adf3827a0331c0723f14da13e2ff4743a4be0f7f9db5` |
| 命令输出日志（本会话 commands） | `40ebbb85afefa1e0b75f969451158514f4e2dcfb1310c21cc328fbd42de9d7c4` |

### 9.2 输入与脚本身份（只读核对，未改）

| 文件 | SHA-256 |
| --- | --- |
| `lib/src/shared/studio_driver_state.dart` | `7dc1b5b652fdf006686085b35c407dd1ef79d729139d3ca2d9175fd297dc510d` |
| `lib/src/shared/studio_driver_projection.dart` | `2e1839e41b05b0be3b819cf9e2e4b4e5207d97eb148dd4c10b3df1cfd3e02132` |
| `test_driver/timeline_observation.dart` | `c534f02be268cd1403cd7dd344bb33e61a919f9b4f9e5603399d162ec148ec4c` |
| `test_driver/timeline_streaming_journey.dart` | `2e377471d02d1920ff17e6c47c51445834c0512353ab29ea5e234dfa7b4cbbf3` |
| `test/client/studio_driver_query_test.dart` | `f4ee49027491c35532fe181839b8ab8c7aa7ceb0e5e006bca19dadbacb8729e2` |
| `scratch/run_timeline_acceptance.py`（冻结 harness，未改） | `dd3f87be6d8b7ae4ed1266d4f6b851fa2fb942c26dcd591dc8a512789c23d514` |
| `scratch/extract_connection_diagnostics.py`（本轮新增只读提取器） | `933851c7cc86291e6f716f607b54adf4de9fde086155ed040cb18cfa413bc615` |

旧 raw 报告与其余三份冻结脚本本轮**未改动**，其已审 SHA 继续有效
（`t1a-native-acceptance.md` = `feafa086…defedc`；`run_timeline_raw_probe.py` = `31c70bf1…2f7`；
`timeline_raw_feed_probe_main.dart` = `6273395e…386d`；`timeline_raw_feed_probe_client.dart` = `3d76c2f5…e6f1`）。

## 10. 资源与后台状态

- 本轮无后台任务、无交互等待。唯一启动的 exec task `task:call_00_sSGhqXeqX2QtKGAUWPth9523`
  以 `remoteDisconnected` 返回失败；本会话归档的命令输出另记录到 wrapper 的 `signal 15` →
  `KeyboardInterrupt` → `Session terminated`。这是**两条并存的观察**，其发送方与因果链未知；
  冻结 wrapper 的 `finally` 分支在 child 尚存时会尝试 `killpg(SIGTERM)`／必要时 `SIGKILL` 并 `wait`，
  但本轮**没有**证据表明该分支每一步都已完整执行，也**没有** native exit／后代回收报告。
- 恢复后 owned-process scan = `[]`（acceptance／fixture／GUI／Driver／Xvfb 均不存在）。
- 未删除任何旧失败现场、未清理旧数据根；本轮新输出目录与 xauth 原样保留供复审。
