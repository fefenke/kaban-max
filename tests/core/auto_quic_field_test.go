//go:build with_quic

package autoroute

import (
 "context"
 "crypto/tls"
 "crypto/x509"
 "errors"
 "net"
 "net/http"
 "net/http/httptest"
 "sync/atomic"
 "testing"

 "github.com/sagernet/quic-go/http3"
 "github.com/sagernet/quic-go"
 "time"
 "github.com/sagernet/sing-box/adapter"
 "github.com/sagernet/sing/service"
 M "github.com/sagernet/sing/common/metadata"
)

type fieldPacketOutbound struct {
 adapter.Outbound
 peer net.Addr
 packets atomic.Int32
}
func(o *fieldPacketOutbound) DialContext(ctx context.Context,network string,d M.Socksaddr)(net.Conn,error){
 if network!="udp" {return o.Outbound.DialContext(ctx,network,d)}
 o.packets.Add(1)
 return (&net.Dialer{}).DialContext(ctx,"udp",o.peer.String())
}
type fieldPacketConn struct {net.PacketConn; peer, requested net.Addr}
func(c *fieldPacketConn) WriteTo(p []byte,_ net.Addr)(int,error){return c.PacketConn.WriteTo(p,c.peer)}
func(c *fieldPacketConn) ReadFrom(p []byte)(int,net.Addr,error){n,_,e:=c.PacketConn.ReadFrom(p);return n,c.requested,e}
func(o *fieldPacketOutbound) ListenPacket(ctx context.Context,d M.Socksaddr)(net.PacketConn,error){
 o.packets.Add(1)
 socket,e:=net.ListenPacket("udp","127.0.0.1:0");if e!=nil{return nil,e}
 return &fieldPacketConn{PacketConn:socket,peer:o.peer,requested:&net.UDPAddr{IP:net.IP(d.Addr.AsSlice()),Port:int(d.Port)}},nil
}

func TestUDPAlternativeRequiresRealHTTP3AndAutoApplies(t *testing.T){
 m,q,_,direct:=webManager(t,204,"")
 cert:=httptest.NewTLSServer(http.HandlerFunc(func(http.ResponseWriter,*http.Request){}));defer cert.Close()
 socket,e:=net.ListenPacket("udp","127.0.0.1:0");if e!=nil{t.Fatal(e)}
 server:=&http3.Server{TLSConfig:&tls.Config{Certificates:cert.TLS.Certificates},Handler:http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){
  if r.ProtoMajor!=3 || r.Host!="example.com:443"{t.Error("not pinned application HTTP3",r.Proto,r.Host)}
  w.WriteHeader(204)
 })}
 go server.Serve(socket)
 defer server.Close()
 packetOut:=&fieldPacketOutbound{Outbound:direct,peer:socket.LocalAddr()}
 original:=m.Outbound
 m.Outbound=func(tag string)(adapter.Outbound,bool){if tag=="direct-out"{return packetOut,true};return original(tag)}
 m.events=map[string]*Event{}
 meta:=metadata(q);meta.Network="udp";event:=m.Observe(&meta,q.Source);m.Failed(event,errors.New("logged UDP timeout"))
 s:=m.sources[q.Source];s.AutoApply=true;m.sources[q.Source]=s
 m.Sweep(context.Background())
 if len(m.leases)!=1 || packetOut.packets.Load()!=2 || direct.calls.Load()!=0 {t.Fatalf("UDP used TCP proof or failed HTTP3: leases=%d UDP=%d TCP=%d state=%+v",len(m.leases),packetOut.packets.Load(),direct.calls.Load(),m.State())}
}

func TestNativeQUICALPNChecksAuthenticatedPacketsWithoutHTTP3(t *testing.T){
 m,q,_,direct:=webManager(t,200,normalPage)
 cert:=httptest.NewTLSServer(http.HandlerFunc(func(http.ResponseWriter,*http.Request){}));defer cert.Close()
 socket,err:=net.ListenPacket("udp","127.0.0.1:0");if err!=nil{t.Fatal(err)};defer socket.Close()
 listener,err:=quic.Listen(socket,&tls.Config{Certificates:cert.TLS.Certificates,NextProtos:[]string{"native-test-protocol"}},&quic.Config{MaxIdleTimeout:2*time.Second});if err!=nil{t.Fatal(err)};defer listener.Close()
 serverCtx,cancel:=context.WithCancel(context.Background());defer cancel()
 go func(){for {conn,e:=listener.Accept(serverCtx);if e!=nil{return};context.AfterFunc(serverCtx,func(){conn.CloseWithError(0,"")})}}()
 out:=&fieldPacketOutbound{Outbound:direct,peer:socket.LocalAddr()};original:=m.Outbound
 m.Outbound=func(tag string)(adapter.Outbound,bool){if tag=="direct-out"{return out,true};return original(tag)}
 m.events=map[string]*Event{};meta:=metadata(q);meta.Network="udp";meta.Protocol="quic";meta.SniffedALPN=[]string{"native-test-protocol"};meta.QUICVersion=uint32(quic.Version1)
 event:=m.Observe(&meta,q.Source);m.Failed(event,errors.New("logged native QUIC error"))
 answer,e:=m.Probe(context.Background(),event.Query);if e!=nil{t.Fatal(e)};decision:=answer.(Decision)
 if decision.Status!="proposed" || out.packets.Load()!=2 || direct.calls.Load()!=0{t.Fatalf("native QUIC was replaced with an HTTP request: %+v",answer)}
 for _,attempt:=range decision.Attempts {if !attempt.TLSVerified || attempt.TransportBytes==0 || attempt.NegotiatedProtocol!="native-test-protocol" || attempt.HTTPStatus!=0{t.Fatal("no authenticated native QUIC evidence",attempt)}}
 m.ctx=service.ContextWith[adapter.CertificateStore](m.ctx,&testRoots{pool:x509.NewCertPool()})
 m.cooldown=map[string]time.Time{}
 untrusted,err:=m.Probe(context.Background(),event.Query);if err!=nil{t.Fatal(err)}
 if untrusted.(Decision).Status=="proposed"||len(m.leases)!=0{t.Fatal("untrusted QUIC certificate accepted",untrusted)}

}
