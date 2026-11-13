import { describe, expect, it } from 'vitest';
import { validPreRoutingResolveDomains } from '../validatePreRoutingResolve';

describe('pre-routing resolve domains', () => {
  it('accepts suffix and exact domains with the routing list separators', () => {
    expect(
      validPreRoutingResolveDomains(
        'example.org, full:ONLY.example\n# note\nпример.рф',
      ),
    ).toBe(true);
  });
  it('requires at least one domain', () => {
    expect(validPreRoutingResolveDomains('# comment')).toBe(false);
  });
  it.each([
    '192.0.2.1',
    'keyword:example',
    'regex:.*',
    'https://example.org',
    'example..org',
    'example.org/path',
  ])('refuses %s', (value) => {
    expect(validPreRoutingResolveDomains(value)).toBe(false);
  });
});
