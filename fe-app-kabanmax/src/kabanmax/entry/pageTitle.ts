import { normalizeCompiledVersion } from '../../helpers/normalizeCompiledVersion';

// The build writes the version into the bundle; a development build has none. LuCI rebuilds the
// heading from the map title on every save and reset, and moves these same nodes into it.
// Themes draw h2 small as the muted part of a heading.
export function pageTitle(compiledVersion: string, status: HTMLElement) {
  const version = normalizeCompiledVersion(compiledVersion);
  const logo = document.createElement('img');
  logo.src = '/luci-static/resources/view/kabanmax/kaban-max.png';
  logo.alt = 'K.A.B.A.N.-MAX';
  logo.width = 48;
  logo.height = 48;
  logo.className = 'kaban-max-logo';
  if (version === 'dev') {
    return [logo, ' K.A.B.A.N.-MAX ', status];
  }

  const small = document.createElement('small');
  small.textContent = version;
  return [logo, ' K.A.B.A.N.-MAX ', small, ' ', status];
}
