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
  check(
    help?.parentElement?.classList.contains('cbi-value-title'),
    'help at title',
  );
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
  const labelRect = help.parentElement!.getBoundingClientRect();
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
  const count = 64;
  const requests: Record<string, unknown>[] = [];
  const batches: string[][] = [];
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
            rows: Array.from(
              { length: Math.min(limit, count - start) },
              (_, i) => ({
                id: `c${start + i}`,
                ip: `203.0.113.${start + i}`,
                source_id: 'zap',
                source: 'zap',
                status: 'identity_unknown',
                domain_known: false,
              }),
            ),
            total: count,
            page,
            counts: { pending: count, applied: 0, excluded: 0 },
            version: 1,
            bulk_supported: true,
            selection: Array.from({ length: count }, (_, i) => ({
              id: `c${i}`,
              eligible: false,
            })),
          };
        },
    },
  });
  const records = renderAutoRecords('zap');
  root.append(records);
  await new Promise((resolve) => setTimeout(resolve, 1200));
  check(records.querySelectorAll('tr').length === 26, '25 records per page');
  Array.from(records.querySelectorAll<HTMLButtonElement>('button'))
    .find((node) => node.textContent === '\u2192')!
    .click();
  await new Promise((resolve) => setTimeout(resolve, 0));
  check(
    requests[requests.length - 1]?.page === 2 &&
      requests.every((query) => query.page_size === 25),
    'server pagination',
  );
  check(records.querySelectorAll('tr').length <= 26, 'DOM bound');
  const confirm = window.confirm;
  window.confirm = () => true;
  Array.from(records.querySelectorAll<HTMLButtonElement>('button'))
    .find((node) => node.textContent === 'Exclude all')!
    .click();
  await new Promise((resolve) => setTimeout(resolve, 0));
  window.confirm = confirm;
  check(
    batches.flat().length === 64 && new Set(batches.flat()).size === 64,
    'all filtered records once across pages',
  );
  check(records.textContent?.includes('Completed: 64'), 'bulk result');
  records.remove();
  const auto = document.createElement('section');
  auto.innerHTML =
    ['enabled', 'apply', 'direct', 'use_warp', 'ip_only']
      .map(
        (name) =>
          `<div class="cbi-value" data-name="auto_routing_${name}" data-widget="CBI.FlagValue"><label class="cbi-value-title">${name}</label><div class="cbi-value-field"><input type="checkbox"></div></div>`,
      )
      .join('') +
    '<div class="cbi-value" data-name="auto_routing_contract"><label class="cbi-value-title">Contract</label><div class="cbi-value-field"><textarea rows="2"></textarea></div></div>';
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
  check(!direct.disabled && apply.disabled, 'ordinary HTTPS is manual');
  const contract = auto.querySelector('textarea')!;
  contract.value = '{"mode":"strict","domain":"one.test","prefix":"ok:"}';
  contract.dispatchEvent(new Event('input', { bubbles: true }));
  check(!apply.disabled, 'strict eligibility');
  check(
    auto.querySelector<HTMLInputElement>(
      '[data-name="auto_routing_ip_only"] input',
    )!.disabled,
    'IP-only no false promise',
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
