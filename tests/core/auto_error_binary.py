"""Error-first acceptance of the real core; isolated --network none + NET_ADMIN only."""
import contextlib
import http.server
import json
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
import urllib.request

BINARY,FIXTURES,TOOLS=sys.argv[1:]
IP='203.0.113.7'
NFT=['nft'] if TOOLS=='system' else [TOOLS+'/musl','--library-path',TOOLS+'/libs',TOOLS+'/nft']

def exact(sock,size):
    data=b''
    while len(data)<size:
        chunk=sock.recv(size-len(data))
        if not chunk:raise EOFError()
        data+=chunk
    return data

def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1',0));return sock.getsockname()[1]

class DNS(socketserver.BaseRequestHandler):
    def handle(self):
        packet=exact(self.request,struct.unpack('!H',exact(self.request,2))[0])
        pos=12
        while packet[pos]:pos+=1+packet[pos]
        pos+=1
        kind=struct.unpack('!H',packet[pos:pos+2])[0]
        question=packet[12:pos+4]
        answer=b'\xc0\x0c'+struct.pack('!HHIH',1,1,30,4)+socket.inet_aton(IP) if kind==1 else b''
        if kind==28:
            answer=b'\xc0\x0c'+struct.pack('!HHIH',28,1,30,16)+socket.inet_pton(socket.AF_INET6,'2001:db8::7')
        response=packet[:2]+struct.pack('!HHHHH',0x8180,1,bool(answer),0,0)+question+answer
        self.request.sendall(struct.pack('!H',len(response))+response)

class Page(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body=b'<html><body>Verified synthetic application content.</body></html>'
        self.send_response(200);self.send_header('Content-Type','text/html');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    def log_message(self,*args):pass

def api(port,op=None,**args):
    request=urllib.request.Request(f'http://127.0.0.1:{port}/kabanmax/auto',
        data=json.dumps({'op':op,**args}).encode() if op else None,
        headers={'Authorization':'Bearer synthetic-only','Content-Type':'application/json'})
    with urllib.request.urlopen(request,timeout=15) as response:return json.load(response)

def fetch(socks_port,domain,port,ip_only=False):
    with socket.create_connection(('127.0.0.1',socks_port),timeout=3) as conn:
        conn.sendall(b'\5\1\0');assert exact(conn,2)==b'\5\0'
        dest=b'\1'+socket.inet_aton(IP) if ip_only else b'\3'+bytes([len(domain)])+domain.encode()
        conn.sendall(b'\5\1\0'+dest+struct.pack('!H',port))
        head=exact(conn,4)
        if head[1]!=0:raise ConnectionError('synthetic refused route')
        exact(conn,6 if head[3]==1 else 18)
        ctx=ssl.create_default_context(cafile=FIXTURES+'/cert.pem')
        with ctx.wrap_socket(conn,server_hostname=domain) as secure:
            secure.sendall(f'GET / HTTP/1.0\r\nHost: {domain}\r\n\r\n'.encode())
            data=b''
            while chunk:=secure.recv(4096):data+=chunk
            return data

def fail_request(socks,domain,port,ip_only=False):
    try:fetch(socks,domain,port,ip_only)
    except (OSError,EOFError):return
    raise AssertionError('expected original connection failure')

@contextlib.contextmanager
def running(config):
    with tempfile.TemporaryDirectory() as directory,tempfile.TemporaryFile() as log:
        path=directory+'/config.json'
        with open(path,'w') as output:json.dump(config,output)
        subprocess.run([BINARY,'check','-c',path],check=True,capture_output=True)
        proc=subprocess.Popen([BINARY,'run','-c',path],stdout=log,stderr=log)
        try:
            time.sleep(.35);assert proc.poll() is None
            yield log
        finally:
            proc.send_signal(signal.SIGTERM);proc.wait(timeout=10)
            assert proc.returncode==0

def wait_state(api_port,predicate,seconds=12):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        state=api(api_port)
        if predicate(state):return state
        time.sleep(.1)
    raise AssertionError('state did not reach expected condition: '+json.dumps(state))

subprocess.run(['ip','addr','add',IP+'/32','dev','lo'],check=True)
dns=socketserver.ThreadingTCPServer(('127.0.0.1',0),DNS);dns.daemon_threads=True
threading.Thread(target=dns.serve_forever,daemon=True).start()
server=http.server.ThreadingHTTPServer((IP,0),Page);server.daemon_threads=True
tls=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);tls.load_cert_chain(FIXTURES+'/cert.pem',FIXTURES+'/key.pem')
server.socket=tls.wrap_socket(server.socket,server_side=True)
threading.Thread(target=server.serve_forever,daemon=True).start()
port=server.server_port;refused=free_port()
rules=('add table ip kabanmax_auto_error_test\n'
       'add chain ip kabanmax_auto_error_test out { type nat hook output priority -100; policy accept; }\n'
       f'add rule ip kabanmax_auto_error_test out meta mark 0x02000001 ip daddr {IP} tcp dport {port} redirect to :{refused}\n'
       f'add rule ip kabanmax_auto_error_test out meta mark 0x02000002 ip daddr {IP} tcp dport {port} redirect to :{refused}\n')
