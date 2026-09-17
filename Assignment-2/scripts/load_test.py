import argparse
import concurrent.futures
import statistics
import time
import uuid

import requests


def send_request(base_url):
    started = time.perf_counter()
    try:
        response = requests.post(
            f"{base_url.rstrip('/')}/node",
            json={"type": "Treasure", "name": f"Treasure-{uuid.uuid4().hex[:8]}"},
            timeout=15,
        )
        return response.status_code, (time.perf_counter() - started) * 1000
    except requests.RequestException:
        return 0, (time.perf_counter() - started) * 1000


def main():
    parser = argparse.ArgumentParser(description="Generate traffic for the TreasureBook API")
    parser.add_argument("--url", default="http://localhost:5002")
    parser.add_argument("--requests", type=int, default=500)
    parser.add_argument("--workers", type=int, default=30)
    args = parser.parse_args()

    started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(lambda _: send_request(args.url), range(args.requests)))
    elapsed = time.perf_counter() - started
    latencies = [latency for _, latency in results]
    success = sum(status == 201 for status, _ in results)

    print(f"Requests: {args.requests}")
    print(f"Successful: {success}")
    print(f"Elapsed: {elapsed:.2f} seconds")
    print(f"Throughput: {args.requests / elapsed:.2f} requests/second")
    print(f"Mean latency: {statistics.mean(latencies):.2f} ms")
    print(f"P95 latency: {sorted(latencies)[int(len(latencies) * 0.95) - 1]:.2f} ms")


if __name__ == "__main__":
    main()
