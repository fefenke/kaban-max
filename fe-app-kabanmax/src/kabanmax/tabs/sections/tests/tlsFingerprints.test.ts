import { describe, expect, it } from 'vitest';
import {
  TLS_FINGERPRINTS,
  selectableFingerprints,
  fingerprintProfile,
  fingerprintSelectionDefaults,
  selectedFingerprint,
} from '../../../services/tlsFingerprints';
import { connectionFingerprintSupported } from '../../../services/coreFeatures.service';
import { parseConnectionUri, exportConnectionUri } from '../connectionUri';

describe('shared TLS fingerprint catalog', () => {
  it('offers real profiles without legacy Chrome aliases', () => {
    expect(selectableFingerprints.map((p) => p.id)).toEqual([
      'chrome',
      'chrome_155',
      'firefox',
      'edge',
      'safari',
      'ios',
      'android',
      'random',
      'randomized',
      'qq',
      '360',
    ]);
    expect(fingerprintProfile('chrome')?.version).toBe('133');
    expect(fingerprintProfile('chrome_155')?.version).toBe('155');
  });
  it('selects Chrome versions and preserves old aliases without rewriting', () => {
    expect(selectedFingerprint('chrome', 'chrome')).toBe('chrome');
    expect(selectedFingerprint('chrome', 'chrome_155')).toBe('chrome_155');
    expect(selectedFingerprint('', 'chrome_155')).toBe('');
    for (const profile of TLS_FINGERPRINTS.filter((p) => p.aliasOf)) {
      expect(fingerprintSelectionDefaults(profile.id)._tls_variant).toBe(
        'chrome',
      );
      expect(selectedFingerprint('chrome', 'chrome', profile.id)).toBe(
        profile.id,
      );
    }
  });
  it.each(selectableFingerprints)(
    'exports effective $id and validates REALITY restrictions',
    (profile) => {
      const source =
        'vless://id@a.example:443?security=tls&fp=chrome&unknown=%23#Node';
      const exported = exportConnectionUri(source, profile.id);
      expect(parseConnectionUri(exported).fingerprint).toBe(profile.id);
      expect(exported).toContain('unknown=%23');
      expect(connectionFingerprintSupported(source, profile.id)).toBe(true);
      expect(
        connectionFingerprintSupported(
          source.replace('security=tls', 'security=reality'),
          profile.id,
        ),
      ).toBe(profile.reality !== 'unsupported');
    },
  );
});
