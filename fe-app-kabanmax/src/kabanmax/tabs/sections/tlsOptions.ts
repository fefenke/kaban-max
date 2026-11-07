export function validateRealityTlsOption(
  uri: string,
  enabled: unknown,
): true | string {
  if (enabled !== '1') return true;
  return /^vless:\/\//i.test(uri) && /[?&]security=reality(?:[&#]|$)/i.test(uri)
    ? true
    : _('This TLS option requires a VLESS connection with REALITY.');
}
