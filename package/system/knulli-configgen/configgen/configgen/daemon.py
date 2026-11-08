#!/usr/bin/env python
"""
configgend: a resident launcher that keeps configgen imported and warm.

Every launch otherwise pays for the interpreter, the configgen import tree, the
generator, and parsing the controller and games databases.  configgend does
that once, then fork()s a worker per launch; the worker inherits it all
copy-on-write, runs the normal emulatorlauncher session (generate, run the
emulator, wait, restore) and exits, so the parent stays small.

Protocol, one game at a time over a Unix socket:
  stub -> daemon  one sendmsg: JSON {"argv", "cwd", "env"} + newline, with
                  stdin/stdout/stderr passed as SCM_RIGHTS
  daemon -> stub  b"PID <pid>\\n", then b"EXIT <code>\\n" when the session ends

The worker leads its own process group.  If the stub goes away (ES killed it)
the group is terminated, so a game never outlives its launcher.
"""
from __future__ import annotations

import argparse
import array
import json
import logging
import os
import select
import signal
import socket
import sys
import time

SOCKET_PATH = os.environ.get("CONFIGGEND_SOCKET", "/run/configgend.sock")

# libretro covers most systems
DEFAULT_PRELOAD = ["libretro"]

log = logging.getLogger("configgend")

def _preload(preload: list[str]) -> None:
    import configgen.emulatorlauncher  # noqa: F401
    from configgen.batoceraPaths import ES_GAMES_METADATA
    from configgen.controller import Controller
    from configgen.generators import get_generator
    from configgen.utils import metadata

    try:
        Controller.prewarm()
        metadata.prewarm(ES_GAMES_METADATA)
        log.info("preloaded controller and games databases")
    except Exception as e:
        log.warning("database prewarm failed: %s", e)

    for emulator in preload:
        try:
            get_generator(emulator)
            log.info("preloaded generator: %s", emulator)
        except Exception as e:
            log.warning("could not preload generator %s: %s", emulator, e)

def _run_worker(argv: list[str], cwd: str, env: dict[str, str], fds: list[int]) -> None:
    os.setpgid(0, 0)
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGCHLD):
        signal.signal(sig, signal.SIG_DFL)

    for target, fd in zip((0, 1, 2), fds):
        os.dup2(fd, target)
    for fd in fds:
        if fd > 2:
            os.close(fd)

    try:
        if cwd:
            os.chdir(cwd)
    except OSError:
        pass

    os.environ.clear()
    os.environ.update(env)
    sys.argv = ["emulatorlauncher", *argv]

    # launch() sets up its own logging; drop the daemon's handlers
    logging.root.handlers.clear()

    from configgen.emulatorlauncher import launch
    launch()

def _send_line(conn: socket.socket, text: str) -> None:
    try:
        conn.sendall(text.encode())
    except OSError:
        pass

def _stop_group(pid: int) -> None:
    for sig, grace in ((signal.SIGTERM, 5.0), (signal.SIGKILL, 0)):
        try:
            os.killpg(pid, sig)
        except ProcessLookupError:
            return
        deadline = time.monotonic() + grace
        while time.monotonic() < deadline:
            if os.waitpid(pid, os.WNOHANG)[0]:
                return
            time.sleep(0.1)

def _wait_worker(conn: socket.socket, pid: int) -> int:
    poller = select.poll()
    poller.register(conn, select.POLLIN | select.POLLHUP)
    while True:
        done, status = os.waitpid(pid, os.WNOHANG)
        if done:
            break
        # the stub never writes after its request: readable means it is gone
        if poller.poll(250):
            log.warning("launcher %d lost its client, stopping it", pid)
            _stop_group(pid)
            try:
                os.waitpid(pid, 0)
            except ChildProcessError:
                pass
            return 1
    if os.WIFEXITED(status):
        return os.WEXITSTATUS(status)
    if os.WIFSIGNALED(status):
        return 128 + os.WTERMSIG(status)
    return 1

def _handle(conn: socket.socket) -> None:
    fds: list[int] = []
    msg, ancdata, _flags, _addr = conn.recvmsg(1 << 20, socket.CMSG_LEN(3 * array.array("i").itemsize))
    for level, typ, cmsg in ancdata:
        if level == socket.SOL_SOCKET and typ == socket.SCM_RIGHTS:
            a = array.array("i")
            a.frombytes(cmsg[: len(cmsg) - (len(cmsg) % a.itemsize)])
            fds.extend(a.tolist())

    try:
        header = json.loads(msg.split(b"\n", 1)[0].decode())
        argv, cwd, env = header["argv"], header.get("cwd", ""), header["env"]
        if len(fds) != 3:
            raise ValueError(f"expected 3 stdio fds, got {len(fds)}")
    except (ValueError, KeyError, UnicodeDecodeError) as e:
        log.error("bad request: %s", e)
        for fd in fds:
            os.close(fd)
        _send_line(conn, "EXIT 1\n")
        conn.close()
        return

    # a stub that timed out while we were busy has launched in-process already
    probe = select.poll()
    probe.register(conn, select.POLLIN | select.POLLHUP)
    if probe.poll(0):
        log.warning("dropping a request whose client is gone")
        for fd in fds:
            os.close(fd)
        conn.close()
        return

    pid = os.fork()
    if pid == 0:
        try:
            conn.close()
            _run_worker(argv, cwd, env, fds)
            code = 0
        except SystemExit as e:
            code = e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
        except BaseException:
            logging.getLogger("configgend.worker").exception("worker crashed")
            code = 1
        sys.stdout.flush()
        sys.stderr.flush()
        os._exit(code)

    for fd in fds:
        os.close(fd)
    _send_line(conn, f"PID {pid}\n")
    _send_line(conn, f"EXIT {_wait_worker(conn, pid)}\n")
    conn.close()

def serve(socket_path: str, preload: list[str]) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s configgend %(levelname)s %(message)s")
    signal.signal(signal.SIGCHLD, signal.SIG_DFL)

    _preload(preload)

    try:
        os.unlink(socket_path)
    except FileNotFoundError:
        pass
    os.makedirs(os.path.dirname(socket_path), exist_ok=True)

    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(socket_path)
    os.chmod(socket_path, 0o660)
    srv.listen(8)
    log.info("listening on %s (preload=%s)", socket_path, preload)

    while True:
        try:
            conn, _ = srv.accept()
        except InterruptedError:
            continue
        try:
            _handle(conn)
        except Exception:
            log.exception("error handling connection")
            try:
                conn.close()
            except OSError:
                pass

def main() -> None:
    p = argparse.ArgumentParser(description="configgen launcher daemon")
    p.add_argument("--socket", default=SOCKET_PATH, help="unix socket path")
    p.add_argument("--preload", default=",".join(DEFAULT_PRELOAD),
                   help="comma-separated emulators whose generators to pre-import")
    args = p.parse_args()
    serve(args.socket, [x for x in args.preload.split(",") if x])

if __name__ == "__main__":
    main()
