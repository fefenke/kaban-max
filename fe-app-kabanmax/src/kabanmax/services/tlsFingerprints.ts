import catalog from '../../../../shared/tls-fingerprints.json';

export const TLS_FINGERPRINTS = catalog;
export const selectableFingerprints = catalog.filter((item) => !item.aliasOf);
export const fingerprintProfile = (id: string) =>
  catalog.find((item) => item.id === id.trim().toLowerCase());
export const fingerprintFamily = (id: string) =>
  fingerprintProfile(id)?.family || id;
export function fingerprintLabel(id: string) {
  const profile = fingerprintProfile(id);
  return profile
    ? `${profile.label}${profile.version ? ` ${profile.version}` : ''}`
    : id;
}

export function selectedFingerprint(
  family: unknown,
  variant: unknown,
  original: unknown = '',
) {
  const id = `${family || ''}`;
  if (id !== 'chrome') return id;
  if (variant === 'chrome_155') return 'chrome_155';
  const previous = fingerprintProfile(`${original || ''}`);
  return previous?.aliasOf === 'chrome' ? previous.id : 'chrome';
}

export function fingerprintSelectionDefaults(id: string) {
  return {
    _tls_original: id,
    _tls_variant:
      fingerprintProfile(id)?.id === 'chrome_155' ? 'chrome_155' : 'chrome',
  };
}
