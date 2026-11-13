import { afterEach, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  check: vi.fn(),
  toast: vi.fn(),
  buttons: [] as Array<{ text: string; onClick: () => void }>,
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
    querySelector: () => ({ append: vi.fn(), replaceChildren: vi.fn() }),
  },
}));

afterEach(() => vi.unstubAllGlobals());

it('confirms every manual check that finds no application updates', async () => {
  vi.stubGlobal('E', () => ({
    replaceChildren: vi.fn(),
    append: vi.fn(),
    addEventListener: vi.fn(),
  }));
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
    await vi.waitFor(() => expect(mocks.toast).toHaveBeenCalledTimes(checks));
    expect(mocks.toast).toHaveBeenLastCalledWith(
      'No updates available',
      'success',
    );
  }
});
