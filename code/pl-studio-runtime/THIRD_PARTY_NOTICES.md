# 第三方预置技能声明

本 crate 的部分预置系统技能由 `cargo xtask sync-skills` 从以下上游仓库的默认
分支最新提交同步而来,完全替换 `assets/skills/<name>/` 后提交进源码库;源码库即
canonical 内容,构建期不访问网络。每次同步后需人工核对本文件中的 revision 并随
变更一起提交。

## anthropics/skills

- 上游:<https://github.com/anthropics/skills>
- 最近同步 revision:`3b3fad96af16a10759d930941b4520ba0c40edae`
- 技能:`canvas-design`、`frontend-design`
- 许可:Apache License 2.0,Copyright Anthropic, PBC。各技能目录自带
  `LICENSE.txt`,同步拷贝时原样保留。
- 注意:同仓库的 `pdf`、`docx`、`pptx`、`xlsx` 使用 Anthropic 专有
  source-available 许可(禁止再分发),**不得**加入预置集合。

## NousResearch/hermes-agent

- 上游:<https://github.com/NousResearch/hermes-agent>
- 最近同步 revision:`cced6fa360a589ba50abfde687ef1bcba8ddaf2e`
- 技能:`docx`、`pdf`、`powerpoint`、`xlsx`(位于 `skills/productivity/`)
- 许可:MIT License,Copyright (c) Nous Research。按 MIT 条款在产物中随技能
  分发时保留本声明中的版权与许可指向;许可全文见上游仓库 `LICENSE`。

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
