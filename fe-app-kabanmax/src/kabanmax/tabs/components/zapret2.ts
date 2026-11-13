import { E } from '../../../helpers/element';
import { executeShellCommand } from '../../../helpers/executeShellCommand';

interface Zapret2Status {
  installed?: string;
  latest?: string;
  architecture?: string;
  running?: boolean;
  success?: boolean;
  message?: string;
}

export function zapretAction(
  state: Zapret2Status,
  checked: boolean,
  busy: boolean,
) {
  const available =
    checked &&
    state.success !== false &&
    state.latest &&
    state.latest !== state.installed;
  return {
    action: available ? (state.installed ? 'update' : 'install') : 'check',
    disabled: busy,
  };
}

async function command(args: string[]): Promise<Zapret2Status> {
  const reply = await executeShellCommand({
    command: '/usr/bin/kabanmax',
    args,
    timeout: 15000,
  });
  const result = JSON.parse(reply.stdout || '{}') as Zapret2Status;
  if (
    reply.code ||
    (args[0] !== 'zapret2_status' && result.success === false)
  ) {
    throw new Error(result.message || reply.stderr || _('Failed to execute'));
  }
  return result;
}

export function renderZapret2(): HTMLElement {
  const status = E(
    'span',
    { class: 'fkp_components-page__heading-version' },
    '',
  );
  const details = E('p', { role: 'status', hidden: true });
  const install = E(
    'button',
    { type: 'button', class: 'cbi-button cbi-button-action' },
    _('Install / Update'),
  ) as HTMLButtonElement;
  const root = E('div', { class: 'fkp_components-page__block' }, [
    E('div', { class: 'fkp_components-page__heading' }, [
      E('b', {}, 'Zapret2'),
      status,
    ]),
    details,
    install,
  ]);
  let busy = true;
  let state: Zapret2Status = {};
  let checked = false;
  function showDetails(text: string, tone: '' | 'success' | 'error' = '') {
    details.textContent = text;
    details.hidden = !text;
    details.className = `fkp_components-page__update-status${tone ? ` fkp_components-page__update-status--${tone}` : ''}`;
  }
  function draw() {
    const next = zapretAction(state, checked, busy);
    install.disabled = next.disabled;
    install.textContent = busy
      ? _('in progress')
      : next.action === 'update'
        ? _('Update')
        : next.action === 'install'
          ? _('Install')
          : _('Check for updates');
  }

  async function refresh() {
    try {
      state = await command(['zapret2_status']);
      busy = Boolean(state.running);
      status.textContent = state.installed || '\u2014';
      showDetails(
        state.success === false || busy
          ? state.message || (busy ? _('in progress') : _('failed'))
          : checked && state.latest
            ? state.latest === state.installed
              ? _('No updates available')
              : `${_('Update available')}: ${state.latest}`
            : '',
        busy
          ? ''
          : state.success === false
            ? 'error'
            : checked && state.latest
              ? 'success'
              : '',
      );
      if (busy && root.isConnected)
        window.setTimeout(() => void refresh(), 1500);
    } catch (error) {
      showDetails((error as Error).message, 'error');
      busy = false;
      checked = false;
    }
    draw();
  }

  async function run(action: string) {
    if (busy) return;
    busy = true;
    showDetails(_('in progress'));
    draw();
    try {
      await command(['zapret2_update', action]);
      checked = true;
      await refresh();
    } catch (error) {
      showDetails((error as Error).message, 'error');
      busy = false;
      checked = false;
      draw();
    }
  }
  install.onclick = () =>
    void run(
      zapretAction(state, checked, busy).action !== 'check'
        ? 'install'
        : 'check',
    );
  draw();
  window.setTimeout(() => void refresh(), 0);
  return root;
}
