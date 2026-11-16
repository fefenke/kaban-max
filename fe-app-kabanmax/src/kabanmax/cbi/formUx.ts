// Adapt LuCI's rendered frames, leaving CBI values, dependencies and save hooks intact.
export const formUxStyles = `
.kabanmax-ui .cbi-value:not(.hidden) { display:grid; grid-template-columns:minmax(10em, 2fr) minmax(0,3fr); align-items:center; gap:.5em 1em; }
.kabanmax-ui .cbi-value > .cbi-value-title { float:none; width:auto; margin:0; padding:0; text-align:left; line-height:1.5; }
.kabanmax-ui .cbi-value > .cbi-value-field { width:auto; min-width:0; margin:0; padding:0; }
.kabanmax-ui textarea { min-height:9em; resize:vertical; max-width:100%; box-sizing:border-box; white-space:pre-wrap; overflow-wrap:anywhere; overflow-x:hidden; }
.kabanmax-ui .km-empty-auto-tab { display:none; }
.kabanmax-ui .km-flag:not(.hidden) { grid-template-columns:minmax(0,1fr) auto; }
.kabanmax-ui .km-flag > .cbi-value-field { display:flex; align-items:center; justify-content:center; }
.kabanmax-ui .km-flag input[type=checkbox] { margin:0; vertical-align:middle; }
.kabanmax-ui .km-nested { margin-left:1.5em; }
.kabanmax-ui .km-nested-deep { margin-left:3em; }
.kabanmax-ui.fkp-single-field-modal .cbi-value > .cbi-value-title { display:block; }
.kabanmax-ui .cbi-value[data-name="_uri_editor"]:not(.hidden),.kabanmax-ui .cbi-value[data-name="_uri_import"]:not(.hidden) { display:none; }
.km-help { display:inline-flex; align-items:center; justify-content:center; width:1.5em; height:1.5em; padding:0; margin:0 0 0 .4em; border:1px solid currentColor; border-radius:50%; color:inherit; background:transparent; font:inherit; font-size:.85em; vertical-align:middle; cursor:pointer; }
.km-help:focus-visible { outline:2px solid currentColor; outline-offset:2px; }
.km-help-card { position:fixed; z-index:10001; box-sizing:border-box; width:max-content; max-width:min(26em,calc(100vw - 16px)); max-height:min(22em,calc(100vh - 16px)); overflow:auto; padding:1em; border:1px solid currentColor; border-radius:.5em; background:var(--background-color-high,#fff); color:var(--text-color-high,#222); box-shadow:0 3px 18px #0004; }
@media(prefers-color-scheme:dark) { .km-help-card { background:var(--background-color-high,#242424); color:var(--text-color-high,#eee); } }
@media(max-width:480px) { .kabanmax-ui .cbi-value:not(.hidden):not(.km-flag) { grid-template-columns:minmax(0,1fr); } }
.km-forecast label { display:grid; gap:.35em; margin:.75em 0; }
.km-forecast input,.km-forecast select { width:100%; box-sizing:border-box; }
.km-records { overflow-x:auto; }
.km-records table { width:100%; }
.km-records td,.km-records th { padding:.5em; text-align:left; vertical-align:top; }
.km-records__tools { display:flex; gap:.5em; flex-wrap:wrap; align-items:center; margin:.75em 0; }
.kabanmax-ui .cbi-value[data-name="_automatic_routes"]:not(.hidden),.kabanmax-ui .km-forecast:not(.hidden) { grid-template-columns:minmax(0,1fr); }
`;

