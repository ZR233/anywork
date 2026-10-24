// Adapter-owned typed collection of the current generated Studio bridge surface.
//
// 这是手写 adapter 的导出汇集，不是 FRB 生成文件：`lib/src/rust/**` 完全由 FRB
// 独占，本文件只把当前生成模块里的 typed API 转出给 infrastructure/frb 手写层
// 使用（`import 'studio_bridge_api.dart' as frb`）。
//
// 边界约定：
// - 不写包装函数、类型别名或 raw JSON 回退，不复制 DTO，只做 `export` 汇集；
// - 模块集合跟随当前生成输出，旧模块（如已移除的 `handlers/providers.dart`）
//   在这里不保留转发，账号操作导出当前的 `handlers/accounts.dart`；
// - 生成器统一重建输出集后，本文件与引用方保持同一份 canonical 生成 API。

export '../../rust/api/studio/handlers/history.dart';
export '../../rust/api/studio/handlers/agent_profiles.dart';
export '../../rust/api/studio/handlers/external_state.dart';
export '../../rust/api/studio/handlers/lifecycle.dart';
export '../../rust/api/studio/handlers/prompt.dart';
export '../../rust/api/studio/handlers/persistence.dart';
export '../../rust/api/studio/handlers/accounts.dart';
export '../../rust/api/studio/handlers/acp.dart';
export '../../rust/api/studio/handlers/acp_install.dart';
export '../../rust/api/studio/handlers/bots.dart';
export '../../rust/api/studio/handlers/settings.dart';
export '../../rust/api/studio/handlers/snapshot.dart';
export '../../rust/api/studio/handlers/thread.dart';
export '../../rust/api/studio/handlers/updater.dart';
export '../../rust/api/studio/subscription.dart';
export '../../rust/api/studio/types/event.dart';
export '../../rust/api/studio/types/agent_profile.dart';
export '../../rust/api/studio/types/acp.dart';
export '../../rust/api/studio/types/acp_install.dart';
export '../../rust/api/studio/types/bots.dart';
export '../../rust/api/studio/types/error.dart';
export '../../rust/api/studio/types/response.dart';
export '../../rust/api/studio/types/runtime.dart';
export '../../rust/api/studio/types/thread_stream.dart';
export '../../rust/api/studio/types/thread_preparation.dart';
export '../../rust/api/studio/types/settings.dart';
export '../../rust/api/studio/types/updater.dart';
