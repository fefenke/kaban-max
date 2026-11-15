import { E } from '../../../helpers/element';
import { callUbus } from '../../../helpers/callUbus';
import { KABANMAX_UCI_PACKAGE } from '../../../constants';

export interface AutoEntry {
  id?: string;
  ip: string;
  domain?: string;
  domain_known?: boolean;
  evidence?: string;
  apply_allowed?: boolean;
  auto_apply_eligible?: boolean;
  source?: string;
  source_id?: string;
  source_ip?: string;
  source_port?: number;
  inbound?: string;
  port?: number;
  network?: string;
  target?: string;
  target_section?: string;
  status: string;
  reason?: string;
  created?: string;
  expires?: string;
  count?: number;
}
export interface AutoState {
  version?: number;
  reason?: string;
  sources: { id: string; outbound: string }[];
  candidates: AutoEntry[];
  unattributed: AutoEntry[];
  leases: AutoEntry[];
  decisions: AutoEntry[];
  history: AutoEntry[];
  warp_profiles?: string[];
  suppressed_count?: number;
  suppressed_counts?: Record<string, number>;
  disabled_sources?: string[];
  suppression_error?: string;
}
const emptyState: AutoState = {
  sources: [],
  candidates: [],
  unattributed: [],
  leases: [],
  decisions: [],
  history: [],
};

export function canApply(row: AutoEntry, now = Date.now()): boolean {
  return (
    row.status === 'proposed' &&
    row.apply_allowed === true &&
    row.domain_known === true &&
    !!row.domain &&
    Date.parse(row.expires || '') > now
  );
}

function evidenceText(evidence: string): string {
  const labels: Record<string, string> = {
    healthy: _('Original HTTPS resource responds; no change'),
    suspected_failure: _('Repeated transport failure; blocking is not proven'),
    alternative_reachable: _(
      'Alternative HTTPS response verified; manual confirmation only',
    ),
    verified_for_apply: _(
      'Strict application contract verified; eligible for automatic application',
    ),
    transport_diagnostic: _(
      'TCP diagnostic only; application identity unknown',
    ),
  };
  return labels[evidence] || _('Insufficient evidence');
}

export function statusText(status: string): string {
  const labels: Record<string, string> = {
    observing: _('Detected'),
    detected: _('Detected'),
    checking: _('Checking'),
    inconclusive: _('Insufficient evidence'),
    identity_unknown: _('Insufficient evidence'),
    unattributed: _('Source section not established'),
    proposed: _('Proposed'),
    applied: _('Applied'),
    unchanged: _('Zapret2 verified; no change'),
    expired: _('Expired'),
    removed: _('Removed'),
    rolled_back: _('Rolled back'),
    rechecked: _('Rechecked'),
    replaced: _('Replaced'),
    closed: _('Connection closed'),
    blocked_by_policy: _('Forbidden by policy'),
  };
  return labels[status] || _('See diagnostic details');
}

function reasonText(reason: string): string {
  if (reason === 'original_https_inconclusive')
    return _(
      'Original HTTPS checks are inconclusive; no route change is authorized',
    );
  if (reason === 'repeated_transport_failure_alternative_reachable')
    return _(
      'The same IP and hostname responded through the alternative; this does not prove DPI',
    );
  if (reason === 'actual_destination_ip_unknown')
    return _(
      'The actual dialled IP is unknown; other DNS addresses will not be checked',
    );
  if (reason === 'original_flow_not_attested')
    return _('No matching original flow attests this IP and identity');
  if (
    [
      'identity_unknown',
      'no_connection_identity',
      'connection_error_without_identity',
    ].includes(reason)
  )
    return _('Destination identity is not established');
  if (['first_match_changed', 'first_match_not_routable'].includes(reason))
    return _('A different rule wins; no automatic change');
  if (reason === 'source_mark_unattributed')
    return _('The source is not an attested Zapret2 route');
  if (reason === 'probe_scope_requires_connection_metadata')
    return _('Earlier rules require unavailable connection metadata');
  if (reason === 'original_failure_unproven')
    return _('The application failure contract was not confirmed');
  if (reason.startsWith('dns_'))
    return _('DNS evidence is unavailable, changed or expired');
  if (reason === 'suppressed') return _('Excluded by the user');
  if (reason === 'udp_not_supported')
    return _('UDP is observed but is not checked by this HTTPS mechanism');
  if (reason === 'connection_error' || reason === 'no_progress')
    return _(
      'A connection problem was observed; application verification is required',
    );
  if (reason.includes('infrastructure'))
    return _('Infrastructure protection forbids this check');
  if (reason === 'verified_alternative_after_contract_failure')
    return _('The alternative passed the configured application contract');
  return reason ? _('See diagnostic details') : '';
}

