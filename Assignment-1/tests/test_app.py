import os
import sys

import mongomock


PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(PROJECT_ROOT, "app"))

from app import create_app  # noqa: E402


def make_client():
    database = mongomock.MongoClient()["assignment1"]
    app = create_app(database["items"])
    app.config.update(TESTING=True)
    return app.test_client()


def test_health_endpoint():
    client = make_client()
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json()["status"] == "healthy"


def test_favicon_does_not_generate_browser_error():
    client = make_client()
    response = client.get("/favicon.ico")
    assert response.status_code == 204


def test_complete_crud_flow():
    client = make_client()

    created = client.post(
        "/api/items",
        json={"name": "Mechanical keyboard", "description": "Lab system", "quantity": 2},
    )
    assert created.status_code == 201
    item_id = created.get_json()["id"]

    fetched = client.get(f"/api/items/{item_id}")
    assert fetched.status_code == 200
    assert fetched.get_json()["name"] == "Mechanical keyboard"

    updated = client.put(
        f"/api/items/{item_id}",
        json={"name": "Mechanical keyboard", "description": "Updated", "quantity": 4},
    )
    assert updated.status_code == 200
    assert updated.get_json()["quantity"] == 4

    listed = client.get("/api/items")
    assert listed.status_code == 200
    assert len(listed.get_json()) == 1

    deleted = client.delete(f"/api/items/{item_id}")
    assert deleted.status_code == 204
    assert client.get("/api/items").get_json() == []


def test_rejects_invalid_item_data():
    client = make_client()
    missing_name = client.post("/api/items", json={"name": "", "quantity": 1})
    negative_quantity = client.post(
        "/api/items", json={"name": "Monitor", "quantity": -1}
    )
    invalid_quantity = client.post(
        "/api/items", json={"name": "Monitor", "quantity": "several"}
    )

    assert missing_name.status_code == 400
    assert negative_quantity.status_code == 400
    assert invalid_quantity.status_code == 400


def test_unknown_and_invalid_ids():
    client = make_client()
    assert client.get("/api/items/not-an-object-id").status_code == 400
    assert client.get("/api/items/507f1f77bcf86cd799439011").status_code == 404