subprocess.run(NFT+['-f','-'],input=rules.encode(),check=True)
try:
    def config(auto_apply=False,logging=True,healthy=False,ip_only=False):
        api_port,socks=free_port(),free_port();mark=0x02000003 if healthy else 0x02000001
        source={'id':'meta','outbound':'zap','mark':mark,'probe_zapret':True,'direct':True,'auto_apply':auto_apply,'allow_ip_only':ip_only,'mode':'web','path':'/','port':port,'status':200}
        rules=[{'action':'resolve','server':'dns-server'},
            {'domain':['two.example.test'],'action':'route','outbound':'warp'},
            {'domain':['one.example.test'],'action':'route','outbound':'zap'}]
        if ip_only:rules.append({'ip_cidr':[IP+'/32'],'action':'route','outbound':'zap'})
        value={'log':{'disabled':not logging,'level':'error','timestamp':False},
            'certificate':{'store':'none','certificate_path':[FIXTURES+'/cert.pem']},
            'inbounds':[{'type':'socks','tag':'tproxy-in','listen':'127.0.0.1','listen_port':socks}],
            'outbounds':[{'type':'direct','tag':'zap','routing_mark':mark},{'type':'direct','tag':'warp','routing_mark':0x02000002},{'type':'direct','tag':'direct-out'}],
            'dns':{'servers':[{'type':'tcp','tag':'dns-server','server':'127.0.0.1','server_port':dns.server_address[1]}]},
            'route':{'rules':rules,'final':'direct-out','default_domain_resolver':'dns-server','kabanmax_auto':[source]},
            'experimental':{'clash_api':{'external_controller':f'127.0.0.1:{api_port}','secret':'synthetic-only'}}}
        return value,api_port,socks
    value,api_port,socks=config()
    with running(value) as log:
        fail_request(socks,'two.example.test',port);time.sleep(.2)
        assert not api(api_port)['candidates'],'foreign WARP error was attributed to META'
        fail_request(socks,'one.example.test',port)
        state=wait_state(api_port,lambda s:len(s['candidates'])==1)
        row=state['candidates'][0]
        assert row['source_id']=='meta' and row['domain']=='one.example.test' and row['failure']['id']==row['id']
        assert row['ip']==IP,'failed mixed A/AAAA connection lost its actual IP'
        log.flush();log.seek(0);text=log.read().decode();assert row['id'] in text and 'outbound=zap' in text,'candidate has no matching error log'
        api(api_port,'registry_dismiss',source_id='meta',id=row['id'])
        assert not api(api_port)['candidates'] and not api(api_port)['leases'],'dismiss retained records or created a route'
    print('PASS executable: logged META error only, WARP excluded, dismiss without permissions',flush=True)
    value,api_port,socks=config(logging=False)
    with running(value):
        fail_request(socks,'one.example.test',port);time.sleep(.2)
        assert not api(api_port)['candidates'],'disabled logging admitted an unlogged error'
    value,api_port,socks=config(healthy=True)
    with running(value):
        assert b'Verified synthetic' in fetch(socks,'one.example.test',port)
        assert not api(api_port)['candidates'],'healthy connection observed as an error'
    print('PASS executable: no logging or no failure means no candidate',flush=True)
    value,api_port,socks=config(auto_apply=True)
    with running(value):
        fail_request(socks,'one.example.test',port)
        state=wait_state(api_port,lambda s:len(s['leases'])==1)
        assert state['leases'][0]['failure']['source_id']=='meta' and state['leases'][0]['target']=='direct-out'
        assert b'Verified synthetic' in fetch(socks,'one.example.test',port),'automatic lease did not route application data'
        fail_request(socks,'two.example.test',port)
        assert all(row['domain']!='two.example.test' for row in api(api_port)['candidates'])
    print('PASS executable: mixed A/AAAA logged error -> actual IP -> verification -> automatic Direct -> received content; WARP remains owned',flush=True)
finally:
    server.shutdown();server.server_close();dns.shutdown();dns.server_close()
    subprocess.run(NFT+['delete','table','ip','kabanmax_auto_error_test'],check=False)
