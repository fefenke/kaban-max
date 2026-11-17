package ja3

import (
 "encoding/binary"
 "reflect"
 "testing"
)

func TestQUICClientHelloALPNIsBoundedAndValidated(t *testing.T) {
 var names []byte
 for _,name:=range []string{"h3","native-app-protocol"} {names=append(names,byte(len(name)));names=append(names,name...)}
 list:=binary.BigEndian.AppendUint16(nil,uint16(len(names)));list=append(list,names...)
 extension:=[]byte{0,16};extension=binary.BigEndian.AppendUint16(extension,uint16(len(list)));extension=append(extension,list...)
 hello:=binary.BigEndian.AppendUint16(nil,uint16(len(extension)));hello=append(hello,extension...)
 var parsed ClientHello
 if err:=parsed.parseExtensions(hello);err!=nil{t.Fatal(err)}
 if !reflect.DeepEqual(parsed.ALPN,[]string{"h3","native-app-protocol"}){t.Fatal("lost original ALPN",parsed.ALPN)}
 for _,bad:=range [][]byte{{0,7,0,16,0,3,0,1,0},{0,7,0,16,0,3,0,2,1}} {
  var invalid ClientHello
  if invalid.parseExtensions(bad)==nil{t.Fatal("accepted malformed ALPN",bad)}
 }
}
