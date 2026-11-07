import type { KabanMax } from '../types';

type ServiceStatusTone = 'success' | 'error' | 'progress';

interface ServiceStatusDisplay {
  label: string;
  tone: ServiceStatusTone;
}

const BUSY_LABELS: Record<KabanMax.ServiceBusy, () => string> = {
  start: () => _('The boar comes out of the bushes...'),
  stop: () => _('The boar wraps up the hunt...'),
  restart: () => _('The boar stretches its hooves...'),
  apply: () => _('The boar tidies up its grounds...'),
  install: () => _('The boar updates its homestead...'),
};

// While an operation runs, readiness is briefly false by design, so the operation is reported
// instead of running or stopped.
export function getServiceStatusDisplay({
  running,
  busy,
}: {
  running: boolean;
  busy?: KabanMax.ServiceBusy | null;
}): ServiceStatusDisplay {
  if (busy) {
    return { label: BUSY_LABELS[busy](), tone: 'progress' };
  }

  return running
    ? { label: _('The boar keeps the acorns in check'), tone: 'success' }
    : { label: _('The boar rests'), tone: 'error' };
}

export function getServiceStatusTitle(
  running: boolean,
  busy?: KabanMax.ServiceBusy | null,
): string {
  switch (busy) {
    case 'start':
      return _('starting...');
    case 'stop':
      return _('stopping...');
    case 'restart':
      return _('restarting...');
    case 'apply':
      return _('applying...');
    case 'install':
      return _('installer running...');
    default:
      return running ? _('running') : _('stopped');
  }
}
