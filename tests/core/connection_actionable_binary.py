"""Loopback-only genuine proxy TLS failure must identify what to investigate."""
import contextlib
import json
import os
from pathlib import Path
import socket
import socketserver
import ssl
import subprocess
import sys
import tempfile
import threading
import time


def main(binary):
    with tempfile.TemporaryDirectory(prefix="connection-actionable-") as directory:
        root = Path(directory)
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=proxy.test", "-addext", "subjectAltName=DNS:proxy.test", "-keyout", str(root / "key.pem"), "-out", str(root / "cert.pem")], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.minimum_version = ssl.TLSVersion.TLSv1_3
        tls.load_cert_chain(root / "cert.pem", root / "key.pem")

        class Peer(socketserver.BaseRequestHandler):
            def handle(self):
                self.request.settimeout(3)
                try:
                    with tls.wrap_socket(self.request, server_side=True) as stream:
                        stream.recv(1)
                except (ssl.SSLError, OSError):
                    pass

        class Server(socketserver.ThreadingTCPServer):
            allow_reuse_address = True
            daemon_threads = True

        server = Server(("127.0.0.1", 0), Peer)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        config = {
            "log": {"level": "debug", "timestamp": False},
            "certificate": {"store": "none", "certificate_path": [str(root / "cert.pem")]},
            "inbounds": [{"type": "socks", "tag": "fixture-in", "listen": "127.0.0.1", "listen_port": port}],
            "outbounds": [{"type": "http", "tag": "fixture-proxy", "server": "127.0.0.1", "server_port": server.server_address[1], "tls": {"enabled": True, "server_name": "proxy.test", "max_version": "1.2"}}],
            "route": {"final": "fixture-proxy"},
        }
        (root / "config.json").write_text(json.dumps(config))
        try:
            with (root / "core.log").open("w") as output:
                process = subprocess.Popen([binary, "run", "-c", str(root / "config.json")], cwd=root, stdout=output, stderr=subprocess.STDOUT)
                try:
                    until = time.monotonic() + 5
                    while True:
                        if process.poll() is not None:
                            raise AssertionError("core exited: " + (root / "core.log").read_text())
                        try:
                            client = socket.create_connection(("127.0.0.1", port), 1)
                            break
                        except OSError:
                            if time.monotonic() >= until:
                                raise
                            time.sleep(.02)
                    with client:
                        client.settimeout(3)
                        client.sendall(b"\x05\x01\x00")
                        assert client.recv(2) == b"\x05\x00"
                        client.sendall(b"\x05\x01\x00\x03\x0btarget.test\x01\xbb")
                        reply = client.recv(10)
                        assert len(reply) >= 2 and reply[0] == 5 and reply[1] != 0, reply
                    until = time.monotonic() + 2
                    while True:
                        logs = (root / "core.log").read_text()
                        errors = [line for line in logs.splitlines() if "ERROR" in line and "connection failure" in line]
                        if errors or time.monotonic() >= until:
                            break
                        time.sleep(.02)
                    assert len(errors) == 1, logs
                    for required in ["stage=connect", "target.test:443", "http[fixture-proxy]", "check=", "TLS compatibility", "protocol version not supported"]:
                        assert required in errors[0], (required, errors[0])
                finally:
                    process.terminate()
                    with contextlib.suppress(subprocess.TimeoutExpired):
                        process.wait(timeout=5)
                    if process.poll() is None:
                        process.kill()
                        process.wait()
        finally:
            server.shutdown()
            server.server_close()
    print("PASS executable TLS failure: destination, selected profile, phase, original cause and next check")


if __name__ == "__main__":
    main(os.path.abspath(sys.argv[1]))
