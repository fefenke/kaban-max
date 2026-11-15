"""Actual r11 executable, isolated synthetic IP and loopback HTTPS/DNS only.

Requires an isolated --network none container with NET_ADMIN. Never run on an
existing router/host namespace: nft changes are private to this container.
"""
import contextlib
import copy
import http.server
import json
import os
import signal
import socket
import socketserver
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

BINARY, FIXTURES, TOOLS = sys.argv[1:]
IP = "203.0.113.7"
COUNTS = {"zap": 0, "direct": 0}
DNS_WRONG_OWNER = False
WEB_MODE = False
DNS_MULTIPLE = False
DNS_TTL = 2
NFT = [TOOLS + "/musl", "--library-path", TOOLS + "/libs", TOOLS + "/nft"]


def command(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, **kwargs)


def exact(conn, size):
    result = b""
    while len(result) < size:
        part = conn.recv(size - len(result))
        if not part:
            raise EOFError()
        result += part
    return result


class DNS(socketserver.BaseRequestHandler):
    def handle(self):
        request = exact(self.request, struct.unpack("!H", exact(self.request, 2))[0])
        qtype = struct.unpack("!H", request[-4:-2])[0]
        response = request[:2] + struct.pack("!HHHHH", 0x8180, 1, (2 if DNS_MULTIPLE else 1) if qtype == 1 else 0, 0, 0) + request[12:]
        if qtype == 1:
            owner = b"\x05other\x07example\x04test\x00" if DNS_WRONG_OWNER else b"\xc0\x0c"
            response += owner + struct.pack("!HHIH", 1, 1, DNS_TTL, 4) + socket.inet_aton(IP)
            if DNS_MULTIPLE:
                response += owner + struct.pack("!HHIH", 1, 1, DNS_TTL, 4) + socket.inet_aton("203.0.113.8")
        self.request.sendall(struct.pack("!H", len(response)) + response)


def https(kind):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            COUNTS[kind] += 1
            if WEB_MODE and kind == "zap" and self.headers.get("Host", "").startswith("one.example.test"):
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
                return
            nonce = self.headers.get("X-Kabanmax-Probe")
            self.send_response(200 if WEB_MODE else (451 if kind == "zap" else 200))
            if WEB_MODE:
                self.send_header("Content-Type", "text/html")
            if nonce:
                self.send_header("X-Kabanmax-Probe", nonce)
            body = ((kind + ": <html><body>Ordinary resource content without nonce support.</body></html>") if WEB_MODE else (("fail:" if kind == "zap" else "ok:") + nonce if nonce else kind)).encode()
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("0.0.0.0", 0), Handler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(FIXTURES + "/cert.pem", FIXTURES + "/key.pem")
    server.socket = ctx.wrap_socket(server.socket, server_side=True)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def free_port():
    with socket.socket() as conn:
        conn.bind(("127.0.0.1", 0))
        return conn.getsockname()[1]


@contextlib.contextmanager
def running(config):
    with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryFile() as log:
        path = directory + "/config.json"
        with open(path, "w") as output:
            json.dump(config, output)
        command(BINARY, "check", "-c", path)
        proc = subprocess.Popen([BINARY, "run", "-c", path], stdout=log, stderr=log)
        try:
            time.sleep(0.3)
            assert proc.poll() is None, "core exited"
            yield proc
        finally:
            if proc.poll() is None:
                proc.send_signal(signal.SIGTERM)
            proc.wait(timeout=10)
            log.seek(0)
            text = log.read().decode(errors="replace")
            if proc.returncode:
                raise AssertionError(text)


