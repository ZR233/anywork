---
name: flutter-frb-rust-design
description: 新增、修改或审查本项目 Flutter／FRB／Rust 功能时，涉及跨层分工、Riverpod 状态、类型化路由、领域数据交付、资源所有权或持久化边界时使用。提供基础技术栈与设计判断方法，不规定具体页面组件库；构建和生成使用 flutter-studio-build。
category: development
---

# Flutter／FRB／Rust 跨层设计

先确定事实与资源的所有者，再选择接口和组件。目标是从契约上减少重复状态与补偿逻辑，
而不是给每个功能增加一套 Manager、Facade、UseCase 或消息总线。

## 适用边界

本技能用于本项目的跨层开发。不可变历史、连续完成交付等模式有各自前提；
不得因此将所有业务数据改为只追加，也不得假定现役可变协议已经被替换。

产品接口和行为以 [设计索引](../../../design/README.md) 对应的权威文档为准；
修改契约先同步其唯一所有者。技能不维护第二份 DTO、预算、库版本或页面清单，
也不固定聊天列表、Markdown 等具体页面库。组件选型与自研门槛遵循
[AGENTS.md](../../../AGENTS.md)。

## 按问题阅读

| 涉及的变更 | 读取内容 |
| --- | --- |
| 功能放哪层、基础库、Riverpod／Freezed、路由和草稿 | [基础栈与统一路由](references/project-stack-and-routing.md) |
| 命令／观察／查询、版本、流控、恢复和关闭 | [数据交付与生命周期](references/data-delivery-and-lifecycle.md) |
| 内存与落盘交接、迁移、组件复用和验证范围 | [演进与验证](references/evolution-and-verification.md) |

## 开始改动前回答

1. **是什么数据？** 区分业务事实、领域当前态、展示派生值、用户草稿和资源对象；
   写清每类数据的唯一写入口。只读镜像、有界在途交付与 UI 局部状态不等于第二事实源。
2. **在哪个边界完成？** 分开命令受理、业务完成、可查询、消费者接纳和可靠保存。
   不用“Future 返回了”替代领域成功，也不用“已发送”替代对端消费。
3. **谁仍有资格？** 每次异步交接都核对原目标、owner、操作和版本；
   路由、组件、订阅、业务 Session 的生命周期不能互相代替。
4. **能否删掉一层？** 优先复用现有领域 owner 与组件公开能力。
   若只是搬运同一状态或重复验证同一增量，先找原职责，而不是增加镜像或兜底刷新。

## 与专项技能的分工

- Rust 实现质量使用 `rust-code-quality`；共享类型和错误使用 `rust-api-design`。
- 锁、任务、回调、取消的同步证明使用 `rust-concurrency-safety`；
  unsafe、FFI 内存和外部句柄的安全证明使用 `rust-unsafe-safety`。
- 测试设计使用 `test-quality`，生成、构建和原生观察使用 `flutter-studio-build`。
  不因加载本技能追加固定的全量测试或 GUI 验收。

交付时说明实际改变的边界、删除的重复职责以及证据覆盖范围；不把目标设计、
组件文档或其他版本的测试结果表述为本次已实现、已验证的能力。
