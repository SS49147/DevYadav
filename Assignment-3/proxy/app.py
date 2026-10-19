import os
import socket
import time

import requests
from flask import Flask, Response, g, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest


UPSTREAM_URL = os.getenv("UPSTREAM_URL", "http://ai-service:5001/styleTransfer")
UPSTREAM_HOST = os.getenv("UPSTREAM_HOST", "ai-service")
UPSTREAM_PORT = int(os.getenv("UPSTREAM_PORT", "5001"))

REQUESTS = Counter(
    "visualcraft_requests_total",
    "Requests received by the style transfer endpoint",
    ["status"],
)
LATENCY = Histogram(
    "visualcraft_request_duration_seconds",
    "Style transfer response time in seconds",
    buckets=(0.1, 0.25, 0.5, 1, 2.5, 5, 10, 20, 40, 80, float("inf")),
)

for response_status in ("200", "400", "413", "500"):
    REQUESTS.labels(response_status).inc(0)

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 10 * 1024 * 1024


@app.before_request
def start_request_timer():
    if request.endpoint == "style_transfer" and request.method == "POST":
        g.style_transfer_started = time.perf_counter()


@app.after_request
def record_request_metrics(response):
    started = getattr(g, "style_transfer_started", None)
    if started is not None:
        REQUESTS.labels(str(response.status_code)).inc()
        LATENCY.observe(time.perf_counter() - started)
    return response


@app.get("/health")
def health():
    try:
        with socket.create_connection((UPSTREAM_HOST, UPSTREAM_PORT), timeout=2):
            return jsonify(status="healthy", upstream="reachable")
    except OSError:
        return jsonify(status="unhealthy", upstream="unreachable"), 503


@app.post("/styleTransfer")
def style_transfer():
    try:
        image = request.files.get("image")
        if image is None or not image.filename:
            status = 400
            return jsonify(error="a JPEG file is required in the image field"), status
        if image.mimetype not in {"image/jpeg", "image/jpg"}:
            status = 400
            return jsonify(error="only JPEG images are accepted"), status

        upstream = requests.post(
            UPSTREAM_URL,
            files={"image": (image.filename, image.stream, image.mimetype)},
            timeout=120,
        )
        status = upstream.status_code
        content_type = upstream.headers.get("Content-Type", "application/octet-stream")
        return Response(upstream.content, status=status, content_type=content_type)
    except requests.RequestException as error:
        status = 500
        app.logger.warning("Style transfer upstream request failed: %s", error)
        return jsonify(error="style transfer service is unavailable"), status


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), content_type=CONTENT_TYPE_LATEST)


@app.errorhandler(413)
def too_large(_error):
    return jsonify(error="image exceeds the 10 MB limit"), 413


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
