import { describe, expect, it } from 'vitest';
import { validateRealityTlsOption } from '../tlsOptions';

describe('independent TLS options', () => {
  it('allows either flag on a VLESS REALITY connection', () => {
    expect(
      validateRealityTlsOption('vless://id@host:443?security=reality', '1'),
    ).toBe(true);
    expect(
      validateRealityTlsOption(
        'VLESS://id@host:443?security=REALITY&type=tcp',
        '1',
      ),
    ).toBe(true);
  });
  it('allows a disabled flag for other connection types', () => {
    expect(validateRealityTlsOption('trojan://host?security=tls', '0')).toBe(
      true,
    );
  });
  it('rejects enabled flags without VLESS and REALITY', () => {
    for (const uri of [
      'vless://host?security=tls',
      'trojan://host?security=reality',
      'vless://host?security=reality-extra',
      'vless://host',
    ]) {
      expect(validateRealityTlsOption(uri, '1')).not.toBe(true);
    }
  });
});
