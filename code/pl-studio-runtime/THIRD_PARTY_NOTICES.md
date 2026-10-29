# 第三方预置技能声明

本 crate 的部分预置系统技能由工具读取下列固定上游提交后手动拷贝并整理至
`assets/skills/<name>/`，直接检入源码库；源码库是 canonical 内容。维护不使用
子模块、外部仓库 checkout、自动同步脚本或构建期下载。更新时核对来源、许可证
与本地适配，并将本文件和技能资源一起提交。

## anthropics/skills

- 上游:<https://github.com/anthropics/skills>
- 固定 revision:`ca45fc496a3436251f191354091d557da31c15b5`
- 技能:`canvas-design`、`frontend-design`
- 来源目录:`skills/canvas-design/`、`skills/frontend-design/`。
- 许可:Apache License 2.0,Copyright Anthropic, PBC。各技能目录自带
  `LICENSE.txt`,同步拷贝时原样保留。
- 本地适配:`frontend-design/SKILL.md` 采用固定提交的上游原文；
  `canvas-design/SKILL.md` 保留设计理念、画布创作和检查精修流程，精简重复修饰，
  移除特定模型、虚构用户要求及默认下载授权，按当前会话约定定位资源、临时文件
  与交付物。两项技能的许可证和既有字体资源不变；字体仍适用随资源保留的各自许可。
- 注意:同仓库的 `pdf`、`docx`、`pptx`、`xlsx` 使用 Anthropic 专有
  source-available 许可(禁止再分发),**不得**加入预置集合。

## deepseek-ai/deepseek-harness

- 上游:<https://github.com/deepseek-ai/deepseek-harness>
- 固定 revision:`f3803c96974ad4a94195fb97e5c637e9c2a3afe3`
- 上游包:`@deepseek-ai/dsh-skill-office`，版本 `0.2.2-alpha.2`。
- 来源目录:`packages/skill/skill-office/assets/`。
- 技能:`office`、`office-docx`、`office-pptx`、`office-xlsx`、
  `office-render`、`office-recalculate`、`office-export-pdf`。
- 许可:MIT License，Copyright (c) 2026 DeepSeek。每个技能目录保留上游
  `LICENSE` 全文，随嵌入资源一起分发。
- 本地适配:采用本项目标准技能目录；基础环境说明独立完整，移除 Harness 专属
  工具调用和宿主路径注入假设，临时与交付文件遵循当前会话规则。上游
  `office/references/sidecar.md` 按操作技能整理为各自目录内的支持文件，
  避免跨技能支持文件依赖；保留领域操作、源文件保护和适用验证边界。
- 不分发 Harness 的 TypeScript provider、Python 创作库、Node 或
  LibreOffice Kit 及其引擎。外部工具适用各自许可证，本文的 MIT 许可不覆盖它们。

许可原文（对应固定 revision 的仓库 `LICENSE`）：

```text
MIT License

Copyright (c) 2026 DeepSeek

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## larksuite/node-sdk（协议对照，非运行依赖）

- 上游:<https://github.com/larksuite/node-sdk>
- npm 包:`@larksuiteoapi/node-sdk@1.76.0`
- npm gitHead:`1889911f0841e669de0be5bd02c737a3f1fd20fa`（GitHub 无法按该 SHA 取路径）
- 对照仓库 revision:`b188be60134d409b61259546bcf69c731d2b0b7c`
- 使用范围:注册 begin/poll、addons gzip+base64url、`/callback/ws/endpoint`、pbbp2 Frame/Header 字段编号、ping/pong 与事件 ACK。不复制整个 SDK，不引入 Node 运行依赖。
- 许可:MIT License, Copyright (c) 2022 Lark Technologies Pte. Ltd.

许可原文（对应上述固定仓库 revision 的 `LICENSE`）：

```text
MIT License

Copyright (c) 2022 Lark Technologies Pte. Ltd.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice, shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
