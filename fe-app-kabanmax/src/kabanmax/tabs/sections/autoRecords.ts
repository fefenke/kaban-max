import { E } from '../../../helpers/element';
import { callUbus } from '../../../helpers/callUbus';
import {
  canApply,
  routeText,
  recordStateText,
  type AutoEntry,
} from './autoRouting';

export interface RecordQuery {
  source_section: string;
  status: string;
  search: string;
  sort: string;
  page: number;
  page_size: number;
}
export interface BatchResult {
  done: number;
  skipped: number;
  failed: number;
  results: { id: string; status: string; reason?: string }[];
}
type RecordAction =
  | 'apply'
  | 'exclude'
  | 'remove'
  | 'forget'
  | 'recheck'
  | 'dismiss';
interface RecordPage {
  rows: AutoEntry[];
  total: number;
  page: number;
  counts: Record<string, number>;
  version: number;
  reason?: string;
  warning?: string;
  legacy_overflow?: boolean;
  bulk_supported?: boolean;
  selection?: { id: string; eligible: boolean }[];
}

export function registryNotice(message = ''): string {
  return message.includes('automatic_routing_unavailable') ? '' : message;
}

export function confirmRecordAction(
  label: string,
  count: number,
): Promise<boolean> {
  return new Promise((resolve) => {
    const previous = document.activeElement as HTMLElement | null;
    const dialog = E('dialog', { class: 'km-record-confirm' }, [
      E('h3', {}, label),
      E('p', {}, `${_('Selected records')}: ${count}`),
    ]) as HTMLDialogElement;
    const finish = (accepted: boolean) => {
      dialog.close();
      dialog.remove();
      previous?.focus();
      resolve(accepted);
    };
    dialog.append(
      E('div', { class: 'km-record-confirm__actions' }, [
        E(
          'button',
          { type: 'button', class: 'cbi-button', click: () => finish(false) },
          _('Cancel'),
        ),
        E(
          'button',
          {
            type: 'button',
            class: 'cbi-button cbi-button-action',
            click: () => finish(true),
          },
          label,
        ),
      ]),
    );
    dialog.addEventListener('cancel', (event) => {
      event.preventDefault();
      finish(false);
    });
    document.body.append(dialog);
    dialog.showModal();
  });
}
export async function autoRecords(query: RecordQuery): Promise<RecordPage> {
  const reply = await callUbus<RecordPage>({
    object: 'kabanmax',
    method: 'auto_records',
    params: { ...query },
    timeoutMs: 15000,
  });
  if (!reply.success) throw new Error(reply.message);
  return reply.data;
}
export async function registryAction(
  query: RecordQuery,
  action: RecordAction,
  ids: string[],
): Promise<BatchResult> {
  const selected = [...new Set(ids)];
  if (selected.length > 64) throw new Error(_('Select at most 64 records'));
  const result: BatchResult = { done: 0, skipped: 0, failed: 0, results: [] };
  for (let offset = 0; offset < selected.length; offset += 8) {
    const chunk = selected.slice(offset, offset + 8);
    try {
      const reply = await callUbus<
        BatchResult & { success: boolean; message?: string }
      >({
        object: 'kabanmax',
        method: 'auto_action',
        params: {
          op: 'records',
          id: JSON.stringify({ ...query, action, ids: chunk }),
        },
        timeoutMs: 185000,
        retryUnavailable: false,
      });
      if (!reply.success) throw new Error(reply.message);
      if (!reply.data.success)
        throw new Error(reply.data.message || _('Registry action failed'));
      result.done += reply.data.done;
      result.skipped += reply.data.skipped;
      result.failed += reply.data.failed;
      result.results.push(...reply.data.results);
    } catch (error) {
      result.failed += chunk.length;
      result.results.push(
        ...chunk.map((id) => ({
          id,
          status: 'failed',
          reason: error instanceof Error ? error.message : String(error),
        })),
      );
    }
  }
  return result;
}
export function renderAutoRecords(sectionId: string) {
  const root = E('div', { class: 'km-records' }, []);
  const message = E('p', { class: 'km-records__message' }, _('Loading…'));
  message.setAttribute('aria-live', 'polite');
  const outcome = E('p', {}, '');
  outcome.setAttribute('aria-live', 'polite');
  const tabs = E('div', { class: 'km-records__tools', role: 'group' }, []);
  const actions = E('div', { class: 'km-records__tools' }, []);
  const body = E('div', {}, []);
  const pages = E('div', { class: 'km-records__pages' }, []);
  const query: RecordQuery = {
    source_section: sectionId,
    status: 'pending',
    search: '',
    sort: 'newest',
    page: 1,
    page_size: 25,
  };
  let busy = false;
  let rendered = '';
  let renderedQuery = '';
  let debounce: ReturnType<typeof setTimeout>;
  let selection: NonNullable<RecordPage['selection']> = [];
  const button = (text: string, click: () => unknown, disabled = false) => {
    const node = E(
      'button',
      { type: 'button', class: 'cbi-button', click },
      text,
    ) as HTMLButtonElement;
    node.disabled = disabled;
    return node;
  };
  const mutate = async (action: RecordAction, ids: string[]) => {
    if (busy || !ids.length) return;
    const frozenQuery = { ...query };
    busy = true;
    const label = {
      apply: _('Apply'),
      exclude: _('Exclude'),
      remove: _('Remove exclusions'),
      forget: _('Remove saved approvals'),
      recheck: _('Check'),
      dismiss: _('Remove'),
    }[action];
    if (
      action !== 'recheck' &&
      !(await confirmRecordAction(label, ids.length))
    ) {
      busy = false;
      return;
    }
    root.setAttribute('aria-busy', 'true');
    outcome.textContent = _('Processing…');
    try {
      const result = await registryAction(frozenQuery, action, ids);
      outcome.textContent = `${_('Completed')}: ${result.done}; ${_('Skipped')}: ${result.skipped}; ${_('Failed')}: ${result.failed}`;
      const reasons = [
        ...new Set(
          result.results
            .filter((item) => item.reason)
            .map((item) => item.reason),
        ),
      ];
      if (reasons.length)
        outcome.textContent += ` · ${reasons.slice(0, 3).join('; ')}`;
    } catch (error) {
      outcome.textContent =
        error instanceof Error ? error.message : String(error);
    } finally {
      busy = false;
      root.removeAttribute('aria-busy');
      void load();
    }
  };
  const load = async () => {
    if (busy) return;
    busy = true;
    root.setAttribute('aria-busy', 'true');
    const requested = JSON.stringify(query);
    if (!rendered || requested !== renderedQuery)
      message.textContent = _('Loading…');
    let again = false;
    try {
      const data = await autoRecords({ ...query });
      if (requested !== JSON.stringify(query)) {
        again = true;
        return;
      }
      query.page = data.page;
      const signature = JSON.stringify({ query, data });
      if (signature === rendered) {
        message.textContent = registryNotice(data.warning);
        return;
      }
      rendered = signature;
      renderedQuery = JSON.stringify(query);
      selection = data.selection || [];
      const supported = data.bulk_supported === true;
      const bulkSupported = supported && !data.legacy_overflow;
      tabs.replaceChildren(
        ...['pending', 'applied', 'excluded'].map((status, i) => {
          const node = button(
            `${[_('Awaiting'), _('Applied records'), _('Excluded')][i]} ${data.counts[status] || 0}`,
            () => {
              query.status = status;
              query.page = 1;
              void load();
            },
          );
          node.setAttribute('aria-pressed', String(status === query.status));
          return node;
        }),
      );
      actions.replaceChildren();
      const ids = selection.map((row) => row.id).filter(Boolean);
      if (query.status === 'pending')
        actions.append(
          button(
            _('Apply all'),
            () => mutate('apply', ids),
            !bulkSupported || !selection.some((row) => row.eligible),
          ),
        );
      if (query.status !== 'excluded')
        actions.append(
          button(
            _('Exclude all'),
            () => mutate('exclude', ids),
            !bulkSupported || !ids.length,
          ),
        );
      else
        actions.append(
          button(
            _('Remove all'),
            () => mutate('remove', ids),
            !bulkSupported || !ids.length,
          ),
        );
      if (query.status === 'applied')
        actions.append(
          button(
            _('Remove all'),
            () => mutate('forget', ids),
            !bulkSupported || !ids.length,
          ),
        );
      if (query.status === 'pending')
        actions.append(
          button(
            _('Remove all'),
            () => mutate('dismiss', ids),
            !bulkSupported || !ids.length,
          ),
        );
      const openDetails = new Set(
        Array.from(body.querySelectorAll<HTMLTableRowElement>('tr[data-id]'))
          .filter((row) => row.querySelector('details[open]'))
          .map((row) => row.dataset.id),
      );
      body.replaceChildren();
      if (!data.rows.length)
        body.append(
          E(
            'p',
            {},
            query.search ? _('No matching IPs') : _('No connection errors'),
          ),
        );
      else
        body.append(
          E('table', { class: 'table' }, [
            E(
              'tr',
              {},
              ['IP', _('Route'), _('State'), _('Action')].map((text) =>
                E('th', {}, text),
              ),
            ),
            ...data.rows.map((row) =>
              E('tr', { 'data-id': row.id || '' }, [
                E('td', {}, [
                  E('strong', {}, row.ip),
                  E('div', {}, row.domain || _('Domain unknown')),
                ]),
                E('td', {}, routeText(row)),
                E('td', {}, [
                  recordStateText(row),
                  ...(row.expires
                    ? [E('div', {}, new Date(row.expires).toLocaleString())]
                    : []),
                  ...(row.failure
                    ? [
                        E(
                          'details',
                          {
                            ...(openDetails.has(row.id) ? { open: true } : {}),
                          },
                          [
                            E('summary', {}, _('Error')),
                            E('p', {}, row.failure.message),
                            E(
                              'p',
                              {},
                              new Date(row.failure.at).toLocaleString(),
                            ),
                            ...[
                              ...new Set(
                                (row.attempts || []).map(
                                  (attempt) => attempt.outbound,
                                ),
                              ),
                            ].map((target) =>
                              E(
                                'div',
                                {},
                                `${target === row.source ? _('Current route') : target === 'direct-out' ? 'Direct' : target}: ${(row.attempts || []).filter((attempt) => attempt.outbound === target).every((attempt) => attempt.status === 'verified') ? _('Verified') : _('Not verified')}`,
                              ),
                            ),
                          ],
                        ),
                      ]
                    : []),
                ]),
                E('td', {}, [
                  ...(row.status === 'proposed'
                    ? [
                        button(
                          _('Apply'),
                          () => mutate('apply', [row.id!]),
                          !supported || !canApply(row),
                        ),
                      ]
                    : []),
                  ...(row.status === 'excluded'
                    ? [
                        button(
                          _('Remove'),
                          () => mutate('remove', [row.id!]),
                          !supported,
                        ),
                      ]
                    : [
                        button(
                          _('Exclude'),
                          () => mutate('exclude', [row.id!]),
                          !supported ||
                            !row.id ||
                            (!row.source_id && !row.source),
                        ),
                      ]),
                  ...(row.status === 'saved'
                    ? [
                        button(
                          _('Check'),
                          () => mutate('recheck', [row.id!]),
                          !supported,
                        ),
                        button(
                          _('Remove'),
                          () => mutate('forget', [row.id!]),
                          !supported,
                        ),
                      ]
                    : []),
                  ...(['pending', 'applied'].includes(query.status) &&
                  row.status !== 'saved'
                    ? [
                        button(
                          _('Remove'),
                          () =>
                            mutate(
                              query.status === 'pending' ? 'dismiss' : 'forget',
                              [row.id!],
                            ),
                          !supported || !row.id,
                        ),
                      ]
                    : []),
                  ...(!['applied', 'saved', 'proposed', 'excluded'].includes(
                    row.status,
                  ) &&
                  row.id &&
                  row.source &&
                  row.network === 'tcp'
                    ? [
                        button(
                          _('Check'),
                          () => mutate('recheck', [row.id!]),
                          !supported,
                        ),
                      ]
                    : []),
                ]),
              ]),
            ),
          ]),
        );
      const count = Math.max(1, Math.ceil(data.total / query.page_size));
      pages.replaceChildren();
      if (count > 1) {
        pages.append(
          button(
            '‹',
            () => {
              query.page--;
              void load();
            },
            query.page <= 1,
          ),
        );
        for (let page = 1; page <= count; page++) {
          const number = button(String(page), () => {
            query.page = page;
            void load();
          });
          if (page === query.page) number.setAttribute('aria-current', 'page');
          pages.append(number);
        }
        pages.append(
          button(
            '›',
            () => {
              query.page++;
              void load();
            },
            query.page >= count,
          ),
        );
      }
      message.textContent =
        registryNotice(data.warning) ||
        (data.legacy_overflow
          ? _(
              'Legacy exclusions exceed 64 records. Remove entries explicitly or narrow the filter; no exclusions were discarded.',
            )
          : '') ||
        '';
    } catch (error) {
      message.textContent =
        error instanceof Error &&
        error.message.includes('automatic_routing_unavailable')
          ? ''
          : error instanceof Error
            ? error.message
            : String(error);
    } finally {
      busy = false;
      root.removeAttribute('aria-busy');
      if (again) void load();
    }
  };
  const search = E('input', {
    type: 'search',
    placeholder: _('Search IP or domain'),
    'aria-label': _('Search IP or domain'),
  }) as HTMLInputElement;
  search.addEventListener('input', () => {
    clearTimeout(debounce);
    debounce = setTimeout(() => {
      query.search = search.value;
      query.page = 1;
      void load();
    }, 300);
  });
  const sort = E(
    'select',
    { 'aria-label': _('Sort') },
    [
      ['newest', _('Newest first')],
      ['oldest', _('Oldest first')],
      ['ip', _('By IP')],
    ].map(([value, text]) => E('option', { value }, text)),
  ) as HTMLSelectElement;
  sort.addEventListener('change', () => {
    query.sort = sort.value;
    query.page = 1;
    void load();
  });
  root.append(
    tabs,
    E('div', { class: 'km-records__tools' }, [
      search,
      sort,
      button('↻', () => load()),
    ]),
    actions,
    outcome,
    message,
    body,
    pages,
  );
  let mounted = false;
  let last = 0;
  const started = Date.now();
  const timer = setInterval(() => {
    if (root.isConnected) mounted = true;
    else if (mounted || Date.now() - started > 60000) {
      clearInterval(timer);
      clearTimeout(debounce);
      return;
    }
    if (
      root.isConnected &&
      root.getClientRects().length &&
      document.visibilityState !== 'hidden' &&
      Date.now() - last > 15000
    ) {
      last = Date.now();
      void load();
    }
  }, 1000);
  return root;
}