export async function autoState(): Promise<AutoState> {
  const reply = await callUbus<Partial<AutoState>>({
    object: 'kabanmax',
    method: 'auto_state',
    timeoutMs: 15000,
  });
  if (!reply.success) throw new Error(reply.message);
  const result = { ...emptyState, ...reply.data };
  for (const key of [
    'sources',
    'candidates',
    'unattributed',
    'leases',
    'decisions',
    'history',
  ] as const) {
    if (!Array.isArray(result[key])) result[key] = [];
  }
  return result;
}
export async function autoAction(
  op: 'probe' | 'apply' | 'delete' | 'clear' | 'reset' | 'disable',
  id: string,
) {
  const reply = await callUbus<{ success: boolean; message?: string }>({
    object: 'kabanmax',
    method: 'auto_action',
    params: { op, id },
    timeoutMs: 75000,
    retryUnavailable: false,
  });
  if (!reply.success) throw new Error(reply.message);
  if (!reply.data.success)
    throw new Error(reply.data.message || _('Automatic routing action failed'));
  return reply.data;
}
export function sourceRows(state: AutoState, sectionId: string) {
  const tag = state.sources.find((source) => source.id === sectionId)?.outbound;
  const owned = (row: AutoEntry) =>
    row.source_id === sectionId || (!!tag && row.source === tag);
  return {
    candidates: [...state.candidates.filter(owned), ...state.unattributed],
    leases: state.leases.filter(owned),
    decisions: state.decisions
      .filter(owned)
      .filter((row) => row.status === 'proposed'),
    results: state.decisions
      .filter(owned)
      .filter((row) => row.status !== 'proposed'),
    history: state.history.filter(owned),
  };
}
export function targetRows(state: AutoState, sectionId: string, tag: string) {
  return state.leases.filter(
    (row) =>
      row.target_section === sectionId ||
      (row.target !== 'direct-out' && row.target?.startsWith(`${tag}/`)),
  );
}

