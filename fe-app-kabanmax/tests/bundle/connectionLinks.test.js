import { beforeEach, describe, expect, it } from 'vitest';

import { coreFeatures } from '../lib/coreFeatures.js';
import { createHarness } from '../lib/luciForm.js';

let harness;

beforeEach(() => {
  harness = createHarness();
  harness.bundle.setCoreFeatures(coreFeatures());
  harness.uci.add('kabanmax', 'section', 'sec');
  Object.assign(harness.store.get('sec'), {
    action: 'connection',
    enabled: '1',
    label: 'Proxy',
  });
});

function linkList() {
  const map = new harness.form.Map('kabanmax');
  const grid = map.section(harness.form.GridSection, 'section');
  delete grid.load;
  harness.bundle.createSectionContent(grid);
  const option = (name) => grid.children.find((item) => item.option === name);
  for (const name of ['connection_link', 'urltest']) {
    option(name).cfgvalue('sec', option(name).load('sec'));
  }
  return option('connection_link');
}

function paste(list, values, link) {
  const itemId = list.createTypedItem('sec', link);
  const label = list.renderListItemLabel('sec', itemId).textContent;
  values.push(itemId);
  list.onListChange('sec', values.slice());
  return label;
}

function storedLinks() {
  return harness.uci
    .sections('kabanmax', 'connection_link')
    .map(({ section, uri, name, order }) => ({ section, uri, name, order }));
}

describe('manual servers referenced by fallback levels', () => {
  it('keeps protocol parameters collapsed and has one effective TLS selector', async () => {
    const list = linkList();
    const values = [];
    paste(
      list,
      values,
      'vless://a@node.example:443?security=tls&fp=chrome#Node',
    );
    const dialog = await harness.openDialog(list, 'sec', values[0]);
    const fields = dialog.map.children[0].children;
    const option = (name) => fields.find((o) => o.option === name);
    expect(option('_uri_show').default).toBe('0');
    expect(option('_uri_server').deps).toEqual(
      expect.arrayContaining([expect.objectContaining({ _uri_show: '1' })]),
    );
    expect(option('tls_fingerprint').vallist).not.toContain('Firefox 148');
    expect(option('_tls_variant').vallist).toEqual(['133', '155']);
  });
  beforeEach(() => {
    for (const [id, name, order] of [
      ['austria', 'Austria', '0'],
      ['poland', 'Poland', '1'],
    ]) {
      harness.uci.add('kabanmax', 'connection_link', id);
      Object.assign(harness.store.get(id), {
        section: 'sec',
        name,
        order,
        uri: `socks://127.0.0.1:1080#${name}`,
      });
    }
    harness.uci.add('kabanmax', 'fallback_group', 'backup');
    Object.assign(harness.store.get('backup'), {
      section: 'sec',
      name: 'Backup',
    });
    harness.uci.add('kabanmax', 'fallback_level', 'level');
    Object.assign(harness.store.get('level'), {
      group: 'backup',
      name: 'Primary',
      order: '0',
      include_outbounds: ['Austria', 'Poland'],
      exclude_outbounds: ['Poland'],
      include_regex: '^Poland$',
    });
    harness.uci.add('kabanmax', 'fallback_group', 'other');
    Object.assign(harness.store.get('other'), {
      section: 'other_section',
      name: 'Other',
    });
    harness.uci.add('kabanmax', 'fallback_level', 'other_level');
    Object.assign(harness.store.get('other_level'), {
      group: 'other',
      include_outbounds: ['Poland'],
    });
  });

  it('keeps identity on URI edit and follows repeated renames without changing priority or regex', async () => {
    const list = linkList();
    list.formvalue = () => ['austria', 'poland'];
    const dialog = await harness.openDialog(list, 'sec', 'poland');
    dialog.map.children[0].children.find((o) => o.option === 'uri').formvalue =
      () => 'socks://127.0.0.1:1081#New';
    dialog.map.children[0].children.find(
      (o) => o.option === '_uri_editor',
    ).formvalue = () => 'raw';
    dialog.map.children[0].children.find(
      (o) => o.option === '_uri_show',
    ).formvalue = () => '1';
    expect((await dialog.save()).saved).toBe(true);
    expect(harness.store.get('poland').uri).toBe('socks://127.0.0.1:1081#New');
    for (const name of ['Warsaw', 'Poland']) {
      const rename = await harness.openDialog(list, 'sec', 'poland');
      rename.map.children[0].children.find(
        (o) => o.option === 'name',
      ).formvalue = () => name;
      expect((await rename.save()).saved, harness.toasts().join('; ')).toBe(
        true,
      );
      expect(harness.store.get('level').include_outbounds).toEqual([
        'Austria',
        name,
      ]);
      expect(harness.store.get('level').exclude_outbounds).toEqual([name]);
    }
    await list.parse('sec');
    await list.parse('sec');
    expect(storedLinks().map(({ name }) => name)).toEqual([
      'Austria',
      'Poland',
    ]);
    expect(harness.store.get('level').order).toBe('0');
    list.formvalue = () => ['poland', 'austria'];
    await list.parse('sec');
    expect(harness.store.get('poland').order).toBe('0');
    expect(harness.store.get('austria').order).toBe('1');
    expect(harness.store.get('level').include_outbounds).toEqual([
      'Austria',
      'Poland',
    ]);
    expect(harness.store.get('level').include_regex).toBe('^Poland$');
    expect(harness.store.get('other_level').include_outbounds).toEqual([
      'Poland',
    ]);
  });

  it('clears deleted server references before a new server can reuse its name', async () => {
    const list = linkList();
    list.formvalue = () => ['austria'];
    await list.parse('sec');
    expect(harness.store.get('level').include_outbounds).toEqual(['Austria']);
    expect(harness.store.get('level').exclude_outbounds).toBeUndefined();
    const values = ['austria'];
    list.formvalue = () => values.slice();
    expect(paste(list, values, 'socks://127.0.0.1:1082#Poland')).toBe('Poland');
    await list.parse('sec');
    await list.parse('sec');
    expect(storedLinks().map(({ name }) => name)).toEqual([
      'Austria',
      'Poland',
    ]);
    expect(harness.store.get('level').include_outbounds).toEqual(['Austria']);
    expect(harness.store.get('other_level').include_outbounds).toEqual([
      'Poland',
    ]);
  });
});

