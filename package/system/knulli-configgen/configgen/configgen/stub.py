#!/usr/bin/env python
"""
emulatorlauncher: hands the launch to configgend (see daemon.py) and relays
signals and the exit code.  Without a daemon, or with one that does not answer,
the launcher runs in this process exactly as before.
"""
from __future__ import annotations

import array
import json
import os
import signal
import socket
import sys

SOCKET_PATH = os.environ.get("CONFIGGEND_SOCKET", "/run/configgend.sock")

# a free daemon answers at once; a busy or hung one must not hold the launch
ACCEPT_TIMEOUT = 2.0

def _fallback() -> None:
    from configgen.emulatorlauncher import launch
    launch()

def _descendants(root: int) -> list[int]:
    children: dict[int, list[int]] = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat") as f:
                ppid = int(f.read().rsplit(")", 1)[1].split()[1])
        except (OSError, IndexError, ValueError):
            continue
        children.setdefault(ppid, []).append(int(entry))
    # breadth first, so reversed() is deepest first
    found: list[int] = []
    queue = [root]
    while queue:
        for child in children.get(queue.pop(0), []):
            found.append(child)
            queue.append(child)
    return found

def _readline(conn: socket.socket) -> bytes:
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = conn.recv(1)
        if not chunk:
            break
        buf += chunk
    return buf

def main() -> None:
    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        conn.settimeout(ACCEPT_TIMEOUT)
        conn.connect(SOCKET_PATH)
        header = json.dumps({
            "argv": sys.argv[1:],
            "cwd": os.getcwd(),
            "env": dict(os.environ),
        }).encode() + b"\n"
        conn.sendmsg([header], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array("i", [0, 1, 2]))])
        line = _readline(conn)
        if not line.startswith(b"PID "):
            raise OSError("no worker")
        worker_pid = int(line.split()[1])
    except (OSError, ValueError):
        conn.close()
        _fallback()
        return
    conn.settimeout(None)

    def forward(signum, _frame):
        try:
            os.kill(worker_pid, signum)
        except ProcessLookupError:
            pass

    # knulli-es-swissknife --emukill terminates the launcher's descendants,
    # deepest first, so the emulator can save; the game hangs off the worker
    # now, so do that walk here and let the worker finish normally.
    def terminate_emulator(_signum, _frame):
        for pid in reversed(_descendants(worker_pid)):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    signal.signal(signal.SIGINT, forward)
    signal.signal(signal.SIGTERM, terminate_emulator)

    code = 1
    while line := _readline(conn):
        if line.startswith(b"EXIT "):
            try:
                code = int(line.split()[1])
            except (IndexError, ValueError):
                pass
            break
    conn.close()
    sys.exit(code)

if __name__ == "__main__":
    main()
