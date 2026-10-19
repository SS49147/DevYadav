import argparse
import datetime
import hashlib
import json
import subprocess
import time
from pathlib import Path

import requests
from prometheus_client.parser import text_string_to_metric_families

ROOT = Path(__file__).resolve().parent


def wait_for_json(url, predicate, timeout=120):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            response = requests.get(url, timeout=5)
            response.raise_for_status()
            data = response.json()
            if predicate(data):
                return data
            last_error = f"Not ready: {url}"
        except (requests.RequestException, ValueError) as error:
            last_error = str(error)
        time.sleep(2)
    raise RuntimeError(f"Readiness timeout: {last_error}")


def transform(base_url, destination):
    with (ROOT / "evidence" / "sample-input.jpg").open("rb") as source:
        response = requests.post(
            base_url + "/styleTransfer",
            files={"image": ("sample-input.jpg", source, "image/jpeg")}, timeout=150,
        )
    response.raise_for_status()
    if not response.content.startswith(b"\xff\xd8\xff"):
        raise RuntimeError("Style transfer did not return a JPEG")
    destination.write_bytes(response.content)
    return {"status": response.status_code, "bytes": len(response.content),
            "sha256": hashlib.sha256(response.content).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description="Verify the deployed VisualCraft service and monitoring")
    parser.add_argument("--base-url", default="http://127.0.0.1:5001")
    parser.add_argument("--prometheus-url", default="http://127.0.0.1:9090")
    parser.add_argument("--grafana-url", default="http://127.0.0.1:3000")
    parser.add_argument("--check-restart", action="store_true")
    args = parser.parse_args()
    base = args.base_url.rstrip("/")
    evidence = ROOT / "evidence"
    report = {"checked_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()}
    try:
        report["health"] = wait_for_json(base + "/health", lambda data: data.get("status") == "healthy")
        report["style_transfer"] = transform(base, evidence / "ci-styled-output.jpg")
        invalid = requests.post(base + "/styleTransfer", timeout=10)
        if invalid.status_code != 400:
            raise RuntimeError(f"Missing-image request returned {invalid.status_code}, expected 400")
        report["missing_image_status"] = invalid.status_code

        def counters():
            response = requests.get(base + "/metrics", timeout=10)
            response.raise_for_status()
            return {sample.labels["status"]: sample.value
                    for family in text_string_to_metric_families(response.text)
                    for sample in family.samples if sample.name == "visualcraft_requests_total"}

        before = counters()
        oversized = requests.post(base + "/styleTransfer", data=b"x" * (10 * 1024 * 1024 + 1),
                                  headers={"Content-Type": "application/octet-stream"}, timeout=30)
        after = counters()
        increments = {status: after.get(status, 0) - before.get(status, 0) for status in after.keys() | before.keys()}
        if oversized.status_code != 413 or increments.get("413") != 1 or sum(increments.values()) != 1:
            raise RuntimeError(f"Oversized upload was not counted once as HTTP 413: {increments}")
        report["oversized_upload"] = {"status": oversized.status_code, "counter_increments": increments}
        report["request_counters"] = after

        targets = wait_for_json(
            args.prometheus_url.rstrip("/") + "/api/v1/targets",
            lambda data: {target["labels"]["job"] for target in data.get("data", {}).get("activeTargets", [])
                          if target.get("health") == "up"} >= {"visualcraft-api", "cadvisor"},
        )
        report["prometheus_targets"] = [
            {"job": target["labels"]["job"], "health": target["health"]}
            for target in targets["data"]["activeTargets"]
        ]
        report["grafana_health"] = wait_for_json(
            args.grafana_url.rstrip("/") + "/api/health", lambda data: data.get("database") == "ok",
        )
        if args.check_restart:
            container = subprocess.check_output(["docker", "compose", "ps", "-q", "api"], cwd=ROOT, text=True).strip()
            if not container:
                raise RuntimeError("Compose API container not found")

            def restart_count():
                return int(subprocess.check_output(["docker", "inspect", "--format", "{{.RestartCount}}", container], text=True))

            previous = restart_count()
            result = subprocess.run([
                "docker", "compose", "exec", "-T", "api", "python", "-c",
                "import os,signal; os.kill(1, signal.SIGTERM)",
            ], cwd=ROOT, capture_output=True, text=True)
            deadline = time.monotonic() + 90
            while restart_count() <= previous:
                if time.monotonic() >= deadline:
                    raise RuntimeError(f"API did not restart after SIGTERM: {result.stderr}")
                time.sleep(2)
            wait_for_json(base + "/health", lambda data: data.get("status") == "healthy")
            report["restart"] = {"before": previous, "after": restart_count(),
                                 "style_transfer": transform(base, evidence / "ci-styled-output.jpg")}
        report["passed"] = True
    finally:
        (evidence / "integration.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
