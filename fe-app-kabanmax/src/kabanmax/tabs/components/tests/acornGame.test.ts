import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { jumpRunner, newRunner, stepRunner } from '../acornPhysics';
import { createAcornGame } from '../acornGame';

class Node extends EventTarget {
  children: Node[] = [];
  isConnected = true;
  hidden = false;
  textContent = '';
  className = '';
  append(...nodes: Node[]) {
    this.children.push(...nodes);
  }
  focus() {
    doc.activeElement = this as unknown as Element;
  }
  getContext() {
    return new Proxy({}, { get: () => () => undefined });
  }
}
let callbacks: Map<number, FrameRequestCallback>;
let visibility: EventTarget;
let doc: { hidden: boolean; activeElement: Element | null; body: Node };
let disconnected: boolean;
beforeEach(() => {
  callbacks = new Map();
  visibility = new EventTarget();
  disconnected = false;
  doc = { hidden: false, activeElement: null, body: new Node() };
  vi.stubGlobal('_', (text: string) => text);
  vi.stubGlobal('E', (_tag: string, _attrs: unknown, children: Node[] = []) => {
    const node = new Node();
    if (Array.isArray(children)) node.append(...children);
    return node;
  });
  vi.stubGlobal(
    'document',
    Object.assign(doc, {
      addEventListener: visibility.addEventListener.bind(visibility),
      removeEventListener: visibility.removeEventListener.bind(visibility),
    }),
  );
  let id = 0;
  vi.stubGlobal('requestAnimationFrame', (callback: FrameRequestCallback) => {
    callbacks.set(++id, callback);
    return id;
  });
  vi.stubGlobal('cancelAnimationFrame', (handle: number) =>
    callbacks.delete(handle),
  );
  vi.stubGlobal(
    'MutationObserver',
    class {
      observe() {}
      disconnect() {
        disconnected = true;
      }
    },
  );
  vi.stubGlobal('localStorage', { getItem: () => null, setItem: vi.fn() });
});
afterEach(() => vi.unstubAllGlobals());
function nodes(game: ReturnType<typeof createAcornGame>) {
  const root = game.element as unknown as Node;
  return { button: root.children[0].children[2], canvas: root.children[1] };
}
function space(canvas: Node) {
  const event = new Event('keydown', { cancelable: true });
  Object.assign(event, { code: 'Space', repeat: false });
  canvas.dispatchEvent(event);
  return event;
}
describe('acorn runner physics', () => {
  it('jumps once, clears logs, and lands after a bounded arc', () => {
    const state = newRunner();
    jumpRunner(state);
    stepRunner(state, 0.04);
    const velocity = state.velocity;
    jumpRunner(state);
    expect(state.velocity).toBe(velocity);
    expect(state.y).toBeGreaterThan(0);
    for (let n = 0; n < 25; n++) stepRunner(state, 0.04);
    expect(state.y).toBe(0);
  });
  it('collects each acorn once and ends on a ground collision', () => {
    const state = newRunner();
    state.y = 30;
    state.items = [{ x: 60, kind: 'acorn' }];
    stepRunner(state, 0.01);
    expect(state.score).toBe(1);
    stepRunner(state, 0.01);
    expect(state.score).toBe(1);
    state.y = 0;
    state.items = [{ x: 60, kind: 'log' }];
    stepRunner(state, 0.01);
    expect(state.over).toBe(true);
    const elapsed = state.elapsed;
    stepRunner(state, 0.04);
    expect(state.elapsed).toBe(elapsed);
  });
  it('caps a delayed frame rather than teleporting into obstacles', () => {
    const state = newRunner();
    stepRunner(state, 100);
    expect(state.elapsed).toBe(0.04);
  });
});
describe('runner input and lifecycle', () => {
  it('consumes Space only on the focused active canvas', () => {
    const game = createAcornGame();
    const { button, canvas } = nodes(game);
    expect(space(canvas).defaultPrevented).toBe(false);
    button.dispatchEvent(new Event('click'));
    expect(space(canvas).defaultPrevented).toBe(true);
    doc.activeElement = null;
    expect(space(canvas).defaultPrevented).toBe(false);
    game.dispose();
  });
  it('cancels frames when hidden and needs an explicit restart', () => {
    const game = createAcornGame();
    const { button } = nodes(game);
    button.dispatchEvent(new Event('click'));
    expect(callbacks.size).toBe(1);
    doc.hidden = true;
    visibility.dispatchEvent(new Event('visibilitychange'));
    expect(callbacks.size).toBe(0);
    doc.hidden = false;
    visibility.dispatchEvent(new Event('visibilitychange'));
    expect(callbacks.size).toBe(0);
    button.dispatchEvent(new Event('click'));
    expect(callbacks.size).toBe(1);
    game.setShown(false);
    expect(callbacks.size).toBe(0);
    game.setShown(true);
    expect(callbacks.size).toBe(0);
    game.dispose();
    expect(disconnected).toBe(true);
  });
  it('pauses when focus leaves the canvas', () => {
    const game = createAcornGame();
    const { button, canvas } = nodes(game);
    button.dispatchEvent(new Event('click'));
    canvas.dispatchEvent(new Event('blur'));
    expect(callbacks.size).toBe(0);
    game.dispose();
  });
});
