import hashlib
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

deployment = Path(sys.argv[1]).resolve()
source = Path(__file__).with_name('app.py').resolve()
deployed = deployment / 'app.py'
pid = int((deployment / 'app.pid').read_text().strip())
command = (Path('/proc') / str(pid) / 'cmdline').read_bytes().split(b'\0')
assert str(deployed).encode() in command, 'Recorded PID does not run the deployed application'
assert hashlib.sha256(source.read_bytes()).digest() == hashlib.sha256(deployed.read_bytes()).digest(), 'Deployed file differs from source'
url = 'http://127.0.0.1:5000/'
for attempt in range(50):
    try:
        with urllib.request.urlopen(url, timeout=2) as response:
            status = response.status
            body = response.read().decode('utf-8')
        break
    except (urllib.error.URLError, TimeoutError):
        time.sleep(0.2)
else:
    raise RuntimeError('Deployed application did not become reachable')
assert status == 200
assert body == 'Hello, Jenkins Multi-Stage Pipeline!'
report = {
    'checked_at_utc': datetime.now(timezone.utc).isoformat(),
    'url': url, 'http_status': status, 'body': body, 'process_id': pid,
    'deployment_path': str(deployed), 'deployed_sha256': hashlib.sha256(deployed.read_bytes()).hexdigest(),
    'source_matches_deployment': True, 'pid_runs_deployed_app': True,
}
evidence = Path(__file__).with_name('evidence')
evidence.mkdir(exist_ok=True)
(evidence / 'http-response.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
