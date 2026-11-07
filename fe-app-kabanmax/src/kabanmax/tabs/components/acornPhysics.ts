export interface RunnerItem {
  x: number;
  kind: 'log' | 'acorn';
}
export interface RunnerState {
  y: number;
  velocity: number;
  elapsed: number;
  spawnIn: number;
  score: number;
  over: boolean;
  items: RunnerItem[];
}
export const GROUND = 102;
export function newRunner(): RunnerState {
  return {
    y: 0,
    velocity: 0,
    elapsed: 0,
    spawnIn: 0.9,
    score: 0,
    over: false,
    items: [],
  };
}
export function jumpRunner(state: RunnerState) {
  if (!state.over && state.y === 0) state.velocity = 280;
}
export function stepRunner(
  state: RunnerState,
  seconds: number,
  random = Math.random,
) {
  if (state.over) return;
  const dt = Math.min(0.04, Math.max(0, seconds));
  state.elapsed += dt;
  state.velocity -= 780 * dt;
  state.y = Math.max(0, state.y + state.velocity * dt);
  if (state.y === 0) state.velocity = 0;
  const speed = Math.min(180, 96 + state.elapsed * 0.8);
  state.spawnIn -= dt;
  if (state.spawnIn <= 0) {
    state.items.push({ x: 365, kind: random() < 0.55 ? 'log' : 'acorn' });
    state.spawnIn = 1.25 + random() * 0.6;
  }
  for (const item of state.items) {
    item.x -= speed * dt;
    // The visible boar occupies x=38..82, with a deliberately forgiving hitbox.
    if (item.x < 75 && item.x + 14 > 46) {
      if (item.kind === 'log' && state.y < 17) state.over = true;
      if (item.kind === 'acorn' && state.y > 15 && state.y < 65) {
        state.score++;
        item.x = -30;
      }
    }
  }
  state.items = state.items.filter((item) => item.x > -30);
}
