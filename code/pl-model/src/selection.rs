use pl_model_wire::model::{
    AgentTaskCategory, BundledSelectionGuide, ModelSelectionGuide, ModelSelectionMeasurement,
    ModelSelectionSource, ModelSelectionSourceKind,
};

/// 按精确「目录 + model_id」查找内置选模资料。
///
/// 同一 model_id 在不同目录（或同目录的不同账号）之间不互相借用资料；未收录的型号返回
/// `None`，由调用方如实报告未知。
pub fn bundled_selection_guide(
    catalog: &str,
    model_id: &str,
) -> Option<&'static ModelSelectionGuide> {
    BUNDLED_SELECTION_GUIDES
        .iter()
        .find(|entry| entry.model_id == model_id && entry.catalogs.contains(&catalog))
        .map(|entry| &entry.guide)
}

/// 全部内置选模资料，供目录打包完整性校验消费。
pub fn bundled_selection_guides() -> &'static [BundledSelectionGuide] {
    BUNDLED_SELECTION_GUIDES
}

/// 2026-10-22（UTC）的核验时间；本批次资料统一在该日期核对来源。
const VERIFIED_AT: i64 = 1_792_627_200;
const TERRA_VERIFIED_AT: i64 = 1_793_059_200;
const GPT62_VERIFIED_AT: i64 = 1_794_960_000;
const GEMINI4_VERIFIED_AT: i64 = 1_795_478_400; // 2026-11-24 UTC
const GLM53_FLASH_VERIFIED_AT: i64 = 1_795_651_200; // 2026-11-26 UTC

const OPENAI_MODELS_DOC: &str = "https://developers.openai.com/api/docs/models";

