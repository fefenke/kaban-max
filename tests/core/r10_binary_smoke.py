"""Exercise the built r10 executable, using only loopback and synthetic data."""
import contextlib
import ipaddress
import json
import os
import signal
import socket
import socketserver
import struct
import subprocess
import sys
import tempfile
import threading
import time

BINARY = sys.argv[1]
ANSWERS = ["203.0.113.7", "198.51.100.7"]


def exact(sock, size):
    data = b""
    while len(data) < size:
        part = sock.recv(size - len(data))
        if not part:
            raise EOFError()
        data += part
    return data


class DNS(socketserver.BaseRequestHandler):
    def handle(self):
        query = exact(self.request, struct.unpack("!H", exact(self.request, 2))[0])
        response = query[:2] + struct.pack("!HHHHH", 0x8180, 1, len(ANSWERS), 0, 0) + query[12:]
        for address in ANSWERS:
            response += b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 1, 4) + socket.inet_aton(address)
        self.request.sendall(struct.pack("!H", len(response)) + response)


def port(kind=socket.SOCK_STREAM):
    with socket.socket(type=kind) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


@contextlib.contextmanager
def running(config, directory):
    path = os.path.join(directory, "config.json")
    with open(path, "w") as output:
        json.dump(config, output)
    subprocess.run([BINARY, "check", "-c", path], check=True, capture_output=True)
    with tempfile.TemporaryFile() as log:
        process = subprocess.Popen([BINARY, "run", "-c", path], stdout=log, stderr=log)
        try:
            time.sleep(0.3)
            assert process.poll() is None, "core exited before readiness"
            yield process
        finally:
            if process.poll() is None:
                process.send_signal(signal.SIGTERM)
            process.wait(timeout=10)
            log.seek(0)
            text = log.read().decode(errors="replace")
            if process.returncode != 0:
                raise AssertionError(text)


def query_dns(listen_port):
    question = b"".join(bytes([len(part)]) + part.encode() for part in "mixed.example.org".split(".")) + b"\0\0\1\0\1"
    query = struct.pack("!HHHHHH", 123, 0x100, 1, 0, 0, 0) + question
    with socket.socket(type=socket.SOCK_DGRAM) as sock:
        sock.settimeout(2)
        sock.sendto(query, ("127.0.0.1", listen_port))
        response = sock.recv(4096)
    assert struct.unpack("!H", response[6:8])[0] == 1
    return ipaddress.ip_address(response[-4:])


with tempfile.TemporaryDirectory() as directory, socketserver.ThreadingTCPServer(("127.0.0.1", 0), DNS) as upstream:
    threading.Thread(target=upstream.serve_forever, daemon=True).start()
    dns_port, socks_port = port(socket.SOCK_DGRAM), port()
    with open("/fixtures/detour-off.json") as source:
        config = json.load(source)
    # Same generated policy as Go regression; replace privileged/environment inputs.
    config = json.loads(json.dumps(config).replace("192.0.2.7/32", "127.0.0.1/32").replace("192.0.2.0/24", "127.0.0.0/8"))
    config["log"] = {"disabled": True}
    config["inbounds"] = [{"type": "direct", "tag": "source-dns-in", "listen": "127.0.0.1", "listen_port": dns_port, "network": "udp"}]
    config["experimental"] = {"cache_file": {"enabled": True, "path": directory + "/cache.db", "store_fakeip": True}}
    config["route"].pop("default_mark", None)
    for rule_set in config["route"]["rule_set"]:
        rule_set.clear()
        rule_set.update(type="inline", tag="inline-custom-481c7be49167-ruleset", rules=[{"ip_cidr": ["203.0.113.0/24"]}])
    for server in config["dns"]["servers"]:
        if server["tag"] == "dns-server":
            server.clear()
            server.update(type="tcp", tag="dns-server", server="127.0.0.1", server_port=upstream.server_address[1])
    with running(config, directory):
        first = query_dns(dns_port)
        assert first in ipaddress.ip_network("198.18.0.0/16"), first
    with running(config, directory):
        assert query_dns(dns_port) == first, "FakeIP changed after graceful restart"
    print("PASS built binary: generated mixed DNS -> FakeIP, graceful disk-cache restart")

    # A real listener at the lower Direct address detects accidental fallthrough.
    with socket.socket() as target:
        target.bind(("127.0.0.1", 0))
        target.listen()
        target.settimeout(0.4)
        config = {
            "log": {"disabled": True},
            "inbounds": [{"type": "socks", "tag": "in", "listen": "127.0.0.1", "listen_port": socks_port}],
            "outbounds": [{"type": "direct", "tag": "direct"}],
            "dns": {"servers": [{"type": "tcp", "tag": "dns", "server": "127.0.0.1", "server_port": upstream.server_address[1]}]},
            "route": {"final": "direct", "rules": []},
        }
        for mode in ["resolved-isolation", "resolved-control", "missing-provider", "direct-control"]:
            if mode.startswith("resolved-"):
                ANSWERS[:] = ["127.0.0.2", "127.0.0.1"]
                allowed = "127.0.0.2/32" if mode == "resolved-isolation" else "127.0.0.1/32"
                config["route"]["rules"] = [{"action": "resolve", "server": "dns"}, {"ip_cidr": [allowed], "action": "route", "outbound": "direct"}]
            elif mode == "missing-provider":
                config["route"]["rules"] = [{"rule_set": "missing", "action": "route", "outbound": "direct"}]
                config["route"]["rule_set"] = [{"type": "remote", "tag": "missing", "format": "source", "url": "http://127.0.0.1:1/missing.json", "download_detour": "direct"}]
            else:
                config["route"] = {"final": "direct", "rules": []}
            with running(config, directory):
                with socket.create_connection(("127.0.0.1", socks_port), timeout=2) as client:
                    client.sendall(b"\5\1\0")
                    assert exact(client, 2) == b"\5\0"
                    host = b"mixed.example.org"
                    destination = b"\3" + bytes([len(host)]) + host if mode.startswith("resolved-") else b"\1" + socket.inet_aton("127.0.0.1")
                    client.sendall(b"\5\1\0" + destination + struct.pack("!H", target.getsockname()[1]))
                    try:
                        client.recv(256)
                    except (ConnectionError, TimeoutError):
                        pass
                try:
                    conn, _ = target.accept()
                except TimeoutError:
                    assert not mode.endswith("control"), "control listener was unreachable"
                else:
                    conn.close()
                    assert mode.endswith("control"), mode + " leaked to lower Direct address"
            print("PASS built binary: " + mode)
    upstream.shutdown()
