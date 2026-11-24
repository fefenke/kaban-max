package wireguard

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"net"
	"net/netip"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/control"
	M "github.com/sagernet/sing/common/metadata"
	"github.com/sagernet/wireguard-go/device"
	wgTun "github.com/sagernet/wireguard-go/tun"
	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
)

type recoveryTun struct {
	Device
	events   chan wgTun.Event
	outgoing chan []byte
	incoming chan []byte
	done     chan struct{}
	once     sync.Once
}

func newRecoveryTun() *recoveryTun {
	return &recoveryTun{events: make(chan wgTun.Event, 1), outgoing: make(chan []byte, 8), incoming: make(chan []byte, 8), done: make(chan struct{})}
}
func (d *recoveryTun) Start() error               { d.events <- wgTun.EventUp; return nil }
func (d *recoveryTun) SetDevice(*device.Device)   {}
func (d *recoveryTun) File() *os.File             { return nil }
func (d *recoveryTun) MTU() (int, error)          { return 1280, nil }
func (d *recoveryTun) Name() (string, error)      { return "synthetic", nil }
func (d *recoveryTun) Events() <-chan wgTun.Event { return d.events }
func (d *recoveryTun) BatchSize() int             { return 1 }
func (d *recoveryTun) Close() error               { d.once.Do(func() { close(d.done); close(d.events) }); return nil }
func (d *recoveryTun) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	select {
	case p := <-d.outgoing:
		sizes[0] = copy(bufs[0][offset:], p)
		return 1, nil
	case <-d.done:
		return 0, os.ErrClosed
	}
}
func (d *recoveryTun) Write(bufs [][]byte, offset int) (int, error) {
	for _, p := range bufs {
		select {
		case d.incoming <- bytes.Clone(p[offset:]):
		case <-d.done:
			return 0, os.ErrClosed
		}
	}
	return len(bufs), nil
}

type recoveryDirectDialer struct{}

func (recoveryDirectDialer) UDPListenerControl() (control.Func, bool) { return nil, false }
func (recoveryDirectDialer) DialContext(ctx context.Context, n string, a M.Socksaddr) (net.Conn, error) {
	return (&net.Dialer{}).DialContext(ctx, n, a.String())
}
func (recoveryDirectDialer) ListenPacket(ctx context.Context, a M.Socksaddr) (net.PacketConn, error) {
	return (&net.ListenConfig{}).ListenPacket(ctx, "udp", a.String())
}

func recoveryEndpoint(t *testing.T, private, public wgtypes.Key, peer netip.AddrPort, port uint16, hint ...uint16) (*Endpoint, *recoveryTun) {
	t.Helper()
	tun := newRecoveryTun()
	ipc := "private_key=" + hex.EncodeToString(private[:])
	if port != 0 {
		ipc += fmt.Sprintf("\nlisten_port=%d", port)
	}
	r := option.Range[uint32]{From: 1, To: 1}
	e := &Endpoint{options: EndpointOptions{Context: context.Background(), Logger: log.NewNOPFactory().NewLogger("recovery"), Dialer: recoveryDirectDialer{}, ListenPort: port, Workers: 1, Amnezia: &AmneziaOptions{RekeyTimeout: &r}}, ipcConf: ipc, tunDevice: tun, returnDevice: &returnDeviceWrapper{Device: tun}, peers: []peerConfig{{endpoint: peer, publicKeyHex: hex.EncodeToString(public[:]), allowedIPs: []netip.Prefix{netip.MustParsePrefix("0.0.0.0/0")}}}}
	if len(hint) > 0 {
		e.options.ListenPortHint = hint[0]
	}
	if err := e.Start(false); err != nil {
		t.Fatal(err)
	}
	if err := e.device.Up(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = e.Close() })
	return e, tun
}

func recoveryPort(t *testing.T, e *Endpoint) int {
	t.Helper()
	ipc, err := e.device.IpcGet()
	if err != nil {
		t.Fatal(err)
	}
	for _, line := range strings.Split(ipc, "\n") {
		if strings.HasPrefix(line, "listen_port=") {
			port, _ := strconv.Atoi(strings.TrimPrefix(line, "listen_port="))
			return port
		}
	}
	t.Fatal("missing listen port")
	return 0
}

func recoveryPacket(payload string) []byte {
	p := make([]byte, 28+len(payload))
	p[0] = 0x45
	p[8] = 64
	p[9] = 17
	binary.BigEndian.PutUint16(p[2:4], uint16(len(p)))
	copy(p[12:16], []byte{192, 0, 2, 1})
	copy(p[16:20], []byte{198, 51, 100, 2})
	binary.BigEndian.PutUint16(p[20:22], 12345)
	binary.BigEndian.PutUint16(p[22:24], 443)
	binary.BigEndian.PutUint16(p[24:26], uint16(8+len(payload)))
	var sum uint32
	for i := 0; i < 20; i += 2 {
		sum += uint32(binary.BigEndian.Uint16(p[i : i+2]))
	}
	for sum>>16 != 0 {
		sum = (sum & 0xffff) + (sum >> 16)
	}
	binary.BigEndian.PutUint16(p[10:12], ^uint16(sum))
	copy(p[28:], payload)
	return p
}

