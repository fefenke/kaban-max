import { E } from '../../../helpers/element';
import { drawAcorn, drawBoar } from '../../helpers/boar';
import { GROUND, jumpRunner, newRunner, stepRunner } from './acornPhysics';

const BEST_KEY = 'kabanmax-acorn-best';
export function createAcornGame() {
  const canvas = E('canvas', {
    width: 360,
    height: 122,
    tabindex: 0,
    'aria-label': _('Jump over logs and collect acorns. Click or press Space.'),
  }) as HTMLCanvasElement;
  const score = E('span', {});
  const message = E('span', { role: 'status' });
  const button = E(
    'button',
    { type: 'button', class: 'btn cbi-button' },
    _('Go for acorns!'),
  ) as HTMLButtonElement;
  const element = E('section', { class: 'fkp_acorn-game' }, [
    E('div', { class: 'fkp_acorn-game__bar' }, [score, message, button]),
    canvas,
  ]);
  const ctx = canvas.getContext('2d');
  let state = newRunner();
  let active = false;
  let shown = true;
  let frame = 0;
  let previous = 0;
  let disposed = false;
  let mounted = false;
  let best = 0;
  try {
    best = Math.max(
      0,
      Math.min(999999, Number(localStorage.getItem(BEST_KEY)) || 0),
    );
  } catch {
    /* storage can be disabled */
  }
  function draw() {
    if (!ctx) return;
    ctx.clearRect(0, 0, 360, 122);
    ctx.fillStyle = '#8a9865';
    ctx.fillRect(0, GROUND + 1, 360, 1);
    ctx.fillStyle = '#758453';
    for (let x = 8; x < 360; x += 43) ctx.fillRect(x, GROUND + 4, 6, 2);
    drawBoar(
      ctx,
      38,
      GROUND - 28 - state.y,
      2,
      state.over ? 'stopped' : 'running',
      Math.floor(state.elapsed * 8),
    );
    for (const item of state.items) {
      if (item.kind === 'acorn')
        drawAcorn(ctx, Math.round(item.x), GROUND - 37, 2);
      else {
        ctx.fillStyle = '#78583b';
        ctx.fillRect(Math.round(item.x), GROUND - 15, 18, 15);
        ctx.fillStyle = '#ba945e';
        ctx.fillRect(Math.round(item.x) + 13, GROUND - 13, 5, 11);
        ctx.fillStyle = '#97754c';
        ctx.fillRect(Math.round(item.x) + 2, GROUND - 11, 10, 2);
      }
    }
    score.textContent = `${_('Acorns')}: ${state.score}${best ? ` / ${_('Best')}: ${best}` : ''}`;
  }
  function pause() {
    if (!active) return;
    active = false;
    cancelAnimationFrame(frame);
    frame = 0;
    button.hidden = false;
    button.textContent = _('Continue');
    message.textContent = _('Paused');
  }
  function tick(now: number) {
    frame = 0;
    if (!active || disposed) return;
    if (!shown || document.hidden || !element.isConnected) {
      pause();
      return;
    }
    stepRunner(state, previous ? (now - previous) / 1000 : 0);
    previous = now;
    draw();
    if (state.over) {
      active = false;
      if (state.score > best) {
        best = state.score;
        try {
          localStorage.setItem(BEST_KEY, String(best));
        } catch {
          /* optional best */
        }
      }
      message.textContent = _('You are a boar');
      button.textContent = _('More acorns!');
      button.hidden = false;
      draw();
      return;
    }
    frame = requestAnimationFrame(tick);
  }
  function start() {
    if (disposed || document.hidden || !shown || !element.isConnected || !ctx)
      return;
    if (state.over) state = newRunner();
    active = true;
    previous = 0;
    button.hidden = true;
    message.textContent = '';
    canvas.focus();
    if (!frame) frame = requestAnimationFrame(tick);
  }
  const visibility = () => {
    if (document.hidden) pause();
  };
  const keydown = (event: KeyboardEvent) => {
    if (
      event.code !== 'Space' ||
      event.repeat ||
      !active ||
      document.activeElement !== canvas
    )
      return;
    event.preventDefault();
    event.stopPropagation();
    jumpRunner(state);
  };
  const pointer = () => {
    if (active) {
      canvas.focus();
      jumpRunner(state);
    }
  };
  const blur = () => pause();
  button.addEventListener('click', start);
  canvas.addEventListener('keydown', keydown);
  canvas.addEventListener('pointerdown', pointer);
  canvas.addEventListener('blur', blur);
  document.addEventListener('visibilitychange', visibility);
  // LuCI removes entire tab trees. No timers or handlers survive that removal.
  const observer = new MutationObserver(() => {
    if (element.isConnected) mounted = true;
    else if (mounted) dispose();
  });
  observer.observe(document.body, { childList: true, subtree: true });
  function dispose() {
    if (disposed) return;
    pause();
    disposed = true;
    observer.disconnect();
    button.removeEventListener('click', start);
    canvas.removeEventListener('keydown', keydown);
    canvas.removeEventListener('pointerdown', pointer);
    canvas.removeEventListener('blur', blur);
    document.removeEventListener('visibilitychange', visibility);
  }
  draw();
  return {
    element,
    dispose,
    setShown(value: boolean) {
      shown = value;
      if (!shown) pause();
    },
  };
}
