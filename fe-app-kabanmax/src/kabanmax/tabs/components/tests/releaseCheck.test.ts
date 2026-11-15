import { describe, expect, it, vi } from 'vitest';
import { checkRelease, releaseAction } from '../releaseCheck';
const shell = vi.hoisted(() => vi.fn());
vi.mock('../../../../helpers/executeShellCommand', () => ({ executeShellCommand: shell }));
describe('component update action', () => {
  it('checks before offering an installation', () => {
    expect(releaseAction(null)).toBe('check');
  });
  it('offers core updates even when application versions are equal', () => {
    expect(
      releaseAction({
        success: true,
        installed: '0.1.0',
        latest: '0.1.0',
        update_available: true,
      }),
    ).toBe('install');
  });
  it('checks again when current and retries failed checks', () => {
    expect(releaseAction({ success: true, update_available: false })).toBe(
      'check',
    );
    expect(releaseAction({ success: false, update_available: true })).toBe(
      'check',
    );
  });
});

it('rejects a malformed success response instead of reporting a current version', async () => {
  shell.mockResolvedValue({ code: 0, stdout: '{"success":true}' });
  await expect(checkRelease()).rejects.toThrow();
});
