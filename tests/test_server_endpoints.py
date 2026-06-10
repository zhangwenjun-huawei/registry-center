# Copyright (c) 2026 Huawei Technologies Co., Ltd.
# All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

"""Integration tests for server REST endpoints using FastAPI dependency overrides."""

import json
import pytest
from unittest.mock import AsyncMock, MagicMock, patch

from fastapi.testclient import TestClient
from a2a.types import AgentCard

from agent_registry.server import app
from agent_registry.core import RegistryCore
from agent_registry.persistence.base import AgentRecord
from agent_registry.signature.agent_card_signature_validator import (
    AgentCardSignatureValidator, ValidationResult
)


VALID_AGENT_CARD = {
    "name": "TestAgent",
    "provider": {"organization": "TestOrg", "url": "https://test.org"},
    "description": "A test agent for testing",
    "version": "1.0.0",
    "capabilities": {"streaming": False},
    "default_input_modes": ["text/plain"],
    "default_output_modes": ["text/plain"],
    "skills": [{
        "id": "s1", "name": "TestSkill", "description": "Test",
        "tags": [], "input_modes": ["text/plain"], "output_modes": ["text/plain"]
    }]
}


def _mock_agent(name="TestAgent", org="TestOrg", desc="Test", status="published"):
    return AgentCard(
        name=name, provider={"organization": org, "url": "https://test.org"},
        description=desc, version="1.0.0",
        capabilities={"streaming": False},
        default_input_modes=[], default_output_modes=[],
        skills=[]
    )


@pytest.fixture
def mock_registry():
    mock = MagicMock(spec=RegistryCore)
    mock.count.return_value = 0
    mock.get_agents.return_value = {}
    mock.get_status.return_value = "published"
    mock.get_by_key_with_owner.return_value = AgentRecord(
        agent_card=_mock_agent(), owner=None, status="published"
    )
    return mock


@pytest.fixture
def mock_validator():
    mock = MagicMock(spec=AgentCardSignatureValidator)
    mock.validate_agent_card.return_value = ValidationResult(is_valid=True)
    return mock


@pytest.fixture
def mock_signer():
    mock = MagicMock()
    mock.is_enabled.return_value = False
    return mock


@pytest.fixture(autouse=True)
def clean_app_overrides():
    app.dependency_overrides.clear()
    yield
    app.dependency_overrides.clear()


def _override_deps(mock_registry, mock_validator, mock_signer):
    from agent_registry.server import get_registry, get_signature_validator, get_registry_signer
    app.dependency_overrides[get_registry] = lambda: mock_registry
    app.dependency_overrides[get_signature_validator] = lambda: mock_validator
    app.dependency_overrides[get_registry_signer] = lambda: mock_signer


class TestRegisterEndpoint:

    def test_register_success(self, mock_registry, mock_validator, mock_signer):
        _override_deps(mock_registry, mock_validator, mock_signer)
        mock_handler = MagicMock()
        mock_handler.handle = AsyncMock(return_value=True)

        with patch('common.custom.custom_handle.HandlerRegistry.get_handler', return_value=mock_handler):
            client = TestClient(app)
            response = client.post(
                "/rest/v1/registry-center/agent-cards",
                json={"agentCards": [VALID_AGENT_CARD]}
            )
            assert response.status_code == 201

    def test_register_duplicate_returns_409(self, mock_registry, mock_validator, mock_signer):
        _override_deps(mock_registry, mock_validator, mock_signer)
        mock_registry.get_agents.return_value = {("TestAgent", "TestOrg"): True}
        mock_handler = MagicMock()
        mock_handler.handle = AsyncMock()

        with patch('common.custom.custom_handle.HandlerRegistry.get_handler', return_value=mock_handler):
            client = TestClient(app)
            response = client.post(
                "/rest/v1/registry-center/agent-cards",
                json={"agentCards": [VALID_AGENT_CARD]}
            )
            assert response.status_code == 409


class TestGetEndpoint:

    def test_get_agents_empty(self, mock_registry, mock_validator, mock_signer):
        _override_deps(mock_registry, mock_validator, mock_signer)
        mock_handler = MagicMock()
        mock_handler.handle = AsyncMock(return_value=[])

        with patch('common.custom.custom_handle.HandlerRegistry.get_handler', return_value=mock_handler):
            client = TestClient(app)
            response = client.get("/rest/v1/registry-center/agent-cards")
            assert response.status_code == 200


class TestGetSingleEndpoint:

    def test_get_single_agent_found(self, mock_registry, mock_validator, mock_signer):
        _override_deps(mock_registry, mock_validator, mock_signer)
        agent = _mock_agent()
        record = AgentRecord(agent_card=agent, owner=None, status="published")
        mock_handler = MagicMock()
        mock_handler.handle = AsyncMock(return_value=record)

        with patch('common.custom.custom_handle.HandlerRegistry.get_handler', return_value=mock_handler):
            client = TestClient(app)
            response = client.get("/rest/v1/registry-center/agent-cards/TestOrg/TestAgent")
            assert response.status_code == 200


class TestDeleteEndpoint:

    def test_delete_success(self, mock_registry, mock_validator, mock_signer):
        _override_deps(mock_registry, mock_validator, mock_signer)
        mock_handler = MagicMock()
        mock_handler.handle = AsyncMock(return_value=True)

        with patch('common.custom.custom_handle.HandlerRegistry.get_handler', return_value=mock_handler):
            client = TestClient(app)
            response = client.delete("/rest/v1/registry-center/agent-cards/TestOrg/TestAgent")
            assert response.status_code == 200

    def test_delete_not_found(self, mock_registry, mock_validator, mock_signer):
        _override_deps(mock_registry, mock_validator, mock_signer)
        mock_handler = MagicMock()
        mock_handler.handle = AsyncMock(return_value=False)

        with patch('common.custom.custom_handle.HandlerRegistry.get_handler', return_value=mock_handler):
            client = TestClient(app)
            response = client.delete("/rest/v1/registry-center/agent-cards/TestOrg/TestAgent")
            assert response.status_code == 404


class TestSemanticQueryEndpoint:

    def test_semantic_query_success(self, mock_registry, mock_validator, mock_signer):
        agent = _mock_agent()
        mock_handler = MagicMock()
        mock_handler.handle = AsyncMock(return_value=[agent])

        with patch('common.custom.custom_handle.HandlerRegistry.get_handler', return_value=mock_handler):
            client = TestClient(app)
            response = client.post(
                "/rest/v1/registry-center/agent-cards/semantic-query",
                params={"top_n": 3},
                json={"task": "Find test agents"}
            )
            assert response.status_code == 200
