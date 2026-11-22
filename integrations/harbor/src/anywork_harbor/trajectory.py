"""将原生完成原件与单次账单映射到固定 Harbor 的 ATIF 1.8。"""

import json
from collections import defaultdict

from harbor.models.agent.context import AgentContext, ModelUsage
from harbor.models.trajectories import Trajectory
from harbor.utils.trajectory_validator import TrajectoryValidator

from .artifacts import RunArtifacts, decode_json
from .errors import AnywkArtifactError


def _native_event(event: dict, data: dict) -> dict:
    return {
        "eventSeq": event["eventSeq"],
        "emittedAt": event["emittedAt"],
        "source": event["source"],
        "header": data.get("header"),
        "payload": data.get("payload"),
        "contentsManifest": data.get("contentsManifest"),
    }


def _valid_tokens(usage: dict) -> dict:
    result = {
        k: v if isinstance(v, int) and not isinstance(v, bool) and v >= 0 else None
        for k, v in usage.items()
    }
    i, o = result.get("inputTokens"), result.get("outputTokens")
    for field, whole in (("cacheReadTokens", i), ("cacheWriteTokens", i), ("reasoningTokens", o)):
        value = result.get(field)
        if value is not None and whole is not None and value > whole:
            result[field] = None
    total = result.get("totalTokens")
    if total is not None and i is not None and o is not None and total != i + o:
        # 原始矛盾保留 extra；不能当作有效计量。
        result = {key: None for key in result}
    return result


def _metrics(billing: dict) -> dict:
    accounting = billing["accounting"]
    usage, pricing = _valid_tokens(accounting["usage"]), accounting["pricing"]
    cost = None
    if pricing["kind"] == "noCharge":
        cost = 0.0
    elif pricing["kind"] == "estimated" and pricing["cost"]["currency"] == "USD":
        cost = pricing["cost"]["amount"]
    return {
        "prompt_tokens": usage.get("inputTokens"),
        "completion_tokens": usage.get("outputTokens"),
        "cached_tokens": usage.get("cacheReadTokens"),
        "cost_usd": cost,
    }


def _model(billing: dict) -> str | None:
    observation = billing.get("modelObservation") or {}
    return (
        observation.get("reportedModel") or observation.get("sentModel") or billing.get("modelId")
    )


def convert_run_to_atif(artifacts: RunArtifacts) -> Trajectory:
    try:
        return _convert_run_to_atif(artifacts)
    except AnywkArtifactError:
        raise
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        raise AnywkArtifactError(f"原生轨迹转换失败：{type(error).__name__}") from error


