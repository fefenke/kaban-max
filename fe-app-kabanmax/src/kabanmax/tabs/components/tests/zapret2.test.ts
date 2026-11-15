import { describe, expect, it } from 'vitest';
import { zapretAction } from '../zapret2';

describe('Zapret2 action', () => {
  it('offers installation as soon as status confirms the engine is missing', () => {
    expect(zapretAction({ installed: '', present: false }, false, false).action).toBe('install');
    expect(zapretAction({}, false, false).action).toBe('check');
    expect(zapretAction({ latest: 'v2' }, true, false)).toEqual({
      action: 'install',
      disabled: false,
    });
    expect(zapretAction({ latest: 'v2' }, false, false).action).toBe('check');
  });
  it('offers an update only when the checked version differs', () => {
    expect(zapretAction({ present: true, installed: '', latest: 'v2' }, true, false).action).toBe('check');
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
