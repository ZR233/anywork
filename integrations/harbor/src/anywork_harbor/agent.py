"""Harbor installed-agent 的生产 CLI 适配。"""

import asyncio
import hashlib
import json
import shlex
import tempfile
import time
from importlib.resources import files
from pathlib import Path, PurePosixPath
from typing import ClassVar
from uuid import uuid4

from harbor.agents.agent_auth_resolution import parse_model_name
from harbor.agents.capabilities import AgentCapabilities
from harbor.agents.installed.base import (
    BaseInstalledAgent,
    NonZeroAgentExitCodeError,
    with_prompt_template,
)
from harbor.agents.options import InstalledAgentOptions
from pydantic import Field, model_validator

from .artifacts import read_and_validate_run_artifacts
from .errors import AnywkArtifactError, AnywkSetupError, classify_failure
from .trajectory import convert_run_to_atif, populate_context


class AnyworkOptions(InstalledAgentOptions):
    binary_path: Path | None = None
    config_path: Path
    account_id: str = Field(min_length=1)
    mode: str = "mode.simple"
    max_model_steps: int | None = Field(default=None, gt=0)
    no_default_user_skills: bool = True
    extra_skill_dirs: list[Path] = Field(default_factory=list)
    history_seed_dir: Path | None = None
    expected_git_commit: str | None = Field(default=None, pattern=r"^[0-9a-f]{40}$")
    config: None = None
    base_url: None = None

    @model_validator(mode="after")
    def require_binary(self):
        if self.history_seed_dir is not None and self.expected_git_commit is None:
            raise ValueError("历史种子必须提供 expected_git_commit")
        if not self.skip_install and self.binary_path is None:
            raise ValueError("安装必须提供 binary_path")
        return self


def check_upload_tree(directory: Path) -> None:
    if not directory.is_dir() or directory.is_symlink():
        raise AnywkSetupError("技能或种子目录无效")
    for child in directory.rglob("*"):
        if child.is_symlink() or not (child.is_file() or child.is_dir()):
            raise AnywkSetupError("上传目录不接受链接或特殊文件")


