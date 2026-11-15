import { readFileSync, writeFileSync } from 'node:fs';
const source = new URL('../shared/tls-fingerprints.json', import.meta.url);
const output = new URL('../kabanmax/files/usr/lib/singbox/fingerprints.uc', import.meta.url);
const catalog = JSON.parse(readFileSync(source, 'utf8'));
if (new Set(catalog.map((item) => item.id)).size !== catalog.length) throw new Error('Duplicate TLS fingerprint ID');
const content = '// Generated from shared/tls-fingerprints.json; run node scripts/generate-fingerprints.mjs\nreturn ' + JSON.stringify(catalog, null, 4) + ';\n';
if (process.argv.includes('--check')) {
  if (readFileSync(output, 'utf8').replaceAll('\r\n', '\n') !== content) throw new Error('TLS fingerprint catalog is stale: run node scripts/generate-fingerprints.mjs');
} else writeFileSync(output, content);
