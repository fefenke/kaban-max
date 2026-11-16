import { describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ request: vi.fn() }));
vi.mock('../routeForecast', async (original) => ({
  ...(await original<Record<string, unknown>>()),
  requestRouteForecast: mocks.request,
}));
import { renderRouteForecast } from '../renderRouteForecast';

type Node = {
  type: string;
  attrs: Record<string, unknown>;
  children: Node[];
  value: string;
  textContent: string;
  disabled: boolean;
  setAttribute: (key: string, value: string) => void;
  addEventListener: (type: string, listener: unknown) => void;
};

describe('route forecast UI', () => {
  it('only runs on explicit click, suppresses concurrent clicks and displays text', async () => {
    const nodes: Node[] = [];
    vi.stubGlobal(
      'E',
      (type: string, attrs: Record<string, unknown>, children: Node[]) => {
        const node: Node = {
          type,
          attrs,
          children,
          value: String(attrs.value ?? ''),
          textContent: '',
          disabled: false,
          addEventListener(type, listener) {
            this.attrs[type] = listener;
          },
          setAttribute(key, value) {
            this.attrs[key] = value;
          },
        };
        nodes.push(node);
        return node;
      },
    );
    mocks.request.mockReset();
    try {
      renderRouteForecast();
      expect(mocks.request).not.toHaveBeenCalled();
      const inputs = nodes.filter((node) => node.type === 'input');
      inputs[0].value = ' example.test ';
      nodes.find((node) => node.type === 'select')!.value = '@system';
      const button = nodes.find((node) => node.type === 'button')!;
      const output = nodes.find((node) => node.type === 'pre')!;
      let finish!: (value: unknown) => void;
      mocks.request.mockReturnValue(
        new Promise((resolve) => {
          finish = resolve;
        }),
      );
      const click = button.attrs.click as () => Promise<void>;
      const pending = click();
      await click();
      expect(mocks.request).toHaveBeenCalledTimes(1);
      expect(mocks.request).toHaveBeenCalledWith(
        'example.test',
        '@system',
        '443',
      );
      finish({
        predicted: { status: 'unknown', reason: '<script>untrusted</script>' },
      });
      await pending;
      expect(output.textContent).toContain('<script>untrusted</script>');
      expect(button.disabled).toBe(false);
      expect(nodes.filter((node) => node.type === 'button')).toHaveLength(1);
    } finally {
      vi.unstubAllGlobals();
    }
  });
});
