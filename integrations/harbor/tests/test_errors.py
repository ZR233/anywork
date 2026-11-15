import pytest
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

from anywork_harbor.errors import AnywkArtifactError, AnywkSetupError, classify_failure


@pytest.mark.parametrize(
    ("exit_code", "category", "kind", "status", "code", "expected"),
    [
        (2, None, None, None, None, AnywkSetupError),
        (11, None, None, None, None, AnywkSetupError),
        (12, None, None, None, None, AnywkArtifactError),
        (13, None, None, None, None, AnywkArtifactError),
        (10, "tool", "authentication", 401, None, NonZeroAgentExitCodeError),
        (10, "provider", "authentication", 429, None, AgentAuthenticationError),
        (10, "provider", "transport", 503, None, NetworkConnectionError),
        (10, "providerCapacity", "capacity", 429, "server_error", ApiRateLimitError),
        (10, "providerCapacity", "capacity", 500, "rate_limit_exceeded", ApiInternalServerError),
        (10, "providerCapacity", "capacity", 503, None, ApiOverloadedError),
        (10, "provider", "configuration", 404, "model_not_found", ApiProviderResourceNotFoundError),
        (10, "provider", "configuration", None, "model_not_found", ModelNotFoundError),
        (10, "provider", "configuration", 400, "invalid_request_error", UnknownApiError),
        (10, "provider", "unknown", 429, None, UnknownApiError),
    ],
)
def test_typed_mapping_precedence(exit_code, category, kind, status, code, expected):
    result = {
        "error": {
            "turnFailure": {
                "category": category,
                "providerKind": kind,
                "httpStatus": status,
                "code": code,
            }
        }
    }
    assert classify_failure(exit_code, result) is expected


def test_nonzero_without_artifacts_retains_original_class():
    assert classify_failure(10, None) is NonZeroAgentExitCodeError
    assert classify_failure(143, None) is NonZeroAgentExitCodeError
