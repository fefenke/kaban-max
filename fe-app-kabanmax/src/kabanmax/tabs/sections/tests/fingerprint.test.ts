import { describe, expect, it } from 'vitest';
import { connectionFingerprintSupported } from '../../../services/coreFeatures.service';

describe('connection fingerprint capability', () => {
  it('rejects TLS 1.2-only profiles for REALITY while preserving other profiles', () => {
    const uri = 'vless://u@a:443?security=reality';
    expect(connectionFingerprintSupported(uri, 'android')).toBe(false);
    expect(connectionFingerprintSupported(uri, '360')).toBe(false);
    for (const fingerprint of [
      'chrome',
      'chrome_155',
      'firefox',
      'edge',
      'ios',
      'safari',
      'random',
    ]) {
      expect(connectionFingerprintSupported(uri, fingerprint)).toBe(true);
    }
    expect(
      connectionFingerprintSupported('vless://u@a:443?security=tls', 'android'),
    ).toBe(true);
  });
  it('requires an existing TCP TLS connection', () => {
    for (const uri of [
      'vless://u@a:443?security=tls',
      'trojan://p@a:443',
      'anytls://p@a:443',
      'https://a:443',
    ]) {
      expect(connectionFingerprintSupported(uri)).toBe(true);
    }
    for (const uri of [
      'vless://u@a:443',
      'socks://a:1080',
      'http://a:80?security=tls',
      'trojan://p@a:443?security=none',
      'vless://u@a:443?pbk=key',
      'tuic://u:p@a:443',
      'hy2://p@a:443',
      'vless://u@a:443?security=tls&type=xhttp&alpn=h3',
    ]) {
      expect(connectionFingerprintSupported(uri)).toBe(false);
    }
  });
  it('reads VMess TLS from its structured payload and rejects QUIC', () => {
    const uri = (net: string) =>
      `vmess://${btoa(JSON.stringify({ add: 'a.example', port: '443', tls: 'tls', net }))}`;
    expect(connectionFingerprintSupported(uri('tcp'))).toBe(true);
    expect(connectionFingerprintSupported(uri('quic'))).toBe(false);
  });
});
