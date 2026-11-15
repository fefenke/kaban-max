import { validateRealityTlsOption } from './tlsOptions';
import {
  connectionFingerprintSupported,
  validateCoreFeature,
} from '../../services/coreFeatures.service';
import {
  fingerprintSelectionDefaults,
  fingerprintProfile,
} from '../../services/tlsFingerprints';
import {
  addFingerprintOptions,
  currentFingerprintSelection,
} from './fingerprintOptions';
import { parseConnectionUri } from './connectionUri';
import { KABANMAX_UCI_PACKAGE } from '../../../constants';
import { getProxyUrlName } from '../../../helpers/getProxyUrlName';
import { nextNumberedName } from '../../../helpers/nextNumberedName';
import { validateProxyUrl } from '../../../validators/validateProxyUrl';
import { getChildItemIds, isExistingChildItem } from '../../cbi/childItems';
import { updateDynamicListItemLabel } from '../../cbi/listItems';
import {
  modalOptionFormValue,
  showChildItemSettingsModal,
} from '../../cbi/modal';
import { required } from '../../cbi/required';
import { childPendingSettingsStore } from '../../cbi/itemSettings';
import { E } from '../../../helpers/element';
import {
  addConnectionEditorOptions,
  connectionEditorDefaults,
  connectionEditorUri,
  currentConnectionEditorUri,
} from './connectionEditor';
import { addCascadeOptions } from './cascade';
import { validateConnectionUriCore } from './coreSupport';
import {
  refreshLiveChoiceWidgets,
  outboundNameSourceOptions,
  sectionChildNames,
  validateSectionChildListName,
} from './outboundNames';

export function validateConnectionLink(value: unknown) {
  const link = `${value ?? ''}`.trim();
  if (!link) {
    return true;
  }

  const validation = validateProxyUrl(link);
  return validation === true ? validateConnectionUriCore(link) : validation;
}

// As the dialog holds them now, or the stored links when the list is not on screen.
function listedLinkValues(sectionId: string, option: CBIOption): string[] {
  let values: unknown = null;
  try {
    values = option && option.formvalue ? option.formvalue(sectionId) : null;
  } catch (_error) {
    values = null;
  }

  return Array.isArray(values)
    ? values.map((value) => `${value || ''}`.trim()).filter(Boolean)
    : getChildItemIds(sectionId, 'connection_link');
}

// A link still in the add field is no entry yet and holds no name.
function listedLinkName(sectionId: string, value: string) {
  return isExistingChildItem(sectionId, value, 'connection_link')
    ? `${uci.get(KABANMAX_UCI_PACKAGE, value, 'name') || ''}`.trim()
    : '';
}

// Named after the server it describes ("／" for "/"), or "Node #N"; a name the section already
// holds gets "#1" and up, so the same link added twice is two servers.
export function nextLinkName(
  sectionId: string,
  option: CBIOption,
  link: string,
) {
  const linkNames = listedLinkValues(sectionId, option)
    .map((value) => listedLinkName(sectionId, value))
    .filter(Boolean);
  const taken = new Set([
    ...linkNames,
    ...sectionChildNames(sectionId)
      .filter((child) => child.kind !== 'link')
      .map((child) => child.name),
  ]);
  const own = getProxyUrlName(link).trim().replaceAll('/', '／');
  if (own && !taken.has(own)) {
    return own;
  }
  return nextNumberedName(own || 'Node', [...taken]);
}

export function connectionLinkListItemLabel(sectionId: string, value: string) {
  return E(
    'span',
    { class: 'fkp-dynlist-label' },
    listedLinkName(sectionId, value),
  );
}

// Fallback and URLTest exact filters store display names, not connection ids.
// Keep their positions on rename and clear references before a name can be reused.
function updateManualLinkReferences(
  sectionId: string,
  previousName: string,
  nextName = '',
) {
  if (!previousName || previousName === nextName) return;
  const groups = new Set(getChildItemIds(sectionId, 'fallback_group'));
  const filters = [
    ...uci
      .sections(KABANMAX_UCI_PACKAGE, 'fallback_level')
      .filter((level) => groups.has(`${level.group || ''}`)),
    ...uci
      .sections(KABANMAX_UCI_PACKAGE, 'urltest')
      .filter((group) => group.section === sectionId),
  ];
  filters.forEach((level) => {
    for (const key of ['include_outbounds', 'exclude_outbounds']) {
      const names = L.toArray(level[key]).map((name) => `${name}`);
      if (!names.some((name) => `${name}`.trim() === previousName)) continue;
      const updated = names.flatMap((name) =>
        `${name}`.trim() === previousName
          ? nextName
            ? [nextName]
            : []
          : [name],
      );
      if (updated.length) {
        uci.set(KABANMAX_UCI_PACKAGE, level['.name'], key, updated);
      } else {
        uci.unset(KABANMAX_UCI_PACKAGE, level['.name'], key);
      }
    }
  });
  const urltestOption = outboundNameSourceOptions.get('urltest');
  if (urltestOption) {
    for (const settings of Object.values(
      childPendingSettingsStore(urltestOption, sectionId),
    )) {
      for (const key of ['include_outbounds', 'exclude_outbounds']) {
        const values = L.toArray(settings[key]).map((value) => `${value}`);
        if (!values.some((value) => value.trim() === previousName)) continue;
        const updated = values.flatMap((value) =>
          value.trim() === previousName
            ? nextName
              ? [nextName]
              : []
            : [value],
        );
        if (updated.length) settings[key] = updated;
        else delete settings[key];
      }
    }
  }
}

