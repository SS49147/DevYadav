import json
import os
import signal
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

deployment = Path(sys.argv[1]).resolve()
pid_file = deployment / 'app.pid'
if not pid_file.exists():
    print('No application PID file to clean up.')
    sys.exit(0)
pid = int(pid_file.read_text().strip())
assert pid > 1, 'Invalid application PID'
process = Path('/proc') / str(pid)
if process.exists():
    command = (process / 'cmdline').read_bytes().split(b'\0')
    assert str(deployment / 'app.py').encode() in command, 'Refusing to stop an unrelated process'
    os.kill(pid, signal.SIGTERM)
    for _ in range(50):
        try:
            state = (process / 'stat').read_text().split()[2]
        except FileNotFoundError:
            break
        if state == 'Z':
            break
        time.sleep(0.1)
    else:
        raise RuntimeError('Application did not stop after SIGTERM')
pid_file.unlink()
report = {'checked_at_utc': datetime.now(timezone.utc).isoformat(), 'process_id': pid, 'application_stopped': True, 'pid_file_removed': not pid_file.exists()}
evidence = Path(__file__).with_name('evidence')
evidence.mkdir(exist_ok=True)
(evidence / 'server-cleanup.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
