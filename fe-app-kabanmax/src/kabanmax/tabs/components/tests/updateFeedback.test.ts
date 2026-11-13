import { afterEach, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  check: vi.fn(),
  toast: vi.fn(),
  buttons: [] as Array<{ text: string; onClick: () => void }>,
  actions: [] as Array<{
    tag: string;
    role?: string;
    className: string;
    hidden?: boolean;
    children: unknown[];
  }>,
}));

vi.mock('../releaseCheck', async (original) => ({
  ...(await original<typeof import('../releaseCheck')>()),
  checkRelease: mocks.check,
}));
vi.mock('../../../../helpers/showToast', () => ({ showToast: mocks.toast }));
vi.mock('../../../../partials', () => ({
  renderButton: (props: { text: string; onClick: () => void }) => {
    mocks.buttons.push(props);
    return {};
  },
  renderModal: vi.fn(),
}));
vi.mock('../acornGame', () => ({
  createAcornGame: () => ({ element: {}, setShown: vi.fn() }),
}));
vi.mock('../terminal', () => ({
  createTerminal: () => ({ element: {}, setInput: vi.fn() }),
}));
vi.mock('../installerRun', () => ({
  createInstallerRun: () => ({
    state: {
      id: '',
      starting: false,
      running: false,
      startedAt: null,
      finishedAt: null,
    },
    setShown: vi.fn(),
  }),
}));
vi.mock('../../../helpers/isActiveLuciTab', () => ({
  isActiveLuciTab: () => false,
}));
vi.mock('../../../services/store.service', () => ({
  store: {
    get: () => ({
      tabService: { current: 'dashboard' },
      serviceState: { data: { kabanmaxBusy: null } },
      diagnosticsSystemInfo: {},
    }),
    subscribeKey: vi.fn(),
  },
}));
vi.mock('../render', () => ({
  pageRoot: {
    querySelector: (selector: string) => ({
      append: vi.fn(),
      replaceChildren: (...children: typeof mocks.actions) => {
        if (selector === '#components-actions') mocks.actions = children;
      },
    }),
  },
}));

afterEach(() => vi.unstubAllGlobals());

it('shows successful checks above the application button without a toast, including repeated checks', async () => {
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
      replaceChildren: vi.fn(),
      append: vi.fn(),
      addEventListener: vi.fn(),
    }),
  );
  vi.stubGlobal('document', {
    createElementNS: () => ({ setAttribute: vi.fn(), appendChild: vi.fn() }),
  });
  mocks.check.mockResolvedValue({ success: true, update_available: false });
  const { initController } = await import('../initController');
  initController();
  for (let checks = 1; checks <= 2; checks++) {
    [...mocks.buttons]
      .reverse()
      .find((button) => button.text === 'Check for updates')!
      .onClick();
    await vi.waitFor(() => {
      const status = mocks.actions.find((node) => node.role === 'status')!;
      expect(status.children).toEqual(['No updates available']);
      expect(status.hidden).toBe(false);
      expect(status.className).toContain('update-status--success');
      expect(mocks.actions.indexOf(status)).toBe(2);
    });
    expect(mocks.check).toHaveBeenCalledTimes(checks);
    expect(mocks.toast).not.toHaveBeenCalled();
  }
  mocks.check.mockRejectedValueOnce(new Error('offline'));
  [...mocks.buttons]
    .reverse()
    .find((button) => button.text === 'Check for updates')!
    .onClick();
  expect(mocks.actions[2].className).not.toMatch(/--success|--error/);
  await vi.waitFor(() =>
    expect(mocks.actions[2].className).toContain('update-status--error'),
  );
  expect(mocks.actions[2].children).toEqual(['offline']);
  mocks.check.mockResolvedValueOnce({
    success: true,
    update_available: true,
    latest: 'v9',
  });
  [...mocks.buttons]
    .reverse()
    .find((button) => button.text === 'Check for updates')!
    .onClick();
  await vi.waitFor(() =>
    expect(mocks.actions[2].children).toEqual(['Update available: v9']),
  );
  expect(mocks.actions[2].className).toContain('update-status--success');
  expect(mocks.toast).not.toHaveBeenCalled();
});
