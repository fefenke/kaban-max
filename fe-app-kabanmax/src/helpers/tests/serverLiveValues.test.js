import { describe, expect, it } from 'vitest';

import { installLuciStubs } from './luciStubs';
import { visibleClientFields } from '../../kabanmax/tabs/servers/clients';
import { liveOption } from '../../kabanmax/tabs/servers/formValues';
import { isAuthenticationEnabled } from '../../kabanmax/tabs/servers/protocols';

function widget(sectionId, name, value) {
  return {
    [`cbid.kabanmax.${sectionId}.${name}`]: {
      instance: { getValue: () => value },
    },
  };
}

function load(server, widgets = {}) {
  installLuciStubs(
    { srv: { '.type': 'server', label: 'Home', enabled: '1', ...server } },
    widgets,
  );
  return { isAuthenticationEnabled, visibleClientFields, liveOption };
}

describe('live option values', () => {
  it('reads a flag from its widget, not from the configuration', () => {
    const view = load(
      { protocol: 'mixed', mixed_auth_enabled: '0' },
      widget('srv', 'mixed_auth_enabled', '1'),
    );

    expect(view.liveOption('srv', 'mixed_auth_enabled')).toBe('1');
    expect(view.isAuthenticationEnabled('srv')).toBe(true);
  });

  it('offers a password once authentication is switched on', () => {
    const off = load({ protocol: 'mixed', mixed_auth_enabled: '0' });
    expect(off.visibleClientFields('srv')).toEqual([]);

    const pending = load(
      { protocol: 'mixed', mixed_auth_enabled: '0' },
      widget('srv', 'mixed_auth_enabled', '1'),
    );
    expect(pending.visibleClientFields('srv')).toEqual(['password']);
  });

  it('falls back to the configuration when no widget is mounted', () => {
    const view = load({ protocol: 'mixed', mixed_auth_enabled: '1' });

    expect(view.liveOption('srv', 'mixed_auth_enabled')).toBe('1');
    expect(view.visibleClientFields('srv')).toEqual(['password']);
  });
});
