import { singBoxDurationSeconds } from '../../../../validators/validateSingBoxDuration';
import { KABANMAX_UCI_PACKAGE } from '../../../../constants';

export function addAutoStorageOptions(section: CBISection) {
  for (const [key, label, help, fallback, min, max] of [
    [
      'auto_routing_save_interval',
      _('Automatic routing save interval'),
      _(
        'Save changed routes and exclusions to flash. Default: 1d. Unsaved changes may be lost on power failure. Memory pressure can trigger a checkpoint, at most once per 15 minutes.',
      ),
      '1d',
      900,
      2592000,
    ],
  ] as const) {
    const o = section.option(form.Value, key, label, help);
    o.default = fallback;
    o.placeholder = fallback;
    o.cfgvalue = (sectionId: string) =>
      uci.get(KABANMAX_UCI_PACKAGE, sectionId, key) || fallback;
    o.validate = (_sectionId: string, value: string) => {
      const seconds = singBoxDurationSeconds(value);
      return seconds !== null && seconds >= min && seconds <= max
        ? true
        : _('Duration is outside the allowed range');
    };
  }
  const memory = section.option(
    form.Value,
    'auto_routing_memory_mib',
    _('Automatic routing memory budget (MiB)'),
    _(
      'Accounted memory budget, 1–32 MiB. Half is reserved for routes and exclusions; the rest is for pending errors and check results, kept until reviewed. When full, existing records are kept and new records are rejected. Increasing this does not add router RAM.',
    ),
  );
  memory.default = '4';
  memory.placeholder = '4';
  memory.cfgvalue = (sectionId: string) =>
    uci.get(KABANMAX_UCI_PACKAGE, sectionId, 'auto_routing_memory_mib') || '4';
  memory.validate = (_sectionId: string, value: string) =>
    /^\d+$/.test(value) && Number(value) >= 1 && Number(value) <= 32
      ? true
      : _('Enter a whole number from 1 to 32');
}