def api(port, op=None, **args):
    request = urllib.request.Request("http://127.0.0.1:%d/kabanmax/auto" % port,
        data=json.dumps({"op": op, **args}).encode() if op else None,
        headers={"Authorization": "Bearer synthetic-only", "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response)


def fetch(socks_port, domain, port, fake_ip=None):
    with socket.create_connection(("127.0.0.1", socks_port), timeout=3) as conn:
        conn.sendall(b"\5\1\0")
        assert exact(conn, 2) == b"\5\0"
        dest = b"\1" + socket.inet_aton(fake_ip) if fake_ip else b"\3" + bytes([len(domain)]) + domain.encode()
        conn.sendall(b"\5\1\0" + dest + struct.pack("!H", port))
        head = exact(conn, 4)
        assert head[1] == 0, head
        exact(conn, 6 if head[3] == 1 else 18)
        ctx = ssl.create_default_context(cafile=FIXTURES + "/cert.pem")
        with ctx.wrap_socket(conn, server_hostname=domain) as secure:
            secure.sendall(("GET /contract HTTP/1.0\r\nHost: %s\r\n\r\n" % domain).encode())
            response = b""
            while part := secure.recv(4096):
                response += part
            return response.split(b"\r\n\r\n", 1)[1].decode()


command("ip", "addr", "add", IP + "/32", "dev", "lo")
dns = socketserver.ThreadingTCPServer(("127.0.0.1", 0), DNS)
threading.Thread(target=dns.serve_forever, daemon=True).start()
failure, success = https("zap"), https("direct")
port = success.server_port
# Source Zapret's actual socket mark chooses a separate synthetic response. This
# touches only this disposable network namespace and never flushes any table.
rules = ("add table ip kabanmax_auto_test\n"
         "add chain ip kabanmax_auto_test out { type nat hook output priority -100; policy accept; }\n"
         "add rule ip kabanmax_auto_test out meta mark 0x02000001 ip daddr %s tcp dport %d redirect to :%d\n" % (IP, port, failure.server_port))
subprocess.run(NFT + ["-f", "-"], input=rules.encode(), check=True)
try:
    for mode in ("disabled", "all", "selected"):
        api_port, socks_port = free_port(), free_port()
        source = {"id": "s1", "outbound": "zap", "mark": 0x02000001, "probe_zapret": True,
                  "direct": True, "auto_apply": False, "domain": "one.example.test", "path": "/contract",
                  "port": port, "status": 200, "prefix": "ok:", "failure_status": 451, "failure_prefix": "fail:"}
        zap = {"domain_suffix": ["example.test"], "action": "route", "outbound": "zap"}
        resolve = {"action": "resolve", "server": "dns-server"}
        if mode == "selected":
            resolve["domain"] = ["one.example.test", "two.example.test"]
        config = {
            "log": {"disabled": True}, "certificate": {"store": "none", "certificate_path": [FIXTURES + "/cert.pem"]},
            "inbounds": [{"type": "socks", "tag": "tproxy-in", "listen": "127.0.0.1", "listen_port": socks_port}],
            "outbounds": [{"type": "direct", "tag": "zap", "routing_mark": 0x02000001}, {"type": "direct", "tag": "direct-out"}],
            "dns": {"servers": [{"type": "tcp", "tag": "dns-server", "server": "127.0.0.1", "server_port": dns.server_address[1]}]},
            "route": {"rules": ([resolve] if mode != "disabled" else []) + [zap, {"domain_suffix": ["example.test"], "action": "reject"}], "final": "direct-out", "default_domain_resolver": "dns-server", "kabanmax_auto": [source]},
            "experimental": {"clash_api": {"external_controller": "127.0.0.1:%d" % api_port, "secret": "synthetic-only"}},
        }
        query = {"ip": IP, "domain": source["domain"], "source_ip": "127.0.0.1", "inbound": "tproxy-in", "port": port, "source": "zap"}
        with running(config):
            assert fetch(socks_port, source["domain"], port) == "zap"
            decision = api(api_port, "probe", query=query)
            assert decision["status"] == "proposed", decision
            assert len(decision["attempts"]) == 4 and all(a["tls_verified"] for a in decision["attempts"]), decision
            api(api_port, "apply", id=decision["id"])
            assert fetch(socks_port, "one.example.test", port) == "direct", mode
            assert fetch(socks_port, "two.example.test", port) == "zap", "shared CDN address escaped"
            api(api_port, "delete", id=decision["id"])
            assert fetch(socks_port, "one.example.test", port) == "zap", "delete did not withdraw"
            assert api(api_port, "probe", query=query)["reason"] == "suppressed"
            assert not api(api_port)["leases"]
        # A new process does not reactivate a former proof or lease.
        with running(config):
            assert not api(api_port)["leases"]
        with running(config):
            decision = api(api_port, "probe", query=query)
            api(api_port, "apply", id=decision["id"])
            time.sleep(2.2)
            assert fetch(socks_port, "one.example.test", port) == "zap", "expired lease remained active"
            assert not api(api_port)["leases"]
        if mode == "disabled":
            DNS_WRONG_OWNER = True
            before = COUNTS.copy()
            with running(config):
                invalid = api(api_port, "probe", query=query)
                assert invalid["status"] == "inconclusive" and COUNTS == before, "unrelated DNS owner authorized HTTPS"
            DNS_WRONG_OWNER = False
            fake_config = copy.deepcopy(config)
            fake_config["dns"]["servers"].append({"type": "fakeip", "tag": "fake", "inet4_range": "198.18.0.0/15", "inet6_range": "fc00::/112"})
            fake_config["dns"]["rules"] = [{"domain_suffix": ["example.test"], "action": "route", "server": "fake"}]
            with running(fake_config):
                def fake_address(domain):
                    req = urllib.request.Request("http://127.0.0.1:%d/dns/query?name=%s&type=A" % (api_port, domain), headers={"Authorization": "Bearer synthetic-only"})
                    with urllib.request.urlopen(req, timeout=3) as response:
                        answer = json.load(response)["Answer"][0]["data"].strip()
                        assert answer.startswith("198.18."), answer
                        return answer
                one, two = fake_address("one.example.test"), fake_address("two.example.test")
                assert fetch(socks_port, "one.example.test", port, one) == "zap"
                decision = api(api_port, "probe", query=query)
                api(api_port, "apply", id=decision["id"])
                assert fetch(socks_port, "one.example.test", port, one) == "direct"
                assert fetch(socks_port, "two.example.test", port, two) == "zap", "FakeIP CDN scope leaked"
            print("PASS executable: actual FakeIP mapping and domain isolation", flush=True)
        # Ordinary web response has no nonce echo or application-failure marker.
        WEB_MODE, DNS_TTL = True, 20
        web_config = copy.deepcopy(config)
        web_config["route"]["kabanmax_auto"] = [{"id": "s1", "outbound": "zap", "mark": 0x02000001, "probe_zapret": True,
            "direct": True, "auto_apply": True, "mode": "web", "path": "/", "port": port, "status": 200}]
        with running(web_config):
            try:
                fetch(socks_port, "one.example.test", port)
                raise AssertionError("synthetic original unexpectedly worked")
            except (EOFError, ssl.SSLError, ConnectionError, IndexError):
                pass
            candidate = next(e for e in api(api_port)["candidates"] if e["domain"] == "one.example.test")
            assert candidate["domain_known"] and candidate["ip"] == IP, candidate
            original = {k: candidate[k] for k in ("ip", "domain", "source_ip", "source_port", "inbound", "port", "source")}
            proposed = api(api_port, "probe", query=original)
            assert proposed["status"] == "proposed" and proposed["evidence"] == "alternative_reachable" and proposed["apply_allowed"] and not proposed["auto_apply_eligible"], proposed
            assert not api(api_port)["leases"], "web silently auto-applied"
            assert len(proposed["attempts"]) == 4 and all(a["dial_ip"] == IP for a in proposed["attempts"])
            api(api_port, "apply", id=proposed["id"])
            assert fetch(socks_port, "one.example.test", port).startswith("direct:")
            assert fetch(socks_port, "two.example.test", port).startswith("zap:"), "ordinary CDN domain escaped"
            api(api_port, "delete", id=proposed["id"])
            assert not api(api_port)["leases"]
            healthy = next(e for e in api(api_port)["candidates"] if e["domain"] == "two.example.test")
            healthy_query = {k: healthy[k] for k in ("ip", "domain", "source_ip", "source_port", "inbound", "port", "source")}
            verified = api(api_port, "probe", query=healthy_query)
            assert verified["evidence"] == "healthy" and not verified["apply_allowed"]
        if mode == "disabled":
            ip_config = copy.deepcopy(web_config)
            ip_config["route"]["rules"].insert(0, {"ip_cidr": [IP + "/32"], "action": "route", "outbound": "zap"})
            with running(ip_config):
                assert fetch(socks_port, "two.example.test", port, IP).startswith("zap:")
                unknown = next(e for e in api(api_port)["candidates"] if e["ip"] == IP and not e["domain"])
                assert not unknown["domain_known"] and unknown["source_id"] == "s1" and unknown["routing_mark"] == 0x02000001, unknown
                diagnostic_query = {k: unknown[k] for k in ("ip", "domain", "source_ip", "source_port", "inbound", "port", "source")}
                diagnostic = api(api_port, "probe", query=diagnostic_query)
                assert diagnostic["status"] == "identity_unknown" and not diagnostic["apply_allowed"] and not api(api_port)["leases"]
                try:
                    api(api_port, "apply", id=diagnostic["id"])
                    raise AssertionError("IP-only apply succeeded")
                except urllib.error.HTTPError as error:
                    assert error.code == 409
            web_fake = copy.deepcopy(fake_config)
            web_fake["route"]["kabanmax_auto"] = web_config["route"]["kabanmax_auto"]
            with running(web_fake):
                one, two = fake_address("one.example.test"), fake_address("two.example.test")
                try:
                    fetch(socks_port, "one.example.test", port, one)
                except (EOFError, ssl.SSLError, ConnectionError, IndexError):
                    pass
                candidate = next(e for e in api(api_port)["candidates"] if e["domain"] == "one.example.test")
                assert candidate["domain_known"] and candidate["ip"] == IP, candidate
                fake_query = {k: candidate[k] for k in ("ip", "domain", "source_ip", "source_port", "inbound", "port", "source")}
                proposed = api(api_port, "probe", query=fake_query)
                api(api_port, "apply", id=proposed["id"])
                assert fetch(socks_port, "one.example.test", port, one).startswith("direct:")
                assert fetch(socks_port, "two.example.test", port, two).startswith("zap:")
            print("PASS executable: ordinary FakeIP identity and IP-only diagnostic without apply", flush=True)
        # A mixed DNS name must not be pinned to the failed address by a lease.
        DNS_MULTIPLE = True
        with running(web_config):
            try:
                fetch(socks_port, "one.example.test", port)
            except (EOFError, ssl.SSLError, ConnectionError, IndexError):
                pass
            candidate = next(e for e in api(api_port)["candidates"] if e["domain"] == "one.example.test")
            assert candidate["ip"] == IP, candidate
            original = {k: candidate[k] for k in ("ip", "domain", "source_ip", "source_port", "inbound", "port", "source")}
            proposed = api(api_port, "probe", query=original)
            assert proposed["status"] == "proposed" and all(a["dial_ip"] == IP for a in proposed["attempts"]), proposed
            api(api_port, "apply", id=proposed["id"])
            try:
                fetch(socks_port, "one.example.test", port)
                raise AssertionError("mixed A answers were pinned by lease")
            except (EOFError, ssl.SSLError, ConnectionError, IndexError):
                pass
            assert fetch(socks_port, "two.example.test", port).startswith("zap:")
        WEB_MODE, DNS_MULTIPLE, DNS_TTL = False, False, 2
        print("PASS executable: ordinary HTTPS, attested actual IP, manual-only proposal, mixed DNS scope, pre-resolve=" + mode, flush=True)
        before = COUNTS.copy()
        config["route"]["rules"].insert(0, {"domain_suffix": ["example.test"], "action": "reject"})
        with running(config):
            denied = api(api_port, "probe", query=query)
            assert denied["status"] == "inconclusive" and not api(api_port)["leases"], denied
            assert COUNTS == before, "Block before Zapret made a probe"
        if mode == "disabled":
            for guard in ({"protocol": "tls", "action": "reject"}, {"process_name": ["unavailable-client-context"], "action": "reject"}):
                config["route"]["rules"][0] = guard
                before = COUNTS.copy()
                with running(config):
                    denied = api(api_port, "probe", query=query)
                    assert denied["status"] == "inconclusive", denied
                    assert COUNTS == before, "unknown earlier context caused a probe"
        print("PASS executable: actual mark, HTTPS contract, CDN, first-match, delete, TTL, restart, pre-resolve=" + mode, flush=True)
finally:
    dns.shutdown()
    failure.shutdown()
    success.shutdown()
