import json
from pathlib import PurePosixPath
from types import SimpleNamespace

import pytest
from harbor.agents.installed.base import NonZeroAgentExitCodeError
from harbor.models.agent.context import AgentContext
from pydantic import ValidationError

from anywork_harbor.agent import AnyworkInstalledAgent, AnyworkOptions, check_upload_tree
from anywork_harbor.errors import AnywkArtifactError, AnywkSetupError


def agent(tmp_path, **kwargs):
    return AnyworkInstalledAgent(
        logs_dir=tmp_path / "logs",
        model_name="native/model/with/slash",
        skip_model_parsing=True,
        skip_install=True,
        config_path=tmp_path / "config.toml",
        account_id="benchmark",
        **kwargs,
    )


def test_options_and_native_model_are_not_reinterpreted(tmp_path):
    for unknown in ("max_cost", "max_tokens", "soft_timeout", "permissions"):
        with pytest.raises(ValidationError):
            AnyworkOptions(
                config_path="profile.toml", account_id="fixture", skip_install=True, **{unknown: 10}
            )
    with pytest.raises(ValidationError):
        AnyworkOptions(
            config_path="profile.toml",
            account_id="fixture",
            binary_path="anywk",
            config={"models": {}},
        )
    instance = agent(tmp_path, reasoning_effort="native-custom", max_model_steps=7)
    instance.private = PurePosixPath("/tmp/private run")
    instance.native = PurePosixPath("/custom/logs/native")
    instance.task_cwd = "/workspace with spaces"
    instance.skill_dirs = ["/remote/harbor/skills", "/tmp/private run/skills/extra-000"]
    argv = instance.command_argv()
    assert argv[argv.index("--model") + 1] == "native/model/with/slash"
    assert argv[argv.index("--reasoning-effort") + 1] == "native-custom"
    assert argv[argv.index("--cwd") + 1] == "/workspace with spaces"
    assert argv[-4:] == [
        "--skill-dir",
        instance.skill_dirs[0],
        "--skill-dir",
        instance.skill_dirs[1],
    ]
    assert "--no-default-user-skills" in argv


def test_output_text_does_not_classify_errors_or_expose_secrets(tmp_path):
    instance = agent(tmp_path)
    result = SimpleNamespace(return_code=10, stdout="authentication failed", stderr="secret=token")
    error = instance._classify_exec_error("command", result)
    assert type(error) is NonZeroAgentExitCodeError
    assert instance.cli_exit_code == 10
    assert "secret" not in str(error)
    assert instance.ERROR_PATTERNS == []


def test_upload_boundary_refuses_outside_symlinks(tmp_path):
    skills = tmp_path / "skills"
    skills.mkdir()
    (skills / "outside").symlink_to(tmp_path / "outside")
    with pytest.raises(AnywkSetupError):
        check_upload_tree(skills)


def test_post_run_fills_context_once_and_detects_late_corruption(archive, tmp_path):
    instance = agent(tmp_path)
    instance.logs_dir = archive.parent
    instance.cli_exit_code = 0
    context = AgentContext()
    instance.populate_context_post_run(context)
    assert context.n_input_tokens == 140
    assert (instance.logs_dir / "trajectory.json").is_file()
    instance._validated_identity = ("wrong-run", "wrong-hash")
    with pytest.raises(AnywkArtifactError):
        instance.populate_context_post_run(AgentContext())
    diagnostics = json.loads((instance.logs_dir / "adapter.json").read_text())
    assert diagnostics["artifactValidation"] == "failed"
    instance._run_error = "ApiRateLimitError"
    context = AgentContext()
    instance.populate_context_post_run(context)
    assert context.metadata["artifactValidation"] == "failed"


async def test_skip_install_still_checks_actual_version_and_loader(tmp_path):
    instance = agent(tmp_path, version="1.2.3")

    class Environment:
        async def exec(self, **kwargs):
            return SimpleNamespace(
                return_code=0, stdout="anywk 9.9.9\n" + "a" * 64 + "  anywk\n", stderr=""
            )

    with pytest.raises(AnywkSetupError, match="版本"):
        await instance._check_binary(Environment())