export function removeConnectionLinkReferences(itemId: string) {
  updateManualLinkReferences(
    `${uci.get(KABANMAX_UCI_PACKAGE, itemId, 'section') || ''}`,
    `${uci.get(KABANMAX_UCI_PACKAGE, itemId, 'name') || ''}`.trim(),
  );
}

function connectionLinkSettingsKeys() {
  return [
    'name',
    'uri',
    'detour_section',
    'tls_record_fragment',
    'tls_classical',
    'tls_fingerprint',
  ];
}

function writeTrimmed(this: CBIOption, itemId: string, value: unknown) {
  return form.Value.prototype.write.call(this, itemId, `${value ?? ''}`.trim());
}

export function showConnectionLinkSettingsModal(
  sectionId: string,
  itemValue: unknown,
  option: CBIOption,
  widget: CBIWidget,
  itemNode: Element | null,
) {
  const name = listedLinkName(sectionId, `${itemValue ?? ''}`);
  let editorMap: CBIMap;
  return showChildItemSettingsModal(sectionId, itemValue, option, {
    typeName: 'connection_link',
    valueOption: 'uri',
    keys: connectionLinkSettingsKeys(),
    itemNode,
    defaults: (inputValue: string) => ({
      uri: inputValue,
      name,
      ...connectionEditorDefaults(inputValue),
      ...fingerprintSelectionDefaults(
        `${uci.get(KABANMAX_UCI_PACKAGE, `${itemValue || ''}`, 'tls_fingerprint') || ''}`,
      ),
    }),
    prepareSave: (settings) => {
      settings = {
        ...settings,
        tls_fingerprint: currentFingerprintSelection(editorMap),
      };
      const uri = connectionEditorUri({
        ...settings,
        uri: modalOptionFormValue(editorMap, 'settings', 'uri') ?? settings.uri,
      });
      const validation = validateConnectionLink(uri);
      if (validation !== true) throw new Error(validation);
      const parsed = parseConnectionUri(uri);
      const effectiveFingerprint = `${settings.tls_fingerprint || parsed.fingerprint}`;
      if (
        parsed.security === 'reality' &&
        fingerprintProfile(effectiveFingerprint)?.reality === 'unsupported'
      )
        throw new Error(_('This fingerprint does not support REALITY.'));
      for (const key of ['tls_record_fragment', 'tls_classical']) {
        const result = validateRealityTlsOption(uri, settings[key]);
        if (result !== true) throw new Error(result);
      }
      if (
        settings.tls_fingerprint &&
        !connectionFingerprintSupported(uri, `${settings.tls_fingerprint}`)
      )
        throw new Error(
          _(
            'TLS fingerprint requires a supported TCP connection with TLS enabled.',
          ),
        );
      if (settings.tls_fingerprint) {
        if (!fingerprintProfile(`${settings.tls_fingerprint}`))
          throw new Error(_('Unsupported TLS fingerprint.'));
        const coreValidation = validateCoreFeature('utls');
        if (coreValidation !== true) throw new Error(coreValidation);
      }
      return { ...settings, uri };
    },
    addOptions: (itemSection: CBISection) => {
      editorMap = itemSection.map;
      let o = itemSection.option(form.Value, 'name', _('Server name'));
      o.write = writeTrimmed;
      o.validate = required(function (_itemId, value) {
        return validateSectionChildListName(
          sectionId,
          'link',
          widget,
          itemNode,
          value,
        );
      });

      addConnectionEditorOptions(itemSection, validateConnectionLink);

      o = itemSection.option(
        form.Flag,
        'tls_record_fragment',
        _('Split ClientHello into two TLS records'),
        _(
          'Split the initial ClientHello into two approximately equal TLS records. Applies to traffic and availability checks.',
        ),
      );
      o.default = '0';
      o.rmempty = true;
      o.validate = function (itemId: string, value: unknown) {
        return validateRealityTlsOption(
          currentConnectionEditorUri(this.map, itemId),
          value,
        );
      };

      o = itemSection.option(
        form.Flag,
        'tls_classical',
        _('Classical key exchange only'),
        _(
          'Disable X25519MLKEM768 for traffic and availability checks. This option is independent of TLS record splitting.',
        ),
      );
      o.default = '0';
      o.rmempty = true;
      o.validate = function (itemId: string, value: unknown) {
        return validateRealityTlsOption(
          currentConnectionEditorUri(this.map, itemId),
          value,
        );
      };

      addFingerprintOptions(itemSection, currentConnectionEditorUri);

      addCascadeOptions(
        itemSection,
        () => sectionId,
        _('Connect to the server through another section'),
      );
    },
    title: () => (name ? _('Server: %s').format(name) : _('Server settings')),
    afterSave: (
      _itemId: string,
      _inputValue: string,
      settings: ChildSettings,
    ) => {
      updateManualLinkReferences(
        sectionId,
        name,
        `${settings.name || ''}`.trim(),
      );
      updateDynamicListItemLabel(itemNode, `${settings.name || ''}`.trim());
      refreshLiveChoiceWidgets(sectionId);
    },
  });
}
