"""只使用原生退出码及 TurnFailure 分类，绝不匹配进程输出。"""

from harbor.agents.installed.base import (
    AgentAuthenticationError,
    ApiInternalServerError,
    ApiOverloadedError,
    ApiProviderResourceNotFoundError,
    ApiRateLimitError,
    ModelNotFoundError,
    NetworkConnectionError,
    NonZeroAgentExitCodeError,
    UnknownApiError,
)


class AnywkSetupError(RuntimeError):
    """配置、安装或启动环境无效。"""


class AnywkArtifactError(RuntimeError):
    """导出、关闭或产物验证失败。"""


ERROR_POLICY = {
    "AnywkSetupError": {"should_retry": False, "should_grade": False, "has_valid_reward": False},
    "AnywkArtifactError": {"should_retry": False, "should_grade": True, "has_valid_reward": False},
}


def classify_failure(exit_code: int, result: dict | None) -> type[RuntimeError]:
    if exit_code in (2, 11):
        return AnywkSetupError
    if exit_code in (12, 13):
        return AnywkArtifactError
    if exit_code != 10 or result is None:
        return NonZeroAgentExitCodeError
    failure = (result.get("error") or {}).get("turnFailure") or {}
    if failure.get("category") not in ("provider", "providerCapacity"):
        return NonZeroAgentExitCodeError
    kind, code, status = (failure.get(k) for k in ("providerKind", "code", "httpStatus"))
    if kind in ("authentication", "authorization"):
        return AgentAuthenticationError
    if kind == "transport":
        return NetworkConnectionError
    if kind == "capacity":
        if status is not None:
            return {
                429: ApiRateLimitError,
                500: ApiInternalServerError,
                502: ApiOverloadedError,
                503: ApiOverloadedError,
                504: ApiOverloadedError,
            }.get(status, UnknownApiError)
        if code in ("rate_limit_exceeded", "websocket_connection_limit_reached"):
            return ApiRateLimitError
        if code == "server_error":
            return ApiInternalServerError
        if code in (
            "temporarily_unavailable",
            "service_unavailable",
            "server_is_overloaded",
            "upstream_error",
        ):
            return ApiOverloadedError
    if kind == "configuration":
        if status == 404:
            return ApiProviderResourceNotFoundError
        if status is None and code in ("model_not_found", "unsupported_model"):
            return ModelNotFoundError
    return UnknownApiError