let nextId = 0;
// One delegated listener set per view, also covering child/stacked dialogs.
export function installFormUx(root: HTMLElement): () => void {
  root.classList.add('kabanmax-ui');
  let active: HTMLButtonElement | null = null;
  let card: HTMLElement | null = null;
  let mounted = root.isConnected;
  let dispose = () => {};
  const descriptions = new WeakMap<HTMLButtonElement, Node[]>();
  const originallyDisabled = new WeakMap<
    HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement,
    boolean
  >();
  const close = (focus = false) => {
    const previous = active;
    previous?.setAttribute('aria-expanded', 'false');
    card?.remove();
    card = null;
    active = null;
    if (focus && previous?.isConnected) previous.focus();
  };
  const attachHelp = (title: HTMLElement, help: HTMLElement[]) => {
    let button = title.querySelector<HTMLButtonElement>('.km-help');
    if (!button) {
      button = document.createElement('button');
      button.type = 'button';
      button.className = 'km-help';
      button.textContent = '?';
      button.setAttribute(
        'aria-label',
        `${_('Help')}: ${title.textContent?.trim() || ''}`,
      );
      button.setAttribute('aria-expanded', 'false');
      button.setAttribute('aria-controls', `km-help-${++nextId}`);
      title.append(button);
    }
    const contents = descriptions.get(button) || [];
    for (const node of help) {
      if (node.textContent?.trim())
        contents.push(...Array.from(node.childNodes));
      const oldIcon = node.closest('.cbi-tooltip-container');
      if (oldIcon && oldIcon !== title) oldIcon.remove();
      else node.remove();
    }
    descriptions.set(button, contents);
  };
  const adapt = (scope: HTMLElement) => {
    scope.classList.add('kabanmax-ui');
    for (const textarea of scope.querySelectorAll<HTMLTextAreaElement>(
      'textarea',
    )) {
      if (textarea.rows < 6) textarea.rows = 6;
      textarea.wrap = 'soft';
    }
    for (const row of scope.querySelectorAll<HTMLElement>('.cbi-value')) {
      if (row.dataset.widget === 'CBI.FlagValue') row.classList.add('km-flag');
      const name = row.dataset.name || '';
      if (name.startsWith('auto_routing_') && name !== 'auto_routing_enabled')
        row.classList.add(
          name === 'auto_routing_ip_only' ? 'km-nested-deep' : 'km-nested',
        );
      const title = row.querySelector<HTMLElement>(':scope > .cbi-value-title');
      if (!title) continue;
      const help = Array.from(
        row.querySelectorAll<HTMLElement>(
          '.cbi-value-description, .cbi-tooltip',
        ),
      ).filter((node) => node.closest('.cbi-value') === row);
      if (!help.length) continue;
      attachHelp(title, help);
    }
    for (const description of scope.querySelectorAll<HTMLElement>(
      '.cbi-section-descr, .cbi-map-descr',
    )) {
      const title = description.parentElement?.querySelector<HTMLElement>(
        ':scope > h2, :scope > h3, :scope > h4',
      );
      if (title) attachHelp(title, [description]);
    }
    // A collapsed advanced group is still nonempty to LuCI's generic tab
    // detector. Base this one tab on its active CBI fields, not that wrapper.
    for (const pane of scope.querySelectorAll<HTMLElement>(
      '[data-tab="auto_routing"][data-tab-title]',
    )) {
      const menu = pane.parentElement?.previousElementSibling;
      const tab = menu?.querySelector<HTMLElement>('[data-tab="auto_routing"]');
      if (tab) {
        const empty = !pane.querySelector('.cbi-value:not(.hidden)');
        tab.hidden = empty;
        tab.classList.toggle('km-empty-auto-tab', empty);
        if (empty && pane.dataset.tabActive === 'true')
          menu?.querySelector<HTMLAnchorElement>('li:not([hidden]) a')?.click();
      }
    }
    for (const row of scope.querySelectorAll<HTMLElement>(
      '.cbi-value[data-name="auto_routing_enabled"]',
    )) {
      const tab = row.parentElement;
      if (!tab) continue;
      const enabled = !!row.querySelector<HTMLInputElement>(
        'input[type=checkbox]',
      )?.checked;
      const contract = tab.querySelector<HTMLTextAreaElement>(
        '[data-name="auto_routing_contract"] textarea',
      );
      let strict = false;
      try {
        const value = JSON.parse(contract?.value || '{}');
        strict =
          !!value.domain &&
          !!value.prefix &&
          (value.mode || 'strict') === 'strict';
      } catch {
        /* Invalid contract never authorizes auto-apply. */
      }
      for (const child of tab.querySelectorAll<HTMLElement>(
        '.cbi-value[data-name^="auto_routing_"]',
      )) {
        const name = child.dataset.name;
        if (name === 'auto_routing_enabled') continue;
        for (const control of child.querySelectorAll<
          HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement
        >('input,select,textarea')) {
          if (!originallyDisabled.has(control))
            originallyDisabled.set(control, control.disabled);
          control.disabled =
            !!originallyDisabled.get(control) ||
            !enabled ||
            name === 'auto_routing_ip_only' ||
            (name === 'auto_routing_apply' && !strict);
        }
      }
      const advanced = tab.querySelector<HTMLElement>(
        '[data-name="auto_routing_contract"]',
      );
      if (advanced && advanced.parentElement === tab) {
        const details = document.createElement('details');
        const summary = document.createElement('summary');
        summary.textContent = _('Advanced settings');
        details.append(summary);
        advanced.before(details);
        details.append(advanced);
      }
    }
  };
  const refresh = () => {
    if (mounted && !root.isConnected) {
      dispose();
      return;
    }
    if (root.isConnected) mounted = true;
    adapt(root);
    // Only dialogs opened while this KABANMAX view is mounted are adapted.
    if (root.isConnected)
      for (const map of document.querySelectorAll<HTMLElement>(
        '#modal_overlay .cbi-map',
      ))
        adapt(map);
    if (active && (!active.isConnected || active.closest('.hidden'))) close();
  };
  const position = () => {
    if (!active || !card) return;
    const rect = active.getBoundingClientRect();
    const box = card.getBoundingClientRect();
    card.style.left = `${Math.max(8, Math.min(rect.left, window.innerWidth - box.width - 8))}px`;
    card.style.top = `${Math.max(8, Math.min(rect.bottom + 6, window.innerHeight - box.height - 8))}px`;
  };
  const click = (event: MouseEvent) => {
    const target = event.target as Element;
    const button = target.closest<HTMLButtonElement>('.km-help');
    if (button && descriptions.has(button)) {
      event.preventDefault();
      event.stopPropagation(); // LuCI label clicks otherwise toggle the associated control.
      if (active === button) return close();
      close();
      active = button;
      card = document.createElement('div');
      card.className = 'km-help-card';
      card.id = button.getAttribute('aria-controls')!;
      card.setAttribute('role', 'region');
      card.setAttribute('aria-label', button.getAttribute('aria-label')!);
      for (const node of descriptions.get(button)!)
        card.append(node.cloneNode(true));
      document.body.append(card);
      button.setAttribute('aria-expanded', 'true');
      position();
    } else if (!card?.contains(target)) close();
  };
  const key = (event: KeyboardEvent) => {
    if (event.key === 'Escape' && active) {
      event.preventDefault();
      event.stopPropagation();
      close(true);
    }
  };
  const scroll = (event: Event) => {
    if (!card?.contains(event.target as Node)) close();
  };
  const change = () => refresh();
  refresh();
  const observer = new MutationObserver(refresh);
  observer.observe(document.body, { childList: true, subtree: true });
  document.addEventListener('click', click, true);
  document.addEventListener('keydown', key, true);
  document.addEventListener('change', change, true);
  document.addEventListener('input', change, true);
  document.addEventListener('widget-change', change, true);
  document.addEventListener('dependency-update', change, true);
  window.addEventListener('resize', position);
  window.addEventListener('scroll', scroll, true);
  dispose = () => {
    close();
    observer.disconnect();
    document.removeEventListener('click', click, true);
    document.removeEventListener('keydown', key, true);
    document.removeEventListener('change', change, true);
    document.removeEventListener('input', change, true);
    document.removeEventListener('widget-change', change, true);
    document.removeEventListener('dependency-update', change, true);
    window.removeEventListener('resize', position);
    window.removeEventListener('scroll', scroll, true);
  };
  return dispose;
}
