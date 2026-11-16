import { renderAutoRecords } from './autoRecords';
import { callUbus } from '../../../helpers/callUbus';
import { KABANMAX_UCI_PACKAGE } from '../../../constants';

export interface AutoEntry {
  failure?: { id: string; source_id: string; message: string; at: string };
  ip_only?: boolean;
  attempts?: { outbound: string; status: string; reason?: string }[];
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
    ((row.domain_known === true && !!row.domain) || row.ip_only === true) &&
    Date.parse(row.expires || '') > now
  );
}

export function statusText(status: string): string {
  const labels: Record<string, string> = {
    observing: _('Needs verification'),
    detected: _('Needs verification'),
    checking: _('Checking'),
    inconclusive: _('Insufficient evidence'),
    identity_unknown: _('Needs verification'),
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
    row.source_id
      ? row.source_id === sectionId && (!row.source || row.source === tag)
      : !!tag && row.source === tag;
  return {
    candidates: state.candidates
      .filter(owned)
      .filter((row) => row.failure?.source_id === sectionId),
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

export { renderAutoRecords as renderAutoRouting } from './autoRecords';

export function attachAutoRouting(section: CBISection) {
  section.tab('auto_routing', _('Automatic routing'));
  for (const [key, label, defaultValue] of [
    ['auto_routing_enabled', _('Enable automatic routing'), '0'],
    ['auto_routing_direct', 'Direct', '0'],
    ['auto_routing_use_warp', _('WARP'), '1'],
    ['auto_routing_apply', _('Apply automatically'), '0'],
    ['auto_routing_ip_only', _('Allow redirecting IPs without a domain'), '0'],
  ]) {
    const option = section.taboption('auto_routing', form.Flag, key, label);
    option.modalonly = true;
    option.depends('action', 'zapret2');
    option.default = defaultValue;
    option.retain = true;
    if (key === 'auto_routing_direct')
      option.description = _(
        'Check Direct as an alternative for failed connections in this section.',
      );
    if (key === 'auto_routing_use_warp')
      option.description = _(
        'Check the selected WARP profile as an alternative for failed connections in this section.',
      );
    if (key === 'auto_routing_use_warp')
      option.load = (id) =>
        uci.get(KABANMAX_UCI_PACKAGE, id, key) ??
        (uci.get(KABANMAX_UCI_PACKAGE, id, 'auto_routing_warp') ? '1' : '0');
    if (key === 'auto_routing_apply')
      option.description = _(
        'Verify logged failures in this section and automatically apply a working permitted route. Save & Apply activates changes.',
      );
    if (key === 'auto_routing_ip_only') {
      option.description = _(
        'Also allow automatic routing for IP-only connections after verified HTTPS content and a valid certificate for that IP. A TCP connection alone is not enough.',
      );
    }
  }
  const contract = section.taboption(
    'auto_routing',
    form.TextValue,
    'auto_routing_contract',
    _('HTTPS verification settings'),
  );
  contract.modalonly = true;
  contract.depends('action', 'zapret2');
  contract.retain = true;
  contract.rows = 3;
  contract.description = _(
    'Leave empty for standard HTTPS verification. Strict nonce contracts are preserved.',
  );
  contract.validate = (_id, value) => {
    if (!value.trim()) return true;
    try {
      const v = JSON.parse(value);
      return v && typeof v === 'object' && !Array.isArray(v)
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
    _('WARP profile'),
  );
  warp.modalonly = true;
  warp.depends({ action: 'zapret2', auto_routing_use_warp: '1' });
  warp.retain = true;
  warp.value('', _('Select a WARP profile'));
  warp.load = async function (id) {
    const snapshot = await autoState().catch(() => emptyState);
    const selected = String(
      uci.get(KABANMAX_UCI_PACKAGE, id, 'auto_routing_warp') || '',
    );
    this.keylist = [''];
    this.vallist = [_('Select a WARP profile')];
    for (const profile of new Set([
      ...(snapshot.warp_profiles || []),
      ...(selected ? [selected] : []),
    ]))
      this.value(profile, profile);
    return selected;
  };
  const list = section.taboption(
    'auto_routing',
    form.DummyValue,
    '_automatic_routes',
    _('Found IPs'),
  );
  list.modalonly = true;
  list.description = _(
    'Up to 64 records per list. Saved approvals are inactive until fresh verification; bulk actions use the entire current filter.',
  );
  list.depends('action', 'zapret2');
  list.write = () => undefined;
  list.remove = () => undefined;
  list.renderWidget = (id) => renderAutoRecords(id);
}
