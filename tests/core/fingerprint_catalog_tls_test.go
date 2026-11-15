// Copied into common/tls of pinned UPSTREAM+patches by run_fingerprints.sh.
package tls

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	stdtls "crypto/tls"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"math/big"
	"net"
	"os"
	"slices"
	"testing"
	"time"
)

func TestApplicationFingerprintCatalog(t *testing.T) {
	data, err := os.ReadFile(os.Getenv("KABANMAX_FINGERPRINT_CATALOG"))
	if err != nil {
		t.Fatal(err)
	}
	var profiles []struct{ ID, Client, Version, Reality, AliasOf string }
	if err = json.Unmarshal(data, &profiles); err != nil {
		t.Fatal(err)
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(1), DNSNames: []string{"example.org"}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	for _, profile := range profiles {
		t.Run(profile.ID, func(t *testing.T) {
			id, err := uTLSClientHelloID(profile.ID)
			if err != nil {
				t.Fatal(err)
			}
			if profile.Client != "" && (id.Client != profile.Client || id.Version != profile.Version) {
				t.Fatalf("catalog differs from runtime: %s %s", id.Client, id.Version)
			}
			if profile.AliasOf != "" {
				canonical, err := uTLSClientHelloID(profile.AliasOf)
				if err != nil || id != canonical {
					t.Fatal("alias is a different ClientHello")
				}
			}
			hello := buildClientHello(t, profile.ID)
			if len(hello.HandshakeState.Hello.Raw) == 0 {
				t.Fatal("missing ClientHello")
			}
			if profile.ID == "random" {
				again, _ := uTLSClientHelloID("random")
				if again != id || !slices.Contains([]string{"Chrome", "Firefox", "Safari"}, id.Client) {
					t.Fatal("random did not keep its process-wide browser choice")
				}
			}
			if profile.ID == "randomized" {
				again, _ := uTLSClientHelloID("randomized")
				if id.Seed == nil || again.Seed != id.Seed || !slices.Contains(hello.HandshakeState.Hello.AlpnProtocols, "h2") {
					t.Fatal("randomized seed or ALPN differs from contract")
				}
			}
			logger, _ := newWarnLogger(t)
			_, err = NewClient(context.Background(), logger, "example.org", realityOptionsForTest(profile.ID, true))
			if (err != nil) != (profile.Reality == "unsupported") {
				t.Fatalf("REALITY compatibility differs from catalog: %v", err)
			}
			options := realityOptionsForTest(profile.ID, false)
			options.Certificate = []string{string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}))}
			config, err := NewClient(context.Background(), logger, "example.org", options)
			if err != nil {
				t.Fatal(err)
			}
			client, server := net.Pipe()
			defer client.Close()
			defer server.Close()
			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			defer cancel()
			done := make(chan error, 1)
			go func() {
				done <- stdtls.Server(server, &stdtls.Config{SessionTicketsDisabled: true, Certificates: []stdtls.Certificate{{Certificate: [][]byte{der}, PrivateKey: key}}}).HandshakeContext(ctx)
			}()
			conn, err := config.Client(client)
			if err != nil {
				t.Fatal(err)
			}
			if err = conn.HandshakeContext(ctx); err != nil {
				t.Fatal(err)
			}
			if err = <-done; err != nil {
				t.Fatal(err)
			}
		})
	}
}
