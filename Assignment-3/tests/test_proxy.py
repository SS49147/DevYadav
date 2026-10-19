from io import BytesIO
from unittest.mock import Mock, patch

import requests
from prometheus_client import REGISTRY

from proxy.app import app


def test_missing_image_returns_400():
    client = app.test_client()
    response = client.post("/styleTransfer")
    assert response.status_code == 400


def test_non_jpeg_returns_400():
    client = app.test_client()
    response = client.post(
        "/styleTransfer",
        data={"image": (BytesIO(b"not an image"), "sample.png", "image/png")},
        content_type="multipart/form-data",
    )
    assert response.status_code == 400


@patch("proxy.app.requests.post")
def test_jpeg_is_forwarded(mock_post):
    mock_post.return_value = Mock(
        status_code=200,
        content=b"styled-image",
        headers={"Content-Type": "image/jpeg"},
    )
    client = app.test_client()
    response = client.post(
        "/styleTransfer",
        data={"image": (BytesIO(b"jpeg-data"), "sample.jpg", "image/jpeg")},
        content_type="multipart/form-data",
    )
    assert response.status_code == 200
    assert response.data == b"styled-image"


def test_metrics_are_exposed():
    client = app.test_client()
    response = client.get("/metrics")
    assert response.status_code == 200
    assert b"visualcraft_requests_total" in response.data


def metric_snapshot():
    return {
        status: REGISTRY.get_sample_value("visualcraft_requests_total", {"status": status}) or 0
        for status in ("200", "400", "413", "500")
    }


def test_oversized_upload_is_counted_once_as_413():
    before = metric_snapshot()
    observations = REGISTRY.get_sample_value("visualcraft_request_duration_seconds_count")
    response = app.test_client().post(
        "/styleTransfer",
        data=b"x" * (app.config["MAX_CONTENT_LENGTH"] + 1),
        content_type="application/octet-stream",
    )
    assert response.status_code == 413
    after = metric_snapshot()
    assert {status: after[status] - before[status] for status in before} == {
        "200": 0, "400": 0, "413": 1, "500": 0,
    }
    assert REGISTRY.get_sample_value("visualcraft_request_duration_seconds_count") == observations + 1


@patch("proxy.app.requests.post", side_effect=requests.ConnectionError("upstream unavailable"))
def test_upstream_failure_is_counted_once_as_500(mock_post):
    before = metric_snapshot()
    response = app.test_client().post(
        "/styleTransfer",
        data={"image": (BytesIO(b"jpeg-data"), "sample.jpg", "image/jpeg")},
    )
    assert response.status_code == 500
    after = metric_snapshot()
    assert {status: after[status] - before[status] for status in before} == {
        "200": 0, "400": 0, "413": 0, "500": 1,
    }