static BUNDLED_SELECTION_GUIDES: &[BundledSelectionGuide] = &[
    BundledSelectionGuide {
        catalogs: &["openai"],
        model_id: "gpt-6.2-astra",
        guide: ModelSelectionGuide {
            summary: "OpenAI 复杂推理、编码与专业工作的旗舰型号，适合高难度、长流程任务，以及需要结合图像与文档的分析。",
            task_suitability: &[
                AgentTaskCategory::Reasoning,
                AgentTaskCategory::Coding,
                AgentTaskCategory::Tooling,
                AgentTaskCategory::Multimodal,
            ],
            limitations: &[
                "相对 GPT-6.2 Sol 单价更高，应按任务难度选择",
                "不支持 none 或 minimal 思考档位；工具调用须使用 Responses API",
                "修改已有上下文前缀时，服务端可能丢弃后续推理项，影响质量、用量与延迟",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://developers.openai.com/api/docs/models/gpt-6.2-astra",
                    verified_at: GPT62_VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://developers.openai.com/api/docs/guides/latest-model",
                    verified_at: GPT62_VERIFIED_AT,
                    measurement: None,
                },
            ],
        },
    },
    BundledSelectionGuide {
        catalogs: &["openai"],
        model_id: "gpt-6.2-sol",
        guide: ModelSelectionGuide {
            summary: "面向日常编码、自然写作与多步智能体工作的 OpenAI 主力型号，相对 GPT-6.2 Astra 成本更低，适合作为常用实现与协作模型。",
            task_suitability: &[
                AgentTaskCategory::Coding,
                AgentTaskCategory::Tooling,
                AgentTaskCategory::General,
            ],
            limitations: &[
                "最困难的推理和专业任务可评估 GPT-6.2 Astra，主力定位不保证适合所有任务",
                "不支持 none 或 minimal 思考档位；工具调用须使用 Responses API",
                "修改已有上下文前缀时，服务端可能丢弃后续推理项，影响质量、用量与延迟",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://developers.openai.com/api/docs/models/gpt-6.2-sol",
                    verified_at: GPT62_VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://developers.openai.com/api/docs/guides/latest-model",
                    verified_at: GPT62_VERIFIED_AT,
                    measurement: None,
                },
            ],
        },
    },
    BundledSelectionGuide {
        catalogs: &["openai"],
        model_id: "gpt-6-astra",
        guide: ModelSelectionGuide {
            summary: "OpenAI 复杂推理与编码旗舰，适合高难度、长流程的规划与实现任务；相对 Sol 档位换取更强推理，同时单价更高。",
            task_suitability: &[
                AgentTaskCategory::Reasoning,
                AgentTaskCategory::Coding,
                AgentTaskCategory::Tooling,
            ],
            limitations: &[
                "厂商发布稿引用的基准分数来自 Artificial Analysis v4.1.1 口径，不能与新版指数直接比较",
                "同目录 Sol/Luna 档位在多数边界清晰的任务上更省成本，旗舰定位不等于整体性价比更高",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: OPENAI_MODELS_DOC,
                    verified_at: VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://openai.com/index/gpt-6-astra/",
                    verified_at: VERIFIED_AT,
                    measurement: Some(ModelSelectionMeasurement {
                        model: "GPT-6 Astra",
                        effort: None,
                        metric: "厂商引用的 Artificial Analysis Intelligence Index",
                        metric_version: Some("v4.1.1"),
                        score: None,
                    }),
                },
            ],
        },
    },
    BundledSelectionGuide {
        catalogs: &["openai"],
        model_id: "gpt-6.1-terra",
        guide: ModelSelectionGuide {
            summary: "面向视觉推理、屏幕操作与自然写作的 OpenAI 型号；适合以图像理解和交互为核心的任务。",
            task_suitability: &[AgentTaskCategory::Multimodal, AgentTaskCategory::Reasoning],
            limitations: &[
                "官方资料未提供此处可直接比较的独立基准分数或社区结论",
                "本资料不将其定位为编码旗舰；具体适配仍取决于任务输入与所选 effort",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://developers.openai.com/api/docs/models/gpt-6.1-terra",
                    verified_at: TERRA_VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://developers.openai.com/api/docs/guides/latest-model",
                    verified_at: TERRA_VERIFIED_AT,
                    measurement: None,
                },
            ],
        },
    },
    BundledSelectionGuide {
        catalogs: &["openai"],
        model_id: "gpt-6.1-sol",
        guide: ModelSelectionGuide {
            summary: "在复杂编码、计算机使用与 Agent 任务上接近旗舰水平的能力/成本折中档位，适合作为主力实现模型。",
            task_suitability: &[
                AgentTaskCategory::Coding,
                AgentTaskCategory::Tooling,
                AgentTaskCategory::Reasoning,
            ],
            limitations: &[
                "官方定位为折中档，最高难度推理与 Astra 仍有差距",
                "未核实独立基准分数，外部评分与社区结论保持未知",
            ],
            sources: &[ModelSelectionSource {
                kind: ModelSelectionSourceKind::Official,
                url: OPENAI_MODELS_DOC,
                verified_at: VERIFIED_AT,
                measurement: None,
            }],
        },
    },
    BundledSelectionGuide {
        catalogs: &["openai"],
        model_id: "gpt-6-sol",
        guide: ModelSelectionGuide {
            summary: "面向复杂编码与 Agent 工作流的主力档位，能力低于旗舰但成本更可控，适合多数实现与修复任务。",
            task_suitability: &[AgentTaskCategory::Coding, AgentTaskCategory::Tooling],
            limitations: &[
                "开放式高难推理任务仍应优先 Astra 或 6.1 Sol",
                "未核实独立基准分数，不能据此认定质量优于其他供应商同类档位",
            ],
            sources: &[ModelSelectionSource {
                kind: ModelSelectionSourceKind::Official,
                url: OPENAI_MODELS_DOC,
                verified_at: VERIFIED_AT,
                measurement: None,
            }],
        },
    },
    BundledSelectionGuide {
        catalogs: &["openai"],
        model_id: "gpt-6-luna",
        guide: ModelSelectionGuide {
            summary: "低成本高吞吐档位，适合边界清晰、批量或高频的编码与工具任务；复杂开放式任务需要更多验收与返修预算。",
            task_suitability: &[
                AgentTaskCategory::Coding,
                AgentTaskCategory::Tooling,
                AgentTaskCategory::LongContext,
            ],
            limitations: &[
                "社区对它与 DeepSeek、GLM 同类档位的编码优劣存在分歧，属个体经验而非一致结论",
                "Artificial Analysis 指数为 Max effort 测量，其他 effort 档位不可等同",
                "预计边际成本低不等于返修成本低，质量要求高的任务需要留出复核时间",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: OPENAI_MODELS_DOC,
                    verified_at: VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Benchmark,
                    url: "https://artificialanalysis.ai/models/comparisons/gpt-6-luna-vs-deepseek-v4-pro",
                    verified_at: VERIFIED_AT,
                    measurement: Some(ModelSelectionMeasurement {
                        model: "GPT-6 Luna",
                        effort: Some("max"),
                        metric: "Artificial Analysis Intelligence Index",
                        metric_version: Some("v4.3.2"),
                        score: Some(38.0),
                    }),
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Community,
                    url: "https://www.reddit.com/r/DeepSeek/comments/1wns9ar/gpt_6_luna_vs_deepseek_v41_flash_for_coding/",
                    verified_at: VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Community,
                    url: "https://www.reddit.com/r/opencode/comments/1wslocq/gpt_6_luna_glm_53_flash_or_dsv41_flash/",
                    verified_at: VERIFIED_AT,
                    measurement: None,
                },
            ],
        },
    },
    BundledSelectionGuide {
        catalogs: &["deepseek"],
        model_id: "deepseek-v4-pro",
        guide: ModelSelectionGuide {
            summary: "DeepSeek 旗舰推理档位，思考模式配合百万级上下文，适合多步排查、长程编码与需要完整推理链的任务。",
            task_suitability: &[
                AgentTaskCategory::Reasoning,
                AgentTaskCategory::Coding,
                AgentTaskCategory::LongContext,
            ],
            limitations: &[
                "基准指数为 0813 版本 Max effort 测量，其他日期版本或 effort 不可混算",
                "effort 档位与按时间段的计价由供应商定义，账号实际额度与可用性仍需自行确认",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://api-docs.deepseek.com/news/news260813/",
                    verified_at: VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Benchmark,
                    url: "https://artificialanalysis.ai/models/comparisons/gpt-6-luna-vs-deepseek-v4-pro",
                    verified_at: VERIFIED_AT,
                    measurement: Some(ModelSelectionMeasurement {
                        model: "DeepSeek V4 Pro 0813",
                        effort: Some("max"),
                        metric: "Artificial Analysis Intelligence Index",
                        metric_version: Some("v4.3.2"),
                        score: Some(36.0),
                    }),
                },
            ],
        },
    },
    BundledSelectionGuide {
        catalogs: &["deepseek"],
        model_id: "deepseek-flash",
        guide: ModelSelectionGuide {
            summary: "DeepSeek 快速多模态推理档位（V4.1 Flash），适合低成本、高并发的编码、摘要与图片辅助任务。",
            task_suitability: &[
                AgentTaskCategory::Coding,
                AgentTaskCategory::Multimodal,
                AgentTaskCategory::Tooling,
            ],
            limitations: &[
                "社区对它与 Luna 等同类档位的编码表现评价分歧，工作流与任务类型影响很大",
                "未核实独立基准分数，不能把个别好评当作一致结论",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Community,
                    url: "https://www.reddit.com/r/DeepSeek/comments/1wns9ar/gpt_6_luna_vs_deepseek_v41_flash_for_coding/",
                    verified_at: VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Community,
                    url: "https://www.reddit.com/r/opencode/comments/1wslocq/gpt_6_luna_glm_53_flash_or_dsv41_flash/",
                    verified_at: VERIFIED_AT,
                    measurement: None,
                },
            ],
        },
    },
    BundledSelectionGuide {
        catalogs: &["xai"],
        model_id: "grok-4.7",
        guide: ModelSelectionGuide {
            summary: "xAI 旗舰编码与 Agent 档位，适合工具调用密集、需要多步执行与长输出的任务。",
            task_suitability: &[AgentTaskCategory::Coding, AgentTaskCategory::Tooling],
            limitations: &[
                "基准指数 46 的测量条件为 xhigh 档，其他 effort 档位不可等同",
                "xhigh 档输出量约为同级模型的两倍以上，长任务需先评估预算与耗时",
                "不能沿用 Grok 4.6 的价格或档位结论推断本型号",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Benchmark,
                    url: "https://artificialanalysis.ai/models/grok-4-7/",
                    verified_at: VERIFIED_AT,
                    measurement: Some(ModelSelectionMeasurement {
                        model: "Grok 4.7",
                        effort: Some("xhigh"),
                        metric: "Artificial Analysis Intelligence Index",
                        metric_version: Some("v4.3.2"),
                        score: Some(46.0),
                    }),
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Benchmark,
                    url: "https://artificialanalysis.ai/articles/benchmarking-grok-4-7",
                    verified_at: VERIFIED_AT,
                    measurement: Some(ModelSelectionMeasurement {
                        model: "Grok 4.7",
                        effort: Some("xhigh"),
                        metric: "Artificial Analysis Intelligence Index（文章仅给出 xhigh 条件与 token 用量，未标注指标版本）",
                        metric_version: None,
                        score: None,
                    }),
                },
            ],
        },
    },
    BundledSelectionGuide {
        catalogs: &["zhipu", "zhipu-responses"],
        model_id: "glm-5.3",
        guide: ModelSelectionGuide {
            summary: "智谱编码与长程 Agent 档位，厂商说明强调编码与工具编排；订阅按积分配额使用。",
            task_suitability: &[
                AgentTaskCategory::Coding,
                AgentTaskCategory::Tooling,
                AgentTaskCategory::LongContext,
            ],
            limitations: &[
                "Max 与 Low effort 的指数与成本差异明显（45/34），不能合并为一个通用分数",
                "Coding Plan 积分不等于无限额度，实际可用量取决于账号与当期政策",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://z.ai/blog/glm-5.3",
                    verified_at: VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Benchmark,
                    url: "https://artificialanalysis.ai/models/glm-5-3/",
                    verified_at: VERIFIED_AT,
                    measurement: Some(ModelSelectionMeasurement {
                        model: "GLM-5.3",
                        effort: Some("max"),
                        metric: "Artificial Analysis Intelligence Index",
                        metric_version: Some("v4.3.2"),
                        score: Some(45.0),
                    }),
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Benchmark,
                    url: "https://artificialanalysis.ai/models/comparisons/glm-5-3-low-vs-glm-5-3",
                    verified_at: VERIFIED_AT,
                    measurement: Some(ModelSelectionMeasurement {
                        model: "GLM-5.3",
                        effort: Some("low"),
                        metric: "Artificial Analysis Intelligence Index",
                        metric_version: Some("v4.3.2"),
                        score: Some(34.0),
                    }),
                },
            ],
        },
    },
    BundledSelectionGuide {
        catalogs: &["zhipu", "zhipu-responses"],
        model_id: "glm-5.3-flash",
        guide: ModelSelectionGuide {
            summary: "智谱面向日常编码的低成本多模态模型，适合按明确方案实现功能、补写和运行测试、定位代码调用点，以及结合截图排查界面问题。",
            task_suitability: &[
                AgentTaskCategory::Coding,
                AgentTaskCategory::Tooling,
                AgentTaskCategory::Multimodal,
            ],
            limitations: &[
                "跨模块设计取舍和关键审查宜交给更强的推理模型",
                "在 Artificial Analysis 的 Max 档评测中，单题耗时高于同类模型中位数，且输出较长",
                "糊来帮的内置目录当前接收文本和图片输入",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://docs.bigmodel.cn/cn/guide/models/vlm/glm-5.3-flash",
                    verified_at: GLM53_FLASH_VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://docs.bigmodel.cn/cn/coding-plan/learning-resources/flash-and-glm-5-4",
                    verified_at: GLM53_FLASH_VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Benchmark,
                    url: "https://artificialanalysis.ai/models/glm-5-3-flash",
                    verified_at: GLM53_FLASH_VERIFIED_AT,
                    measurement: Some(ModelSelectionMeasurement {
                        model: "GLM-5.3-Flash",
                        effort: Some("max"),
                        metric: "Artificial Analysis Intelligence Index",
                        metric_version: Some("v5.0.2"),
                        score: Some(28.0),
                    }),
                },
            ],
        },
    },
    BundledSelectionGuide {
        catalogs: &["mimo"],
        model_id: "mimo-v2.5-pro",
        guide: ModelSelectionGuide {
            summary: "小米 MiMo 长程 Agent 档位，思考模式配合百万级上下文，以 Token Plan 订阅计量；适合中长流程的工具编排任务。",
            task_suitability: &[AgentTaskCategory::Tooling, AgentTaskCategory::LongContext],
            limitations: &[
                "榜单已将该型号标注 deprecated，只继续更新默认 10k 输入工作负载，其他工作负载结果为历史数据",
                "Artificial Analysis 指数 26 属于上述归档测量，不是实时结果，也不应当前速度承诺",
                "目录能力为纯文本输入，不能按视觉或多模态任务派发",
                "Token Plan 的 1x/Pro 2x 倍率只描述计量方式，不证明额度充足",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://mimo.xiaomi.com/mimo-v2-5",
                    verified_at: VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Benchmark,
                    url: "https://artificialanalysis.ai/models/mimo-v2-5-pro/",
                    verified_at: VERIFIED_AT,
                    measurement: Some(ModelSelectionMeasurement {
                        model: "MiMo V2.5 Pro",
                        effort: None,
                        metric: "Artificial Analysis Intelligence Index",
                        metric_version: Some("v4.3.2"),
                        score: Some(26.0),
                    }),
                },
            ],
        },
    },
    BundledSelectionGuide {
        catalogs: &["gemini", "vertex-ai"],
        model_id: "gemini-4-hydrogen",
        guide: ModelSelectionGuide {
            summary: "Google Gemini 4 日常主力多模态推理模型，兼顾低延迟、高性价比与 1M 统一上下文，适合日常编码、多步工具调用与并行子任务。",
            task_suitability: &[
                AgentTaskCategory::Coding,
                AgentTaskCategory::Tooling,
                AgentTaskCategory::Multimodal,
                AgentTaskCategory::LongContext,
                AgentTaskCategory::General,
            ],
            limitations: &[
                "支持思考档位 low/medium/high/xhigh（默认 high），不支持 minimal；xhigh 会显著增加耗时与思考词元消耗",
                "仅支持隐式上下文缓存（4,096 tokens 起生效），不支持显式缓存管理，亦不包含 OpenAI hosted tool 语义",
                "通过 Vertex AI 访问时按区域模型可用性提供服务，非 Global 区域端点另行计价",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://ai.google.dev/gemini-api/docs/models/gemini-4-hydrogen",
                    verified_at: GEMINI4_VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://ai.google.dev/gemini-api/docs/pricing",
                    verified_at: GEMINI4_VERIFIED_AT,
                    measurement: None,
                },
            ],
        },
    },
    BundledSelectionGuide {
        catalogs: &["gemini", "vertex-ai"],
        model_id: "gemini-4-neon",
        guide: ModelSelectionGuide {
            summary: "Google Gemini 4 中高阶前沿多模态模型，在复杂软件工程、知识工作与科学分析上提供接近旗舰的深度推理与更快的端到端完成速度。",
            task_suitability: &[
                AgentTaskCategory::Coding,
                AgentTaskCategory::Reasoning,
                AgentTaskCategory::Tooling,
                AgentTaskCategory::Multimodal,
                AgentTaskCategory::LongContext,
            ],
            limitations: &[
                "仅提供付费层（无 Free Tier），单价为 Hydrogen 的两倍，常规轻任务优先考虑 gemini-4-hydrogen",
                "支持思考档位 low/medium/high/xhigh（默认 high），不支持 minimal；仅支持隐式上下文缓存",
                "通过 Vertex AI 访问时按区域可用性提供服务，非 Global 区域端点另行计价",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://ai.google.dev/gemini-api/docs/models/gemini-4-neon",
                    verified_at: GEMINI4_VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://ai.google.dev/gemini-api/docs/pricing",
                    verified_at: GEMINI4_VERIFIED_AT,
                    measurement: None,
                },
            ],
        },
    },
    BundledSelectionGuide {
        catalogs: &["gemini", "vertex-ai"],
        model_id: "gemini-4-argon",
        guide: ModelSelectionGuide {
            summary: "Google Gemini 4 高效前沿推理模型，面向复杂编码、Agent 编排与数理科学任务，相对 Carbon 响应更快且单轮思考词元开销更低。",
            task_suitability: &[
                AgentTaskCategory::Reasoning,
                AgentTaskCategory::Coding,
                AgentTaskCategory::Tooling,
                AgentTaskCategory::Multimodal,
                AgentTaskCategory::LongContext,
            ],
            limitations: &[
                "仅提供付费层（无 Free Tier）；目录内置为 2026-12-01 起的正式标准价，2026-11-30 前存在官方半价促销",
                "支持思考档位 low/medium/high（默认 medium），不支持 minimal 或 xhigh；仅支持隐式上下文缓存",
                "最高难度的深度验证与长程排查可升级评估 gemini-4-carbon",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://ai.google.dev/gemini-api/docs/models/gemini-4-argon",
                    verified_at: GEMINI4_VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://ai.google.dev/gemini-api/docs/pricing",
                    verified_at: GEMINI4_VERIFIED_AT,
                    measurement: None,
                },
            ],
        },
    },
    BundledSelectionGuide {
        catalogs: &["gemini", "vertex-ai"],
        model_id: "gemini-4-carbon",
        guide: ModelSelectionGuide {
            summary: "Google Gemini 4 最强深度推理旗舰模型，适合复杂架构设计、长程自主编码、密集多模态核验、科研推理与安全审计。",
            task_suitability: &[
                AgentTaskCategory::Reasoning,
                AgentTaskCategory::Coding,
                AgentTaskCategory::Tooling,
                AgentTaskCategory::Multimodal,
                AgentTaskCategory::LongContext,
            ],
            limitations: &[
                "仅提供付费层（无 Free Tier），单轮思考词元消耗与首字延迟最高；目录内置为 2026-12-01 起的正式标准价（2026-11-30 前有半价促销）",
                "支持思考档位 low/medium/high（默认 medium），不支持 minimal 或 xhigh；仅支持隐式上下文缓存",
                "日常迭代与交互式任务优先考虑 gemini-4-hydrogen 或 gemini-4-neon",
            ],
            sources: &[
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://ai.google.dev/gemini-api/docs/models/gemini-4-carbon",
                    verified_at: GEMINI4_VERIFIED_AT,
                    measurement: None,
                },
                ModelSelectionSource {
                    kind: ModelSelectionSourceKind::Official,
                    url: "https://ai.google.dev/gemini-api/docs/pricing",
                    verified_at: GEMINI4_VERIFIED_AT,
                    measurement: None,
                },
            ],
        },
    },
];
