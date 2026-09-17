from io import BytesIO
from unittest.mock import Mock, patch

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