export function renderAutoRouting(sectionId: string) {
  const root = E('div', {}, []);
  const body = E(
    'div',
    {},
    _('Refresh to view backend candidates and temporary routes.'),
  );
  const message = E('p', {}, '');
  const source =
    uci.get(KABANMAX_UCI_PACKAGE, sectionId, 'action') === 'zapret2';
  let state = emptyState;
  let busy = false;
  const tag = () =>
    state.sources.find((s) => s.id === sectionId)?.outbound ||
    String(uci.get(KABANMAX_UCI_PACKAGE, sectionId, 'label') || sectionId);
  const run = async (op?: Parameters<typeof autoAction>[0], id?: string) => {
    if (busy) return;
    busy = true;
    message.textContent = '…';
    try {
      if (op && id) await autoAction(op, id);
      state = await autoState();
      body.replaceChildren();
      if (source) {
        const rows = sourceRows(state, sectionId);
        const processed = new Set(
          [...rows.leases, ...rows.decisions, ...rows.results, ...rows.history]
            .map((row) => row.ip)
            .filter(Boolean),
        ).size;
        body.appendChild(
          E(
            'p',
            {},
            `${_('Candidates')}: ${rows.candidates.length}; ${_('Processed IPs (recent results)')}: ${processed}; ${_('Active')}: ${rows.leases.length}; ${_('Suppressed')}: ${state.suppressed_counts?.[sectionId] ?? 0}`,
          ),
        );
        for (const [title, entries] of [
          [_('Candidates'), rows.candidates],
          [_('Active redirects'), rows.leases],
          [_('Proposals'), rows.decisions],
          [_('Check results'), rows.results],
          [_('History'), rows.history],
        ] as const) {
          body.appendChild(E('h4', {}, title));
          body.appendChild(table(entries));
        }
      } else {
        body.appendChild(E('h4', {}, _('Added automatically')));
        body.appendChild(table(targetRows(state, sectionId, tag())));
      }
      message.textContent = state.version
        ? _(
            'Temporary routes are scoped inside the original Zapret2 section. No manual entries are changed.',
          )
        : state.reason ||
          _(
            'Enable automatic routing in a Zapret2 section and apply with the test core.',
          );
      if (state.disabled_sources?.includes(tag()))
        message.textContent = _(
          'Stopped until the next configuration apply. Disable the section option and Save & Apply to persist this choice.',
        );
      if (state.suppression_error)
        message.textContent = state.suppression_error;
    } catch (error) {
      message.textContent =
        error instanceof Error ? error.message : String(error);
    } finally {
      busy = false;
    }
  };
  const button = (
    label: string,
    op?: Parameters<typeof autoAction>[0],
    id?: string,
    disabled = false,
  ) =>
    E(
      'button',
      {
        type: 'button',
        class: 'cbi-button',
        disabled,
        click: () => run(op, id),
      },
      label,
    );
  function table(entries: AutoEntry[]) {
    return E('table', { class: 'table' }, [
      E(
        'tr',
        {},
        [
          'IP',
          _('Domain'),
          _('Source'),
          _('Route'),
          _('Status'),
          _('Evidence'),
          _('Created'),
          _('Expires'),
          _('Details'),
        ].map((text) => E('th', {}, text)),
      ),
      ...entries.map((row) =>
        E('tr', {}, [
          E(
            'td',
            {},
            `${row.ip || '—'}:${row.port ?? '—'} (${row.network || 'tcp'})`,
          ),
          E('td', {}, row.domain || _('Not established')),
          E(
            'td',
            {},
            `${row.source || _('Unattributed')} / ${row.source_ip || '—'}`,
          ),
          E('td', {}, row.target || '—'),
          E(
            'td',
            {},
            `${statusText(row.status)}. ${reasonText(row.reason || '')}`,
          ),
          E('td', {}, [
            evidenceText(row.evidence || ''),
            ...(row.status === 'proposed' && !canApply(row)
              ? [
                  E(
                    'p',
                    {},
                    _(
                      'Apply unavailable: identity, permission or validity period is not confirmed',
                    ),
                  ),
                ]
              : []),
          ]),
          E(
            'td',
            {},
            row.created ? new Date(row.created).toLocaleString() : '—',
          ),
          E(
            'td',
            {},
            row.expires ? new Date(row.expires).toLocaleString() : '—',
          ),
          E('td', {}, [
            E('details', {}, [
              E('summary', {}, _('Details')),
              E('pre', {}, JSON.stringify(row, null, 2)),
            ]),
            ...(row.id && row.status === 'proposed'
              ? [
                  button(_('Apply'), 'apply', row.id, !canApply(row)),
                  button(_('Delete'), 'delete', row.id),
                ]
              : []),
            ...(row.id &&
            row.status === 'applied' &&
            state.leases.some((active) => active.id === row.id)
              ? [button(_('Delete'), 'delete', row.id)]
              : []),
            ...(row.id &&
            row.source &&
            row.network === 'tcp' &&
            !['applied', 'proposed'].includes(row.status)
              ? [button(_('Check'), 'probe', row.id)]
              : []),
          ]),
        ]),
      ),
    ]);
  }
  root.appendChild(
    E('h3', {}, source ? _('Automatic routing') : _('Added automatically')),
  );
  root.appendChild(button(_('Refresh')));
  if (source) {
    root.appendChild(
      E(
        'p',
        {},
        _(
          'Deleting a route withdraws it and stores persistent suppression. Reset suppression to allow automatic selection again.',
        ),
      ),
    );
    root.appendChild(
      E(
        'button',
        {
          type: 'button',
          class: 'cbi-button',
          click: () => run('clear', sectionId),
        },
        _('Clear automatic list'),
      ),
    );
    root.appendChild(
      E(
        'button',
        {
          type: 'button',
          class: 'cbi-button',
          click: () => run('reset', sectionId),
        },
        _('Reset suppression'),
      ),
    );
    root.appendChild(
      E(
        'button',
        {
          type: 'button',
          class: 'cbi-button',
          click: () => run('disable', sectionId),
        },
        _('Stop automatic routing now'),
      ),
    );
  }
  root.appendChild(message);
  root.appendChild(body);
  return root;
}

