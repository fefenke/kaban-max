import { E } from '../../../helpers/element';
import type { ReleaseCheck } from './releaseCheck';

export function renderUpdateStatus(
  busy: boolean,
  error: string,
  release: ReleaseCheck | null,
) {
  const node = E(
    'p',
    {
      role: 'status',
      class: `fkp_components-page__update-status${busy ? '' : error ? ' fkp_components-page__update-status--error' : release ? ' fkp_components-page__update-status--success' : ''}`,
    },
    busy
      ? _('The boar looks for fresh acorns...')
      : error ||
          (release?.update_available
            ? `${_('Update available')}: ${release.latest || release.release || ''}`
            : release
              ? _('No updates available')
              : ''),
  );
  node.hidden = !busy && !error && !release;
  return node;
}
