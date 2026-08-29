import os
from datetime import datetime, timezone

from bson import ObjectId
from flask import Flask, jsonify, redirect, render_template, request, url_for
from pymongo import MongoClient
from pymongo.errors import PyMongoError


def create_app(test_collection=None):
    app = Flask(__name__)
    app.config["MONGO_URI"] = os.getenv(
        "MONGO_URI", "mongodb://localhost:27017/assignment1"
    )

    if test_collection is None:
        client = MongoClient(app.config["MONGO_URI"], serverSelectionTimeoutMS=3000)
        collection = client.get_default_database()["items"]
        app.extensions["mongo_client"] = client
    else:
        collection = test_collection

    app.extensions["items_collection"] = collection

    def serialize(item):
        return {
            "id": str(item["_id"]),
            "name": item["name"],
            "description": item.get("description", ""),
            "quantity": item.get("quantity", 0),
            "created_at": item.get("created_at", ""),
        }

    def parse_item(source):
        name = str(source.get("name", "")).strip()
        description = str(source.get("description", "")).strip()
        try:
            quantity = int(source.get("quantity", 0))
        except (TypeError, ValueError) as exc:
            raise ValueError("Quantity must be a whole number.") from exc

        if not name:
            raise ValueError("Name is required.")
        if quantity < 0:
            raise ValueError("Quantity cannot be negative.")

        return {"name": name, "description": description, "quantity": quantity}

    def object_id(value):
        if not ObjectId.is_valid(value):
            raise ValueError("Invalid item identifier.")
        return ObjectId(value)

    @app.get("/")
    def index():
        items = [serialize(item) for item in collection.find().sort("created_at", -1)]
        return render_template("index.html", items=items)

    @app.post("/items")
    def create_item():
        try:
            item = parse_item(request.form)
            item["created_at"] = datetime.now(timezone.utc).isoformat()
            collection.insert_one(item)
            return redirect(url_for("index"))
        except ValueError as exc:
            return render_template("error.html", message=str(exc)), 400

    @app.post("/items/<item_id>/update")
    def update_item(item_id):
        try:
            item = parse_item(request.form)
            result = collection.update_one({"_id": object_id(item_id)}, {"$set": item})
            if result.matched_count == 0:
                return render_template("error.html", message="Item not found."), 404
            return redirect(url_for("index"))
        except ValueError as exc:
            return render_template("error.html", message=str(exc)), 400

    @app.post("/items/<item_id>/delete")
    def delete_item(item_id):
        try:
            result = collection.delete_one({"_id": object_id(item_id)})
            if result.deleted_count == 0:
                return render_template("error.html", message="Item not found."), 404
            return redirect(url_for("index"))
        except ValueError as exc:
            return render_template("error.html", message=str(exc)), 400

    @app.get("/api/items")
    def api_list_items():
        return jsonify([serialize(item) for item in collection.find().sort("created_at", -1)])

    @app.post("/api/items")
    def api_create_item():
        try:
            item = parse_item(request.get_json(silent=True) or {})
            item["created_at"] = datetime.now(timezone.utc).isoformat()
            result = collection.insert_one(item)
            saved = collection.find_one({"_id": result.inserted_id})
            return jsonify(serialize(saved)), 201
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400

    @app.get("/api/items/<item_id>")
    def api_get_item(item_id):
        try:
            item = collection.find_one({"_id": object_id(item_id)})
            if item is None:
                return jsonify({"error": "Item not found."}), 404
            return jsonify(serialize(item))
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400

    @app.put("/api/items/<item_id>")
    def api_update_item(item_id):
        try:
            updated = parse_item(request.get_json(silent=True) or {})
            result = collection.update_one(
                {"_id": object_id(item_id)}, {"$set": updated}
            )
            if result.matched_count == 0:
                return jsonify({"error": "Item not found."}), 404
            item = collection.find_one({"_id": ObjectId(item_id)})
            return jsonify(serialize(item))
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400

    @app.delete("/api/items/<item_id>")
    def api_delete_item(item_id):
        try:
            result = collection.delete_one({"_id": object_id(item_id)})
            if result.deleted_count == 0:
                return jsonify({"error": "Item not found."}), 404
            return "", 204
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400

    @app.get("/health")
    def health():
        try:
            if test_collection is None:
                app.extensions["mongo_client"].admin.command("ping")
            else:
                collection.find_one()
            return jsonify({"service": "flask-app", "status": "healthy"})
        except PyMongoError as exc:
            return jsonify({"status": "unhealthy", "reason": str(exc)}), 503

    @app.get("/favicon.ico")
    def favicon():
        return "", 204

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