export function attachAutoRouting(section: CBISection) {
  section.tab('auto_routing', _('Automatic routing'));
  for (const [key, label, defaultValue] of [
    ['auto_routing_enabled', _('Enable automatic routing'), '0'],
    ['auto_routing_probe_zapret', _('Allow Zapret2 probes'), '1'],
    ['auto_routing_direct', _('Allow Direct probes'), '0'],
    [
      'auto_routing_apply',
      _('Apply verified temporary routes automatically'),
      '0',
    ],
  ]) {
    const option = section.taboption('auto_routing', form.Flag, key, label);
    option.modalonly = true;
    option.depends('action', 'zapret2');
    option.default = defaultValue;
    option.retain = true;
  }
  const contract = section.taboption(
    'auto_routing',
    form.TextValue,
    'auto_routing_contract',
    _('HTTPS verification settings'),
    _(
      'Leave empty for ordinary HTTPS checks on port 443 using the trusted flow hostname and GET /. These checks only propose scoped routes for manual confirmation, even when automatic application is enabled. Optional JSON mode web configures path, port, status and content prefix. Existing nonce contracts use mode strict and can qualify for automatic application. Timeout is not proof of DPI; UDP is not verified. Save & Apply may interrupt TCP connections.',
    ),
  );
  contract.modalonly = true;
  contract.depends('action', 'zapret2');
  contract.retain = true;
  contract.rows = 5;
  contract.placeholder = '{"mode":"web","path":"/","port":443,"status":200}';
  contract.validate = (_sectionId, value) => {
    if (!value.trim()) return true;
    try {
      const parsed = JSON.parse(value);
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
        ? true
        : _('Expected a JSON object');
    } catch {
      return _('Expected a JSON object');
    }
  };
  const warp = section.taboption(
    'auto_routing',
    form.ListValue,
    'auto_routing_warp',
    _('WARP profile for automatic routing'),
  );
  warp.modalonly = true;
  warp.depends('action', 'zapret2');
  warp.retain = true;
  warp.value('', _('Do not use WARP'));
  warp.load = async function (sectionId: string) {
    const snapshot = await autoState().catch(() => emptyState);
    for (const profile of snapshot.warp_profiles || [])
      this.value(profile, profile);
    return uci.get(KABANMAX_UCI_PACKAGE, sectionId, 'auto_routing_warp') || '';
  };
  const direct = section.taboption(
    'auto_routing',
    form.ListValue,
    'auto_routing_direct_section',
    _('Show Direct routes in Bypass section'),
  );
  direct.modalonly = true;
  direct.depends('action', 'zapret2');
  direct.retain = true;
  direct.value('', _('Direct without a section'));
  for (const entry of uci.sections(KABANMAX_UCI_PACKAGE, 'section') || []) {
    if (entry.action === 'bypass')
      direct.value(entry['.name'], String(entry.label || entry['.name']));
  }
  const list = section.taboption(
    'auto_routing',
    form.DummyValue,
    '_automatic_routes',
    _('Automatic IP records'),
  );
  list.modalonly = true;
  list.write = () => undefined;
  list.remove = () => undefined;
  list.renderWidget = (sectionId: string) => renderAutoRouting(sectionId);
}
