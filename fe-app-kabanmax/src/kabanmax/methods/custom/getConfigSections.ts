import { KabanMax } from '../../types';
import { KABANMAX_UCI_PACKAGE } from '../../../constants';
import { callUbus } from '../../../helpers/callUbus';
import {
  KABANMAX_CALL_TIMEOUT_MS,
  KABANMAX_SERVICE_OBJECT,
} from '../../services/kabanmaxWaitTransport';

// The configuration the core runs, which its tags and the Clash API key come from: rpcd lays the
// session's unsaved changes over every uci read of the page.
// The backend refuses a configuration holding a section type ConfigSection does not list.
export async function getConfigSections(): Promise<KabanMax.ConfigSection[]> {
  const applied = await callUbus<{ sections: KabanMax.ConfigSection[] }>({
    object: KABANMAX_SERVICE_OBJECT,
    method: 'config',
    timeoutMs: KABANMAX_CALL_TIMEOUT_MS,
    retryUnavailable: false,
  });
  if (applied.success) {
    return applied.data.sections;
  }
  if (!applied.unavailable) {
    throw new Error(applied.message);
  }

  // Without the state service, the session's view, which differs only while changes are unsaved.
  await uci.load(KABANMAX_UCI_PACKAGE);
  return uci.sections(KABANMAX_UCI_PACKAGE) as KabanMax.ConfigSection[];
}
