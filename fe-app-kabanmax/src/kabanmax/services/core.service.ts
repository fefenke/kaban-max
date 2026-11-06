import { TabServiceInstance } from './tab.service';
import { store } from './store.service';
import { logger } from './logger.service';
import {
  getKabanMaxLogCursor,
  startKabanMaxLogFeed,
} from './kabanmaxLogFeed.service';
import { KabanMaxLogNotification } from './logNotificationDeduper.service';
import { LogAlerts } from './logAlerts.service';
import {
  dropLogNotificationHandoff,
  saveLogNotificationHandoff,
  takeLogNotificationHandoff,
} from './logNotificationHandoff.service';
import {
  registerRuntimeStateResumeRefresh,
  startRuntimeUiStatePolling,
} from './runtimeUiState.service';
import { ensureSystemInfo } from './systemInfo.service';
import { E } from '../../helpers/element';

// Collecting the versions takes seconds, so they are warmed once per page, after a delay that
// lets the first state poll go first.
const SYSTEM_INFO_PREFETCH_DELAY_MS = 2000;

function showLogNotification(notification: KabanMaxLogNotification) {
  return ui.addNotification(
    _('KabanMax Error'),
    E('div', {}, notification.message),
    'error',
    'fkp-log-error-notification',
  );
}

export function coreService() {
  TabServiceInstance.onChange((activeId, tabs) => {
    logger.info('[TAB]', activeId);
    store.set({
      tabService: {
        current: activeId || '',
        all: tabs.map((tab) => tab.id),
      },
    });
  });

  const logAlerts = new LogAlerts(showLogNotification);
  const handoff = takeLogNotificationHandoff();
  logAlerts.reopen(handoff?.lines ?? []);

  window.addEventListener('pagehide', () => {
    saveLogNotificationHandoff({
      cursor: getKabanMaxLogCursor() || handoff?.cursor || 0,
      lines: logAlerts.openLines(),
    });
  });
  window.addEventListener('pageshow', (event) => {
    if (event.persisted) {
      dropLogNotificationHandoff();
    }
  });

  startKabanMaxLogFeed((line) => logAlerts.read(line), handoff?.cursor ?? 0);
  window.setTimeout(() => {
    void ensureSystemInfo().catch(() => null);
  }, SYSTEM_INFO_PREFETCH_DELAY_MS);

  registerRuntimeStateResumeRefresh();
  startRuntimeUiStatePolling();
}
