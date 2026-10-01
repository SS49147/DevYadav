import argparse
import json
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from prepare_data import ROOT


CASES = [
    ("Introduction to Artificial Intelligence", ["Introduction to Artificial Intelligence"]),
    ("The college offers Machine Learning and Operating Systems.", ["Machine Learning", "Operating Systems"]),
    ("Next term I plan to take Deep Learning and Software Testing.", ["Deep Learning", "Software Testing"]),
    ("The library closes at five.", []),
]


def wait_for_health(base_url):
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        try:
            with urlopen(f"{base_url}/health", timeout=5) as response:
                health = json.load(response)
            if health == {"status": "healthy", "model_loaded": True}:
                return health
        except (URLError, OSError):
            pass
        time.sleep(1)
    raise TimeoutError("The API did not become healthy within 60 seconds.")


def main():
    parser = argparse.ArgumentParser(description="Check the running course extraction API")
    parser.add_argument("--url", default="http://localhost:8004")
    args = parser.parse_args()
    health = wait_for_health(args.url)
    records = []
    for text, expected in CASES:
        request = Request(
            f"{args.url}/extract-course-name/", data=json.dumps({"text": text}).encode(),
            headers={"Content-Type": "application/json"}, method="POST",
        )
        with urlopen(request, timeout=30) as response:
            payload = json.load(response)
            status = response.status
        actual = payload["extracted_course_names"]
        if status != 200 or actual != expected:
            raise AssertionError(f"Unexpected extraction for {text!r}: {actual!r}, expected {expected!r}")
        records.append({"text": text, "http_status": status, "response": payload})
    for invalid_text in ("  ", "course " * 300):
        invalid = Request(
            f"{args.url}/extract-course-name/", data=json.dumps({"text": invalid_text}).encode(),
            headers={"Content-Type": "application/json"}, method="POST",
        )
        try:
            with urlopen(invalid, timeout=30):
                raise AssertionError("Invalid input should return HTTP 422")
        except HTTPError as error:
            if error.code != 422:
                raise
            records.append({"text": invalid_text, "http_status": error.code, "response": json.load(error)})
    report = {"base_url": args.url, "health": health, "checks_passed": len(records) + 1, "requests": records}
    path = ROOT / "evidence" / "api-responses.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
