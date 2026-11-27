"""Loopback TLS/data: independent confirmation success and full outage failover."""
import contextlib
import http.server
import json
import os
from pathlib import Path
import select
import socket
import socketserver
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def main(binary):
    with tempfile.TemporaryDirectory(prefix='fallback-partial-') as directory:
        root = Path(directory)
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=health.test', '-addext', 'subjectAltName=DNS:health.test,DNS:confirm.test,DNS:user.test', '-keyout', str(root/'key.pem'), '-out', str(root/'cert.pem')], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        failed = [threading.Event(), threading.Event()]
        confirmation_failed = [threading.Event(), threading.Event()]
        failed[0].set()
        marker = b'verified TLS application response through selected fallback\n' * 64

        class Web(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_HEAD(self):
                self.send_response(204); self.send_header('Content-Length', '0'); self.end_headers()
            def do_GET(self):
                self.send_response(200); self.send_header('Content-Length', str(len(marker))); self.end_headers(); self.wfile.write(marker)

        web = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Web)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(root/'cert.pem', root/'key.pem')
        web.socket = tls.wrap_socket(web.socket, server_side=True)

        class Proxy(socketserver.StreamRequestHandler):
            def handle(self):
                self.connection.settimeout(3)
                request = self.rfile.readline(1024).decode().split()
                if len(request) != 3 or request[0] != 'CONNECT': return
                for _ in range(32):
                    if self.rfile.readline(2048) in (b'\r\n', b''): break
                else: return
                host = request[1].split(':')[0]
                if host not in ('health.test', 'confirm.test', 'user.test'): return
                if (host == 'health.test' and failed[self.server.member].is_set()) or (host == 'confirm.test' and confirmation_failed[self.server.member].is_set()):
                    self.wfile.write(b'HTTP/1.1 503 Unavailable\r\nContent-Length: 0\r\n\r\n'); self.wfile.flush(); return
                with socket.create_connection(web.server_address, 3) as remote:
                    self.wfile.write(b'HTTP/1.1 200 Connection Established\r\n\r\n'); self.wfile.flush()
                    while True:
                        ready, _, _ = select.select([self.connection, remote], [], [], 3)
                        if not ready: return
                        for source in ready:
                            data = source.recv(32768)
                            if not data: return
                            (remote if source is self.connection else self.connection).sendall(data)

        class Server(socketserver.ThreadingTCPServer):
            allow_reuse_address = True
            daemon_threads = True

        servers = [Server(('127.0.0.1', 0), Proxy) for _ in range(2)]
        for i, server in enumerate(servers): server.member = i
        for server in [web, *servers]: threading.Thread(target=server.serve_forever, daemon=True).start()
        api_port, socks_port = free_port(), free_port()
        cfg = {'log': {'level': 'warn', 'timestamp': False}, 'certificate': {'store': 'none', 'certificate_path': [str(root/'cert.pem')]},
               'inbounds': [{'type': 'socks', 'tag': 'in', 'listen': '127.0.0.1', 'listen_port': socks_port}],
               'outbounds': [{'type': 'http', 'tag': tag, 'server': '127.0.0.1', 'server_port': servers[i].server_address[1]} for i, tag in enumerate(['primary', 'backup'])] +
               [{'type': 'fallback', 'tag': 'test', 'outbounds': ['primary', 'backup'], 'stable': True, 'url': 'https://health.test/primary', 'confirm_url': 'https://confirm.test/confirm', 'expected_status': '204', 'confirm_expected_status': '204', 'interval': '100ms', 'idle_timeout': '1m', 'timeout': '300ms', 'attempt_timeout': '300ms', 'failure_retry_interval': '1s', 'recovery_interval': '1s', 'recovery_successes': 3}],
               'route': {'final': 'test'}, 'experimental': {'clash_api': {'external_controller': f'127.0.0.1:{api_port}', 'secret': 'local-fixture-only'}}}
        (root/'config.json').write_text(json.dumps(cfg))
        def state():
            request = urllib.request.Request(f'http://127.0.0.1:{api_port}/proxies/test', headers={'Authorization': 'Bearer local-fixture-only'})
            with urllib.request.urlopen(request, timeout=1) as response: return json.load(response)
        def wait_for(condition, label):
            until = time.monotonic() + 8
            while time.monotonic() < until:
                if process.poll() is not None: raise AssertionError('core exited: '+(root/'core.log').read_text())
                try:
                    if condition(state()): return
                except (OSError, ValueError): pass
                time.sleep(.02)
            raise AssertionError(label + ': ' + (root/'core.log').read_text())
        with (root/'core.log').open('w') as output:
            process = subprocess.Popen([binary, 'run', '-c', str(root/'config.json')], cwd=root, stdout=output, stderr=subprocess.STDOUT)
            try:
                wait_for(lambda s: s['stable']['state'] == 'primary' and s['history'], 'confirmation did not establish healthy primary')
                time.sleep(1.2)
                assert state()['now'] == 'primary', 'partial service failure switched a working tunnel'
                assert 'WARN' not in (root/'core.log').read_text(), 'successful confirmation produced a warning'
                confirmation_failed[0].set()
                wait_for(lambda s: s['now'] == 'backup', 'confirmed full outage did not select healthy backup')
                with socket.create_connection(('127.0.0.1', socks_port), 3) as sock:
                    sock.sendall(b'\x05\x01\x00'); assert sock.recv(2) == b'\x05\x00'
                    sock.sendall(b'\x05\x01\x00\x03\x09user.test\x01\xbb')
                    reply = sock.recv(4); assert reply[:2] == b'\x05\x00', reply
                    remaining = 6 if reply[3] == 1 else 18
                    while remaining:
                        part = sock.recv(remaining); assert part; remaining -= len(part)
                    context = ssl.create_default_context(cafile=str(root/'cert.pem'))
                    with context.wrap_socket(sock, server_hostname='user.test') as stream:
                        stream.sendall(b'GET / HTTP/1.0\r\nHost: user.test\r\n\r\n')
                        data = b''
                        while True:
                            part = stream.recv(8192)
                            if not part: break
                            data += part
                        assert data.split(b'\r\n\r\n', 1)[1] == marker
                failed[1].set()
                confirmation_failed[1].set()
                wait_for(lambda s: s['stable']['state'] == 'degraded', 'shared service outage was hidden')
                assert state()['now'] == 'backup', 'shared outage bounced onto unhealthy primary'
                confirmation_failed[1].clear()
                wait_for(lambda s: s['stable']['state'] == 'backup', 'backup did not recover')
                confirmation_failed[0].clear()
                wait_for(lambda s: s['now'] == 'primary', 'priority did not recover')
                logs = (root/'core.log').read_text()
                assert 'WARN' in logs and 'confirmation=request_failed' in logs and 'fallback switched from primary to backup' in logs, logs
            finally:
                process.terminate()
                with contextlib.suppress(subprocess.TimeoutExpired): process.wait(timeout=5)
                if process.poll() is None: process.kill(); process.wait()
                for server in [*servers, web]: server.shutdown(); server.server_close()
        print('PASS executable TLS/data: confirmation success stays healthy without Warn, full outage failover, shared outage holds backup, priority recovery')


if __name__ == '__main__': main(os.path.abspath(sys.argv[1]))