def _convert_run_to_atif(artifacts: RunArtifacts) -> Trajectory:
    members, by_thread, bills, lifecycles = (
        {},
        defaultdict(list),
        defaultdict(dict),
        defaultdict(list),
    )
    for event in artifacts.events:
        kind, data, thread = (event[k] for k in ("type", "data", "threadId"))
        if kind == "agentRegistered":
            members[thread] = data
        elif kind == "inferenceFinished":
            bills[thread][data["billing"]["inferenceId"]] = event
        elif kind == "completion":
            by_thread[thread].append(event)
        elif kind == "executionLifecycle":
            lifecycles[thread].extend(data["facts"])
    if not members:
        raise AnywkArtifactError("尚无可转换的原生轨迹成员")
    run_id = artifacts.manifest["runId"]
    trajectories, call_steps = {}, {}
    for thread, member in members.items():
        steps, inference_steps, tools = [], {}, {}

        def order(event):
            return event["data"]["header"]["event"]["seq"]

        def new_step(inference=None, steps=steps, inference_steps=inference_steps):
            step = {
                "step_id": len(steps) + 1,
                "source": "agent",
                "message": "",
                "llm_call_count": 0,
                "extra": {"nativeInferenceId": inference},
            }
            steps.append(step)
            if inference is not None:
                inference_steps[inference] = step
            return step

        for event in sorted(by_thread[thread], key=order):
            data = event["data"]
            header = data["header"]["event"]
            atom = data["atom"]
            contents = defaultdict(list)
            opaque_contents = []
            for content in artifacts.manifest_contents(data["contentsManifest"]):
                role = content["role"]
                if role is None:
                    if content["historyRole"]["kind"] not in {
                        "canonicalPayload",
                        "canonicalMetadata",
                    }:
                        opaque_contents.append(content)
                    continue
                if content["encoding"] != "utf-8":
                    if role == "body":
                        raise ValueError("最终正文 body 不是 UTF-8")
                    opaque_contents.append(content)
                    continue
                contents[role].append(artifacts.content(content).decode("utf-8"))
            body = "".join(contents["body"])
            source = header["source"] or {}
            parent_input = (
                source.get("kind") == "inboxMessage" and atom.get("textChannel") == "parentAgent"
            )
            if atom["entityKind"] == "input" or parent_input:
                step_extra = {
                    "nativeSource": source,
                    "nativeEvents": [_native_event(event, data)],
                }
                if opaque_contents:
                    step_extra["nativeOpaqueContents"] = opaque_contents
                steps.append(
                    {
                        "step_id": len(steps) + 1,
                        "source": "user",
                        "message": body,
                        "extra": step_extra,
                    }
                )
                continue
            inference = header.get("attemptId")
            payload = decode_json(artifacts.content(data["payload"]))
            if atom["entityKind"] == "inference":
                inference = payload.get("data", {}).get("inferenceId")
            if atom["entityKind"] == "turnReceipt":
                continue
            step = inference_steps.get(inference) if inference else None
            tool = atom.get("tool")
            if step is None and tool:
                step = tools.get(tool["callId"])
            if step is None:
                step = new_step(inference)
            step["extra"].setdefault("nativeAtoms", []).append(atom)
            step["extra"].setdefault("nativeEvents", []).append(_native_event(event, data))
            if opaque_contents:
                step["extra"].setdefault("nativeOpaqueContents", []).extend(opaque_contents)
            step["message"] += body
            reasoning = "".join(contents["reasoningSummary"])
            if reasoning:
                # 没有关联到账单的公开摘要仍保留，不伪造推理次数。
                step["extra"].setdefault("publicReasoning", []).append(reasoning)
            if tool:
                call_id = tool["callId"]
                if call_id not in tools:
                    arguments_text = "".join(contents["toolArguments"])
                    argument_refs = [
                        content
                        for content in opaque_contents
                        if content["historyRole"]["kind"] == "toolArguments"
                    ]
                    if argument_refs:
                        arguments = {"nativeOpaqueContents": argument_refs}
                    else:
                        try:
                            arguments = json.loads(arguments_text) if arguments_text else {}
                        except ValueError:
                            arguments = {"nativeArguments": arguments_text}
                        if not isinstance(arguments, dict):
                            arguments = {"nativeArguments": arguments}
                    step.setdefault("tool_calls", []).append(
                        {
                            "tool_call_id": call_id,
                            "function_name": tool["name"],
                            "arguments": arguments,
                        }
                    )
                    tools[call_id] = step
                output = "".join(contents["toolOutput"])
                native_state = payload.get("data", {}).get("state")
                output_refs = [
                    content
                    for content in opaque_contents
                    if content["historyRole"]["kind"] in {"toolOutput", "attachment"}
                ]
                if output or native_state is not None or output_refs:
                    result_extra = {
                        "nativeState": native_state,
                        "nativePayload": data["payload"],
                    }
                    if output_refs:
                        result_extra["nativeOpaqueContents"] = output_refs
                    tools[call_id].setdefault("observation", {"results": []})["results"].append(
                        {
                            "source_call_id": call_id,
                            "content": output or None,
                            "extra": result_extra,
                        }
                    )
        for inference, event in bills[thread].items():
            billing = event["data"]["billing"]
            step = inference_steps.get(inference)
            if step is None:
                step = new_step(inference)
            step["llm_call_count"] = 1
            step["metrics"] = _metrics(billing)
            step["model_name"] = _model(billing)
            step["extra"].update(
                {
                    "billing": billing,
                    "status": event["data"]["status"],
                    "auxiliary": event["data"]["auxiliary"],
                    "nativeEvent": _native_event(event, event["data"]),
                    "noText": not bool(step["message"]),
                }
            )
            if step["extra"].get("publicReasoning"):
                step["reasoning_content"] = "".join(step["extra"]["publicReasoning"])
        if not steps:
            # 登记但尚无模型/正文的取消成员：确定性空步骤，事实在 extra。
            step = new_step()
            step["extra"]["noCompletion"] = True
        trajectories[thread] = {
            "schema_version": "ATIF-v1.8",
            "session_id": run_id,
            "trajectory_id": f"{run_id}:{thread}",
            "agent": {"name": "anywk", "version": artifacts.manifest["build"]["version"]},
            "steps": steps,
            "extra": {
                "nativeRun": artifacts.manifest,
                "nativeMember": member,
                "traceComplete": artifacts.complete,
                "executionLifecycle": lifecycles[thread],
            },
        }
        call_steps[thread] = tools
    roots = []
    for thread, member in members.items():
        parent = member["parentThreadId"]
        if parent is None:
            roots.append(thread)
            continue
        trajectories[parent].setdefault("subagent_trajectories", []).append(trajectories[thread])
        spawn = member["spawnToolCallId"]
        step = call_steps[parent].get(spawn)
        if step is not None:
            step.setdefault("observation", {"results": []})["results"].append(
                {
                    "source_call_id": spawn,
                    "subagent_trajectory_ref": [{"trajectory_id": f"{run_id}:{thread}"}],
                }
            )
    if len(roots) != 1:
        raise AnywkArtifactError("轨迹根成员不唯一")
    root = trajectories[roots[0]]
    usage = (artifacts.result or {}).get("usage")
    if usage:
        totals = usage["totals"]
        root["final_metrics"] = {
            "total_prompt_tokens": totals["inputTokens"],
            "total_completion_tokens": totals["outputTokens"],
            "total_cached_tokens": totals["cacheReadTokens"],
            "total_cost_usd": totals["estimatedCostUsd"],
            "extra": {"nativeUsage": usage},
        }
    validator = TrajectoryValidator()
    if not validator.validate(root):
        raise AnywkArtifactError("ATIF 官方验证失败：" + "; ".join(validator.get_errors()))
    return Trajectory.model_validate(root)


