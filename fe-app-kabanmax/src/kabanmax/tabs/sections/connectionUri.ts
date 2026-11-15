import { TLS_FINGERPRINTS } from '../../services/tlsFingerprints';

// The pinned core's parser/link/{query,vless,trojan,http,socks,quic}.go is the
// contract. Keep raw components so opening a form never normalizes a share URI.
export interface ConnectionFields {
  supported: boolean;
  protocol: string;
  server: string;
  port: string;
  credential: string;
  password: string;
  security: string;
  sni: string;
  alpn: string;
  publicKey: string;
  shortId: string;
  fingerprint: string;
  flow: string;
  encryption: string;
  transport: string;
  host: string;
  path: string;
  serviceName: string;
  mode: string;
  extra: string;
}

const PARAMETERS = {
  security: ['security'],
  sni: ['sni', 'peer', 'servername'],
  alpn: ['alpn'],
  publicKey: ['pbk', 'public-key'],
  shortId: ['sid', 'short-id'],
  fingerprint: ['fp', 'client-fingerprint'],
  flow: ['flow'],
  encryption: ['encryption'],
  transport: ['type', 'net'],
  host: ['host'],
  path: ['path'],
  serviceName: ['serviceName', 'grpc-service-name', 'servicename'],
  mode: ['mode'],
  extra: ['extra'],
} as const;

