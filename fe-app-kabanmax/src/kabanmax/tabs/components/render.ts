import { E } from '../../../helpers/element';
import { renderZapret2 } from './zapret2';

// The controller starts with the form, before LuCI puts the node into the document.
export let pageRoot: HTMLElement | null = null;

// One compact control rail; the game uses the remaining width.
export function render() {
  pageRoot = E(
    'div',
    { id: 'components-status', class: 'fkp_components-page' },
    [
      E('div', { class: 'fkp_components-page__controls' }, [
        E('div', {
          id: 'components-actions',
          class: 'fkp_components-page__block',
        }),
        renderZapret2(),
        E('div', {
          id: 'components-config',
          class: 'fkp_components-page__block',
        }),
      ]),
      E('div', { id: 'components-game', class: 'fkp_components-page__game' }),
      E('div', { id: 'components-run', class: 'fkp_components-page__run' }),
    ],
  );
  return pageRoot;
}
