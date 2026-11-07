export type BoarPose =
  | 'running'
  | 'start'
  | 'apply'
  | 'restart'
  | 'stop'
  | 'stopped'
  | 'check'
  | 'download'
  | 'install';

// A 22 x 16 pixel character; no bitmap, network asset or animation timer.
const BODY = [
  '       cc c           ',
  '      ccccccc         ',
  '    ccccccccccc c     ',
  '   cdddddddddddcc     ',
  '  cdddddddddddddcc    ',
  ' cdddddddddddddddc    ',
  ' cdddddddddddddddc    ',
  ' cddddddddddddedddccc ',
  ' cddddddddddddddddssc',
  '  cdddddddddddddddsns',
  '   cdddddddddddddtssc',
  '    ccddddddddddttcc ',
  '     ccc cc  ccc     ',
  '     cc  cc  cc      ',
];
const PALETTE: Record<string, string> = {
  c: '#303337',
  d: '#505359',
  e: '#f4cf80',
  s: '#77797b',
  n: '#343638',
  t: '#eee3c8',
};

export function drawBoar(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  scale = 1,
  pose: BoarPose = 'running',
  frame = 0,
) {
  ctx.save();
  ctx.translate(Math.round(x), Math.round(y));
  ctx.scale(scale, scale);
  if (pose === 'stopped') {
    ctx.translate(0, 4);
    ctx.scale(1, 0.72);
  }
  if (pose === 'apply' || pose === 'check') {
    ctx.translate(0, -2);
    ctx.rotate(0.12);
  }
  if (pose === 'restart') {
    ctx.translate(0, 2);
    ctx.scale(1.08, 0.9);
  }
  if (pose === 'stop') {
    ctx.translate(22, 0);
    ctx.scale(-1, 1);
  }
  for (let row = 0; row < BODY.length; row++) {
    for (let col = 0; col < BODY[row].length; col++) {
      const color = PALETTE[BODY[row][col]];
      if (!color) continue;
      ctx.fillStyle =
        pose === 'stopped' && BODY[row][col] === 'e' ? '#303337' : color;
      ctx.fillRect(
        col,
        row + (row > 11 && frame % 2 ? (col % 2 ? -1 : 0) : 0),
        1,
        1,
      );
    }
  }
  if (pose === 'download' || pose === 'install') {
    ctx.fillStyle = '#9e7845';
    ctx.fillRect(4, 3, 7, 5);
    ctx.fillStyle = '#d1aa60';
    ctx.fillRect(5, 2, 5, 2);
  }
  ctx.restore();
  if (pose === 'start') {
    ctx.fillStyle = '#68784a';
    ctx.fillRect(x, y + 10 * scale, 8 * scale, 4 * scale);
    ctx.fillStyle = '#87945e';
    ctx.fillRect(x + 2 * scale, y + 8 * scale, 5 * scale, 3 * scale);
  }
  if (pose === 'install')
    drawAcorn(ctx, x + 24 * scale, y + 11 * scale, scale);
}
export function drawAcorn(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  scale = 1,
) {
  ctx.fillStyle = '#b58a4d';
  ctx.fillRect(x + scale, y + scale, 3 * scale, 4 * scale);
  ctx.fillStyle = '#6f713f';
  ctx.fillRect(x, y, 5 * scale, 2 * scale);
  ctx.fillRect(x + 2 * scale, y - scale, scale, scale);
}
export function createBoar(pose: BoarPose) {
  const node = document.createElement('span');
  node.className = `fkp_boar fkp_boar--${pose}`;
  node.setAttribute?.('aria-hidden', 'true');
  const sheet = document.createElement('canvas');
  sheet.width = 60;
  sheet.height = 72;
  sheet.className = 'fkp_boar__sheet';
  const ctx = sheet.getContext?.('2d');
  if (ctx) {
    drawBoar(ctx, 1, 3, 2, pose);
    drawBoar(ctx, 1, 39, 2, pose, 1);
  }
  node.replaceChildren(sheet);
  return node;
}
export const boarStyles = `
.fkp_boar { width: 40px; height: 24px; display: inline-block; overflow: hidden; vertical-align: middle; flex: 0 0 auto; }
.fkp_boar__sheet { display: block; width: 40px; height: 48px; image-rendering: pixelated; max-width: none; }
.fkp_boar--start .fkp_boar__sheet, .fkp_boar--restart .fkp_boar__sheet, .fkp_boar--stop .fkp_boar__sheet, .fkp_boar--apply .fkp_boar__sheet, .fkp_boar--check .fkp_boar__sheet, .fkp_boar--download .fkp_boar__sheet, .fkp_boar--install .fkp_boar__sheet { animation: fkp_boar-step .8s steps(1,end) infinite; }
@keyframes fkp_boar-step { 50% { transform: translateY(-24px); } }
@media (prefers-reduced-motion: reduce) { .fkp_boar__sheet { animation: none !important; } }
`;
