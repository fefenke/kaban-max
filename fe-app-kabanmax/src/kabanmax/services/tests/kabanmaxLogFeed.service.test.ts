import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ callUbus: vi.fn() }));

vi.mock('../../../helpers/callUbus', () => ({
  callUbus: mocks.callUbus,
}));

async function freshFeed() {
  vi.resetModules();
  return import('../kabanmaxLogFeed.service');
}

const gone = { success: false, message: 'Object not found', unavailable: true };

beforeEach(() => {
  mocks.callUbus.mockReset();
});

describe('the log feed', () => {
  it('starts from where the log stands and takes only the lines after it', async () => {
    mocks.callUbus.mockResolvedValue({ success: true, data: { cursor: 3 } });
    const feed = await freshFeed();

    const lines: string[] = [];
    feed.startKabanMaxLogFeed((line) => lines.push(line));
    feed.takeKabanMaxLogLines({ cursor: 3, lines: ['kabanmax: old'] });
    await feed.placeKabanMaxLogFeed();
    feed.takeKabanMaxLogLines({ cursor: 4, lines: ['kabanmax: new'] });

    expect(lines).toEqual(['kabanmax: new']);
    expect(feed.getKabanMaxLogCursor()).toBe(4);
  });

  it('goes on from the cursor of the page it took over from', async () => {
    const feed = await freshFeed();

    feed.startKabanMaxLogFeed(() => {}, 7);
    await feed.placeKabanMaxLogFeed();

    expect(feed.getKabanMaxLogCursor()).toBe(7);
    expect(mocks.callUbus).not.toHaveBeenCalled();
  });

  it('asks where the log stands again once the state service is back', async () => {
    mocks.callUbus
      .mockResolvedValueOnce(gone)
      .mockResolvedValueOnce({ success: true, data: { cursor: 5 } });
    const feed = await freshFeed();

    feed.startKabanMaxLogFeed(() => {});
    await feed.placeKabanMaxLogFeed();
    expect(feed.getKabanMaxLogCursor()).toBeUndefined();

    await feed.placeKabanMaxLogFeed();
    expect(feed.getKabanMaxLogCursor()).toBe(5);
  });
});
