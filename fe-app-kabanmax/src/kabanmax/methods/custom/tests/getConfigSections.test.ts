import {
  afterAll,
  beforeAll,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from 'vitest';

const mocks = vi.hoisted(() => ({ callUbus: vi.fn() }));
vi.mock('../../../../helpers/callUbus', () => ({ callUbus: mocks.callUbus }));

import { getConfigSections } from '../getConfigSections';

const applied = [{ '.type': 'section', '.name': 'main', label: 'proxy' }];
const unsaved = [{ '.type': 'section', '.name': 'main', label: 'renamed' }];

beforeAll(() => {
  vi.stubGlobal('uci', {
    load: vi.fn().mockResolvedValue(['kabanmax']),
    sections: () => unsaved,
  });
});
afterAll(() => vi.unstubAllGlobals());
beforeEach(() => {
  mocks.callUbus.mockReset();
});

describe('the configuration the runtime views read', () => {
  it('is the one the core runs, not the session with its unsaved changes', async () => {
    mocks.callUbus.mockResolvedValue({
      success: true,
      data: { sections: applied },
    });

    expect(await getConfigSections()).toEqual(applied);
    expect(mocks.callUbus).toHaveBeenCalledWith(
      expect.objectContaining({
        object: 'kabanmax',
        method: 'config',
        nobatch: true,
      }),
    );
  });

  it('shares concurrent reads, then reads fresh applied config next time', async () => {
    let finish!: (value: unknown) => void;
    mocks.callUbus.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          finish = resolve;
        }),
    );
    const first = getConfigSections();
    const second = getConfigSections();
    expect(mocks.callUbus).toHaveBeenCalledTimes(1);
    finish({ success: true, data: { sections: applied } });
    expect(await first).toEqual(applied);
    expect(await second).toEqual(applied);
    mocks.callUbus.mockResolvedValueOnce({
      success: true,
      data: { sections: unsaved },
    });
    expect(await getConfigSections()).toEqual(unsaved);
    expect(mocks.callUbus).toHaveBeenCalledTimes(2);
  });

  it('is the session view when no state service answers for it', async () => {
    mocks.callUbus.mockResolvedValue({
      success: false,
      message: 'Method not found',
      unavailable: true,
    });

    expect(await getConfigSections()).toEqual(unsaved);
  });

  it('is an error when the state service fails', async () => {
    mocks.callUbus.mockResolvedValue({
      success: false,
      message: 'fkp.config timed out',
      unavailable: false,
    });

    await expect(getConfigSections()).rejects.toThrow('fkp.config timed out');
  });
});
