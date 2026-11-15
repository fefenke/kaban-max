import { E } from '../../../helpers/element';
import { requestRouteForecast, formatRouteForecast } from './routeForecast';

// This control has no apply action and never calls /delay or changes a selector.
export function renderRouteForecast() {
  const destination = E('input', {
    type: 'text',
    placeholder: 'example.test / IPv4 / IPv6',
    'aria-label': _('Destination'),
    maxLength: 253,
  }) as HTMLInputElement;
  const source = E('input', {
    type: 'text',
    placeholder: 'LAN IP / @system',
    'aria-label': _('Source'),
    maxLength: 45,
  }) as HTMLInputElement;
  const port = E('input', {
    type: 'number',
    value: '443',
    min: '1',
    max: '65535',
    'aria-label': _('Port'),
  }) as HTMLInputElement;
  const output = E('pre', {}, '');
  output.setAttribute('aria-live', 'polite');
  const button = E(
    'button',
    {
      type: 'button',
      class: 'cbi-button',
      click: async () => {
        if (button.disabled) return;
        button.disabled = true;
        output.textContent = '…';
        try {
          const result = await requestRouteForecast(
            destination.value.trim(),
            source.value.trim(),
            port.value,
          );
          output.textContent = formatRouteForecast(result);
        } catch (error) {
          output.textContent =
            error instanceof Error ? error.message : String(error);
        } finally {
          button.disabled = false;
        }
      },
    },
    _('Route forecast'),
  ) as HTMLButtonElement;
  return E('div', { class: 'cbi-section' }, [
    E('h3', {}, _('Route forecast')),
    E(
      'p',
      {},
      _(
        'Read-only forecast for non-DNS TCP from the generated configuration. DNS, live core state and nft/PBR are not verified. Rule indexes start at zero.',
      ),
    ),
    destination,
    source,
    port,
    button,
    E(
      'p',
      {},
      _(
        'This forecast does not run probes or change routes. Configure opt-in automatic routing in the Zapret2 section; it requires the r11 core extension.',
      ),
    ),
    output,
  ]);
}
