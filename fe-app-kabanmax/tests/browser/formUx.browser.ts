import { installFormUx, formUxStyles } from '../../src/kabanmax/cbi/formUx';
import { renderUpdateStatus } from '../../src/kabanmax/tabs/components/updateStatus';
import { renderAutoRecords } from '../../src/kabanmax/tabs/sections/autoRecords';

async function test() {
  const check = (value: unknown, message: string) => {
    if (!value) throw new Error(message);
  };
  document.head.insertAdjacentHTML(
    'beforeend',
    `<style>${formUxStyles}.fkp_components-page__update-status[hidden]{display:none}</style>`,
  );
  const element = (
    tag: string,
    attrs: Record<string, unknown> = {},
    children: unknown[] = [],
  ) => {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs))
      if (typeof value === 'function')
        node.addEventListener(key, value as EventListener);
      else node.setAttribute(key, String(value));
    for (const child of children || [])
      node.append(child instanceof Node ? child : String(child));
    return node;
  };
  Object.assign(globalThis, { E: element });
  document.body.innerHTML =
    '<main id="cbi-kabanmax"><div class="cbi-value" data-widget="CBI.FlagValue"><label class="cbi-value-title">Long setting label</label><div class="cbi-value-field"><input type="checkbox"><div class="cbi-value-description">Detailed help text</div></div></div></main>';
  const root = document.querySelector('main')!;
  const stop = installFormUx(root);
  const help = root.querySelector<HTMLButtonElement>('.km-help')!;
  const input = root.querySelector('input')!;
  check(help?.closest('.cbi-value-title'), 'help at title');
  check(
    !root.querySelector('.cbi-value-description'),
    'no duplicate description',
  );
  for (let i = 0; i < 10; i++) {
    help.click();
    check(!input.checked, 'help must not toggle control');
    check(document.querySelectorAll('.km-help-card').length === 1, 'one card');
    document.querySelector<HTMLElement>('.km-help-card')!.click();
    check(help.getAttribute('aria-expanded') === 'true', 'inside retains card');
    if (i % 2)
      document.dispatchEvent(
        new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }),
      );
    else document.body.click();
    check(!document.querySelector('.km-help-card'), 'outside/Escape closes');
  }
  const labelRect = help.closest('.cbi-value-title')!.getBoundingClientRect();
  const inputRect = input.getBoundingClientRect();
  check(
    Math.abs(
      (labelRect.top + labelRect.bottom - inputRect.top - inputRect.bottom) / 2,
    ) < 3,
    'checkbox centered',
  );
  check(inputRect.left >= labelRect.right, 'checkbox does not overlap label');
  const second = document.createElement('div');
  second.className = 'cbi-value';
  second.dataset.widget = 'CBI.MultiValue';
  second.innerHTML =
    '<label class="cbi-value-title">Select</label><div class="cbi-value-field"><select><option>One</option></select><div class="cbi-value-description">Selector help</div></div>';
  root.append(second);
  await new Promise((resolve) => setTimeout(resolve, 0));
  help.click();
  second.querySelector<HTMLButtonElement>('.km-help')!.click();
  check(
    help.getAttribute('aria-expanded') === 'false' &&
      document.querySelectorAll('.km-help-card').length === 1,
    'another help closes previous',
  );
  check(!second.classList.contains('km-flag'), 'select is not a flag');
  const card = document
    .querySelector<HTMLElement>('.km-help-card')!
    .getBoundingClientRect();
  check(card.left >= 0 && card.right <= window.innerWidth, 'viewport bounds');
  for (const [busy, error, release] of [
    [true, '', null],
    [false, '', { success: true, update_available: false }],
    [false, '', { success: true, update_available: true, latest: '9.9' }],
    [false, 'Network error', null],
  ] as const) {
    const status = renderUpdateStatus(busy, error, release);
    const action = document.createElement('button');
    root.append(status, action);
    check(
      !status.hasAttribute('hidden') &&
        getComputedStyle(status).display !== 'none',
      'status is visible',
    );
    check(status.nextElementSibling === action, 'status above action');
    status.remove();
    action.remove();
  }
  let count = 64;
  let registryReason = '';
  const requests: Record<string, unknown>[] = [];
  const batches: string[][] = [];
  const operations: Record<string, unknown>[] = [];
  Object.assign(globalThis, {
    rpc: {
      declare:
        (options: { params: string[]; method: string }) =>
        async (...values: unknown[]) => {
          const params = Object.fromEntries(
            options.params.map((key, i) => [key, values[i]]),
          );
          if (options.method === 'auto_action') {
            const payload = JSON.parse(String(params.id));
            check(payload.source_section === 'zap', 'bulk source');
            check(payload.ids.length <= 8, 'batch limit');
            batches.push(payload.ids);
            operations.push(payload);
            return {
              success: true,
              done: payload.ids.length,
              skipped: 0,
              failed: 0,
              results: [],
            };
          }
          check(options.method === 'auto_records', 'paged API only');
          requests.push(params);
          const page = Number(params.page),
            limit = Number(params.page_size),
            start = (page - 1) * limit;
          return {
            reason: registryReason,
            manual_apply_supported: true,
            available_targets: [
              { tag: 'direct-out', name: 'Direct' },
              { tag: 'warp-out', name: 'Configured WARP' },
            ],
            rows: Array.from(
              { length: Math.min(limit, count - start) },
              (_, i) => ({
                id: `c${start + i}`,
                count: requests.length,
                ip:
                  start + i === 0
                    ? '2001:db8:1234:5678:abcd:abcd:abcd:abcd'
                    : `203.0.113.${start + i}`,
                source_id: 'zap',
                source: 'zap',
                status:
                  params.status === 'applied'
                    ? i % 2
                      ? 'saved'
                      : 'applied'
                    : params.status === 'excluded'
                      ? 'excluded'
                      : 'inconclusive',
                domain_known: false,
                domain: '',
                observed_domain: 'api.synthetic.example',
                failure: {
                  id: `error-${start + i}`,
                  source_id: 'zap',
                  message: 'synthetic dial timeout',
                  at: '2026-11-16T00:00:00Z',
                },
              }),
            ),
            total: count,
            page,
            counts: { pending: count, applied: 0, excluded: 0 },
            version: 1,
            bulk_supported: true,
            selection: Array.from({ length: count }, (_, i) => ({
              id: `c${i}`,
              eligible: true,
            })),
          };
        },
    },
  });
  const records = renderAutoRecords('zap');
  check(
    !records.textContent?.includes('Loading'),
    'registry never renders a jumping loading label',
  );
  root.append(records);
  check(
    records.querySelector('.km-records__toolbar input[type=search]') &&
      records.querySelectorAll('.km-records__toolbar button').length === 3 &&
      records.querySelectorAll('[role=tab]').length === 3 &&
      records.querySelectorAll('th').length === 6,
    'search and three bulk actions precede native tabs and persistent table headers',
  );
  await new Promise((resolve) => setTimeout(resolve, 1200));
  check(records.querySelectorAll('tr').length === 26, '25 records per page');
  check(
    records.scrollWidth <= records.clientWidth + 1,
    'records never require horizontal scrolling, including long IPv6',
  );
  const visibleAction = records.querySelector<HTMLButtonElement>(
    'tr[data-id] td:last-child button',
  )!;
  const bounds = records.getBoundingClientRect();
  check(
    visibleAction.getBoundingClientRect().right <= bounds.right + 1,
    'row actions stay inside the visible panel',
  );
  const firstRow = records.querySelector('tr[data-id]')!;
  const firstDetails = firstRow.querySelector('details')!;
  firstDetails.open = true;
  const refreshRecords = () =>
    records
      .querySelector<HTMLElement>('[role=tab][aria-selected=true]')!
      .click();
  refreshRecords();
  await new Promise((resolve) => setTimeout(resolve, 0));
  check(
    records.querySelector('tr[data-id]') === firstRow && firstDetails.open,
    'unchanged refresh preserves row and open error',
  );
  const numbered = Array.from(
    records.querySelectorAll('.km-records__pages [aria-current]'),
  );
  check(
    numbered.length === 1 && numbered[0].textContent === '1',
    'numbered pages identify current page',
  );
  check(
    !records.querySelector('.km-records__pages')!.textContent?.includes('/'),
    'pagination has no counter fractions',
  );
  Array.from(records.querySelectorAll<HTMLButtonElement>('button'))
    .find((node) => node.textContent === '›')!
    .click();
  await new Promise((resolve) => setTimeout(resolve, 0));
  check(
    requests[requests.length - 1]?.page === 2 &&
      requests.every((query) => query.page_size === 25),
    'server pagination',
  );
  check(records.querySelectorAll('tr').length <= 26, 'DOM bound');
  const confirm = window.confirm;
  window.confirm = () => {
    throw new Error('Browser confirm must not be used');
  };
  const confirmDialog = (accept = true) => {
    const dialog = document.querySelector<HTMLDialogElement>(
      'dialog.km-record-confirm',
    );
    check(dialog?.open, 'styled confirmation dialog is open');
    const rect = dialog!.getBoundingClientRect();
    check(
      Math.abs(
        (rect.left + rect.right) / 2 - document.documentElement.clientWidth / 2,
      ) < 2 &&
        Math.abs((rect.top + rect.bottom) / 2 - window.innerHeight / 2) < 2,
      `confirmation is centered in viewport: ${JSON.stringify({ x: rect.x, y: rect.y, width: rect.width, height: rect.height, vw: window.innerWidth, vh: window.innerHeight, position: getComputedStyle(dialog!).position, margin: getComputedStyle(dialog!).margin })}`,
    );
    dialog!
      .querySelectorAll<HTMLButtonElement>('button')
      [accept ? 1 : 0].click();
  };
  Array.from(records.querySelectorAll<HTMLButtonElement>('button'))
    .find((node) => node.textContent === 'Exclude all')!
    .click();
  confirmDialog();
  await new Promise((resolve) => setTimeout(resolve, 0));
  window.confirm = confirm;
  check(
    batches.flat().length === 64 && new Set(batches.flat()).size === 64,
    'all filtered records once across pages',
  );
  check(
    !records.textContent?.includes('Completed:'),
    'no action banner above table',
  );
  const search = records.querySelector<HTMLInputElement>('input[type=search]')!;
  search.value = '203.0.113.';
  search.dispatchEvent(new Event('input', { bubbles: true }));
  await new Promise((resolve) => setTimeout(resolve, 350));
  const selectTab = async (prefix: string) => {
    Array.from(records.querySelectorAll<HTMLElement>('[role=tab]'))
      .find((node) => node.textContent?.startsWith(prefix))!
      .click();
    await new Promise((resolve) => setTimeout(resolve, 0));
  };
  await selectTab('Applied records');
  const removeApplied = Array.from(
    records.querySelectorAll<HTMLButtonElement>('button'),
  ).find((node) => node.textContent === 'Remove all');
  check(
    removeApplied && !removeApplied.disabled,
    'applied list has bulk deletion',
  );
  const beforeCancel = operations.length;
  removeApplied!.click();
  confirmDialog(false);
  await new Promise((resolve) => setTimeout(resolve, 0));
  check(
    operations.length === beforeCancel,
    'cancel bulk deletion performs no mutation',
  );
  removeApplied!.click();
  confirmDialog();
  await new Promise((resolve) => setTimeout(resolve, 0));
  const deletedApplied = operations.slice(beforeCancel);
  check(
    deletedApplied.flatMap((op) => op.ids as string[]).length === 64 &&
      deletedApplied.every(
        (op) =>
          op.action === 'forget' &&
          op.status === 'applied' &&
          op.source_section === 'zap' &&
          op.search === '203.0.113.',
      ),
    'delete all applied spans pages and preserves tab/source',
  );
  await selectTab('Excluded');
  const beforeExcluded = operations.length;
  Array.from(records.querySelectorAll<HTMLButtonElement>('button'))
    .find((node) => node.textContent === 'Remove all')!
    .click();
  confirmDialog();
  await new Promise((resolve) => setTimeout(resolve, 0));
  const deletedExcluded = operations.slice(beforeExcluded);
  check(
    deletedExcluded.flatMap((op) => op.ids as string[]).length === 64 &&
      deletedExcluded.every(
        (op) =>
          op.action === 'remove' &&
          op.status === 'excluded' &&
          op.source_section === 'zap' &&
          op.search === '203.0.113.',
      ),
    'delete all exclusions preserves tab/source',
  );
  window.confirm = confirm;
  check(
    !records.textContent?.includes('Stop automatic routing now'),
    'no redundant stop button',
  );
  check(
    !records.textContent?.includes('Up to 64 records'),
    'no constant technical notice',
  );
  await selectTab('Awaiting');
  const beforeDismiss = operations.length;
  Array.from(records.querySelectorAll<HTMLButtonElement>('tr[data-id] button'))
    .find((node) => node.textContent === 'Remove')!
    .click();
  confirmDialog();
  await new Promise((resolve) => setTimeout(resolve, 0));
  check(
    operations.length === beforeDismiss + 1 &&
      operations[beforeDismiss].action === 'dismiss',
    'pending remove is distinct from exclusion',
  );
  count = 3;
  refreshRecords();
  await new Promise((resolve) => setTimeout(resolve, 0));
  check(
    records.querySelector('.km-records__pages')!.childElementCount === 0,
    'one page has no pagination block',
  );
  const pendingRow = records.querySelector<HTMLTableRowElement>('tr[data-id]')!;
  check(
    Array.from(pendingRow.querySelectorAll('button'))
      .map((button) => button.textContent)
      .join('|') === 'Apply|Remove|Exclude',
    'inconclusive row has three consistent actions without Check',
  );
  check(
    pendingRow.cells[1].textContent === 'api.synthetic.example',
    'observed domain has its own column',
  );
  const direction = pendingRow.querySelector<HTMLSelectElement>('select')!;
  check(
    direction.value === 'warp-out' &&
      direction.selectedOptions[0].textContent === 'Configured WARP',
    'pending direction defaults to configured WARP',
  );
  const beforeManual = operations.length;
  pendingRow.querySelector<HTMLButtonElement>('button')!.click();
  check(
    document
      .querySelector('dialog h3')
      ?.textContent?.includes('Configured WARP'),
    'confirmation names chosen direction',
  );
  search.value = 'changed-during-confirmation';
  search.dispatchEvent(new Event('input', { bubbles: true }));
  direction.value = 'direct-out';
  direction.dispatchEvent(new Event('change'));
  await new Promise((resolve) => setTimeout(resolve, 350));
  confirmDialog();
  await new Promise((resolve) => setTimeout(resolve, 0));
  check(
    operations[beforeManual].search === '203.0.113.' &&
      (operations[beforeManual].targets as Record<string, string>).c0 ===
        'warp-out',
    'manual apply freezes search and chosen direction before confirmation',
  );
  search.value = '203.0.113.';
  search.dispatchEvent(new Event('input', { bubbles: true }));
  await new Promise((resolve) => setTimeout(resolve, 350));
  count = 0;
  registryReason =
    'Auto-routing API unavailable or rejected request: automatic_routing_unavailable';
  for (let i = 0; i < 2; i++) {
    refreshRecords();
    await new Promise((resolve) => setTimeout(resolve, 0));
    check(
      !records.textContent?.includes('Automatic routing is not active') &&
        !records.textContent?.includes('Auto-routing API unavailable') &&
        !records.textContent?.includes('No connection errors'),
      'no availability banner above records',
    );
  }
  check(
    records.querySelectorAll('th').length === 6,
    'empty registry retains all column headers',
  );
  check(
    !records.textContent?.includes('No connection errors'),
    'empty registry has no redundant empty text',
  );
  check(
    Array.from(records.querySelectorAll('[role=tab]'))
      .map((tab) => tab.textContent)
      .join('|') === 'Awaiting|Applied records|Excluded',
    'native tab labels omit counts',
  );
  const ipSort = records.querySelector<HTMLDetailsElement>(
    'th[data-sort=ip] details',
  )!;
  check(!ipSort.open, 'column sort menu is initially hidden');
  ipSort.querySelector<HTMLElement>('summary')!.click();
  check(ipSort.open, 'column title opens sort menu');
  ipSort.querySelector<HTMLButtonElement>('[data-sort-value=ip_desc]')!.click();
  await new Promise((resolve) => setTimeout(resolve, 0));
  check(
    !ipSort.open && requests[requests.length - 1]?.sort === 'ip_desc',
    'column menu selects server-side descending IP order and closes',
  );
  check(
    records.querySelector('th[data-sort=ip]')?.getAttribute('aria-sort') ===
      'descending',
    'column shows selected sort direction',
  );
  check(
    document.activeElement === ipSort.querySelector('summary'),
    'sort selection restores focus to its column header',
  );
  window.confirm = confirm;
  records.remove();
  const auto = document.createElement('section');
  auto.innerHTML =
    ['enabled', 'apply', 'direct', 'use_warp', 'ip_only']
      .map(
        (name) =>
          `<div class="cbi-value" data-name="auto_routing_${name}" data-widget="CBI.FlagValue"><label class="cbi-value-title">${name}</label><div class="cbi-value-field"><input type="checkbox"></div></div>`,
      )
      .join('') +
    '<div class="cbi-value" data-name="auto_routing_contract"><label class="cbi-value-title">Настройки проверки HTTPS</label><div class="cbi-value-field"><textarea rows="2"></textarea><div class="cbi-value-description">HTTPS help</div></div></div>';
  root.append(auto);
  await new Promise((resolve) => setTimeout(resolve, 0));
  const main = auto.querySelector<HTMLInputElement>(
      '[data-name="auto_routing_enabled"] input',
    )!,
    apply = auto.querySelector<HTMLInputElement>(
      '[data-name="auto_routing_apply"] input',
    )!,
    direct = auto.querySelector<HTMLInputElement>(
      '[data-name="auto_routing_direct"] input',
    )!;
  check(apply.disabled && direct.disabled, 'main gating');
  main.checked = true;
  main.dispatchEvent(new Event('change', { bubbles: true }));
  check(
    !direct.disabled && !apply.disabled,
    'auto-apply remains an editable preference',
  );
  for (let i = 0; i < 8; i++) {
    const before = apply.checked;
    apply.click();
    check(
      apply.checked !== before && !apply.disabled,
      'repeated auto-apply clicks stay functional',
    );
  }
  const contract = auto.querySelector('textarea')!;
  contract.value = '{"mode":"strict","domain":"one.test","prefix":"ok:"}';
  contract.dispatchEvent(new Event('input', { bubbles: true }));
  check(!apply.disabled, 'strict eligibility');
  apply.checked = true;
  contract.value = '';
  contract.dispatchEvent(new Event('input', { bubbles: true }));
  check(!apply.disabled, 'saved auto-apply can be turned off without strict');
  apply.click();
  check(
    !apply.checked && !apply.disabled,
    'turning off must not lock the preference',
  );
  apply.checked = true;
  main.checked = false;
  main.dispatchEvent(new Event('change', { bubbles: true }));
  check(!apply.disabled, 'saved auto-apply can be cleared with main disabled');
  apply.click();
  check(!apply.checked && apply.disabled, 'cleared auto-apply stays gated');
  main.checked = true;
  contract.value = '{"mode":"strict","domain":"one.test","prefix":"ok:"}';
  contract.dispatchEvent(new Event('input', { bubbles: true }));
  check(!apply.disabled && !direct.disabled, 'strict/main controls recover');
  const ipOnly = auto.querySelector<HTMLInputElement>(
    '[data-name="auto_routing_ip_only"] input',
  )!;
  check(ipOnly.disabled, 'IP-only requires auto-apply preference');
  const childRow = ipOnly.closest<HTMLElement>('.cbi-value')!;
  check(
    getComputedStyle(childRow).marginInlineStart === '24px',
    'IP-only is visibly indented as a child preference',
  );
  const childTitle = childRow.querySelector<HTMLElement>('.cbi-value-title')!;
  childTitle.textContent = 'Разрешать перенаправление IP без домена';
  const childTitleRect = childTitle.getBoundingClientRect();
  const childInputRect = ipOnly.getBoundingClientRect();
  check(
    childTitleRect.right <= childInputRect.left &&
      childInputRect.left - childTitleRect.right < 25,
    'IP-only label is before checkbox like other flags',
  );
  check(
    getComputedStyle(childRow).display === 'grid',
    'IP-only checkbox uses standard flag columns',
  );
  check(
    getComputedStyle(childRow.querySelector('.cbi-value-title')!, '::before')
      .content === 'none',
    'nested checkbox has no arrow',
  );
  const advanced = auto.querySelector<HTMLElement>('.km-auto-advanced')!;
  advanced.setAttribute('open', '');
  const contractHelp = advanced.querySelector<HTMLElement>('.km-help')!;
  const helpTail = contractHelp.parentElement!.getBoundingClientRect();
  const helpRect = contractHelp.getBoundingClientRect();
  check(
    contractHelp.parentElement?.textContent?.startsWith('HTTPS') &&
      helpRect.top >= helpTail.top - 2 &&
      helpRect.bottom <= helpTail.bottom + 2,
    'HTTPS help remains beside the final label word',
  );
  check(
    parseFloat(getComputedStyle(advanced).marginBottom) >= 16,
    'advanced settings separated from records',
  );
  apply.click();
  check(!ipOnly.disabled, 'IP-only becomes editable under auto-apply');
  ipOnly.click();
  ipOnly.click();
  check(
    !ipOnly.checked && !ipOnly.disabled,
    'IP-only supports repeated clicks',
  );
  check(
    contract.rows >= 6 && getComputedStyle(contract).resize === 'vertical',
    'textarea height and resize',
  );
  contract.value = 'x'.repeat(2000);
  check(
    contract.scrollWidth <= contract.clientWidth + 1,
    'long list lines do not scroll horizontally',
  );
  const tabFixture = document.createElement('section');
  tabFixture.innerHTML =
    '<ul class="cbi-tabmenu"><li data-tab="auto_routing"><a>Auto</a></li></ul><div><div data-tab="auto_routing" data-tab-title="Auto"><details><summary>Advanced</summary><div class="cbi-value hidden"></div></details></div></div>';
  root.append(tabFixture);
  await new Promise((resolve) => setTimeout(resolve, 0));
  const autoTab = tabFixture.querySelector<HTMLElement>('li')!;
  check(autoTab.hidden, 'empty auto tab hidden');
  tabFixture.querySelector('.cbi-value')!.classList.remove('hidden');
  document.dispatchEvent(new Event('dependency-update'));
  check(!autoTab.hidden, 'auto tab restored');
  stop();
  document.body.innerHTML = '<pre id="result">PASS</pre>';
}
test().catch((error) => {
  document.body.innerHTML = '';
  const result = document.createElement('pre');
  result.id = 'result';
  result.textContent = `FAIL: ${error.message}`;
  document.body.append(result);
});