class AnyworkInstalledAgent(BaseInstalledAgent):
    options_model = AnyworkOptions
    capabilities = AgentCapabilities(
        atif=True, native_config=True, reasoning_effort=True, skills=True
    )
    MODEL_CONNECTION = None
    ERROR_PATTERNS: ClassVar[list] = []

    @staticmethod
    def name() -> str:
        return "anywk"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if not self.model_name:
            raise AnywkSetupError("必须显式提供 Harbor model_name")
        if self.mcp_servers or self.load_trajectory:
            raise AnywkSetupError("不支持 Harbor MCP 注入或轨迹恢复")
        self.cli_exit_code = None
        self._run_error = None
        self._validated_identity = None
        self._metadata = {"artifactValidation": "notStarted"}
        self._cleanup = {
            "attempted": False,
            "clean": True,
            "remainingKnownPids": [],
            "identityMismatch": False,
            "elapsedMs": 0,
            "error": None,
        }

    def _classify_exec_error(self, command, result):
        self.cli_exit_code = result.return_code
        error = NonZeroAgentExitCodeError(f"anywk 进程退出码：{result.return_code}")
        error.return_code = result.return_code
        return error

    def get_version_command(self):
        return "/installed-agent/anywk --version"

    async def _check_binary(self, environment):
        command = (
            "test -r /proc/self/stat && test -r /proc/self/environ && "
            "command -v setsid kill cat tr grep sed date sleep sha256sum mv >/dev/null && "
            "setsid --wait /bin/sh -c 'exit 0' && /installed-agent/anywk --version && "
            "sha256sum /installed-agent/anywk"
        )
        try:
            result = await self.exec_as_agent(environment, command)
            lines = result.stdout.splitlines()
            version_line = next(line for line in lines if line.startswith("anywk "))
            version = version_line.removeprefix("anywk ").strip()
            if self.options.version is not None and version != self.options.version:
                raise AnywkSetupError("容器内二进制版本与指定版本不一致")
            digest = lines[-1].split()[0]
            if len(digest) != 64:
                raise AnywkSetupError("二进制摘要无效")
            self._version = version
            self._metadata.update(binaryVersion=version, binarySha256=digest)
        except (NonZeroAgentExitCodeError, ValueError, IndexError, StopIteration) as error:
            raise AnywkSetupError("二进制、动态加载器或 Linux 控制前置能力不可用") from error

    async def install(self, environment):
        source = self.options.binary_path
        if source is None or not source.is_file() or source.is_symlink():
            raise AnywkSetupError("binary_path 必须是可读普通文件")
        await environment.upload_file(source, "/installed-agent/anywk")
        await self.exec_as_root(environment, "chmod 755 /installed-agent/anywk")
        await self._check_binary(environment)

    async def _own(self, environment, path: str):
        if environment.default_user is not None:
            await self.exec_as_root(
                environment, shlex.join(["chown", "-R", str(environment.default_user), path])
            )

    async def configure(self, environment):
        await self._check_binary(environment)
        self.launcher_id = str(uuid4())
        self.private = PurePosixPath("/tmp/anywk-harbor") / self.launcher_id
        self.native = self.environment_logs_dir / "native"
        config = self.options.config_path
        if not config.is_file() or config.is_symlink():
            raise AnywkSetupError("config_path 必须是原生主配置文件")
        try:
            await self.exec_as_agent(environment, shlex.join(["mkdir", "-p", str(self.private)]))
            await self.exec_as_agent(environment, shlex.join(["chmod", "700", str(self.private)]))
            await self.exec_as_agent(
                environment, shlex.join(["mkdir", str(self.private / "studio-home")])
            )
            cwd = await self.exec_as_agent(environment, "pwd -P")
            self.task_cwd = cwd.stdout.strip()
            if not PurePosixPath(self.task_cwd).is_absolute():
                raise AnywkSetupError("任务目录不是容器绝对路径")
            await self.exec_as_agent(environment, shlex.join(["mkdir", str(self.native)]))
            if self.options.history_seed_dir:
                from .history_seed import validate_seed

                seed = validate_seed(
                    self.options.history_seed_dir,
                    config=config,
                    expected_version=self._version,
                    expected_commit=self.options.expected_git_commit,
                )
                await environment.upload_dir(
                    self.options.history_seed_dir / "data", str(self.private / "studio-home/data")
                )
                self._metadata["historySeedSha256"] = seed["seedHash"]
            await environment.upload_file(config, str(self.private / "studio-home/config.toml"))
            for name in ("launch.sh", "cancel.sh"):
                script = files("anywork_harbor").joinpath("scripts", name)
                with tempfile.TemporaryDirectory() as temporary:
                    local = Path(temporary) / name
                    local.write_text(script.read_text())
                    await environment.upload_file(local, str(self.private / name))
            self.skill_dirs = [self.skills_dir] if self.skills_dir else []
            for index, source in enumerate(self.options.extra_skill_dirs):
                check_upload_tree(source)
                destination = str(self.private / "skills" / f"extra-{index:03}")
                await environment.upload_dir(source, destination)
                self.skill_dirs.append(destination)
            await self._own(environment, str(self.private))
            await self.exec_as_agent(
                environment,
                shlex.join(["chmod", "600", str(self.private / "studio-home/config.toml")]),
            )
        except (NonZeroAgentExitCodeError, OSError, ValueError, KeyError, TypeError) as error:
            raise AnywkSetupError("无法准备本 trial 的私有目录或全新输出目录") from error

    def command_argv(self):
        _, model = parse_model_name(self.model_name, skip_model_parsing=self.skip_model_parsing)
        argv = [
            "/installed-agent/anywk",
            "exec",
            "--studio-home",
            str(self.private / "studio-home"),
            "--cwd",
            self.task_cwd,
            "--account",
            self.options.account_id,
            "--model",
            model,
            "--mode",
            self.options.mode,
            "--prompt-file",
            str(self.private / "prompt.txt"),
            "--output-dir",
            str(self.native),
        ]
        if self.options.reasoning_effort is not None:
            argv.extend(["--reasoning-effort", self.options.reasoning_effort])
        if self.options.max_model_steps is not None:
            argv.extend(["--max-model-steps", str(self.options.max_model_steps)])
        if self.options.no_default_user_skills:
            argv.append("--no-default-user-skills")
        for directory in self.skill_dirs:
            argv.extend(["--skill-dir", directory])
        return argv

    async def _download(self, environment, temporary):
        destination = Path(temporary) / "native"
        await environment.download_dir(str(self.native), destination)
        return destination

    async def _cancel(self, environment):
        started = time.monotonic()
        try:
            async with asyncio.timeout(5):
                result = await environment.exec(
                    command=shlex.join(
                        [
                            "/bin/sh",
                            str(self.private / "cancel.sh"),
                            str(self.private),
                            self.launcher_id,
                        ]
                    )
                )
                if result.return_code != 0:
                    raise AnywkArtifactError("取消控制命令失败")
                self._cleanup = json.loads(result.stdout)
        except (OSError, ValueError, TypeError, RuntimeError, asyncio.CancelledError):
            self._cleanup.update(
                attempted=True,
                clean=False,
                error="cleanupControllerFailed",
                elapsedMs=int((time.monotonic() - started) * 1000),
            )
        self.logs_dir.mkdir(parents=True, exist_ok=True)
        (self.logs_dir / "cleanup.json").write_text(json.dumps(self._cleanup))

    @with_prompt_template
    async def run(self, instruction, environment, context):
        await self._upload_config_text(
            environment,
            content=instruction,
            remote_path=str(self.private / "prompt.txt"),
            filename="prompt.txt",
        )
        argv = [
            "setsid",
            "--wait",
            "/bin/sh",
            str(self.private / "launch.sh"),
            str(self.private),
            self.launcher_id,
            *self.command_argv(),
        ]
        started = time.monotonic()
        try:
            try:
                await self.exec_as_agent(
                    environment,
                    shlex.join(argv),
                    env={"ANYWK_HARBOR_RUN_ID": self.launcher_id},
                    cwd=self.task_cwd,
                )
                self.cli_exit_code = 0
            except NonZeroAgentExitCodeError as original:
                code = self.cli_exit_code
                native_result = None
                try:
                    with tempfile.TemporaryDirectory() as temporary:
                        directory = await self._download(environment, temporary)
                        artifacts = read_and_validate_run_artifacts(
                            directory, require_success=False, expected_exit=code
                        )
                        native_result = artifacts.result
                        self._metadata["artifactValidation"] = "partial"
                except (OSError, ValueError, TypeError, RuntimeError):
                    self._metadata["artifactValidation"] = "failed"
                mapped = classify_failure(code, native_result)
                if mapped is NonZeroAgentExitCodeError:
                    raise
                raise mapped(f"anywk 运行失败，退出码 {code}") from original
            validation_started = time.monotonic()
            with tempfile.TemporaryDirectory() as temporary:
                directory = await self._download(environment, temporary)
                artifacts = read_and_validate_run_artifacts(directory, expected_exit=0)
                convert_run_to_atif(artifacts)
                self._validated_identity = (
                    artifacts.manifest["runId"],
                    hashlib.sha256((directory / "result.json").read_bytes()).hexdigest(),
                )
            self._metadata.update(
                artifactValidation="passed",
                validationWallMs=int((time.monotonic() - validation_started) * 1000),
            )
        except asyncio.CancelledError:
            self._run_error = "cancelled"
            await self._cancel(environment)
            raise
        except Exception as error:
            self._run_error = type(error).__name__
            if self.cli_exit_code == 0:
                self._metadata["artifactValidation"] = "failed"
            raise
        finally:
            self._metadata["adapterRunWallMs"] = int((time.monotonic() - started) * 1000)
            self._metadata["cliExitCode"] = self.cli_exit_code
            self.logs_dir.mkdir(parents=True, exist_ok=True)
            (self.logs_dir / "adapter.json").write_text(json.dumps(self._metadata))

    def populate_context_post_run(self, context):
        try:
            artifacts = read_and_validate_run_artifacts(
                self.logs_dir / "native",
                require_success=self._validated_identity is not None,
                expected_exit=self.cli_exit_code,
            )
            if self._validated_identity is not None:
                identity = (
                    artifacts.manifest["runId"],
                    hashlib.sha256((self.logs_dir / "native/result.json").read_bytes()).hexdigest(),
                )
                if identity != self._validated_identity:
                    raise AnywkArtifactError("最终同步产物与 run 内验证的产物不同")
            trajectory = convert_run_to_atif(artifacts)
            (self.logs_dir / "trajectory.json").write_text(
                trajectory.model_dump_json(exclude_none=True, indent=2)
            )
            populate_context(
                context, artifacts, trajectory, {**self._metadata, "cleanup": self._cleanup}
            )
        except Exception as error:
            self._metadata["artifactValidation"] = "failed"
            context.model_usage = {}
            context.metadata = {
                **self._metadata,
                "cleanup": self._cleanup,
                "postRunError": type(error).__name__,
            }
            (self.logs_dir / "adapter.json").write_text(json.dumps(self._metadata))
            if self._run_error is None:
                raise AnywkArtifactError("最终原生产物或 ATIF 无效") from error
