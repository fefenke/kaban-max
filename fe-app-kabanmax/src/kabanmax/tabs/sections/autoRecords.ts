import { E } from '../../../helpers/element';
import { callUbus } from '../../../helpers/callUbus';
import { canApply, recordStateText, type AutoEntry } from './autoRouting';

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
  error?: string;
  registry_overflow?: number;
  legacy_overflow?: boolean;
  bulk_supported?: boolean;
  manual_apply_supported?: boolean;
  available_targets?: { tag: string; name: string }[];
  selection?: { id: string; eligible: boolean }[];
}

// Small RAM-only view cache prevents an empty table when reopening a section.
// Every mounted view still refreshes from the backend; actions never trust it.
const recordPages = new Map<string, RecordPage>();

export function registryNotice(message = ''): string {
  return message.includes('automatic_routing_unavailable')
    ? _(
        'Automatic routing is not active in the running configuration. Save & Apply the section settings and check the application log if activation fails.',
      )
    : message;
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
  if (reply.data.error) throw new Error(reply.data.error);
  return reply.data;
}
export async function registryAction(
  query: RecordQuery,
  action: RecordAction,
  ids: string[],
  targets?: Record<string, string>,
): Promise<BatchResult> {
  const selected = [...new Set(ids)];
  const frozenQuery = { ...query };
  const frozenTargets = targets ? { ...targets } : undefined;
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
          id: JSON.stringify({
            ...frozenQuery,
            action,
            ids: chunk,
            ...(frozenTargets
              ? {
                  targets: Object.fromEntries(
                    chunk
                      .filter((id) => frozenTargets[id])
                      .map((id) => [id, frozenTargets[id]]),
                  ),
                }
              : {}),
          }),
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
  const tabs = E(
    'ul',
    { class: 'cbi-tabmenu km-records__tabs', role: 'tablist' },
    [],
  );
  const actions = E('div', { class: 'km-records__actions' }, []);
  const panelId = `km-auto-records-${sectionId}`;
  const body = E(
    'div',
    { id: panelId, class: 'km-records__panel', role: 'tabpanel' },
    [],
  );
  const rows = E('tbody', {}, []);
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
  const actionErrors = new Map<string, string>();
  let debounce: ReturnType<typeof setTimeout>;
  let selection: NonNullable<RecordPage['selection']> = [];
  let manualSupported = false;
  let availableTargets: NonNullable<RecordPage['available_targets']> = [];
  const directions = new Map<string, string>();
  const chosenDirections = new Set<string>();
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
    const frozenIds = [...ids];
    const frozenTargets =
      action === 'apply' && manualSupported
        ? Object.fromEntries(
            frozenIds.map((id) => [id, directions.get(id) || '']),
          )
        : undefined;
    busy = true;
    let label = {
      apply: _('Apply'),
      exclude: _('Exclude'),
      remove: _('Remove exclusions'),
      forget: _('Remove saved approvals'),
      recheck: _('Check'),
      dismiss: _('Remove'),
    }[action];
    if (frozenTargets) {
      const names = [
        ...new Set(
          Object.values(frozenTargets).map(
            (tag) =>
              availableTargets.find((target) => target.tag === tag)?.name ||
              tag,
          ),
        ),
      ];
      label += `: ${names.join(', ')}`;
    }
    if (
      action !== 'recheck' &&
      !(await confirmRecordAction(label, frozenIds.length))
    ) {
      busy = false;
      return;
    }
    root.setAttribute('aria-busy', 'true');
    for (const id of frozenIds) actionErrors.delete(id);
    try {
      const result = await registryAction(
        frozenQuery,
        action,
        frozenIds,
        frozenTargets,
      );
      for (const item of result.results) {
        if (item.status === 'failed' && item.reason)
          actionErrors.set(item.id, item.reason);
      }
    } catch (error) {
      for (const id of frozenIds)
        actionErrors.set(
          id,
          error instanceof Error ? error.message : String(error),
        );
    } finally {
      busy = false;
      root.removeAttribute('aria-busy');
      rendered = '';
      void load();
    }
  };
  const load = async (cached?: RecordPage) => {
    if (busy) return;
    busy = true;
    const requested = JSON.stringify(query);
    let again = false;
    try {
      const data = cached || (await autoRecords({ ...query }));
      if (requested !== JSON.stringify(query)) {
        again = true;
        return;
      }
      query.page = data.page;
      recordPages.set(JSON.stringify(query), data);
      while (recordPages.size > 16)
        recordPages.delete(recordPages.keys().next().value!);
      const signature = JSON.stringify({ query, data });
      if (signature === rendered) return;
      rendered = signature;
      selection = data.selection || [];
      manualSupported = data.manual_apply_supported === true;
      availableTargets = data.available_targets || [];
      for (const [id, target] of directions)
        if (!availableTargets.some((entry) => entry.tag === target)) {
          directions.delete(id);
          chosenDirections.delete(id);
        }
      const fallback =
        availableTargets.find((target) => target.tag !== 'direct-out')?.tag ||
        availableTargets[0]?.tag;
      for (const selected of selection) {
        if (!chosenDirections.has(selected.id)) {
          const row = data.rows.find((entry) => entry.id === selected.id);
          const target =
            availableTargets.find((entry) => entry.tag === row?.target)?.tag ||
            fallback;
          if (target) directions.set(selected.id, target);
        }
      }
      const supported = data.bulk_supported === true;
      const bulkSupported = supported && !data.legacy_overflow;
      for (const tab of tabs.querySelectorAll<HTMLElement>('[role=tab]')) {
        const active = tab.dataset.status === query.status;
        tab.setAttribute('aria-selected', String(active));
        tab.tabIndex = active ? 0 : -1;
        tab.parentElement!.className = active ? 'cbi-tab' : 'cbi-tab-disabled';
        if (active) body.setAttribute('aria-labelledby', tab.id);
      }
      const ids = selection.map((row) => row.id).filter(Boolean);
      applyAll.disabled =
        !bulkSupported ||
        query.status !== 'pending' ||
        !selection.some((row) => row.eligible);
      excludeAll.disabled =
        !bulkSupported || query.status === 'excluded' || !ids.length;
      removeAll.disabled = !bulkSupported || !ids.length;
      const openDetails = new Set(
        Array.from(body.querySelectorAll<HTMLTableRowElement>('tr[data-id]'))
          .filter((row) => row.querySelector('details[open]'))
          .map((row) => row.dataset.id),
      );
      const nextRows = data.rows.map((row) =>
        E('tr', { 'data-id': row.id || '' }, [
          E('td', {}, [E('strong', {}, row.ip)]),
          E(
            'td',
            {},
            (row.domains?.length
              ? row.domains
              : [row.domain || row.observed_domain || _('Domain unknown')]
            ).map((domain) => E('div', {}, domain)),
          ),
          E(
            'td',
            {},
            row.created && Number.isFinite(Date.parse(row.created))
              ? new Date(row.created).toLocaleString()
              : '—',
          ),
          E('td', {}, [
            query.status === 'pending' && manualSupported
              ? (() => {
                  const select = E(
                    'select',
                    { 'aria-label': _('Direction') },
                    availableTargets.map((target) =>
                      E('option', { value: target.tag }, target.name),
                    ),
                  ) as HTMLSelectElement;
                  select.value = directions.get(row.id || '') || '';
                  select.disabled = !availableTargets.length;
                  select.addEventListener('change', () => {
                    directions.set(row.id || '', select.value);
                    chosenDirections.add(row.id || '');
                  });
                  return select;
                })()
              : row.target === 'direct-out'
                ? 'Direct'
                : row.target_name || row.target || '\u2014',
          ]),
          E('td', {}, [
            recordStateText(row),
            ...(row.expires && !row.persistent_ip && query.status === 'pending'
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
                      E('p', {}, new Date(row.failure.at).toLocaleString()),
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
                          `${target === row.source ? _('Current route') : target === 'direct-out' ? 'Direct' : target}: ${(row.attempts || []).filter((attempt) => attempt.outbound === target).every((attempt) => attempt.status === 'verified') ? _('Verified') : _('Error')} ${(row.attempts || []).find((attempt) => attempt.outbound === target && attempt.reason && attempt.status !== 'verified')?.reason || ''}`,
                        ),
                      ),
                    ],
                  ),
                ]
              : []),
          ]),
          E('td', {}, [
            ...(actionErrors.has(row.id || '')
              ? [
                  E('details', { class: 'km-records__action-error' }, [
                    E('summary', {}, _('Error')),
                    E('p', {}, actionErrors.get(row.id || '') || ''),
                  ]),
                ]
              : []),
            button(
              _('Apply'),
              () => mutate('apply', [row.id!]),
              !supported ||
                query.status !== 'pending' ||
                (manualSupported
                  ? !selection.some(
                      (entry) => entry.id === row.id && entry.eligible,
                    ) || !directions.get(row.id || '')
                  : !canApply(row)),
            ),
            button(
              _('Remove'),
              () =>
                mutate(
                  query.status === 'excluded'
                    ? 'remove'
                    : query.status === 'applied'
                      ? 'forget'
                      : 'dismiss',
                  [row.id!],
                ),
              !supported || !row.id,
            ),
            button(
              _('Exclude'),
              () => mutate('exclude', [row.id!]),
              !supported ||
                query.status === 'excluded' ||
                !row.id ||
                (!row.source_id && !row.source),
            ),
          ]),
        ]),
      );
      // Keep controls and focus across polls, replacing only changed cells.
      const existing = new Map(
        Array.from(
          rows.querySelectorAll<HTMLTableRowElement>('tr[data-id]'),
        ).map((row) => [row.dataset.id, row]),
      );
      let cursor = rows.firstChild;
      for (const next of nextRows) {
        const current = existing.get(next.dataset.id);
        const node = current || next;
        if (current) {
          existing.delete(next.dataset.id);
          Array.from(next.children).forEach((cell, index) => {
            const old = current.children[index];
            if (!old?.isEqualNode(cell)) {
              if (old) old.replaceWith(cell);
              else current.append(cell);
            }
          });
        }
        if (node !== cursor) rows.insertBefore(node, cursor);
        cursor = node.nextSibling;
      }
      for (const stale of existing.values()) stale.remove();
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
    } catch (error) {
      // Preserve the last good table during transient read failures.
      if (!rows.children.length) {
        rows.append(
          E('tr', { 'data-id': '__read_error__' }, [
            E('td', { colSpan: 6 }, [
              button(_('Error'), () => void load()),
              E(
                'span',
                {},
                error instanceof Error ? error.message : String(error),
              ),
            ]),
          ]),
        );
      }
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
  const selectedIds = () => selection.map((row) => row.id).filter(Boolean);
  const applyAll = button(
    _('Apply all'),
    () => mutate('apply', selectedIds()),
    true,
  );
  const excludeAll = button(
    _('Exclude all'),
    () => mutate('exclude', selectedIds()),
    true,
  );
  const removeAll = button(
    _('Remove all'),
    () =>
      mutate(
        query.status === 'excluded'
          ? 'remove'
          : query.status === 'applied'
            ? 'forget'
            : 'dismiss',
        selectedIds(),
      ),
    true,
  );
  actions.append(applyAll, excludeAll, removeAll);
  const statuses = ['pending', 'applied', 'excluded'];
  const labels = [_('Awaiting'), _('Applied records'), _('Excluded')];
  for (const [index, status] of statuses.entries()) {
    const choose = (event: Event) => {
      event.preventDefault();
      query.status = status;
      query.page = 1;
      void load();
    };
    const tab = E(
      'a',
      {
        href: `#${panelId}`,
        id: `${panelId}-${status}`,
        role: 'tab',
        tabindex: status === query.status ? '0' : '-1',
        'data-status': status,
        click: choose,
      },
      labels[index],
    );
    tab.setAttribute('aria-controls', panelId);
    tab.setAttribute('aria-selected', String(status === query.status));
    tab.addEventListener('keydown', (event) => {
      const key = (event as KeyboardEvent).key;
      if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(key)) return;
      event.preventDefault();
      const next =
        key === 'Home'
          ? 0
          : key === 'End'
            ? 2
            : (index + (key === 'ArrowRight' ? 1 : 2)) % 3;
      const target = tabs.querySelectorAll<HTMLElement>('[role=tab]')[next];
      target.focus();
      target.click();
    });
    tabs.append(
      E(
        'li',
        {
          role: 'presentation',
          class: status === query.status ? 'cbi-tab' : 'cbi-tab-disabled',
        },
        [tab],
      ),
    );
  }
  body.setAttribute('aria-labelledby', `${panelId}-pending`);
  const sortHeaders: HTMLElement[] = [];
  const updateSort = () => {
    for (const header of sortHeaders) {
      const active =
        header.dataset.sort === 'ip'
          ? query.sort.startsWith('ip')
          : !query.sort.startsWith('ip');
      header.setAttribute(
        'aria-sort',
        !active
          ? 'none'
          : ['newest', 'ip_desc'].includes(query.sort)
            ? 'descending'
            : 'ascending',
      );
      for (const item of header.querySelectorAll<HTMLElement>(
        '[data-sort-value]',
      ))
        item.setAttribute(
          'aria-checked',
          String(item.dataset.sortValue === query.sort),
        );
    }
  };
  const sortHeader = (
    title: string,
    key: string,
    choices: [string, string][],
  ) => {
    const details = E(
      'details',
      { class: 'km-records__sort' },
      [],
    ) as HTMLDetailsElement;
    const menu = E('div', { class: 'km-records__sort-menu', role: 'menu' }, []);
    for (const [value, label] of choices) {
      const item = button(label, () => {
        query.sort = value;
        query.page = 1;
        details.open = false;
        summary.focus();
        updateSort();
        void load();
      });
      item.setAttribute('role', 'menuitemradio');
      item.dataset.sortValue = value;
      menu.append(item);
    }
    const summary = E('summary', { 'aria-haspopup': 'menu' }, title);
    details.append(summary, menu);
    details.addEventListener('keydown', (event) => {
      if ((event as KeyboardEvent).key === 'Escape') {
        details.open = false;
        summary.focus();
      }
    });
    details.addEventListener('toggle', () => {
      if (details.open)
        for (const other of body.querySelectorAll<HTMLDetailsElement>(
          '.km-records__sort',
        ))
          if (other !== details) other.open = false;
    });
    const header = E('th', { scope: 'col', 'data-sort': key }, [details]);
    sortHeaders.push(header);
    return header;
  };
  body.append(
    E('table', { class: 'table' }, [
      E('thead', {}, [
        E('tr', {}, [
          sortHeader('IP', 'ip', [
            ['ip', _('Ascending')],
            ['ip_desc', _('Descending')],
          ]),
          E('th', { scope: 'col' }, _('Domain')),
          sortHeader(_('Added'), 'created', [
            ['newest', _('Newest first')],
            ['oldest', _('Oldest first')],
          ]),
          ...[_('Direction'), _('State'), _('Action')].map((title) =>
            E('th', { scope: 'col' }, title),
          ),
        ]),
      ]),
      rows,
    ]),
  );
  updateSort();
  root.append(
    E('div', { class: 'km-records__toolbar' }, [search, actions]),
    tabs,
    body,
    pages,
  );
  let mounted = false;
  let last = 0;
  const started = Date.now();
  const cached = recordPages.get(JSON.stringify(query));
  if (cached) void load(cached);
  last = Date.now();
  void load();
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
