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

async function command(args: string[]): Promise<Zapret2Status> {
  const reply = await executeShellCommand({
    command: '/usr/bin/forkop',
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
  const status = E('p', {}, _('Loading...'));
  const details = E(
    'p',
    {},
    _(
      'Official zapret2 engine and Lua update together. Section strategies are kept.',
    ),
  );
  const check = E(
    'button',
    { type: 'button', class: 'cbi-button' },
    _('Check for updates'),
  ) as HTMLButtonElement;
  const install = E(
    'button',
    { type: 'button', class: 'cbi-button cbi-button-action' },
    _('Install / Update'),
  ) as HTMLButtonElement;
  const root = E('div', { class: 'fkp_components-page__block' }, [
    E('b', {}, 'Zapret2'),
    status,
    details,
    check,
    install,
  ]);
  let busy = false;

  async function refresh() {
    try {
      const state = await command(['zapret2_status']);
      busy = Boolean(state.running);
      status.textContent = `Zapret2: ${state.installed || '—'} · ${state.architecture || '—'}${state.latest ? ` · ${state.latest}` : ''}`;
      details.textContent =
        state.message ||
        _(
          'Official zapret2 engine and Lua update together. Section strategies are kept.',
        );
      if (busy && root.isConnected)
        window.setTimeout(() => void refresh(), 1500);
    } catch (error) {
      details.textContent = (error as Error).message;
      busy = false;
    }
    check.disabled = busy;
    install.disabled = busy;
  }

  async function run(action: string) {
    busy = true;
    check.disabled = install.disabled = true;
    try {
      await command(['zapret2_update', action]);
      await refresh();
    } catch (error) {
      details.textContent = (error as Error).message;
      busy = false;
      check.disabled = install.disabled = false;
    }
  }
  check.onclick = () => void run('check');
  install.onclick = () => void run('install');
  window.setTimeout(() => void refresh(), 0);
  return root;
}
