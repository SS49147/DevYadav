import os
from datetime import datetime, timezone

from bson import ObjectId
from flask import Flask, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pymongo import MongoClient


REQUESTS = Counter(
    "treasurebook_http_requests_total",
    "HTTP requests handled by TreasureBook",
    ["method", "endpoint", "status"],
)
LATENCY = Histogram(
    "treasurebook_http_request_duration_seconds",
    "TreasureBook request duration",
    ["endpoint"],
)

NODE_TYPES = {"treasure", "location", "map"}
EDGE_TYPES = {"trail", "hidden-at", "leads-to"}


def _serialize(document):
    result = dict(document)
    result["id"] = str(result.pop("_id"))
    return result


def create_app(mongo_client=None):
    app = Flask(__name__)
    client = mongo_client or MongoClient(
        os.getenv("MONGO_URI", "mongodb://localhost:27017/treasurebook"),
        serverSelectionTimeoutMS=3000,
    )
    database = client[os.getenv("MONGO_DB", "treasurebook")]
    nodes = database.nodes
    edges = database.edges

    @app.before_request
    def start_timer():
        request._started_at = datetime.now(timezone.utc)

    @app.after_request
    def record_metrics(response):
        endpoint = request.url_rule.rule if request.url_rule else "unknown"
        elapsed = (datetime.now(timezone.utc) - request._started_at).total_seconds()
        REQUESTS.labels(request.method, endpoint, response.status_code).inc()
        LATENCY.labels(endpoint).observe(elapsed)
        return response

    @app.get("/")
    def index():
        return jsonify(
            name="TreasureBook API",
            endpoints={
                "nodes": "/node",
                "edges": "/edge",
                "graph": "/graph",
                "health": "/health",
                "metrics": "/metrics",
            },
        )

    @app.get("/health")
    def health():
        try:
            client.admin.command("ping")
            return jsonify(status="healthy", database="connected")
        except Exception:
            return jsonify(status="unhealthy", database="disconnected"), 503

    @app.get("/live")
    def live():
        return jsonify(status="alive")

    @app.post("/node")
    def create_node():
        data = request.get_json(silent=True) or {}
        node_type = str(data.get("type", data.get("Type", ""))).strip().lower()
        name = str(data.get("name", "")).strip()
        if node_type not in NODE_TYPES or not name:
            return jsonify(error="type must be Treasure, Location or Map; name is required"), 400

        document = {
            "type": node_type.title(),
            "name": name,
            "description": str(data.get("description", "")).strip(),
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        document["_id"] = nodes.insert_one(document).inserted_id
        return jsonify(_serialize(document)), 201

    @app.get("/node")
    def list_nodes():
        return jsonify([_serialize(item) for item in nodes.find().sort("created_at", 1)])

    @app.get("/node/<node_id>")
    def get_node(node_id):
        try:
            document = nodes.find_one({"_id": ObjectId(node_id)})
        except Exception:
            document = None
        if document is None:
            return jsonify(error="node not found"), 404
        return jsonify(_serialize(document))

    @app.post("/edge")
    def create_edge():
        data = request.get_json(silent=True) or {}
        edge_type = str(data.get("type", data.get("Type", ""))).strip().lower()
        source = str(data.get("source", "")).strip()
        target = str(data.get("target", "")).strip()
        if edge_type not in EDGE_TYPES or not source or not target:
            return jsonify(error="type must be Trail, Hidden-At or Leads-To; source and target are required"), 400
        try:
            source_id = ObjectId(source)
            target_id = ObjectId(target)
        except Exception:
            return jsonify(error="source and target must be valid node ids"), 400
        if nodes.count_documents({"_id": {"$in": [source_id, target_id]}}) != 2:
            return jsonify(error="source and target nodes must exist"), 400

        labels = {"trail": "Trail", "hidden-at": "Hidden-At", "leads-to": "Leads-To"}
        document = {
            "type": labels[edge_type],
            "source": source,
            "target": target,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        document["_id"] = edges.insert_one(document).inserted_id
        return jsonify(_serialize(document)), 201

    @app.get("/edge")
    def list_edges():
        return jsonify([_serialize(item) for item in edges.find().sort("created_at", 1)])

    @app.get("/graph")
    def graph():
        return jsonify(
            nodes=[_serialize(item) for item in nodes.find()],
            edges=[_serialize(item) for item in edges.find()],
        )

    @app.get("/metrics")
    def metrics():
        return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")))
