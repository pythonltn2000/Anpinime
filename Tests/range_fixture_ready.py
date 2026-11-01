"""Wait for this range fixture's PID, atomic port file and HTTP listener.

Only the selected port is written to stdout for the workflow to export.
"""
import argparse
import http.client
import json
import os
from pathlib import Path
import sys
import time


def wait_for_fixture(pid, ready_file):
    if pid <= 0:
        raise RuntimeError('Invalid range fixture PID')
    deadline = time.monotonic() + 10
    last_error = 'No ready file'
    for _ in range(50):
        if time.monotonic() >= deadline:
            break
        try:
            os.kill(pid, 0)
        except OSError as error:
            raise RuntimeError('Range fixture exited before HTTP readiness') from error
        try:
            ready = json.loads(ready_file.read_text())
        except (OSError, ValueError):
            ready = None
        if ready is not None:
            if not isinstance(ready, dict) or ready.get('server') != 'AnPinime.RangeFixture' or ready.get('pid') != pid:
                raise RuntimeError('Range ready file belongs to a different process')
            port = ready.get('port')
            if ready.get('host') != '127.0.0.1' or type(port) is not int or not 1 <= port <= 65535:
                raise RuntimeError('Range ready file has an invalid loopback endpoint')
            connection = http.client.HTTPConnection('127.0.0.1', port, timeout=min(.5, max(.1, deadline-time.monotonic())))
            try:
                connection.request('GET', '/health')
                response = connection.getresponse()
                health = json.loads(response.read(1024))
                if isinstance(health, dict) and response.status == 200 and health.get('server') == 'AnPinime.RangeFixture' and health.get('pid') == pid and health.get('port') == port:
                    return port
                last_error = 'HTTP health identity or status did not match'
            except (OSError, ValueError, http.client.HTTPException) as error:
                last_error = type(error).__name__
            finally:
                connection.close()
        time.sleep(min(.2, max(0, deadline-time.monotonic())))
    raise RuntimeError('Range fixture did not become ready within 10 seconds: '+last_error)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--ready-file', type=Path, required=True)
    arguments = parser.parse_args()
    try:
        port = wait_for_fixture(arguments.pid, arguments.ready_file)
    except RuntimeError as error:
        print('RANGE_READY: '+str(error), file=sys.stderr, flush=True)
        sys.exit(1)
    print(f'RANGE_READY: verified fixture pid={arguments.pid} port={port}', file=sys.stderr, flush=True)
    print(port, flush=True)
