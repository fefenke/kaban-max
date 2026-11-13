import { execFileSync } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

const frontendRoot = fileURLToPath(new URL('../', import.meta.url));

it('keeps project-only identities in both checked-in catalog headers', async () => {
  for (const relative of [
    'templates/kabanmax.pot',
    'ru/kabanmax.po',
  ]) {
    const catalog = await fs.readFile(
      path.join(frontendRoot, '../luci-app-kabanmax/po', relative),
      'utf8',
    );
    const translator = catalog.match(/^"Last-Translator: ([^\n]*)"$/m)?.[1] || '';
    expect(translator.startsWith('K.A.B.A.N.-MAX contributors'), relative).toBe(true);
    const authors = catalog.split('msgid ""')[0].split('\n').filter(
      (line) => /^# .*?,\s*20\d\d\.?$/.test(line),
    );
    expect(authors.every((line) => line.startsWith('# K.A.B.A.N.-MAX contributors')), relative).toBe(true);
  }
});

it('generates public project metadata regardless of Git identity or old catalog headers', async () => {
  const fixture = await fs.mkdtemp(
    path.join(frontendRoot, '.locale-identity-'),
  );
  try {
    const frontend = path.join(fixture, 'fe-app-kabanmax');
    const catalogs = path.join(fixture, 'luci-app-kabanmax', 'po');
    await fs.mkdir(path.join(frontend, 'src'), { recursive: true });
    await fs.mkdir(path.join(catalogs, 'templates'), { recursive: true });
    await fs.mkdir(path.join(catalogs, 'ru'), { recursive: true });
    await fs.copyFile(
      path.join(frontendRoot, 'sync-locales.js'),
      path.join(frontend, 'sync-locales.js'),
    );
    await fs.writeFile(
      path.join(frontend, 'src', 'sample.ts'),
      '_("Example");\n',
    );
    const oldHeader =
      'msgid ""\nmsgstr ""\n"Last-Translator: Previous Private <previous@example.invalid>\\n"\n';
    const pot = path.join(catalogs, 'templates', 'kabanmax.pot');
    const po = path.join(catalogs, 'ru', 'kabanmax.po');
    // Exercise both the Git identity path and the previous-catalog fallback.
    for (const gitIdentity of ['Synthetic Private', '']) {
      await fs.writeFile(pot, oldHeader);
      await fs.writeFile(
        po,
        `${oldHeader}\nmsgid "Example"\nmsgstr "Пример"\n`,
      );
      execFileSync(process.execPath, [path.join(frontend, 'sync-locales.js')], {
        cwd: frontend,
        env: {
          ...process.env,
          GIT_CONFIG_COUNT: '2',
          GIT_CONFIG_KEY_0: 'user.name',
          GIT_CONFIG_VALUE_0: gitIdentity,
          GIT_CONFIG_KEY_1: 'user.email',
          GIT_CONFIG_VALUE_1: gitIdentity ? 'synthetic@example.invalid' : '',
        },
        stdio: 'pipe',
      });
      const generated = await Promise.all([
        fs.readFile(pot, 'utf8'),
        fs.readFile(po, 'utf8'),
      ]);
      for (const catalog of generated) {
        expect(catalog).not.toMatch(
          /Synthetic Private|Previous Private|synthetic@example\.invalid|previous@example\.invalid/,
        );
        expect(catalog).toContain('K.A.B.A.N.-MAX contributors');
      }
      expect(generated[0]).toContain(
        '341400787+fefenke@users.noreply.github.com',
      );
      expect(generated[1]).toContain('msgstr "Пример"');
    }
  } finally {
    await fs.rm(fixture, { recursive: true, force: true });
  }
});
