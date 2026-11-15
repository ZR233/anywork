"""从已有原生显式目录生成隔离评测配置，不猜测模型能力或价格。"""

import argparse
import copy
from pathlib import Path

import tomlkit


def load_profile(path: Path) -> dict:
    config = tomlkit.parse(path.read_text()).unwrap()
    if config.get("schema_version") != 33:
        raise ValueError("评测仅接受当前原生配置 schema_version=33")
    accounts = config["models"]["accounts"]
    if not accounts:
        raise ValueError("必须提供原生账号")
    for account in accounts.values():
        if account.get("authentication", "apiKey") != "apiKey":
            raise ValueError("评测不支持 OAuth 账号")
        if account.get("bearer_token") or account.get("http_headers"):
            raise ValueError("配置不能携带内联凭据或凭据头；使用 bearer_token_env")
        if account["catalog"]["source"] != "explicit":
            raise ValueError("评测要求冻结的显式模型目录")
        if not account["catalog"]["models"]:
            raise ValueError("显式模型目录不能为空")
    return config


def render_profile(
    config: dict, variant: str, account_id: str, model_id: str, effort: str | None
) -> dict:
    config = copy.deepcopy(config)
    account = config["models"]["accounts"].get(account_id)
    if account is None or model_id not in {m["model_id"] for m in account["catalog"]["models"]}:
        raise ValueError("所选账号/模型不在冻结原生目录中")
    route = {"account_id": account_id, "model_id": model_id}
    if effort is not None:
        route["effort"] = effort
    if variant == "B":
        # 未列出的系统子角色继承完整 mode.simple 路由；所有已声明角色一并固定。
        config["models"]["routes"] = {
            key: dict(route) for key in config["models"].get("routes", {})
        }
        config["mode_model_routes"] = {"mode.simple": dict(route), "mode.task": dict(route)}
    elif variant not in ("C", "D"):
        raise ValueError("原生评测组只能是 B/C/D")
    config.setdefault("delegation", {})["mode"] = "profile" if variant == "B" else "automatic"
    config.setdefault("runtime", {}).setdefault("tool_capabilities", {})["mcp"] = False
    config.setdefault("web_search", {})["mode"] = "disabled"
    config["deepseek_web_search"] = {"enabled": False, "fetch_enabled": False}
    config.setdefault("skills", {})["auto_learn"] = False
    return config


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-config", type=Path, required=True)
    parser.add_argument("--variant", choices=["B", "C", "D"], required=True)
    parser.add_argument("--account", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--effort")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    config = render_profile(
        load_profile(args.base_config), args.variant, args.account, args.model, args.effort
    )
    with args.output.open("x") as output:
        output.write(tomlkit.dumps(config))
    return 0