const TRANSPORTS = new Set([
  '',
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
const TLS_SCHEMES = new Set(['vless', 'trojan', 'anytls']);
const URI_FINGERPRINTS = new Set([
  '',
  ...TLS_FINGERPRINTS.map((profile) => profile.id),
  'unsafe',
  'none',
  'hellogolang',
]);
const SCHEMES = new Set([
  ...TLS_SCHEMES,
  'socks',
  'socks4',
  'socks4a',
  'socks5',
  'http',
  'https',
]);

function decode(value: string, query = false) {
  return decodeURIComponent(query ? value.replaceAll('+', ' ') : value);
}

function parts(source: string) {
  const match = /^([a-z0-9+]+):\/\/([^?#]*)(\?[^#]*)?(#.*)?$/i.exec(source);
  if (!match)
    throw new Error(_('Use the original URI editor for this format.'));
  const authorityEnd = match[2].lastIndexOf('@');
  // A password may contain unescaped slashes: Go reads up to the last @.
  const user = authorityEnd >= 0 ? match[2].slice(0, authorityEnd) : '';
  const endpoint = match[2].slice(authorityEnd + 1);
  const address = /^(\[[^\]]+\]|[^:/]+)(?::([^/]*))?(\/.*)?$/.exec(endpoint);
  if (!address) throw new Error(_('Invalid server address'));
  return {
    scheme: match[1],
    user,
    address: address[1],
    port: address[2] || '',
    suffix: address[3] || '',
    query: match[3]?.slice(1) ?? '',
    hadQuery: !!match[3],
    fragment: match[4] || '',
  };
}

function queryKey(pair: string) {
  try {
    return decode(pair.split('=', 1)[0], true)
      .toLowerCase()
      .replace(/^amp;/, '');
  } catch {
    return '';
  }
}

function getParameter(query: string, names: readonly string[]) {
  for (const name of names) {
    const pair = query
      .split('&')
      .find((part) => queryKey(part) === name.toLowerCase());
    if (pair == null) continue;
    try {
      const value = decode(
        pair.includes('=') ? pair.slice(pair.indexOf('=') + 1) : '',
        true,
      ).trim();
      if (value) return value;
    } catch {
      /* Unknown malformed values stay untouched in the raw query. */
    }
  }
  return '';
}

function setParameter(query: string, names: readonly string[], value: string) {
  const aliases = new Set(names.map((name) => name.toLowerCase()));
  const pairs = query
    ? query.split('&').filter((pair) => !aliases.has(queryKey(pair)))
    : [];
  if (value) pairs.push(`${names[0]}=${encodeURIComponent(value)}`);
  return pairs.join('&');
}

export function parseConnectionUri(source: string): ConnectionFields {
  const fields: ConnectionFields = {
    supported: false,
    protocol: source.split(':', 1)[0].toLowerCase(),
    server: '',
    port: '',
    credential: '',
    password: '',
    security: '',
    sni: '',
    alpn: '',
    publicKey: '',
    shortId: '',
    fingerprint: '',
    flow: '',
    encryption: '',
    transport: '',
    host: '',
    path: '',
    serviceName: '',
    mode: '',
    extra: '',
  };
  try {
    const raw = parts(source);
    if (!SCHEMES.has(fields.protocol)) return fields;
    fields.server = raw.address.replace(/^\[|\]$/g, '');
    fields.port =
      raw.port ||
      (fields.protocol === 'https'
        ? '443'
        : fields.protocol === 'http'
          ? '80'
          : '');
    const colon = raw.user.indexOf(':');
    fields.credential = decode(
      colon >= 0 ? raw.user.slice(0, colon) : raw.user,
    );
    fields.password = colon >= 0 ? decode(raw.user.slice(colon + 1)) : '';
    // SOCKS base64 credentials and password-based links with ambiguous userinfo
    // stay raw rather than presenting a misleading decoded account.
    if (
      (fields.protocol === 'socks' && raw.user && colon < 0) ||
      (TLS_SCHEMES.has(fields.protocol) && colon >= 0)
    )
      return fields;
    for (const key of Object.keys(PARAMETERS) as Array<keyof typeof PARAMETERS>)
      fields[key] = getParameter(raw.query, PARAMETERS[key]);
    if (TLS_SCHEMES.has(fields.protocol)) {
      fields.security ||= fields.protocol === 'vless' ? 'none' : 'tls';
      if (fields.protocol === 'anytls' && fields.security === 'none')
        fields.security = 'tls';
      if (fields.security !== 'none' && getParameter(raw.query, ['pbk']))
        fields.security = 'reality';
      fields.transport ||= 'tcp';
      if (
        !['none', 'tls', 'xtls', 'reality'].includes(fields.security) ||
        !TRANSPORTS.has(fields.transport)
      )
        return fields;
      // AnyTLS has no V2Ray transport. Preserve query as raw, without claiming it works.
      if (fields.protocol === 'anytls' && fields.transport !== 'tcp')
        return fields;
    }
    fields.supported = true;
  } catch {
    /* Raw mode is lossless even for unfamiliar/malformed URIs. */
  }
  return fields;
}

export function serializeConnectionUri(
  source: string,
  fields: ConnectionFields,
): string {
  const original = parseConnectionUri(source);
  if (!original.supported) return source;
  if (
    !fields.server ||
    /[\s/?#@%[\]]/.test(fields.server) ||
    (fields.server.includes(':') &&
      !fields.server.includes('::') &&
      fields.server.split(':').length < 3)
  )
    throw new Error(_('Invalid server address'));
  try {
    new URL(
      `http://${fields.server.includes(':') ? `[${fields.server}]` : fields.server}/`,
    );
  } catch {
    throw new Error(_('Invalid server address'));
  }
  if (!/^\d+$/.test(fields.port) || +fields.port < 1 || +fields.port > 65535)
    throw new Error(_('Port must be between 1 and 65535'));
  if (TLS_SCHEMES.has(original.protocol) && !fields.credential)
    throw new Error(_('Credentials are required'));
  if (
    /\p{Cc}/u.test(
      fields.credential +
        fields.password +
        fields.sni +
        fields.host +
        fields.serviceName,
    )
  )
    throw new Error(_('Control characters are not allowed'));
  if (
    TLS_SCHEMES.has(original.protocol) &&
    (!TRANSPORTS.has(fields.transport) ||
      !['none', 'tls', 'xtls', 'reality'].includes(fields.security))
  )
    throw new Error(_('Unsupported TLS or transport value'));
  if (original.protocol === 'anytls' && fields.security === 'none')
    throw new Error(_('AnyTLS requires TLS'));
  if (
    fields.fingerprint !== original.fingerprint &&
    !URI_FINGERPRINTS.has(fields.fingerprint.toLowerCase()) &&
    !/^(hello(?:chrome|firefox|safari|ios|edge|360|qq|android)_|hellorandomized|randomizednoalpn)/i.test(
      fields.fingerprint,
    )
  )
    throw new Error(_('Unsupported TLS fingerprint.'));
  if (original.protocol === 'vless') {
    if (
      !['', 'xtls-rprx-vision', 'xtls-rprx-vision-udp443'].includes(fields.flow)
    )
      throw new Error(_('Unsupported VLESS flow'));
    if (
      fields.flow &&
      ['', 'none'].includes(fields.encryption) &&
      (fields.security === 'none' ||
        !['tcp', 'raw', 'none'].includes(fields.transport))
    )
      throw new Error(
        _('VLESS Vision requires raw TCP with TLS or VLESS encryption'),
      );
  }
  if (fields.extra && fields.extra !== original.extra) {
    try {
      const extra = JSON.parse(fields.extra);
      if (!extra || typeof extra !== 'object' || Array.isArray(extra))
        throw new Error();
    } catch {
      throw new Error(_('XHTTP extra must be a JSON object'));
    }
  }
  if (fields.security === 'reality' && !fields.publicKey)
    throw new Error(_('REALITY public key is required'));
  const raw = parts(source);
  let query = raw.query;
  for (const key of Object.keys(PARAMETERS) as Array<keyof typeof PARAMETERS>) {
    if (fields[key] !== original[key])
      query = setParameter(query, PARAMETERS[key], fields[key]);
  }
  if (fields.security !== original.security && fields.security !== 'reality') {
    query = setParameter(
      setParameter(query, PARAMETERS.publicKey, ''),
      PARAMETERS.shortId,
      '',
    );
  }
  let authority = raw.address + (raw.port ? `:${raw.port}` : '');
  if (fields.server !== original.server || fields.port !== original.port)
    authority = `${fields.server.includes(':') ? `[${fields.server}]` : fields.server}:${fields.port}`;
  let user = raw.user;
  if (
    fields.credential !== original.credential ||
    fields.password !== original.password
  ) {
    user = encodeURIComponent(fields.credential);
    if (fields.password || raw.user.includes(':'))
      user += `:${encodeURIComponent(fields.password)}`;
  }
  return `${raw.scheme}://${user ? `${user}@` : ''}${authority}${raw.suffix}${query || raw.hadQuery ? `?${query}` : ''}${raw.fragment}`;
}

export function exportConnectionUri(
  source: string,
  fingerprint = '',
  name = '',
) {
  // Export must describe the effective fingerprint, not the URI's inherited one.
  // Unknown formats cannot safely encode an override; never invent a parameter.
  const fields = parseConnectionUri(source);
  if (fingerprint && (!fields.supported || !TLS_SCHEMES.has(fields.protocol)))
    throw new Error(
      _(
        'This format cannot export a TLS fingerprint override. Use the original URI and its separate settings.',
      ),
    );
  let result = source;
  if (fingerprint) {
    const raw = parts(source);
    const query = setParameter(raw.query, PARAMETERS.fingerprint, fingerprint);
    result = `${raw.scheme}://${raw.user ? `${raw.user}@` : ''}${raw.address}${raw.port ? `:${raw.port}` : ''}${raw.suffix}?${query}${raw.fragment}`;
  }
  if (name && fields.supported) {
    const marker = result.indexOf('#');
    let currentName = '';
    try {
      currentName = marker >= 0 ? decode(result.slice(marker + 1)) : '';
    } catch {
      /* Replace only on explicit export. */
    }
    if (currentName !== name)
      result = result.split('#', 1)[0] + `#${encodeURIComponent(name)}`;
  }
  return result;
}
