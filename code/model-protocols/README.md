# 模型协议与真实调用示例

协议 crate 各自持有内置模型声明、在线目录解析和原生服务。OpenAI 官方与通用兼容端点共用 `pl-model-openai`。GLM、DeepSeek、xAI、MiMo 使用共享 wire，同时维护自己的协议扩展。正式产品由 `pl-model` 按开放的 `ProtocolId` 静态装配，示例通过对应协议的同一份 `Adapter` 配置运行时。新增 OpenAI 派生协议时，在该 crate 定义端点、目录与请求差异，并在产品装配登记。

从仓库根目录运行。通过环境设置 `MODEL_API_KEY`，`--base-url` 包含供应商所需的版本前缀。

```sh
cargo run --locked -p pl-model-openai --example openai-live -- \
  --base-url https://api.openai.com/v1 chat --model "$MODEL" --prompt 'Reply with hello.'

cargo run --locked -p pl-model-openai --example openai-live -- \
  --compatible --base-url "$BASE_URL" chat --wire chat --model "$MODEL" --prompt 'Reply with hello.'
```

| 协议 | Cargo package | Example | 场景 |
| --- | --- | --- | --- |
| OpenAI 与通用兼容 | `pl-model-openai` | `openai-live` | `chat`、`models`、`image`、`search` |
| GLM | `pl-model-openai-glm` | `glm-live` | `chat`、`models` |
| DeepSeek | `pl-model-openai-deepseek` | `deepseek-live` | `chat`、`models`、`upload`、`search`、`fetch` |
| xAI | `pl-model-openai-xai` | `xai-live` | `chat`、`models` |
| MiMo | `pl-model-openai-mimo` | `mimo-live` | `chat`、`models` |

- `chat --help` 列出对话参数。`--wire` 用于选择端点支持的 Chat HTTP、Responses HTTP 或 Responses WebSocket。`--effort` 使用模型目录声明的候选值，`--cache-scope` 由端点缓存能力决定是否发送缓存键。
- `chat --stream` 显示流式文本，重试产生的新尝试单独标记。默认输出最终可见文本、工具调用与用量。用 `--tools` 传入 [ToolSpec](pl-model-openai-wire/src/completion/tool.rs) JSON 数组，GLM Chat 可加 `--tool-stream` 调试增量工具参数。
- `image --model "$MODEL" --prompt 'A blue square' --output /path/to/image.png` 调用 Images 能力，输出路径须尚未存在。`search --model "$MODEL" --query '…'` 调用支持 `/alpha/search` 的兼容端点。
- DeepSeek 的 `upload --file /path/to/input`、`search --query '…'`、`fetch --url https://example.org` 分别调试 Files 与 Search & Fetch。由使用者所选端点接收文件或请求。

订阅认证独立运行 `cargo run --locked -p pl-model-auth --example login`。在本机浏览器打开程序显示的链接；成功后程序验证 OAuth 凭据并在退出时丢弃。
