import { describe, expect, it } from 'vitest';
import { zapretAction } from '../zapret2';

describe('Zapret2 action', () => {
  it('installs a missing engine only after an explicit check', () => {
    expect(zapretAction({ latest: 'v2' }, true, false)).toEqual({
      action: 'install',
      disabled: false,
    });
    expect(zapretAction({ latest: 'v2' }, false, false).action).toBe('check');
  });
  it('offers an update only when the checked version differs', () => {
    expect(
      zapretAction({ installed: 'v1', latest: 'v2' }, true, false).action,
    ).toBe('update');
    expect(
      zapretAction({ installed: 'v2', latest: 'v2' }, true, false).action,
    ).toBe('check');
  });
  it('retries failed checks and disables actions during an operation', () => {
    expect(
      zapretAction({ success: false, latest: 'v2' }, true, false).action,
    ).toBe('check');
    expect(zapretAction({ latest: 'v2' }, true, true).disabled).toBe(true);
  });
});
