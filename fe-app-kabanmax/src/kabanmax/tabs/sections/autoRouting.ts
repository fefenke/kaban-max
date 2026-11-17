import { renderAutoRecords } from './autoRecords';
import { callUbus } from '../../../helpers/callUbus';
import { KABANMAX_UCI_PACKAGE } from '../../../constants';
import { showToast } from '../../../helpers/showToast';
import { currentOptionValue } from './subscriptions/model';

export interface AutoEntry {
  domains?: string[];
  new_error?: boolean;
  all_ports?: boolean;
  error_port?: number;
  uncovered_connections?: number;
  persistent_ip?: boolean;
  failure?: { id: string; source_id: string; message: string; at: string };
  ip_only?: boolean;
  attempts?: { outbound: string; status: string; reason?: string }[];
  id?: string;
  ip: string;
  domain?: string;
  observed_domain?: string;
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
  target_name?: string;
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
  warp_sections?: { id: string; name: string; outbound: string }[];
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

export function routeText(row: AutoEntry): string {
  const target = row.target || row.source;
  if (target === 'direct-out') return 'Direct';
  return (row.target && row.target_name) || target || '—';
}

export function recordStateText(row: AutoEntry): string {
  if (row.status === 'applied' && row.uncovered_connections)
    return _('Some connections are not covered by this rule');
  if (row.status === 'applied' && row.new_error && row.error_port)
    return `${_('New connection error on port')}: ${row.error_port}`;
  if (row.status === 'applied')
    return row.new_error
      ? _('New connection error detected')
      : _('No new errors');
  if (row.status === 'saved') return _('Saved route is not active');
  if (row.reason === 'protocol_unconfirmed')
    return _('Protocol operation is unconfirmed');
  if (row.status === 'proposed')
    return `${_('Working alternative found')}: ${routeText(row)}`;
  if (row.reason?.startsWith('checking:')) {
    const target = row.reason.slice('checking:'.length);
    return `${_('Checking')}: ${target === 'direct-out' ? 'Direct' : target}`;
  }
  if (row.status === 'checking')
    return _('Searching for a working alternative…');
  if (
    row.reason === 'cancelled_generation' ||
    ['detected', 'observing'].includes(row.status || '')
  )
    return _('Queued for automatic checking');
  if (row.status === 'excluded') return _('Excluded');
  if (row.status === 'removed') return _('Removed');
  return _('No working alternative found');
}

let stateReading: Promise<AutoState> | undefined;
export function autoState(): Promise<AutoState> {
  return (stateReading ||= readAutoState().finally(() => {
    stateReading = undefined;
  }));
}
async function readAutoState(): Promise<AutoState> {
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
    if (key === 'auto_routing_enabled') {
      const prerequisite = () =>
        String(
          currentOptionValue(option, 'settings', 'yacd_secret_key') || '',
        ).trim()
          ? true
          : _(
              'Set a Clash API key in Settings before enabling automatic routing. YACD WAN access is not required.',
            );
      option.validate = (_id, value) => (value === '1' ? prerequisite() : true);
      option.onchange = function (_event, id, value) {
        if (value !== '1') return;
        const result = prerequisite();
        if (result === true) return;
        this.getUIElement(id)?.setValue('0');
        showToast(result, 'error', 8000);
      };
    }
    if (key === 'auto_routing_direct')
      option.description = _(
        'Check Direct as an alternative for failed connections in this section.',
      );
    if (key === 'auto_routing_use_warp')
      option.description = _(
        'Use the selected section as configured, without matching its destination lists.',
      );
    if (key === 'auto_routing_use_warp')
      option.load = (id) =>
        uci.get(KABANMAX_UCI_PACKAGE, id, key) ??
        (uci.get(KABANMAX_UCI_PACKAGE, id, 'auto_routing_warp_section') ||
        uci.get(KABANMAX_UCI_PACKAGE, id, 'auto_routing_warp')
          ? '1'
          : '0');
    if (key === 'auto_routing_apply')
      option.description = _(
        'Verify logged failures in this section and automatically apply a working permitted route. Save & Apply activates changes.',
      );
    if (key === 'auto_routing_ip_only') {
      option.description = _(
        'Automatically apply verified IP-only proposals too. Manual IP-only proposals do not require this preference.',
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
    'auto_routing_warp_section',
    _('Alternative section'),
  );
  warp.modalonly = true;
  warp.depends({ action: 'zapret2', auto_routing_use_warp: '1' });
  warp.retain = true;
  warp.value('', _('Select a section'));
  warp.load = async function (id) {
    const snapshot = await autoState().catch(() => emptyState);
    const legacy = String(
      uci.get(KABANMAX_UCI_PACKAGE, id, 'auto_routing_warp') || '',
    );
    const selected = String(
      uci.get(KABANMAX_UCI_PACKAGE, id, 'auto_routing_warp_section') ||
        snapshot.warp_sections?.find(
          (item) =>
            legacy.startsWith(`${item.outbound}/`) || legacy === item.outbound,
        )?.id ||
        '',
    );
    this.keylist = [''];
    this.vallist = [_('Select a section')];
    for (const item of snapshot.warp_sections || [])
      this.value(item.id, item.name);
    if (selected && !this.keylist.includes(selected))
      this.value(selected, selected);
    return selected;
  };
  warp.write = (id, value) => {
    uci.set(
      KABANMAX_UCI_PACKAGE,
      id,
      'auto_routing_warp_section',
      String(value ?? ''),
    );
    uci.unset(KABANMAX_UCI_PACKAGE, id, 'auto_routing_warp');
  };
  warp.remove = (id) => {
    uci.unset(KABANMAX_UCI_PACKAGE, id, 'auto_routing_warp_section');
    uci.unset(KABANMAX_UCI_PACKAGE, id, 'auto_routing_warp');
  };
  const list = section.taboption(
    'auto_routing',
    form.DummyValue,
    '_automatic_routes',
    _('Found IPs'),
  );
  list.modalonly = true;
  list.description = _(
    'One record per IP, with its observed domains. Disabling collection keeps manual actions available. Routing changes are saved to flash in batches every 15 minutes.',
  );
  list.depends('action', 'zapret2');
  list.write = () => undefined;
  list.remove = () => undefined;
  list.renderWidget = (id) => renderAutoRecords(id);
}
