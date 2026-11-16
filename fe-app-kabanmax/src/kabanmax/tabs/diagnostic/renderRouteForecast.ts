import { E } from '../../../helpers/element';
import { loadLocalDevices, SYSTEM_DEVICE_VALUE } from '../../cbi/localDevices';
import { requestRouteForecast, formatRouteForecast } from './routeForecast';

// No probes: this only invokes the existing read-only CLI forecast.
export function renderRouteForecast() {
  const destination = E('input', {
    type: 'text',
    maxLength: 253,
    'aria-label': _('Destination domain or IP'),
  }) as HTMLInputElement;
  const source = E('select', { 'aria-label': _('Device') }, [
    E('option', { value: '' }, _('Select a device')),
    E('option', { value: SYSTEM_DEVICE_VALUE }, _('System (router)')),
  ]) as HTMLSelectElement;
  const port = E('input', {
    type: 'number',
    value: '443',
    min: '1',
    max: '65535',
    'aria-label': _('Port'),
  }) as HTMLInputElement;
  const output = E('p', {}, '');
  output.setAttribute('aria-live', 'polite');
  const technical = E('pre', {}, '');
  const details = E('details', {}, [E('summary', {}, _('Details')), technical]);
  details.hidden = true;
  const button = E(
    'button',
    {
      type: 'button',
      class: 'cbi-button',
      click: async () => {
        if (button.disabled) return;
        if (!source.value) {
          output.textContent = _('Select a device');
          return;
        }
        button.disabled = true;
        output.textContent = _('Checking…');
        details.hidden = true;
        try {
          const result = await requestRouteForecast(
            destination.value.trim(),
            source.value,
            port.value,
          );
          const predicted = result.predicted;
          output.textContent = predicted.outbound
            ? `${_('Expected section')}: ${predicted.outbound} / ${_('Route')}: ${predicted.action || predicted.status}`
            : _('Unable to determine the route');
          technical.textContent = formatRouteForecast(result);
          details.hidden = false;
        } catch (error) {
          output.textContent =
            error instanceof Error ? error.message : String(error);
        } finally {
          button.disabled = false;
        }
      },
    },
    _('Show route'),
  ) as HTMLButtonElement;
  let loaded = false;
  const tools = E('details', {}, [
    E('summary', {}, _('Additional tools')),
    E('div', { class: 'km-forecast cbi-value' }, [
      E('h3', { class: 'cbi-value-title' }, _('Route forecast')),
      E('div', { class: 'cbi-value-field' }, [
        E(
          'div',
          { class: 'cbi-value-description' },
          _(
            'Read-only forecast. Does not run network probes or change routes. DNS and live nft/PBR state are not verified.',
          ),
        ),
        E('label', {}, [_('Destination domain or IP'), destination]),
        E('label', {}, [_('Device'), source]),
        E('label', {}, [_('Port'), port]),
        button,
        output,
        details,
      ]),
    ]),
  ]) as HTMLDetailsElement;
  tools.addEventListener('toggle', async () => {
    if (!tools.open || loaded) return;
    loaded = true;
    try {
      const devices = await loadLocalDevices();
      for (const ip of devices.order)
        if (ip !== SYSTEM_DEVICE_VALUE)
          source.append(E('option', { value: ip }, devices.choices[ip] || ip));
      if (!devices.order.length)
        output.textContent = _(
          'No LAN devices available; you can select the router.',
        );
    } catch {
      loaded = false;
      output.textContent = _('Unable to load LAN devices');
    }
  });
  return tools;
}
