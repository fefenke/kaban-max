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

export function renderFallbackObservation(info: KabanMax.FallbackInfo) {
  const status = info.stableStatus;
  if (!status?.stats) return [];
  const summary = observationSummary(status)!;
  const events = recentFallbackEvents(status.events);
  const name = (code: string) =>
    info.outbounds.find((member) => member.code === code)?.displayName ||
    code.split('/').pop() ||
    code;
  const row = (label: string, value: string | number) =>
    E(
      'div',
      {
        style:
          'display:flex;justify-content:space-between;gap:12px;padding:3px 0',
      },
      [E('span', {}, label), E('strong', {}, String(value))],
    );
  return [
    E(
      'section',
      {
        class: 'fkp-fallback-observation',
        style: 'margin:14px 0;overflow-x:auto',
      },
      [
        E('h4', {}, _('Observation')),
        row(_('Observation since'), new Date(summary.since).toLocaleString()),
        row(
          _('Current selection duration'),
          formatDuration(summary.selectedSeconds),
        ),
        row(_('Switches during observation'), summary.switches),
        row(_('Time on backup'), formatDuration(summary.backupSeconds)),
        row(_('Failed check rounds'), summary.failedChecks),
        row(_('Connection opening errors'), summary.connectionErrors),
        E('table', { style: 'width:100%;margin-top:8px' }, [
          E(
            'thead',
            {},
            E(
              'tr',
              {},
              [
                _('Node'),
                _('Time selected'),
                _('Failed check rounds'),
                _('Connection opening errors'),
                _('Switches away'),
              ].map((text) => E('th', {}, text)),
            ),
          ),
          E(
            'tbody',
            {},
            status.stats.members.map((member) =>
              E(
                'tr',
                {},
                [
                  name(member.name),
                  formatDuration(member.selected_seconds),
                  member.failed_checks,
                  member.connection_errors,
                  member.switches_away,
                ].map((value) => E('td', {}, String(value))),
              ),
            ),
          ),
        ]),
        E('details', { style: 'margin-top:10px' }, [
          E('summary', {}, _('Recent events (up to 24 hours)')),
          events.length
            ? E(
                'ol',
                { style: 'padding-left:20px' },
                [...events]
                  .reverse()
                  .map((event) =>
                    E('li', { style: 'padding:4px 0' }, [
                      E('time', {}, new Date(event.at).toLocaleString()),
                      ` · ${checkReason(event.check_reason)}${event.check_reason ? ' · ' : ''}`,
                      event.from && event.to && event.from !== event.to
                        ? `${name(event.from)} → ${name(event.to)} · `
                        : '',
                      event.reason,
                    ]),
                  ),
              )
            : E('p', {}, _('No recent events')),
        ]),
      ],
    ),
  ];
}