describe('a pasted link', () => {
  it('is listed under its own name, a number, or its name and a number', () => {
    const list = linkList();
    const values = [];
    list.formvalue = () => values.slice();

    expect(
      [
        'vless://a@a.example:443#USA',
        'trojan://p@b.example:443',
        'vless://c@c.example:443#USA',
        'vmess://' +
          Buffer.from(
            JSON.stringify({ ps: 'VMess node', add: 'd.example' }),
          ).toString('base64'),
      ].map((link) => paste(list, values, link)),
    ).toEqual(['USA', 'Node #1', 'USA #1', 'VMess node']);
  });

  it('is saved as a link of the section under the name the list shows', async () => {
    const list = linkList();
    const values = [];
    list.formvalue = () => values.slice();
    paste(list, values, 'vless://a@a.example:443#USA');
    paste(list, values, 'trojan://p@b.example:443');

    await list.parse('sec');

    expect(storedLinks()).toEqual([
      {
        section: 'sec',
        uri: 'vless://a@a.example:443#USA',
        name: 'USA',
        order: '0',
      },
      {
        section: 'sec',
        uri: 'trojan://p@b.example:443',
        name: 'Node #1',
        order: '1',
      },
    ]);
  });

  it('pasted twice is two servers told apart by name', async () => {
    const list = linkList();
    const values = [];
    list.formvalue = () => values.slice();
    const link = 'vless://a@a.example:443#USA';

    expect([paste(list, values, link), paste(list, values, link)]).toEqual([
      'USA',
      'USA #1',
    ]);
    await list.parse('sec');

    expect(storedLinks()).toEqual([
      { section: 'sec', uri: link, name: 'USA', order: '0' },
      { section: 'sec', uri: link, name: 'USA #1', order: '1' },
    ]);
  });

  it('takes a name no server or group of the section holds, without a slash', () => {
    harness.uci.add('kabanmax', 'urltest', 'ut1');
    Object.assign(harness.store.get('ut1'), {
      section: 'sec',
      name: 'Fastest',
    });
    const list = linkList();
    const values = [];
    list.formvalue = () => values.slice();

    expect([
      paste(list, values, 'vless://a@a.example:443#Fastest'),
      paste(list, values, 'vless://b@b.example:443#US%2FLA'),
    ]).toEqual(['Fastest #1', 'US／LA']);
  });

  it('takes the name the link carries when the link already in the list was renamed', () => {
    const link = 'vless://a@a.example:443#test1';
    harness.uci.add('kabanmax', 'connection_link', 'link1');
    Object.assign(harness.store.get('link1'), {
      section: 'sec',
      uri: link,
      name: 'test2',
      order: '0',
    });
    const list = linkList();
    const values = ['link1'];
    list.formvalue = () => values.slice();

    expect(paste(list, values, link)).toBe('test1');
  });

  it('typed and saved without being added still gets a name of its own', async () => {
    const list = linkList();
    const values = [];
    paste(list, values, 'vless://a@a.example:443#Same');
    list.formvalue = () => [...values, 'vless://b@b.example:443#Same'];

    await list.parse('sec');

    expect(storedLinks().map((link) => link.name)).toEqual(['Same', 'Same #1']);
  });

  it('takes the name its dialog gave it', async () => {
    const list = linkList();
    const values = [];
    list.formvalue = () => values.slice();
    const link = 'vless://a@a.example:443#USA';
    paste(list, values, link);

    const dialog = await harness.openDialog(list, 'sec', values[0]);
    const fields = dialog.map.children[0].children;
    fields.find((option) => option.option === 'name').formvalue = () =>
      ' New York ';
    expect((await dialog.save()).saved).toBe(true);
    await list.parse('sec');

    expect(storedLinks()).toEqual([
      { section: 'sec', uri: link, name: 'New York', order: '0' },
    ]);
  });

  it('taken out again is gone after the save', async () => {
    harness.uci.add('kabanmax', 'connection_link', 'link1');
    Object.assign(harness.store.get('link1'), {
      section: 'sec',
      uri: 'vless://a@a.example:443#USA',
      name: 'USA',
      order: '0',
    });
    const list = linkList();
    const values = ['link1'];
    list.formvalue = () => values.slice();
    paste(list, values, 'trojan://p@b.example:443#Other');
    values.pop();

    await list.parse('sec');

    expect(storedLinks().map((link) => link.name)).toEqual(['USA']);
  });
});

