import { describe, expect, it, vi } from 'vitest';
vi.stubGlobal('_', (text: string) => text);
import { validateFailureRetryInterval } from '../healthCheck';
describe('failure retry interval', () => {
  it('accepts 1s through 5m and rejects values outside the range', () => {
    for (const value of ['1s', '3s', '12s', '1m30s', '5m'])
      expect(validateFailureRetryInterval(value)).toBe(true);
    for (const value of ['', '0s', '500ms', '301s', 'later'])
      expect(validateFailureRetryInterval(value)).not.toBe(true);
  });
});
