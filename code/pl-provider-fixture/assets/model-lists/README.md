# 真实 `/models` 响应资源

本目录保存验收用的真实模型列表响应原文，由 `pl-provider-fixture` 的 payload 模式
（控制文件实例项的 `"payload": "<name>"`）通过 `include_str!` 编译进二进制后原样
返回，运行时不读取源码树、不联网。

| 资源 | payload 名 | 抓取来源 | id 数 |
| --- | --- | --- | --- |
| `deepseek.json` | `deepseek` | `https://api.deepseek.com/models` | 2（`deepseek-flash`、`deepseek-v4-pro`） |
| `openai-aggregator.json` | `openai-aggregator` | `https://ai.muxai.net/v1/models`（OpenAI 兼容聚合网关） | 19（其中 5 个 `gpt-image-*`） |

- 内容是维护者自己账号调用上述服务的 API 响应，不是第三方代码或文档摘录，
  因此不新增第三方许可证声明，也不进入 `THIRD_PARTY_NOTICES.md`。
- 重新抓取后保持 OpenAI 兼容外壳 `{"object": "list", "data": [{"id": ...}]}`；
  fixture 启动时会校验外壳、非空 id 与 id 唯一性，校验失败直接报错退出。
- 修改这些文件会同时改变 `--model-catalog-inventory real` 的在线观测结果和
  `--model-catalog-check` 的 id 数量输出；数量不作为断言，断言的是"返回体与资源一致"。