describe('a stored link', () => {
  it.each([
    ['vless://u@a.example:443?security=tls', true],
    ['vless://u@a.example:443?security=none', false],
    ['hysteria2://p@a.example:443', false],
  ])(
    'refuses an override with missing uTLS or incompatible transport',
    async (uri, missingUtls) => {
      if (missingUtls)
        harness.bundle.setCoreFeatures(coreFeatures({ remove: ['with_utls'] }));
      harness.store.get('link1').uri = uri;
      const before = JSON.stringify(harness.store.get('link1'));
      const dialog = await harness.openDialog(linkList(), 'sec', 'link1');
      const option = dialog.map.children[0].children.find(
        (o) => o.option === 'tls_fingerprint',
      );
      expect(option.isActive('settings')).toBe(false);
      option.formvalue = () => 'randomized';
      expect((await dialog.save()).saved).toBe(false);
      expect(JSON.stringify(harness.store.get('link1'))).toBe(before);
    },
  );
  it('preserves a legacy alias without offering duplicate Chrome entries', async () => {
    Object.assign(harness.store.get('link1'), {
      uri: 'vless://u@a.example:443?security=tls#USA',
      tls_fingerprint: 'chrome_pq',
    });
    const dialog = await harness.openDialog(linkList(), 'sec', 'link1');
    const field = dialog.map.children[0].children.find(
      (o) => o.option === 'tls_fingerprint',
    );
    expect(field.formvalue('settings')).toBe('chrome');
    expect(field.keylist).not.toContain('chrome_pq');
    expect((await dialog.save()).saved, harness.toasts().join('; ')).toBe(true);
    expect(harness.store.get('link1').tls_fingerprint).toBe('chrome_pq');
  });
  it('uses family and real Chrome versions, then removes override on inheritance', async () => {
    const uri =
      'vless://u@a.example:443?security=tls&fp=chrome&unknown=%2f#USA';
    harness.store.get('link1').uri = uri;
    const list = linkList();
    const dialog = await harness.openDialog(list, 'sec', 'link1');
    const field = (name) =>
      dialog.map.children[0].children.find((o) => o.option === name);
    field('_uri_show').formvalue = () => '1';
    expect(field('tls_fingerprint').keylist).toContain('randomized');
    expect(field('tls_fingerprint').keylist).toContain('qq');
    expect(field('tls_fingerprint').keylist).not.toContain('chrome_psk');
    expect(field('tls_fingerprint').keylist).not.toContain('chrome_155');
    field('tls_fingerprint').formvalue = () => 'chrome';
    field('_tls_variant').formvalue = () => 'chrome_155';
    field('_uri_export').onclick();
    expect(harness.clipboard.at(-1)).toContain('fp=chrome_155');
    expect((await dialog.save()).saved, harness.toasts().join('; ')).toBe(true);
    expect(harness.store.get('link1').tls_fingerprint).toBe('chrome_155');
    expect(harness.store.get('link1').uri).toBe(uri);
    const reopened = await harness.openDialog(list, 'sec', 'link1');
    const fields = reopened.map.children[0].children;
    expect(
      fields.find((o) => o.option === 'tls_fingerprint').formvalue('settings'),
    ).toBe('chrome');
    expect(
      fields.find((o) => o.option === '_tls_variant').formvalue('settings'),
    ).toBe('chrome_155');
    fields.find((o) => o.option === 'tls_fingerprint').formvalue = () => '';
    expect((await reopened.save()).saved, harness.toasts().join('; ')).toBe(
      true,
    );
    expect(harness.store.get('link1').tls_fingerprint || '').toBe('');
    expect(harness.store.get('link1').uri).toBe(uri);
  });
  it('edits VLESS REALITY fields and copies effective parameters under the same ID', async () => {
    const original =
      'vless://secret-id@a.example:443?security=reality&sni=old.example&fp=firefox&pbk=key&sid=abcd&type=ws&path=%2Fkeep&unknown=a%20b#Old';
    harness.uci.add('kabanmax', 'connection_link', 'editor');
    Object.assign(harness.store.get('editor'), {
      section: 'sec',
      name: 'Editor',
      order: '1',
      uri: original,
    });
    harness.uci.add('kabanmax', 'urltest', 'fast');
    Object.assign(harness.store.get('fast'), {
      section: 'sec',
      name: 'Fast',
      include_outbounds: ['Editor'],
    });
    const list = linkList();
    const dialog = await harness.openDialog(list, 'sec', 'editor');
    const draftUrltest = list.section.children.find(
      (o) => o.option === 'urltest',
    );
    draftUrltest.pendingChildSettings = {
      sec: { Draft: { name: 'Draft', include_outbounds: ['Editor'] } },
    };
    const fields = dialog.map.children[0].children;
    const field = (name) => fields.find((o) => o.option === name);
    field('_uri_show').formvalue = () => '1';
    expect(field('_uri_port').formvalue('settings')).toBe('443');
    expect(field('_uri_security').formvalue('settings')).toBe('reality');
    field('_uri_port').formvalue = () => '8443';
    field('_uri_sni').formvalue = () => 'new.example';
    field('tls_fingerprint').formvalue = () => 'chrome_155';
    field('name').formvalue = () => 'New editor';
    field('_uri_export').onclick();
    const exported = harness.clipboard.at(-1);
    expect(exported).toContain(':8443?');
    expect(exported).toContain('sni=new.example');
    expect(exported).toContain('fp=chrome_155');
    expect(exported).not.toContain('fp=firefox');
    expect(harness.store.get('editor').uri).toBe(original);
    expect((await dialog.save()).saved, harness.toasts().join('; ')).toBe(true);
    const stored = harness.store.get('editor');
    expect(stored.uri).toContain(':8443?');
    expect(stored.uri).toContain('sni=new.example');
    expect(stored.uri).toContain('unknown=a%20b');
    expect(stored.uri).toContain('fp=firefox');
    expect(stored.tls_fingerprint).toBe('chrome_155');
    expect(stored.order).toBe('1');
    expect(harness.store.get('fast').include_outbounds).toEqual(['New editor']);
    expect(
      draftUrltest.pendingChildSettings.sec.Draft.include_outbounds,
    ).toEqual(['New editor']);
    expect(Object.keys(stored).some((key) => key.startsWith('_uri_'))).toBe(
      false,
    );
    const reopened = await harness.openDialog(list, 'sec', 'editor');
    const before = stored.uri;
    expect((await reopened.save()).saved, harness.toasts().join('; ')).toBe(
      true,
    );
    expect(harness.store.get('editor').uri).toBe(before);
    expect(harness.messages.join(' ')).not.toContain('secret-id');
  });

  it('refuses bad field values without a partial UCI write or secret-bearing error', async () => {
    const list = linkList();
    const dialog = await harness.openDialog(list, 'sec', 'link1');
    const field = (name) =>
      dialog.map.children[0].children.find((o) => o.option === name);
    field('_uri_show').formvalue = () => '1';
    field('_uri_port').formvalue = () => '65536';
    field('_uri_credential').formvalue = () => 'never-log-this';
    const before = JSON.stringify(harness.store.get('link1'));
    expect((await dialog.save()).saved).toBe(false);
    expect(JSON.stringify(harness.store.get('link1'))).toBe(before);
    expect(harness.toasts().join(' ')).toContain(
      'Port must be between 1 and 65535',
    );
    expect(
      harness.messages.join(' ') + harness.toasts().join(' '),
    ).not.toContain('never-log-this');
  });

  it('imports a replacement raw URI into fields without recreating the connection', async () => {
    const list = linkList();
    const dialog = await harness.openDialog(list, 'sec', 'link1');
    const field = (name) =>
      dialog.map.children[0].children.find((o) => o.option === name);
    field('_uri_show').formvalue = () => '1';
    for (const option of dialog.map.children[0].children) {
      option.getUIElement = () => ({
        setValue: (value) => {
          option.formvalue = () => value;
        },
        triggerValidation() {},
      });
    }
    const replacement =
      'vless://new-id@[2001:db8::2]:8443?security=reality&pbk=key&sni=site.example&unknown=%23#New';
    field('_uri_editor').getUIElement().setValue('raw');
    field('uri').formvalue = () => replacement;
    field('_uri_import').onclick();
    expect(
      dialog.map.data.get(dialog.map.config, 'settings', '_uri_editor'),
    ).toBe('fields');
    expect(field('_uri_server').formvalue('settings')).toBe('2001:db8::2');
    expect((await dialog.save()).saved, harness.toasts().join('; ')).toBe(true);
    expect(harness.store.get('link1').uri).toBe(replacement);
    expect(harness.store.get('link1').name).toBe('USA');
    expect(harness.uci.sections('kabanmax', 'connection_link')).toHaveLength(1);
  });

  it('requires explicit import when a raw URI was edited before switching to fields', async () => {
    const dialog = await harness.openDialog(linkList(), 'sec', 'link1');
    dialog.map.children[0].children.find((o) => o.option === 'uri').formvalue =
      () => 'vless://other@b.example:8443';
    expect((await dialog.save()).saved).toBe(false);
    expect(harness.toasts().join(' ')).toContain(
      'Import the changed URI into fields before saving.',
    );
    expect(harness.store.get('link1').uri).toBe('vless://a@a.example:443#USA');
  });

  it.each([
    'vmess://eyJwcyI6IlJhdyIsImFkZCI6ImEuZXhhbXBsZSIsInVua25vd24iOiJrZWVwIn0=',
    'ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwYXNz@a.example:443#SS',
  ])(
    'keeps special formats unchanged through repeated raw saves',
    async (uri) => {
      Object.assign(harness.store.get('link1'), { uri });
      const list = linkList();
      for (let i = 0; i < 2; i++) {
        const dialog = await harness.openDialog(list, 'sec', 'link1');
        expect(
          dialog.map.data.get(dialog.map.config, 'settings', '_uri_editor'),
        ).toBe('raw');
        expect((await dialog.save()).saved, harness.toasts().join('; ')).toBe(
          true,
        );
        expect(harness.store.get('link1').uri).toBe(uri);
      }
    },
  );
  it('sets a fingerprint by persistent ID with identical URI fragments and a renamed server', async () => {
    const uri = 'vless://u@a.example:443?security=tls&fp=firefox#Same';
    for (const [id, name] of [
      ['first', 'Renamed'],
      ['second', 'Same'],
    ]) {
      harness.uci.add('kabanmax', 'connection_link', id);
      Object.assign(harness.store.get(id), { section: 'sec', name, uri });
    }
    const dialog = await harness.openDialog(linkList(), 'sec', 'first');
    const fields = dialog.map.children[0].children;
    const fingerprint = fields.find(
      (option) => option.option === 'tls_fingerprint',
    );
    fingerprint.formvalue = () => 'chrome_155';
    expect((await dialog.save()).saved).toBe(true);
    expect(harness.store.get('first').tls_fingerprint).toBe('chrome_155');
    expect(harness.store.get('second').tls_fingerprint).toBeUndefined();
    expect(harness.store.get('first').uri).toBe(uri);
    expect(harness.store.get('second').uri).toBe(uri);
    const reopened = await harness.openDialog(linkList(), 'sec', 'first');
    reopened.map.children[0].children.find(
      (option) => option.option === 'tls_fingerprint',
    ).formvalue = () => '';
    expect((await reopened.save()).saved).toBe(true);
    expect(harness.store.get('first').tls_fingerprint || '').toBe('');
    expect(harness.store.get('first').uri).toBe(uri);
  });
  beforeEach(() => {
    harness.uci.add('kabanmax', 'connection_link', 'link1');
    Object.assign(harness.store.get('link1'), {
      section: 'sec',
      uri: 'vless://a@a.example:443#USA',
      name: 'USA',
      order: '0',
    });
  });

  it('is listed under its stored name', () => {
    expect(linkList().renderListItemLabel('sec', 'link1').textContent).toBe(
      'USA',
    );
  });

  it('changes its link and its name in its dialog', async () => {
    const list = linkList();
    const dialog = await harness.openDialog(list, 'sec', 'link1');
    const fields = dialog.map.children[0].children;
    const field = (name) => fields.find((option) => option.option === name);
    field('_uri_show').formvalue = () => '1';
    expect(dialog.map.data.get(dialog.map.config, 'settings', 'uri')).toBe(
      'vless://a@a.example:443#USA',
    );
    expect(field('uri').password, 'the link is shown masked').toBe(true);
    expect(dialog.title).toBe('Server: USA');
    field('uri').formvalue = () => 'trojan://p@b.example:443#Other';
    field('_uri_editor').formvalue = () => 'raw';
    field('name').formvalue = () => 'Chicago';

    expect((await dialog.save()).saved).toBe(true);
    expect(storedLinks()).toEqual([
      {
        section: 'sec',
        uri: 'trojan://p@b.example:443#Other',
        name: 'Chicago',
        order: '0',
      },
    ]);
  });

  it('refuses an empty link and one the core cannot dial', async () => {
    harness.bundle.setCoreFeatures(coreFeatures({ remove: ['with_quic'] }));
    const dialog = await harness.openDialog(linkList(), 'sec', 'link1');
    const fields = dialog.map.children[0].children;
    const check = (name, value) =>
      fields.find((option) => option.option === name).validate('link1', value);

    expect(check('uri', 'hy2://p@b.example:443#H')).toBe(
      'sing-box is built without with_quic',
    );
    expect(check('uri', ' ')).toBe('Required');
    expect(check('uri', 'https://sub.example.com/api/sub/token')).toBe(
      'Probably a subscription URL: paste it into Subscription',
    );
    expect(check('uri', 'vless://a@a.example:443#USA')).toBe(true);
    expect(check('name', '')).toBe('Required');
  });

  it.each([
    ['1', '0'],
    ['0', '1'],
    ['1', '1'],
  ])('saves independent TLS options (%s, %s)', async (split, classical) => {
    const dialog = await harness.openDialog(linkList(), 'sec', 'link1');
    const fields = dialog.map.children[0].children;
    const field = (name) => fields.find((option) => option.option === name);
    field('_uri_show').formvalue = () => '1';
    field('uri').formvalue = () =>
      'vless://a@a.example:443?security=reality#USA';
    field('_uri_editor').formvalue = () => 'raw';
    field('tls_record_fragment').formvalue = () => split;
    field('tls_classical').formvalue = () => classical;
    expect((await dialog.save()).saved).toBe(true);
    const stored = harness.store.get('link1');
    expect(stored.tls_record_fragment || '0').toBe(split);
    expect(stored.tls_classical || '0').toBe(classical);
  });
});
