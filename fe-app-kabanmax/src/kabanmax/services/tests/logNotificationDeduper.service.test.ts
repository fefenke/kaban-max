import { describe, expect, it } from 'vitest';

import {
  getLogNotificationKey,
  getKabanMaxLogNotification,
  isErrorLogLine,
  LogNotificationDeduper,
} from '../logNotificationDeduper.service';

class MemoryStorage implements Storage {
  private values = new Map<string, string>();

  get length() {
    return this.values.size;
  }

  clear() {
    this.values.clear();
  }

  getItem(key: string) {
    return this.values.get(key) ?? null;
  }

  key(index: number) {
    return Array.from(this.values.keys())[index] ?? null;
  }

  removeItem(key: string) {
    this.values.delete(key);
  }

  setItem(key: string, value: string) {
    this.values.set(key, value);
  }
}

describe('LogNotificationDeduper', () => {
  it('accepts only KabanMax errors', () => {
    expect(isErrorLogLine('kabanmax: [info] ok')).toBe(false);
    expect(isErrorLogLine('kabanmax: [error] failed')).toBe(true);
    expect(isErrorLogLine('kabanmax: [warn] retrying what [error] said')).toBe(
      false,
    );
    expect(isErrorLogLine('sing-box[123]: [error] dial failed')).toBe(false);
    expect(
      isErrorLogLine(
        'daemon.err sing-box[123]: ERROR[0000] connection: dial failed',
      ),
    ).toBe(false);
    expect(getKabanMaxLogNotification('kabanmax: [info] ok')).toBeNull();
    expect(
      getKabanMaxLogNotification(
        'Tue Sep 29 02:38:25 2026 user.err kabanmax: [error] Failed to reload sing-box',
      ),
    ).toEqual({
      kind: 'error',
      line: 'Tue Sep 29 02:38:25 2026 user.err kabanmax: [error] Failed to reload sing-box',
      message: 'Failed to reload sing-box',
    });
    expect(
      getKabanMaxLogNotification('sing-box[123]: [error] dial failed'),
    ).toBeNull();
  });

  it('dedupes already shown log lines through session storage', () => {
    const storage = new MemoryStorage();
    const first = new LogNotificationDeduper(storage);

    expect(first.shouldNotify('kabanmax: [error] failed')).toBe(true);
    expect(first.shouldNotify('kabanmax: [error] failed')).toBe(false);
    expect(first.shouldNotify('kabanmax: [error] another failure')).toBe(true);
    expect(first.shouldNotify('sing-box[123]: [error] dial failed')).toBe(
      false,
    );

    const afterReload = new LogNotificationDeduper(storage);

    expect(afterReload.shouldNotify('kabanmax: [error] failed')).toBe(false);
    expect(afterReload.shouldNotify('kabanmax: [error] a later failure')).toBe(
      true,
    );
  });

  it('keeps the full log line as the replay key', () => {
    expect(getLogNotificationKey('  Jun 06 kabanmax: [error] failed  ')).toBe(
      'Jun 06 kabanmax: [error] failed',
    );
  });

  it('remembers only the latest lines it showed', () => {
    const storage = new MemoryStorage();
    const deduper = new LogNotificationDeduper(storage);
    const line = (index: number) => `kabanmax: [error] failure ${index}`;

    for (let index = 0; index <= 500; index++) {
      deduper.shouldNotify(line(index));
    }

    const stored = JSON.parse(
      storage.getItem('kabanmax:shown-log-error-notifications:v1') || '[]',
    );
    expect(stored).toHaveLength(500);
    expect(stored[0]).toBe(line(1));
    expect(deduper.shouldNotify(line(500))).toBe(false);
    expect(deduper.shouldNotify(line(0))).toBe(true);
  });
});
