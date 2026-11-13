import { afterEach, expect, it, vi } from 'vitest';
import { renderZapret2 } from '../zapret2';

const shell = vi.hoisted(() => vi.fn());
vi.mock('../../../../helpers/executeShellCommand', () => ({
  executeShellCommand: shell,
}));
afterEach(() => vi.unstubAllGlobals());

it('keeps Zapret2 check results above its button with success, neutral progress and error tones', async () => {
  vi.stubGlobal(
    'E',
    (
      tag: string,
      attrs: Record<string, unknown> = {},
      children: unknown[] = [],
    ) => ({
      tag,
      ...attrs,
      className: attrs.class || '',
      children,
      textContent: '',
    }),
  );
  let refresh!: () => void;
  vi.stubGlobal('window', {
    setTimeout: (callback: () => void) => {
      refresh = callback;
    },
  });
  const reply = (value: object) => ({ code: 0, stdout: JSON.stringify(value) });
  shell.mockResolvedValue(reply({ installed: 'v1', latest: 'v1' }));
  const root = renderZapret2() as unknown as {
    children: Array<{
      role?: string;
      className: string;
      textContent: string;
      hidden: boolean;
      disabled: boolean;
      onclick: () => void;
    }>;
  };
  const details = root.children[1];
  const button = root.children[2];
  expect(details.role).toBe('status');
  refresh();
  await vi.waitFor(() => expect(button.disabled).toBe(false));
  for (let count = 0; count < 2; count++) {
    button.onclick();
    expect(details.className).not.toMatch(/--success|--error/);
    await vi.waitFor(() =>
      expect(details.textContent).toBe('No updates available'),
    );
    expect(details.hidden).toBe(false);
    expect(details.className).toContain('update-status--success');
  }
  shell.mockRejectedValueOnce(new Error('offline'));
  button.onclick();
  await vi.waitFor(() => expect(details.textContent).toBe('offline'));
  expect(details.className).toContain('update-status--error');
  shell.mockResolvedValue(reply({ installed: 'v1', latest: 'v2' }));
  button.onclick();
  await vi.waitFor(() =>
    expect(details.textContent).toBe('Update available: v2'),
  );
  expect(details.className).toContain('update-status--success');
});
