import { asciiHostname, validAsciiDomain } from './validateDomain';

export function validPreRoutingResolveDomains(text: string): boolean {
  const values = text
    .split('\n')
    .map((line) => line.replace(/\s*\/\/.*$/, '').replace(/\s*#.*$/, ''))
    .join('\n')
    .split(/[,\s]+/)
    .filter(Boolean);
  return (
    values.length > 0 &&
    values.every((value) => {
      while (/^full:/i.test(value)) {
        value = value.slice(5);
      }
      const ascii = asciiHostname(value.toLowerCase());
      return (
        !!ascii &&
        validAsciiDomain(ascii, false) &&
        !/(^|\.)[0-9]+$/.test(ascii)
      );
    })
  );
}
