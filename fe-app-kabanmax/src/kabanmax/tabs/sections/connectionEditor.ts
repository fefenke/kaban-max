import {
  parseConnectionUri,
  serializeConnectionUri,
  exportConnectionUri,
  type ConnectionFields,
} from './connectionUri';
import { modalOptionFormValue, setModalOptionValue } from '../../cbi/modal';
import { copyToClipboard } from '../../../helpers/copyToClipboard';
import { showToast } from '../../../helpers/showToast';
import {
  selectableFingerprints,
  fingerprintLabel,
} from '../../services/tlsFingerprints';
import { currentFingerprintSelection } from './fingerprintOptions';

const FIELD_KEYS = [
  'protocol',
  'server',
  'port',
  'credential',
  'password',
  'security',
  'sni',
  'alpn',
  'publicKey',
  'shortId',
  'fingerprint',
  'flow',
  'encryption',
  'transport',
  'host',
  'path',
  'serviceName',
  'mode',
  'extra',
] as const;

export function connectionEditorDefaults(uri: string): ChildSettings {
  const fields = parseConnectionUri(uri);
  return Object.fromEntries([
    ['_uri_editor', fields.supported ? 'fields' : 'raw'],
    ['_uri_source', uri],
    ...FIELD_KEYS.map((key) => [`_uri_${key}`, fields[key]]),
  ]);
}

export function connectionEditorUri(settings: ChildSettings) {
  const uri = `${settings.uri || ''}`.trim();
  if (settings._uri_editor !== 'fields') return uri;
  if (uri !== settings._uri_source)
    throw new Error(_('Import the changed URI into fields before saving.'));
  const fields = parseConnectionUri(uri);
  if (!fields.supported)
    throw new Error(_('Import this URI again or use the original URI editor.'));
  for (const key of FIELD_KEYS)
    fields[key] = `${settings[`_uri_${key}`] ?? ''}`;
  return serializeConnectionUri(uri, fields);
}

function currentSettings(map: CBIMap, itemId = 'settings'): ChildSettings {
  const read = (key: string) =>
    modalOptionFormValue(map, itemId, key) ??
    map.data.get(map.config, itemId, key);
  const settings = Object.fromEntries(
    [
      'uri',
      'name',
      'tls_fingerprint',
      '_uri_editor',
      '_uri_source',
      ...FIELD_KEYS.map((key) => `_uri_${key}`),
    ].map((key) => [key, read(key)]),
  );
  settings.tls_fingerprint = currentFingerprintSelection(map, itemId);
  return settings;
}

// Validators and explicit export read the same effective URI as Save.
export function currentConnectionEditorUri(map: CBIMap, itemId: string) {
  try {
    return connectionEditorUri(currentSettings(map, itemId));
  } catch {
    return '';
  } // The save hook reports the precise, sanitized field error.
}

