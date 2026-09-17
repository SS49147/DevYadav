import mongomock

from app.app import create_app


def make_client():
    app = create_app(mongomock.MongoClient())
    app.config["TESTING"] = True
    return app.test_client()


def test_health_and_empty_graph():
    client = make_client()
    assert client.get("/live").status_code == 200
    assert client.get("/health").status_code == 200
    assert client.get("/graph").get_json() == {"nodes": [], "edges": []}


def test_create_nodes_and_edge():
    client = make_client()
    treasure = client.post("/node", json={"Type": "Treasure", "name": "Golden Crown"})
    location = client.post("/node", json={"type": "Location", "name": "Cave of Wonders"})
    assert treasure.status_code == 201
    assert location.status_code == 201

    edge = client.post(
        "/edge",
        json={
            "Type": "Hidden-At",
            "source": treasure.get_json()["id"],
            "target": location.get_json()["id"],
        },
    )
    assert edge.status_code == 201
    assert edge.get_json()["type"] == "Hidden-At"
    assert len(client.get("/graph").get_json()["nodes"]) == 2


def test_rejects_invalid_data():
    client = make_client()
    assert client.post("/node", json={"type": "Person", "name": "A"}).status_code == 400
    assert client.post("/edge", json={"type": "Trail"}).status_code == 400


def test_metrics_endpoint():
    client = make_client()
    response = client.get("/metrics")
    assert response.status_code == 200
    assert b"treasurebook_http_requests_total" in response.data
