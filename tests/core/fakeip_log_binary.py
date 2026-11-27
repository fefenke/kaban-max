"""Local executable regression: missing FakeIP stays refused and is visible only in Debug."""
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time


def main(binary):
    for level in ("warn", "error", "debug"):
        with tempfile.TemporaryDirectory(prefix="fakeip-log-") as directory:
            root = Path(directory)
            with socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                port = listener.getsockname()[1]
            config = {
                "log": {"level": level},
                "dns": {"servers": [
                    {"type": "udp", "tag": "unused", "server": "127.0.0.1", "server_port": 9},
                    {"type": "fakeip", "tag": "fake", "inet4_range": "198.18.0.0/15", "inet6_range": "2001:2::/112"},
                ], "final": "unused"},
                "inbounds": [{"type": "mixed", "listen": "127.0.0.1", "listen_port": port}],
                "outbounds": [{"type": "direct", "tag": "direct"}],
                "route": {"final": "direct", "default_domain_resolver": "unused"},
            }
            path = root / "config.json"
            path.write_text(json.dumps(config))
            log_path = root / "core.log"
            with log_path.open("w") as output:
                process = subprocess.Popen([binary, "run", "-c", str(path)], stdout=output, stderr=output)
                try:
                    deadline = time.monotonic() + 5
                    while True:
                        assert process.poll() is None, log_path.read_text()
                        try:
                            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                                break
                        except OSError:
                            assert time.monotonic() < deadline, log_path.read_text()
                            time.sleep(0.02)
                    for destination in ("198.18.0.1:44100", "[2001:2::1]:44100"):
                        with socket.create_connection(("127.0.0.1", port), timeout=2) as client:
                            client.sendall(("CONNECT " + destination + " HTTP/1.1\r\nHost: " + destination + "\r\n\r\n").encode())
                            try:
                                reply = client.recv(1024)
                            except ConnectionResetError:
                                reply = b""
                            # CONNECT can acknowledge before routing. The actual
                            # transport must still close without forwarding data.
                            if b" 200 " in reply:
                                try:
                                    client.sendall(b"probe")
                                    assert not client.recv(1024), "unmapped FakeIP forwarded data"
                                except (BrokenPipeError, ConnectionResetError):
                                    pass
                    time.sleep(0.1)
                finally:
                    process.terminate()
                    process.wait(timeout=5)
            messages = [line for line in log_path.read_text().splitlines() if "no fakeip record" in line]
            if level == "debug":
                assert len(messages) == 2, log_path.read_text()
                assert all("DEBUG" in line and "44100" in line for line in messages), messages
            else:
                assert not messages, messages
            print(level + ": refusal preserved, FakeIP log threshold OK")


if __name__ == "__main__":
    main(sys.argv[1])
