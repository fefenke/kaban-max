import { describe, expect, it } from 'vitest';
import {
  parseConnectionUri,
  serializeConnectionUri,
  exportConnectionUri,
} from '../connectionUri';

const uri =
  'vless://test-id@[2001:db8::1]:443?security=reality&sni=old.example&fp=firefox&type=ws&host=cdn.example&path=%2Fa%3Fed%3D2048&pbk=test-key&sid=abcd&X-unknown=a%20b&X-unknown=%26#%D0%9F%D0%BE%D0%BB%D1%8C%D1%88%D0%B0';

describe('lossless connection fields', () => {
  it('reads VLESS REALITY and keeps the original bytes without edits', () => {
    const draft = parseConnectionUri(uri);
    expect(draft).toMatchObject({
      supported: true,
      protocol: 'vless',
      server: '2001:db8::1',
      port: '443',
      credential: 'test-id',
      security: 'reality',
      sni: 'old.example',
      transport: 'ws',
      path: '/a?ed=2048',
      publicKey: 'test-key',
      shortId: 'abcd',
      fingerprint: 'firefox',
    });
    expect(serializeConnectionUri(uri, draft)).toBe(uri);
  });
  it('changes only requested components and preserves unknown parameters and fragment', () => {
    const draft = {
      ...parseConnectionUri(uri),
      server: 'proxy.example',
      port: '8443',
      sni: 'новый.example',
      path: '/# &%',
      credential: 'id#&%',
    };
    const result = serializeConnectionUri(uri, draft);
    expect(parseConnectionUri(result)).toMatchObject({
      server: 'proxy.example',
      port: '8443',
      sni: 'новый.example',
      path: '/# &%',
      credential: 'id#&%',
    });
    expect(result).toContain('&X-unknown=a%20b&X-unknown=%26');
    expect(result.split('#')[1]).toBe(uri.split('#')[1]);
  });
  it('exports effective fingerprint and name without mutating storage', () => {
    const result = exportConnectionUri(uri, 'chrome_155', 'Warsaw #1');
    expect(parseConnectionUri(result).fingerprint).toBe('chrome_155');
    expect(result).not.toContain('fp=firefox');
    expect(result).toContain('#Warsaw%20%231');
    expect(uri).toContain('fp=firefox');
  });
  it('reads case-insensitive aliases and changes them without competing values', () => {
    const source =
      'vless://id@a.example:443?Security=tls&SERVERNAME=old&client-fingerprint=firefox&net=grpc&grpc-service-name=svc&unknown=%2f#Keep';
    const result = serializeConnectionUri(source, {
      ...parseConnectionUri(source),
      sni: 'new',
      serviceName: 'next',
      fingerprint: 'chrome_155',
    });
    expect(parseConnectionUri(result)).toMatchObject({
      sni: 'new',
      serviceName: 'next',
      fingerprint: 'chrome_155',
      transport: 'grpc',
    });
    expect(result).toContain('unknown=%2f');
    expect(result).not.toContain('SERVERNAME=');
  });
  it('removes REALITY key aliases when explicitly switching security to plain TLS', () => {
    const source = uri + '';
    const result = serializeConnectionUri(source, {
      ...parseConnectionUri(source),
      security: 'tls',
    });
    expect(parseConnectionUri(result)).toMatchObject({
      security: 'tls',
      publicKey: '',
      shortId: '',
    });
    expect(result).not.toContain('pbk=');
  });
  it('does not infer REALITY from public-key alias unless security explicitly enables it', () => {
    expect(
      parseConnectionUri('vless://id@a.example:443?security=tls&public-key=key')
        .security,
    ).toBe('tls');
  });
  it('refuses Vision over WebSocket without VLESS encryption', () => {
    expect(() =>
      serializeConnectionUri(uri, {
        ...parseConnectionUri(uri),
        flow: 'xtls-rprx-vision',
      }),
    ).toThrow('VLESS Vision requires raw TCP with TLS or VLESS encryption');
  });
  it.each(['', '0', '65536', 'abc', '-1'])(
    'rejects invalid VLESS port %s without echoing credentials',
    (port) => {
      expect(() =>
        serializeConnectionUri(uri, { ...parseConnectionUri(uri), port }),
      ).toThrow('Port must be between 1 and 65535');
    },
  );
  it.each(['bad/name', 'name with space', 'name#secret', 'name:443'])(
    'rejects invalid server %s',
    (server) => {
      expect(() =>
        serializeConnectionUri(uri, { ...parseConnectionUri(uri), server }),
      ).toThrow('Invalid server address');
    },
  );
  it.each([
    'trojan://p%23%26%25@t.example:443?security=tls&type=grpc&serviceName=svc#T',
    'anytls://pass@a.example:443?sni=t.example#A',
    'socks5://user:pass@s.example:1080#S',
    'https://user:pass@h.example:443#H',
  ])(
    'round trips and edits a supported authority without losing data',
    (source) => {
      const draft = parseConnectionUri(source);
      expect(draft.supported).toBe(true);
      expect(serializeConnectionUri(source, draft)).toBe(source);
      expect(
        parseConnectionUri(
          serializeConnectionUri(source, { ...draft, port: '8443' }),
        ).port,
      ).toBe('8443');
    },
  );
  it.each([
    'vmess://eyJ2IjoiMiIsInBzIjoiTm9kZSIsImFkZCI6ImEuZXhhbXBsZSIsInBvcnQiOiI0NDMiLCJ1bmtub3duIjoiS2VlcCJ9',
    'vmess://{"ps":"raw","unknown":"keep"}',
    'ss://c2VjcmV0@a.example:443#SS',
    'tt://opaque-payload',
    'vless://id@a.example:443?type=future#Keep',
    'socks://dXNlcjpwYXNz@a.example:1080#Base64',
  ])(
    'uses raw mode for formats whose fields cannot be represented safely',
    (source) => {
      expect(parseConnectionUri(source).supported).toBe(false);
      expect(serializeConnectionUri(source, parseConnectionUri(source))).toBe(
        source,
      );
    },
  );
});