export function addConnectionEditorOptions(
  section: CBISection,
  validateUri: (uri: string) => true | string,
) {
  let option = section.option(
    form.ListValue,
    '_uri_editor',
    _('Connection parameters'),
  );
  option.value('fields', _('Editable fields'));
  option.value('raw', _('Original URI'));
  option.rmempty = false;
  option.description = _(
    'Fields are available for VLESS, Trojan, AnyTLS, SOCKS and HTTP proxies. Other formats keep the original URI. Unknown parameters are preserved.',
  );
  const modeOption = option;
  option.validate = (_id, value) =>
    value !== 'fields' ||
    parseConnectionUri(
      `${modeOption.map.data.get(modeOption.map.config, 'settings', 'uri') || ''}`,
    ).supported
      ? true
      : _('Use the original URI editor for this format.');

  option = section.option(form.Value, 'uri', _('Original connection URI'));
  option.password = true;
  option.retain = true;
  option.rmempty = false;
  option.depends('_uri_editor', 'raw');
  option.validate = (_id, value) =>
    `${value || ''}`.trim() ? validateUri(`${value}`) : _('Required');

  option = section.option(form.Button, '_uri_import', _('Import URI'));
  option.inputtitle = _('Import into fields');
  option.depends('_uri_editor', 'raw');
  option.onclick = () => {
    const raw =
      `${modalOptionFormValue(section.map, 'settings', 'uri') ?? ''}`.trim();
    const defaults = connectionEditorDefaults(raw);
    if (defaults._uri_editor === 'raw') {
      showToast(
        _(
          'This format stays in the original URI editor; its data is preserved.',
        ),
        'error',
      );
      return;
    }
    setModalOptionValue(section.map, modeOption, 'raw');
    section.map.data.set(section.map.config, 'settings', 'uri', raw);
    section.map.data.set(section.map.config, 'settings', '_uri_source', raw);
    for (const key of FIELD_KEYS) {
      const field = section.map.lookupOption(`_uri_${key}`, 'settings')?.[0];
      if (field)
        setModalOptionValue(section.map, field, defaults[`_uri_${key}`]);
    }
    setModalOptionValue(section.map, modeOption, 'fields');
    section.map.checkDepends();
  };

  const field = (
    key: keyof ConnectionFields,
    label: string,
    protocols?: string[],
    choices?: string[],
  ) => {
    const o = section.option(
      choices ? form.ListValue : form.Value,
      `_uri_${key}`,
      label,
    );
    o.retain = true;
    o.rmempty = false;
    o.optional = true;
    if (choices)
      choices.forEach((value) => o.value(value, value || _('Default')));
    if (protocols)
      protocols.forEach((protocol) => {
        const tlsField = [
          'sni',
          'alpn',
          'publicKey',
          'shortId',
          'fingerprint',
        ].includes(key);
        if (tlsField) {
          const securityModes = ['publicKey', 'shortId'].includes(key)
            ? ['reality']
            : ['tls', 'xtls', 'reality'];
          securityModes.forEach((security) =>
            o.depends({
              _uri_editor: 'fields',
              _uri_protocol: protocol,
              _uri_security: security,
            }),
          );
        } else o.depends({ _uri_editor: 'fields', _uri_protocol: protocol });
      });
    else o.depends('_uri_editor', 'fields');
    return o;
  };
  const tls = ['vless', 'trojan', 'anytls'];
  const transport = ['vless', 'trojan'];
  field('protocol', _('Protocol')).readonly = true;
  field('server', _('Server address'));
  field('port', _('Server port'));
  const credential = field('credential', _('UUID / username / password'));
  credential.password = true;
  credential.description = _(
    'VLESS: UUID. Trojan and AnyTLS: server password. HTTP and SOCKS: username.',
  );
  field('password', _('Account password'), [
    'socks',
    'socks5',
    'http',
    'https',
  ]).password = true;
  field('security', _('TLS / REALITY'), tls, [
    'none',
    'tls',
    'xtls',
    'reality',
  ]);
  field('sni', _('TLS server name (SNI)'), tls);
  field('alpn', _('TLS ALPN (comma separated)'), tls).description = _(
    'WebSocket, gRPC, HTTPUpgrade and HTTP transports select ALPN in the core; this value applies only where the transport permits it.',
  );
  field('publicKey', _('REALITY public key'), tls);
  field('shortId', _('REALITY short ID'), tls).password = true;
  const fingerprint = field('fingerprint', _('Fingerprint in URI'), tls);
  selectableFingerprints.forEach((profile) =>
    fingerprint.value(profile.id, fingerprintLabel(profile.id)),
  );
  fingerprint.description = _(
    'The separate TLS fingerprint below overrides this value. Copy link exports the effective fingerprint.',
  );
  field('flow', _('VLESS flow'), ['vless']);
  field('encryption', _('VLESS encryption'), ['vless']);
  field('transport', _('Transport'), transport, [
    'tcp',
    'raw',
    'none',
    'ws',
    'websocket',
    'grpc',
    'gun',
    'httpupgrade',
    'http',
    'h2',
    'h3',
    'xhttp',
    'splithttp',
  ]);
  for (const [key, label] of [
    ['host', _('Transport host')],
    ['path', _('Transport path')],
    ['serviceName', _('gRPC service name')],
    ['mode', _('XHTTP mode')],
    ['extra', _('XHTTP extra (JSON)')],
  ] as const) {
    const o = field(key, label, []);
    const transports =
      key === 'serviceName'
        ? ['grpc', 'gun']
        : key === 'mode' || key === 'extra'
          ? ['xhttp', 'splithttp']
          : [
              'ws',
              'websocket',
              'httpupgrade',
              'http',
              'h2',
              'h3',
              'xhttp',
              'splithttp',
            ];
    transport.forEach((protocol) =>
      transports.forEach((type) =>
        o.depends({
          _uri_editor: 'fields',
          _uri_protocol: protocol,
          _uri_transport: type,
        }),
      ),
    );
    if (key === 'extra') o.password = true;
  }
  option = section.option(form.Button, '_uri_export', _('Export connection'));
  option.inputtitle = _('Copy link');
  option.description = _(
    'Copies effective portable parameters. ClientHello splitting, classical key exchange and cascade settings remain local and are not included in a share URI.',
  );
  option.onclick = () => {
    try {
      const settings = currentSettings(section.map);
      const uri = connectionEditorUri(settings);
      copyToClipboard(
        exportConnectionUri(
          uri,
          `${settings.tls_fingerprint || ''}`,
          `${settings.name || ''}`,
        ),
      );
    } catch (error) {
      // Errors here are fixed messages from our parser, never the URI or account.
      showToast(
        error instanceof Error
          ? error.message
          : _('Unable to export this connection'),
        'error',
      );
    }
  };
}
