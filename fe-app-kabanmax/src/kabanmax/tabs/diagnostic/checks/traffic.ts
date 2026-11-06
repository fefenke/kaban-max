import { KabanMaxShellMethods, RemoteFakeIPMethods } from '../../../methods';
import type { IDiagnosticsChecksItem } from '../../../services';
import type { KabanMax } from '../../../types';
import { CheckOutcome, finding, outcome, unanswered } from './present';

// Whether this browser's request reached the check address through KabanMax, or null for no answer.
export type BrowserCheck = { fakeip: boolean } | null;

function routerItem(router: KabanMax.TrafficCheckResult['router']) {
  const key = _('Router');

  if (router.excluded) {
    return finding('success', key, _('excluded from routing'));
  }
  if (router.fakeip) {
    return finding('success', key, _('goes through KabanMax'));
  }
  if (!router.dns_fakeip) {
    return finding('warning', key, _('resolves past KabanMax'));
  }
  if (router.answered) {
    return finding('error', key, _('goes past KabanMax'));
  }
  return finding(
    'warning',
    key,
    _('not checked: the check service did not answer'),
  );
}

function exitItem(data: KabanMax.TrafficCheckResult) {
  const exit = data.exit!;
  const key = _('Exit via "%s"').format(exit.section);
  const direct = data.router.answered ? data.router.ip : '';

  if (!exit.answered) {
    return finding('warning', key, _('no answer'));
  }
  if (direct && direct === exit.ip) {
    return finding('warning', key, _('%s, the same as direct').format(exit.ip));
  }
  return finding(
    'success',
    key,
    direct ? _('%s, direct %s').format(exit.ip, direct) : exit.ip,
  );
}

function deviceItem(browser: BrowserCheck) {
  const key = _('This device');

  if (browser?.fakeip) {
    return finding('success', key, _('goes through KabanMax'));
  }
  return browser
    ? finding('warning', key, _("does not use the router's DNS"))
    : finding('warning', key, _('not checked: no answer'));
}

export function presentTraffic(
  data: KabanMax.TrafficCheckResult,
  browser: BrowserCheck,
): IDiagnosticsChecksItem[] {
  return [
    routerItem(data.router),
    ...(data.exit ? [exitItem(data)] : []),
    deviceItem(browser),
  ];
}

// The router's side and the browser's run at once; each can take seconds when something is wrong.
export async function runTrafficCheck(): Promise<CheckOutcome> {
  const [response, browser] = await Promise.all([
    KabanMaxShellMethods.checkTraffic(),
    RemoteFakeIPMethods.getFakeIpCheck(),
  ]);

  if (!response.success) {
    return unanswered();
  }

  return outcome(
    presentTraffic(
      response.data,
      browser.success ? { fakeip: Boolean(browser.data.fakeip) } : null,
    ),
  );
}
