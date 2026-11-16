import { modalOptionFormValue } from '../../cbi/modal';
import {
  connectionFingerprintSupported,
  coreHas,
  validateCoreFeature,
} from '../../services/coreFeatures.service';
import {
  fingerprintFamily,
  fingerprintProfile,
  selectableFingerprints,
  selectedFingerprint,
} from '../../services/tlsFingerprints';

export function currentFingerprintSelection(map: CBIMap, itemId = 'settings') {
  const read = (key: string) =>
    modalOptionFormValue(map, itemId, key) ??
    map.data.get(map.config, itemId, key);
  return selectedFingerprint(
    read('tls_fingerprint'),
    read('_tls_variant'),
    read('_tls_original'),
  );
}

export function addFingerprintOptions(
  section: CBISection,
  getUri: (map: CBIMap, id: string) => string,
) {
  const o = section.option(
    form.ListValue,
    'tls_fingerprint',
    _('TLS fingerprint'),
  );
  o.value('', _('Inherit from connection URI'));
  for (const profile of selectableFingerprints) {
    if (profile.id === 'chrome_155') continue;
    o.value(profile.id, profile.label);
  }
  o.default = '';
  o.rmempty = true;
  o.retain = true;
  o.load = function (id: string) {
    return fingerprintFamily(
      `${this.map.data.get(this.map.config, id, 'tls_fingerprint') || ''}`,
    );
  };
  o.description = _(
    'Random selects Chrome, Firefox or Safari once per process. Randomized builds a seeded ClientHello with ALPN. Neither has a browser version. Android and 360 do not support REALITY; Edge, iOS and QQ require older REALITY servers.',
  );
  // Raw formats have no reliable virtual TLS fields. Their initial effective
  // URI is checked here, and every edited value is rechecked before saving.
  if (coreHas('utls')) {
    for (const protocol of ['vless', 'trojan', 'anytls']) {
      for (const security of ['tls', 'xtls', 'reality'])
        o.depends({
          _uri_editor: 'fields',
          _uri_protocol: protocol,
          _uri_security: security,
        });
    }
    o.depends({ _uri_editor: 'fields', _uri_protocol: 'https' });
    if (
      connectionFingerprintSupported(
        `${section.map.data.get(section.map.config, 'settings', 'uri') || ''}`,
      )
    )
      o.depends('_uri_editor', 'raw');
  } else o.depends('_tls_unavailable', '1');
  o.validate = function (id: string) {
    const fingerprint = currentFingerprintSelection(this.map, id);
    if (!fingerprint) return true;
    if (!fingerprintProfile(fingerprint))
      return _('Unsupported TLS fingerprint.');
    if (!connectionFingerprintSupported(getUri(this.map, id), fingerprint))
      return _(
        'TLS fingerprint requires a supported TCP connection with TLS enabled.',
      );
    return validateCoreFeature('utls');
  };
  const variant = section.option(
    form.ListValue,
    '_tls_variant',
    _('Fingerprint version'),
  );
  variant.value('chrome', '133');
  variant.value('chrome_155', '155');
  variant.default = 'chrome';
  variant.rmempty = false;
  variant.retain = true;
  variant.depends('tls_fingerprint', 'chrome');
  variant.validate = (_id, value) =>
    ['chrome', 'chrome_155'].includes(`${value}`)
      ? true
      : _('Unsupported fingerprint version');
  for (const profile of selectableFingerprints) {
    if (profile.family === 'chrome' || !profile.version) continue;
    const version = section.option(
      form.ListValue,
      `_tls_version_${profile.id}`,
      _('Fingerprint version'),
    );
    version.value(profile.version, profile.version);
    version.default = profile.version;
    version.readonly = true;
    version.depends('tls_fingerprint', profile.id);
    version.write = () => undefined;
    version.remove = () => undefined;
  }
}
