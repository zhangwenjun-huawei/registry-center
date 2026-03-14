# tests/test_deregister.py
import pytest
from fastapi.testclient import TestClient

from agent_registry.server import app


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def mock_registry(mocker):
    return mocker.patch('agent_registry.core.RegistryCore')


@pytest.fixture
def valid_agent_data():
    return {
        "name": "TestAgent",
        "provider": {
            "organization": "TestOrg",
            "url": "https://test.org"
        },
        "description": "Test Description",
        "capabilities": {
            "skills": ["text-generation", "code-generation"],
            "input_modes": ["text/plain", "application/json"],
            "output_modes": ["text/plain", "application/json"]
        },
        "default_input_modes": ["text/plain"],
        "default_output_modes": ["text/plain"],
        "url": "https://agent.test",
        "version": "1.0.0",
        "skills": [
            {
                "id": "skill-1",
                "name": "TestSkill",
                "description": "Test Skill Description",
                "tags": ["test", "skill"],
                "input_modes": ["text/plain"],
                "output_modes": ["text/plain"]
            }
        ]
    }


def test_deregister_agent_success(client, mock_registry, valid_agent_data):
    """测试成功删除代理"""
    # 模拟删除操作返回 True
    mock_registry.return_value.deregister.return_value = True

    # 发送 DELETE 请求
    response = client.delete(
        f"/rest/a2a-t/v1/deregister_agent/{valid_agent_data['name']}",
        params={"organization": valid_agent_data['provider']['organization']}
    )

    # 验证响应
    assert response.status_code == 200
    assert response.json() is True


def test_deregister_agent_not_found(client, mock_registry, valid_agent_data):
    """测试删除不存在的代理"""
    # 模拟删除操作返回 False
    mock_registry.return_value.deregister.return_value = False

    # 发送 DELETE 请求
    response = client.delete(
        "/rest/a2a-t/v1/deregister_agent/NonExistentAgent",
        params={"organization": "TestOrg"}
    )

    # 验证响应
    assert response.status_code == 404
    assert response.json() == {"detail": "Agent not found"}


def test_deregister_agent_invalid_request(client, mock_registry, valid_agent_data):
    """测试无效的请求参数"""
    # 发送 DELETE 请求，缺少 organization 参数
    response = client.delete(
        f"/rest/a2a-t/v1/deregister_agent/{valid_agent_data['name']}",
    )

    # 验证响应
    assert response.status_code == 422
    assert "detail" in response.json()