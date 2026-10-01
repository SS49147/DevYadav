from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient

from app import create_app


def test_post_returns_names_from_the_extractor():
    extractor = Mock()
    extractor.extract.return_value = ["Deep Learning", "Software Testing"]
    with TestClient(create_app(extractor)) as client:
        response = client.post("/extract-course-name/", json={"text": "Take Deep Learning and Software Testing."})
    assert response.status_code == 200
    assert response.json() == {"extracted_course_names": ["Deep Learning", "Software Testing"]}
    extractor.extract.assert_called_once_with("Take Deep Learning and Software Testing.")


@pytest.mark.parametrize("body", [{}, {"text": ""}, {"text": "  "}, {"text": 123}, {"text": "x" * 4001}])
def test_rejects_invalid_input(body):
    extractor = Mock()
    with TestClient(create_app(extractor)) as client:
        assert client.post("/extract-course-name/", json=body).status_code == 422
    extractor.extract.assert_not_called()


def test_reports_token_limit_errors():
    extractor = Mock()
    extractor.extract.side_effect = ValueError("Text exceeds the 256-token limit.")
    with TestClient(create_app(extractor)) as client:
        response = client.post("/extract-course-name/", json={"text": "long text"})
    assert response.status_code == 422
    assert "256-token" in response.json()["detail"]


def test_health_and_swagger_are_available():
    with TestClient(create_app(Mock())) as client:
        assert client.get("/health").json() == {"status": "healthy", "model_loaded": True}
        assert client.get("/docs").status_code == 200
        assert "/extract-course-name/" in client.get("/openapi.json").json()["paths"]