func TestDirectSinglePeerRecoversDeadUDPPathAndReceivesContent(t *testing.T) {
	testRecoveryPaths(t, 1, false)
}
func TestWARPColdStartRecoversSeveralDeadUDPPaths(t *testing.T) {
	testRecoveryPaths(t, 3, true)
}
func TestWARPReusesVerifiedUDPPathAfterRestart(t *testing.T) {
	testRecoveryPaths(t, 1, true, true)
}

func TestWARPHandshakeAndKeepalivesDoNotCountAsReceivedIPData(t *testing.T) {
	clientKey, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	serverKey, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	server, _ := recoveryEndpoint(t, serverKey, clientKey.PublicKey(), netip.AddrPort{}, 0)
	address := netip.AddrPortFrom(netip.MustParseAddr("127.0.0.1"), uint16(recoveryPort(t, server)))
	client, _ := recoveryEndpoint(t, clientKey, serverKey.PublicKey(), address, 0)
	var public device.NoisePublicKey
	key := serverKey.PublicKey()
	copy(public[:], key[:])
	peer := client.device.LookupPeer(public)
	if peer == nil {
		t.Fatal("peer missing")
	}
	if err := peer.SendHandshakeInitiation(false); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(3 * time.Second)
	for {
		port, handshake, data, epoch := client.WARPPathStats()
		if port != 0 && handshake != 0 {
			if data != 0 || epoch == 0 {
				t.Fatal("handshake counted as payload")
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("local authenticated handshake missing")
		}
		time.Sleep(10 * time.Millisecond)
	}
	peer.SendKeepalive()
	time.Sleep(50 * time.Millisecond)
	if _, _, data, _ := client.WARPPathStats(); data != 0 {
		t.Fatal("keepalive counted as payload")
	}
	if err := client.device.BindUpdate(); err != nil {
		t.Fatal(err)
	}
	if _, handshake, data, _ := client.WARPPathStats(); handshake != 0 || data != 0 {
		t.Fatal("rebound path inherited old health")
	}
}
func testRecoveryPaths(t *testing.T, deadPaths int, cold bool, restart ...bool) {
	clientKey, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	serverKey, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	server, serverTun := recoveryEndpoint(t, serverKey, clientKey.PublicKey(), netip.AddrPort{}, 0)
	serverAddress := net.UDPAddrFromAddrPort(netip.AddrPortFrom(netip.MustParseAddr("127.0.0.1"), uint16(recoveryPort(t, server))))
	relay, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = relay.Close() })
	changed := make(chan struct{})
	var once sync.Once
	var stablePort atomic.Uint32
	go func() {
		buf := make([]byte, 65536)
		blockedPorts := map[int]bool{}
		var client *net.UDPAddr
		for {
			n, from, err := relay.ReadFromUDP(buf)
			if err != nil {
				return
			}
			if from.Port == serverAddress.Port {
				if client != nil {
					_, _ = relay.WriteToUDP(buf[:n], client)
				}
				continue
			}
			if stable := stablePort.Load(); stable != 0 && uint32(from.Port) != stable {
				continue
			}
			if !blockedPorts[from.Port] && len(blockedPorts) < deadPaths {
				blockedPorts[from.Port] = true
			}
			if blockedPorts[from.Port] {
				continue
			}
			client = from
			once.Do(func() { close(changed) })
			_, _ = relay.WriteToUDP(buf[:n], serverAddress)
		}
	}()
	client, clientTun := recoveryEndpoint(t, clientKey, serverKey.PublicKey(), relay.LocalAddr().(*net.UDPAddr).AddrPort(), 0)
	client.device.SetColdStartRecovery(cold)
	var pub device.NoisePublicKey
	public := serverKey.PublicKey()
	copy(pub[:], public[:])
	peer := client.device.LookupPeer(pub)
	if peer == nil {
		t.Fatal("peer missing")
	}
	if err := peer.SendHandshakeInitiation(false); err != nil {
		t.Fatal(err)
	}
	select {
	case <-changed:
	case <-time.After(10 * time.Second):
		t.Fatal("unanswered handshakes kept the same dead UDP source port")
	}
	marker := "verified encrypted content after fresh UDP path"
	clientTun.outgoing <- recoveryPacket(marker)
	select {
	case packet := <-serverTun.incoming:
		if !bytes.Contains(packet, []byte(marker)) {
			t.Fatal("wrong decrypted content")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("new UDP path did not deliver authenticated content")
	}
	reply := recoveryPacket(marker + " reply")
	left := bytes.Clone(reply[12:16])
	copy(reply[12:16], reply[16:20])
	copy(reply[16:20], left)
	reply[20], reply[22] = reply[22], reply[20]
	reply[21], reply[23] = reply[23], reply[21]
	serverTun.outgoing <- reply
	select {
	case packet := <-clientTun.incoming:
		if !bytes.Contains(packet, []byte(marker+" reply")) {
			t.Fatal("wrong decrypted reply")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("recovered path did not return authenticated content")
	}
	if len(restart) > 0 && restart[0] {
		port := client.LastHandshakePort()
		pathPort, handshakeAt, dataAt, epoch := client.WARPPathStats()
		if pathPort != port || handshakeAt == 0 || dataAt == 0 || epoch == 0 {
			t.Fatalf("received encrypted IP payload missing from path status: port=%d handshake=%d data=%d epoch=%d", pathPort, handshakeAt, dataAt, epoch)
		}
		if port == 0 || int(port) != recoveryPort(t, client) {
			t.Fatal("no authenticated path remembered")
		}
		stablePort.Store(uint32(port))
		_ = client.Close()
		next, nextTun := recoveryEndpoint(t, clientKey, serverKey.PublicKey(), relay.LocalAddr().(*net.UDPAddr).AddrPort(), 0, port)
		if recoveryPort(t, next) != int(port) {
			t.Fatal("restart discarded the verified port hint")
		}
		nextTun.outgoing <- recoveryPacket(marker + " restart")
		select {
		case packet := <-serverTun.incoming:
			if !bytes.Contains(packet, []byte(marker+" restart")) {
				t.Fatal("wrong restart content")
			}
		case <-time.After(5 * time.Second):
			t.Fatal("restart did not preserve authenticated transport")
		}
	}
}

func TestWARPPortHintFallsBackWhenBusy(t *testing.T) {
	key, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	peer, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	occupied, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4zero})
	if err != nil {
		t.Fatal(err)
	}
	defer occupied.Close()
	port := uint16(occupied.LocalAddr().(*net.UDPAddr).Port)
	client, _ := recoveryEndpoint(t, key, peer.PublicKey(), occupied.LocalAddr().(*net.UDPAddr).AddrPort(), 0, port)
	if recoveryPort(t, client) == int(port) {
		t.Fatal("soft hint stole an occupied port")
	}
}

