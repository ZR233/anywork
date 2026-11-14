use std::{
    num::NonZeroU32,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, ensure};
use clap::{Args, Parser, Subcommand};
use pl_studio_runtime::{
    NewThreadModelRoute, SkillSearchOptions, StudioRuntimeOptions, ThreadModeId,
};

#[derive(Parser)]
#[command(name = "anywk", version = pl_studio_update::STUDIO_VERSION.trim(), about = "在原生 Studio 运行时中执行单个任务")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand)]
pub enum Command {
    /// 执行任务，清洁关闭后将最终助手文本写入标准输出。
    Exec(ExecArgs),
}

#[derive(Args)]
#[command(
    after_long_help = "所有相对路径以进程启动目录为基准解析，不改变 HOME 或全局工作目录。\n凭据只读取原生账号 bearer_token_env 指定的非空环境变量；不访问系统凭据库或交互登录。\n技能优先级：项目 > 默认用户 > 系统 > 配置 external_dirs > --skill-dir 出现顺序。\n--skill-dir 直接指向只读技能集合根，不自动添加 .agents/skills，也不扩大写权限。\n--output-dir 可选启用原子运行归档，输出 run.json、events.jsonl、contents/ 与 result.json。\n\n容器示例：\n  anywk exec --studio-home /runs/profile --cwd /workspace/task --account benchmark --model vendor/model --prompt-file /runs/prompt.txt --no-default-user-skills --skill-dir /opt/evaluation/skills --output-dir /runs/export"
)]
pub struct ExecArgs {
    /// 显式 Studio 数据根；其中必须已有有效的 config.toml。
    #[arg(long, value_name = "PATH")]
    pub studio_home: PathBuf,
    /// 已存在的本地任务目录；允许非 Git 目录。
    #[arg(long, value_name = "PATH")]
    pub cwd: PathBuf,
    /// 原生账号 ID。
    #[arg(long, value_name = "ID")]
    pub account: String,
    /// 完整原生模型 ID，不拆分其中的斜杠。
    #[arg(long, value_name = "ID")]
    pub model: String,
    /// 由所选模型的原生能力校验。
    #[arg(long, value_name = "VALUE")]
    pub reasoning_effort: Option<String>,
    /// 原生工作模式 ID。
    #[arg(long, default_value = "mode.simple", value_name = "ID")]
    pub mode: String,
    /// UTF-8 任务文件；- 表示从标准输入读取至结束。正文不会进入进程参数。
    #[arg(long, value_name = "PATH")]
    pub prompt_file: PathBuf,
    /// 收紧根输入的模型步数预算；省略时沿用配置，不是整棵任务树的总预算。
    #[arg(long, value_name = "N")]
    pub max_model_steps: Option<NonZeroU32>,
    /// 仅关闭隐式 HOME/.agents/skills 来源，显式追加同一路径仍有效。
    #[arg(long)]
    pub no_default_user_skills: bool,
    /// 追加只读技能集合根；可重复，按首次出现顺序保留，支持既有 ~ 展开。
    #[arg(long, value_name = "PATH")]
    pub skill_dir: Vec<PathBuf>,
    /// 可选原子导出目录（run.json / events.jsonl / contents / result.json）；必须不存在或为空可写非符号链接目录。
    #[arg(long, value_name = "PATH")]
    pub output_dir: Option<PathBuf>,
}

pub struct PreparedExport {
    pub output_dir: PathBuf,
    pub run_id: String,
    pub cwd: PathBuf,
    pub studio_home: PathBuf,
    pub account_id: Option<String>,
    pub model_id: Option<String>,
    pub reasoning_effort: Option<String>,
    pub mode: Option<String>,
    pub max_model_steps: Option<u32>,
    pub prompt_sha256: String,
    pub skill_search: SkillSearchOptions,
}

pub struct PreparedExec {
    pub runtime: StudioRuntimeOptions,
    pub cwd: PathBuf,
    pub route: NewThreadModelRoute,
    pub mode: ThreadModeId,
    pub prompt: String,
    pub max_model_steps: Option<NonZeroU32>,
    pub export: Option<PreparedExport>,
}

impl ExecArgs {
    /// Synchronous input preparation runs before acquiring any product resources.
    pub fn prepare(self, startup_cwd: &Path, stdin: impl std::io::Read) -> Result<PreparedExec> {
        let resolve = |path: &Path| pl_tool::workspace::resolve_absolute_path(startup_cwd, path);
        let studio_home = resolve(&self.studio_home)?;
        let cwd = resolve(&self.cwd)?;
        ensure!(
            std::fs::metadata(&cwd)
                .context("无法访问任务目录")?
                .is_dir(),
            "任务路径不是目录"
        );
        std::fs::read_dir(&cwd)
            .context("无法读取任务目录")?
            .next()
            .transpose()?;
        // The authoritative loader repeats the read under Strict; this is only input preflight.
        std::fs::File::open(studio_home.join("config.toml"))
            .context("必须提供已有的 config.toml")?;
        let mut input: Box<dyn std::io::Read + '_> = if self.prompt_file == Path::new("-") {
            Box::new(stdin)
        } else {
            Box::new(std::fs::File::open(resolve(&self.prompt_file)?).context("无法打开任务文件")?)
        };
        let mut prompt = String::new();
        input
            .read_to_string(&mut prompt)
            .context("任务必须为有效 UTF-8 文本")?;
        ensure!(!prompt.trim().is_empty(), "任务正文不能为空白");
        let output_dir = self
            .output_dir
            .as_deref()
            .map(resolve)
            .transpose()
            .context("无法解析输出目录路径")?;
        if let Some(dir) = &output_dir {
            pl_studio_runtime::validate_export_output_dir_preflight(dir)
                .context("输出目录必须不存在或为空可写非符号链接目录")?;
        }
        let mut runtime = StudioRuntimeOptions::cli(studio_home.clone());
        runtime.skill_search =
            SkillSearchOptions::resolve(!self.no_default_user_skills, self.skill_dir, startup_cwd)?;
        let export = output_dir.map(|output_dir| PreparedExport {
            output_dir,
            run_id: format!("run-{}", uuid::Uuid::new_v4()),
            cwd: cwd.clone(),
            studio_home,
            account_id: Some(self.account.clone()),
            model_id: Some(self.model.clone()),
            reasoning_effort: self.reasoning_effort.clone(),
            mode: Some(self.mode.clone()),
            max_model_steps: self.max_model_steps.map(NonZeroU32::get),
            prompt_sha256: pl_studio_runtime::export_sha256_hex(prompt.as_bytes()),
            skill_search: runtime.skill_search.clone(),
        });
        Ok(PreparedExec {
            runtime,
            cwd,
            route: NewThreadModelRoute {
                account_id: self.account,
                model_id: self.model,
                effort: self.reasoning_effort,
            },
            mode: ThreadModeId::new(self.mode)?,
            prompt,
            max_model_steps: self.max_model_steps,
            export,
        })
    }
}
