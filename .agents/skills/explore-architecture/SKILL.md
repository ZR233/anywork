---
name: explore-architecture
description: Use when asked to understand, document, or summarize the 糊来帮 architecture across its crates, Studio products, and runtime boundaries.
metadata:
  category: guides
  platforms: ["windows", "linux", "macos"]
---

# 探索糊来帮架构

按具体问题定位架构事实，使用设计、清单和源码相互核对。本文提供取证方法，不规定派发、
等待、审查或测试流程，也不以固定目录清单替代当前仓库。

## 建立全局视角

可按问题选择入口，不必为局部问题加载全部文档：

- `AGENTS.md`：项目边界和工程入口。
- `design/01-overview.md`：系统定位、核心概念和运行时边界。
- `design/02-crates.md`：crate 职责和依赖方向。
- 根 `Cargo.toml`：当前 workspace members 的唯一事实来源。

其他专题可从 `design/README.md` 定位。影响决策或即将修改的契约由主代理核对原文；
探索摘要是来源索引，不是未经核验即可采纳的结论。

## 职责与依赖取证

职责和依赖方向来自 `design/02-crates.md`，实际成员及直接依赖来自根与各 crate 的
`Cargo.toml`。区分编译期依赖、装配关系和运行期调用，不把它们画成同一条线。
本技能不维护第二份组件或依赖清单。

## 分派只读探索

跨领域调查可按独立问题分工；小范围查询通常直接完成。派发能力、参数和生命周期来自
当前宿主声明，不在技能中固化人数、轮次或终态标记。

推荐按真实边界而不是机械地“每个 crate 一个代理”拆分，例如基础协议、模型/LSP、核心编排、
Studio 产品、远程运行与前端桥接。范围过大时进一步缩小问题，不让单个代理承担全仓综述。

## 复核与汇总

沿 `file:line`、符号名及来源版本核对关键结论，不为复核重新读入全部外围材料。

汇总只展开与问题相关的内容，例如：

1. 系统定位与主要用户入口。
2. 当前 workspace members 与非 Cargo 产品目录。
3. crate 职责、公共入口和实际依赖关系。
4. Thread/Turn、模型、工具、Skill、远程与 Studio 的所有权边界。
5. 配置、SQLite 与运行态事实的存储位置。
6. 与问题直接相关的验证入口和仍未核实事项。

发现文档与代码冲突时，明确列出两边证据；涉及长期契约的修改先更新相应 `design/*`。