func TestDirectSinglePeerRecoveryPreservesPinnedPort(t *testing.T) {
	private, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	server, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	sink, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer sink.Close()
	reserved, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	port := uint16(reserved.LocalAddr().(*net.UDPAddr).Port)
	_ = reserved.Close()
	client, _ := recoveryEndpoint(t, private, server.PublicKey(), sink.LocalAddr().(*net.UDPAddr).AddrPort(), port)
	client.device.SetColdStartRecovery(true)
	var public device.NoisePublicKey
	key := server.PublicKey()
	copy(public[:], key[:])
	if err := client.device.LookupPeer(public).SendHandshakeInitiation(false); err != nil {
		t.Fatal(err)
	}
	_ = sink.SetReadDeadline(time.Now().Add(6 * time.Second))
	buf := make([]byte, 2048)
	attempts := 0
	for {
		_, from, err := sink.ReadFromUDP(buf)
		if err != nil {
			if e, ok := err.(net.Error); ok && e.Timeout() {
				break
			}
			t.Fatal(err)
		}
		attempts++
		if from.Port != int(port) {
			t.Fatal("recovery changed an explicitly pinned listen_port")
		}
	}
	if attempts < 4 || recoveryPort(t, client) != int(port) {
		t.Fatal("pinned-port retry path was not exercised", attempts)
	}
}

func TestWARPColdStartRetainsBackoffAfterThreeRotations(t *testing.T) {
	private, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	server, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	sink, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer sink.Close()
	client, _ := recoveryEndpoint(t, private, server.PublicKey(), sink.LocalAddr().(*net.UDPAddr).AddrPort(), 0)
	client.device.SetColdStartRecovery(true)
	var public device.NoisePublicKey
	key := server.PublicKey()
	copy(public[:], key[:])
	if err := client.device.LookupPeer(public).SendHandshakeInitiation(false); err != nil {
		t.Fatal(err)
	}
	_ = sink.SetReadDeadline(time.Now().Add(7 * time.Second))
	ports := map[int]bool{}
	buffer := make([]byte, 2048)
	for {
		_, from, err := sink.ReadFromUDP(buffer)
		if err != nil {
			break
		}
		ports[from.Port] = true
	}
	if len(ports) < 2 || len(ports) > 4 {
		t.Fatalf("unbounded or absent cold recovery: %d source ports", len(ports))
	}
	if client.LastHandshakePort() != 0 {
		t.Fatal("unanswered port was remembered as successful")
	}
}
