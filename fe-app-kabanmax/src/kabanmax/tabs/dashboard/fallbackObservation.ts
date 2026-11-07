import { E } from '../../../helpers/element';
import { formatDuration } from '../../helpers/formatDuration';
import type { ClashAPI, KabanMax } from '../../types';

type Event = ClashAPI.StableFallbackStatus['events'][number];
const DAY_MS = 24 * 60 * 60 * 1000;
const count = (value: number) =>
  Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0;

export function recentFallbackEvents(
  events?: Event[] | null,
  now = Date.now(),
) {
  return (events || [])
    .filter(
      (event) =>
        Number.isFinite(Date.parse(event.at)) &&
        Date.parse(event.at) >= now - DAY_MS,
    )
    .sort((a, b) => Date.parse(a.at) - Date.parse(b.at))
    .slice(-50);
}

export function lastFallbackSwitch(events: Event[]) {
  return [...events]
    .reverse()
    .find((event) => event.from && event.to && event.from !== event.to);
}

export function observationSummary(
  status: ClashAPI.StableFallbackStatus,
  now = Date.now(),
) {
  const stats = status.stats;
  if (!stats) return null;
  return {
    since: stats.since,
    selectedSeconds: count((now - Date.parse(stats.selected_since)) / 1000),
    switches: count(stats.switches_total),
    backupSeconds: count(stats.backup_seconds),
    connectionErrors: stats.members.reduce(
      (sum, member) => sum + count(member.connection_errors),
      0,
    ),
    failedChecks: stats.members.reduce(
      (sum, member) => sum + count(member.failed_checks),
      0,
    ),
  };
}

export function fallbackStateLabel(state: string) {
  switch (state) {
    case 'primary':
      return _('Primary');
    case 'backup':
      return _('Backup');
    case 'suspect':
      return _('Suspected failure');
    case 'no_network':
      return _('No network');
    case 'degraded':
      return _('Degraded');
    default:
      return _('Not checked');
  }
}

function checkReason(reason?: string) {
  switch (reason) {
    case 'periodic':
      return _('Scheduled check');
    case 'dial_failure':
      return _('Check after a connection error');
    case 'recovery':
      return _('Recovery check');
    case 'confirmation':
      return _('Repeated failure confirmation');
    default:
      return '';
  }
}

export function observationPeriod(since: string, now = Date.now()) {
  const seconds = count((now - Date.parse(since)) / 1000);
  return { fullDay: seconds >= 86400, seconds: Math.min(86400, seconds) };
}

function metric(label: string, value: string | number, warning = false) {
  return E(
    'div',
    {
      class: `kaban-observation__metric${warning ? ' kaban-observation__metric--warning' : ''}`,
    },
    [
      E('span', { class: 'kaban-observation__metric-label' }, label),
      E('strong', { class: 'kaban-observation__metric-value' }, String(value)),
    ],
  );
}

export function renderFallbackObservation(info: KabanMax.FallbackInfo) {
  const status = info.stableStatus;
  if (!status?.stats) return [];
  const summary = observationSummary(status)!;
  const period = observationPeriod(summary.since);
  const selected = info.outbounds.find(
    (member) => member.code === status.active,
  );
  return [
    E('section', { class: 'kaban-observation' }, [
      E('header', { class: 'kaban-observation__heading' }, [
        E('div', {}, [
          E('h4', {}, _('Connection overview')),
          E(
            'span',
            { class: 'kaban-observation__period' },
            period.fullDay
              ? _('Last 24 hours')
              : `${_('Since start')} · ${formatDuration(period.seconds)}`,
          ),
        ]),
        E(
          'span',
          {
            class: `kaban-observation__state kaban-observation__state--${status.state}`,
          },
          fallbackStateLabel(status.state),
        ),
      ]),
      E('div', { class: 'kaban-observation__selected' }, [
        E('span', { class: 'kaban-observation__dot', 'aria-hidden': 'true' }),
        E('strong', {}, selected?.displayName || status.active || '—'),
        E(
          'span',
          {},
          `${_('Selected for')} ${formatDuration(Math.min(summary.selectedSeconds, period.seconds))}`,
        ),
      ]),
      ...(status.check_state === 'probe_only_failure'
        ? [
            E(
              'p',
              { class: 'kaban-observation__probe-notice' },
              _(
                'Health checks failed, but a new connection received data. Server selection was kept.',
              ),
            ),
          ]
        : []),
      E('div', { class: 'kaban-observation__metrics' }, [
        metric(_('Switches'), summary.switches),
        metric(_('Time on backup'), formatDuration(summary.backupSeconds)),
        metric(
          _('Connection errors'),
          summary.connectionErrors,
          summary.connectionErrors > 0,
        ),
        metric(
          _('Check failures'),
          summary.failedChecks,
          summary.failedChecks > 0,
        ),
      ]),
    ]),
  ];
}

export function renderMemberObservation(
  info: KabanMax.FallbackInfo,
  code: string,
) {
  const member = info.stableStatus?.stats?.members.find(
    (item) => item.name === code,
  );
  if (!member) return [];
  const item = (label: string, value: string | number, warning = false) =>
    E(
      'span',
      {
        class: warning
          ? 'kaban-observation__node-stat kaban-observation__node-stat--warning'
          : 'kaban-observation__node-stat',
      },
      [E('span', {}, `${label} `), E('b', {}, String(value))],
    );
  return [
    E('div', { class: 'kaban-observation__node-stats' }, [
      item(_('Selected for'), formatDuration(count(member.selected_seconds))),
      item(
        _('Connection errors'),
        count(member.connection_errors),
        member.connection_errors > 0,
      ),
      item(
        _('Check failures'),
        count(member.failed_checks),
        member.failed_checks > 0,
      ),
      item(_('Switches'), count(member.switches_away)),
    ]),
  ];
}

export function renderFallbackEvents(info: KabanMax.FallbackInfo) {
  if (!info.stableStatus?.stats) return [];
  const events = recentFallbackEvents(info.stableStatus.events);
  const name = (code: string) =>
    info.outbounds.find((member) => member.code === code)?.displayName ||
    code.split('/').pop() ||
    code;
  return [
    E('details', { class: 'kaban-observation__events' }, [
      E('summary', {}, [
        E('span', {}, _('Recent events (up to 24 hours)')),
        E(
          'span',
          { class: 'kaban-observation__event-count' },
          String(events.length),
        ),
      ]),
      events.length
        ? E(
            'ol',
            { class: 'kaban-observation__timeline' },
            [...events].reverse().map((event) =>
              E('li', {}, [
                E(
                  'time',
                  {
                    dateTime: event.at,
                    title: new Date(event.at).toLocaleString(),
                  },
                  new Date(event.at).toLocaleTimeString([], {
                    hour: '2-digit',
                    minute: '2-digit',
                  }),
                ),
                E('div', {}, [
                  E(
                    'strong',
                    {},
                    event.from && event.to && event.from !== event.to
                      ? `${name(event.from)} → ${name(event.to)}`
                      : checkReason(event.check_reason) || _('Check'),
                  ),
                  E(
                    'span',
                    { class: 'kaban-observation__event-reason' },
                    event.reason,
                  ),
                ]),
              ]),
            ),
          )
        : E('p', { class: 'kaban-observation__empty' }, _('No recent events')),
    ]),
  ];
}