def populate_context(
    context: AgentContext, artifacts: RunArtifacts, trajectory: Trajectory, metadata: dict
) -> None:
    totals = ((artifacts.result or {}).get("usage") or {}).get("totals", {})
    context.n_input_tokens = totals.get("inputTokens")
    context.n_output_tokens = totals.get("outputTokens")
    context.n_cache_tokens = totals.get("cacheReadTokens")
    context.cost_usd = totals.get("estimatedCostUsd")
    groups = defaultdict(list)

    def visit(current):
        for step in current.steps:
            if step.llm_call_count and step.model_name:
                groups[step.model_name].append(step.metrics)
        for child in current.subagent_trajectories or []:
            visit(child)

    visit(trajectory)
    context.model_usage = {}
    for model, metrics in groups.items():
        if all(
            m is not None
            and all(
                getattr(m, name) is not None
                for name in ("prompt_tokens", "completion_tokens", "cached_tokens")
            )
            for m in metrics
        ):
            context.model_usage[model] = ModelUsage(
                n_input_tokens=sum(m.prompt_tokens for m in metrics),
                n_output_tokens=sum(m.completion_tokens for m in metrics),
                n_cache_tokens=sum(m.cached_tokens for m in metrics),
                cost_usd=sum(m.cost_usd for m in metrics)
                if all(m.cost_usd is not None for m in metrics)
                else None,
            )
    context.metadata = {
        **metadata,
        "nativeResult": artifacts.result,
        "nativeRunId": artifacts.manifest["runId"],
    }
