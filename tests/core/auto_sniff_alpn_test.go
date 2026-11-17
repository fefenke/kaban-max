package sniff

import (
 "context"
 "crypto/tls"
 "net"
 "reflect"
 "testing"
 "time"
 "github.com/sagernet/sing-box/adapter"
)

func TestTLSClientHelloRetainsOnlyNegotiationMetadata(t *testing.T){
 client,server:=net.Pipe();defer client.Close();defer server.Close()
 ctx,cancel:=context.WithTimeout(context.Background(),time.Second);defer cancel()
 done:=make(chan struct{})
 go func(){defer close(done);conn:=tls.Client(client,&tls.Config{ServerName:"example.test",NextProtos:[]string{"h2","native-app-protocol"}});_ =conn.HandshakeContext(ctx)}()
 var metadata adapter.InboundContext
 if err:=TLSClientHello(ctx,&metadata,server);err!=nil{t.Fatal(err)}
 server.Close();<-done
 if metadata.Domain!="example.test" || metadata.Protocol!="tls" || !reflect.DeepEqual(metadata.SniffedALPN,[]string{"h2","native-app-protocol"}){t.Fatal("incorrect handshake metadata",metadata)}
}
