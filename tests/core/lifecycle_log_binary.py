"""Loopback-only HUP regression: old flow failures are Debug; new DNS failures stay visible."""
import json
import os
from pathlib import Path
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time


def wait_for(check, description, process, seconds=10):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if check():
            return
        if process.poll() is not None:
            raise AssertionError("core exited while waiting for " + description)
        time.sleep(0.02)
    raise AssertionError("timed out waiting for " + description)


def main(binary):
    with tempfile.TemporaryDirectory(prefix="lifecycle-log-") as directory:
        root = Path(directory)
        dns = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        dns.bind(("127.0.0.1", 0))
        dns.settimeout(0.1)
        port_socket = socket.socket()
        port_socket.bind(("127.0.0.1", 0))
        proxy_port = port_socket.getsockname()[1]
        port_socket.close()
        seen = threading.Event()
        refuse = threading.Event()
        done = threading.Event()

        def serve_dns():
            while not done.is_set():
                try:
                    query, address = dns.recvfrom(4096)
                except socket.timeout:
                    continue
                except OSError:
                    return
                seen.set()
                if refuse.is_set():
                    end = 12
                    while query[end]:
                        end += query[end] + 1
                    end += 5
                    reply = query[:2] + struct.pack("!HHHHH", 0x8185, 1, 0, 0, 0) + query[12:end]
                    dns.sendto(reply, address)

        thread = threading.Thread(target=serve_dns, daemon=True)
        thread.start()
        config = {
            "log": {"level": "debug", "disabled": False},
            "dns": {"servers": [{"type": "udp", "tag": "held", "server": "127.0.0.1", "server_port": dns.getsockname()[1]}], "final": "held", "strategy": "ipv4_only"},
            "inbounds": [{"type": "mixed", "tag": "local", "listen": "127.0.0.1", "listen_port": proxy_port}],
            "outbounds": [{"type": "direct", "tag": "direct-out"}],
            "route": {"final": "direct-out", "default_domain_resolver": "held"},
        }
        config_path = root / "config.json"
        config_path.write_text(json.dumps(config), encoding="utf-8")
        log_path = root / "core.log"
        clients = []
        with log_path.open("w") as output:
            process = subprocess.Popen([binary, "run", "--disable-color", "-c", str(config_path)], stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT)
            try:
                logs = lambda: log_path.read_text(encoding="utf-8")
                wait_for(lambda: "sing-box started" in logs(), "initial start", process)

                def connect(host):
                    client = socket.create_connection(("127.0.0.1", proxy_port), timeout=2)
                    clients.append(client)
                    client.sendall((f"CONNECT {host}:443 HTTP/1.1\r\nHost: {host}:443\r\n\r\n").encode())

                connect("pending.example.test")
                wait_for(seen.is_set, "pending DNS request", process)
                os.kill(process.pid, signal.SIGHUP)
                wait_for(lambda: logs().count("sing-box started") >= 2, "new generation", process)
                wait_for(lambda: any("connection:" in line and "open connection to pending.example.test" in line for line in logs().splitlines()), "old flow closure", process)
                closing = [line for line in logs().splitlines() if "connection:" in line and "open connection to pending.example.test" in line]
                assert closing, "old flow failure was not logged"
                assert all("DEBUG" in line for line in closing), closing
                refuse.set()
                connect("fresh.example.test")
                wait_for(lambda: any("fresh.example.test" in line and "ERROR" in line for line in logs().splitlines()), "new generation DNS failure", process)
            except Exception:
                print(log_path.read_text(encoding="utf-8"), file=sys.stderr)
                raise
            finally:
                for client in clients:
                    client.close()
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                done.set()
                dns.close()
                thread.join(timeout=1)
        print("PASS executable HUP: old flow failure is Debug, fresh generation DNS failure is Error")


if __name__ == "__main__":
    main(sys.argv[1])
